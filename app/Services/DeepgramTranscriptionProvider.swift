import Foundation

/// Deepgram Nova-3 流式语音识别（English STT）。
/// 只需 API Key，直接用 URLSessionWebSocketTask，零第三方依赖。
/// 端点：wss://api.deepgram.com/v1/listen?model=nova-3&language=en&interim_results=true...
/// 注意：Deepgram 已不再提供流式内置翻译（translation 参数会被静默忽略），
/// 译文由 TranscriptionManager 用「文本翻译」服务（如 Apple 系统翻译）二次翻译。
final class DeepgramTranscriptionProvider: NSObject, TranscriptionProvider, URLSessionWebSocketDelegate {
    var apiKey: String

    var onResult: ((TranscriptResult) -> Void)?
    var onStateChange: ((TranscriptionState) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var isOpen = false
    private var pendingAudio: [Data] = []
    private var language = "en"
    /// 每次启动或停止都会推进代次，用于丢弃已排入主队列的过期状态回调。
    private var generation = 0
    private var keepAliveTimer: DispatchSourceTimer?
    /// 保护 isOpen / pendingAudio / task：音频回调在实时音频线程，
    /// 识别结果在 URLSession 回调队列，两者并发访问需要加锁。
    private let lock = NSLock()

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        self.session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }

    // MARK: - TranscriptionProvider

    func start(language: String, targetLanguage: String) {
        // 静默清理旧连接。注意不能调用 stop()：它会异步派发 .idle，
        // 这个过期状态可能在新会话启动后才到达，把 isRunning 错误翻回 false，
        // 进而导致用户再次点击「开始」时重复 installTap 崩溃。
        let generation = teardownSilently()
        self.language = language
        _ = targetLanguage // Deepgram 不再支持流式内置翻译，译文由文本翻译引擎处理。

        guard let url = makeURL(language: language, targetLanguage: targetLanguage),
              let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : apiKey.trimmingCharacters(in: .whitespacesAndNewlines) else {
            emitState(.failed("Deepgram API Key 无效，请在设置中填写"), generation: generation)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        lock.lock()
        guard self.generation == generation else {
            lock.unlock()
            task.cancel(with: .goingAway, reason: nil)
            return
        }
        self.task = task
        lock.unlock()

        emitState(.connecting, generation: generation)
        task.resume()
        receiveLoop(for: task)
    }

    func sendAudio(_ data: Data) {
        lock.lock()
        let task = self.task
        if isOpen {
            lock.unlock()
            guard let task else { return }
            task.send(.data(data)) { _ in }
        } else {
            // 连接未就绪时缓存，避免丢帧。
            pendingAudio.append(data)
            if pendingAudio.count > 200 {
                pendingAudio.removeFirst(pendingAudio.count - 200)
            }
            lock.unlock()
        }
    }

    func stop() {
        let generation = teardownSilently()
        emitState(.idle, generation: generation)
    }

    /// 取消连接并清空状态，不对外派发任何状态回调。
    @discardableResult
    private func teardownSilently() -> Int {
        lock.lock()
        let old = task
        generation += 1
        let currentGeneration = generation
        task = nil
        isOpen = false
        pendingAudio.removeAll()
        let timer = keepAliveTimer
        keepAliveTimer = nil
        lock.unlock()
        timer?.cancel()
        old?.cancel(with: .goingAway, reason: nil)
        return currentGeneration
    }

    // MARK: - WebSocket receive

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        // 握手成功就是可以发送音频的权威信号。不能等待 Results：Deepgram
        // 必须先收到音频才会产生 Results。
        _ = markOpenAndFlush(for: webSocketTask)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let description = reason.flatMap { String(data: $0, encoding: .utf8) }
            ?? "WebSocket 已关闭（代码 \(closeCode.rawValue)）"
        handleDisconnect(
            NSError(domain: "DeepgramWebSocket", code: closeCode.rawValue, userInfo: [
                NSLocalizedDescriptionKey: description,
            ]),
            of: webSocketTask
        )
    }

    private func receiveLoop(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text, from: task)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text, from: task)
                    }
                @unknown default:
                    break
                }
                // 只有当前连接仍是同一个任务时才继续接收，避免旧任务的回调串到新会话。
                self.lock.lock()
                let stillCurrent = self.task === task
                self.lock.unlock()
                if stillCurrent {
                    self.receiveLoop(for: task)
                }
            case .failure(let error):
                self.handleDisconnect(error, of: task)
            }
        }
    }

    private func handleMessage(_ text: String, from sourceTask: URLSessionWebSocketTask) {
        // 收到任何消息（包括 Deepgram 连接后立刻推送的 Metadata）都说明
        // WebSocket 握手已成功：放行排队音频。绝不能等第一条 Results 才放行——
        // Deepgram 只有收到音频后才回 Results，那样会互相等待形成死锁，
        // 约 10 秒无数据后服务端主动断开连接（表现为「连接失败」）。
        guard let generation = markOpenAndFlush(for: sourceTask) else { return }

        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ResultsPayload.self, from: data) else {
            return
        }
        if payload.type == "UtteranceEnd" {
            emitResult(TranscriptResult(transcript: "", translatedText: nil,
                                        isFinal: false, utteranceEnd: true),
                       from: sourceTask, generation: generation)
            return
        }
        guard payload.type == "Results" || payload.type == nil else { return }
        let alternative = payload.channel?.alternatives?.first
        let transcript = (alternative?.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let translated = alternative?.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFinal = payload.isFinal ?? false

        guard !transcript.isEmpty || !(translated ?? "").isEmpty || payload.speechFinal == true else { return }
        let result = TranscriptResult(
                transcript: transcript,
                translatedText: translated,
                isFinal: isFinal,
                speechFinal: payload.speechFinal ?? false
            )
        emitResult(result, from: sourceTask, generation: generation)
    }

    private func emitResult(_ result: TranscriptResult, from sourceTask: URLSessionWebSocketTask, generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(sourceTask, generation: generation) else { return }
            self.onResult?(result)
        }
    }

    /// 标记连接可用并发送排队音频（幂等，只在首次生效）。
    private func markOpenAndFlush(for sourceTask: URLSessionWebSocketTask) -> Int? {
        lock.lock()
        guard task === sourceTask else {
            lock.unlock()
            return nil
        }
        let currentGeneration = generation
        let shouldNotify = !isOpen
        let frames: [Data]
        if shouldNotify {
            isOpen = true
            frames = pendingAudio
            pendingAudio.removeAll()
        } else {
            frames = []
        }
        lock.unlock()
        for frame in frames {
            sourceTask.send(.data(frame)) { _ in }
        }
        if shouldNotify {
            startKeepAlive(for: sourceTask, generation: currentGeneration)
            emitState(.listening, generation: currentGeneration)
        }
        return currentGeneration
    }

    private func handleDisconnect(_ error: Error, of disconnectedTask: URLSessionWebSocketTask) {
        lock.lock()
        // 旧连接（已被 stop/新会话替换）的断开回调不上报，避免误伤新会话。
        let wasCurrent = task === disconnectedTask
        guard wasCurrent else {
            lock.unlock()
            return
        }
        let wasOpen = isOpen
        let currentGeneration = generation
        let timer = keepAliveTimer
        keepAliveTimer = nil
        task = nil
        isOpen = false
        pendingAudio.removeAll()
        lock.unlock()
        timer?.cancel()
        let state: TranscriptionState = wasOpen
            ? .failed("与 Deepgram 的连接已断开：\(error.localizedDescription)")
            : .failed("无法连接 Deepgram：\(error.localizedDescription)")
        emitState(state, generation: currentGeneration)
    }

    private func emitState(_ state: TranscriptionState, generation expectedGeneration: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isCurrent = self.generation == expectedGeneration
            self.lock.unlock()
            guard isCurrent else { return }
            self.onStateChange?(state)
        }
    }

    private func isCurrent(_ sourceTask: URLSessionWebSocketTask, generation expectedGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return task === sourceTask && generation == expectedGeneration
    }

    /// Deepgram 规定在无音频期间以文本帧保活，防止课堂短暂停顿导致 socket 被服务端关闭。
    private func startKeepAlive(for task: URLSessionWebSocketTask, generation expectedGeneration: Int) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.allenygy.live-translate.deepgram.keepalive"))
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self, self.isCurrent(task, generation: expectedGeneration) else { return }
            task.send(.string(#"{"type":"KeepAlive"}"#)) { _ in }
        }
        lock.lock()
        guard generation == expectedGeneration, self.task === task else {
            lock.unlock()
            timer.cancel()
            return
        }
        let previousTimer = keepAliveTimer
        keepAliveTimer = timer
        lock.unlock()
        previousTimer?.cancel()
        timer.resume()
    }


    private func makeURL(language: String, targetLanguage: String) -> URL? {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")
        components?.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "multichannel", value: "false"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
            URLQueryItem(name: "utterance_end_ms", value: "1000"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
        ]
        guard let http = components?.url else { return nil }
        let ws = http.absoluteString.replacingOccurrences(of: "https://", with: "wss://")
        return URL(string: ws)
    }

    // MARK: - Result payload

    private struct ResultsPayload: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable {
                let transcript: String?
                let translatedText: String?
                enum CodingKeys: String, CodingKey {
                    case transcript
                    case translatedText = "translated_text"
                }
            }
            let alternatives: [Alternative]?
        }
        let type: String?
        let isFinal: Bool?
        let speechFinal: Bool?
        let channel: Channel?
        enum CodingKeys: String, CodingKey {
            case type
            case isFinal = "is_final"
            case speechFinal = "speech_final"
            case channel
        }
    }
}
