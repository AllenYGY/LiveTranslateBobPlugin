import AVFoundation
import SwiftUI

struct CaptionSegment: Identifiable {
    let id = UUID()
    let source: String
    var translation: String?
}

@MainActor
final class LiveTranslateModel: ObservableObject {
    @Published var deepgramAPIKey: String {
        didSet { if oldValue != deepgramAPIKey { saveKey(deepgramAPIKey, "deepgram") } }
    }
    @Published var volcengineAccessKeyID: String {
        didSet { if oldValue != volcengineAccessKeyID { saveKey(volcengineAccessKeyID, "volcengine-id") } }
    }
    @Published var volcengineSecretAccessKey: String {
        didSet { if oldValue != volcengineSecretAccessKey { saveKey(volcengineSecretAccessKey, "volcengine-secret") } }
    }
    @Published var translationBackend: TranslationBackend {
        didSet { UserDefaults.standard.set(translationBackend.rawValue, forKey: "translationBackend") }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var status = "准备就绪"
    @Published private(set) var segments: [CaptionSegment] = []
    @Published private(set) var interim = ""
    @Published private(set) var interimTranslation = ""
    @Published private(set) var settingsMessage = ""

    private let audio = AudioCaptureManager()
    private let provider = DeepgramTranscriptionProvider(apiKey: "")
    private var assembler = LiveUtteranceAssembler()
    private var previewTask: Task<Void, Never>?
    private var generation = 0

    init() {
        deepgramAPIKey = KeychainStore.read("deepgram")
        volcengineAccessKeyID = KeychainStore.read("volcengine-id")
        volcengineSecretAccessKey = KeychainStore.read("volcengine-secret")
        translationBackend = TranslationBackend(
            rawValue: UserDefaults.standard.string(forKey: "translationBackend") ?? "apple"
        ) ?? .apple
        provider.onResult = { [weak self] result in self?.consume(result) }
        provider.onStateChange = { [weak self] state in self?.updateState(state) }
    }

    private func saveKey(_ value: String, _ account: String) {
        if !KeychainStore.save(value, for: account) {
            settingsMessage = "密钥未能保存到钥匙串，请重试。"
        }
    }

    func start() async {
        guard !isRunning else { return }
        guard !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请先在设置中填写 Deepgram API Key"
            return
        }
        guard await audio.requestPermission() else {
            status = "请在系统设置中允许麦克风权限"
            return
        }
        generation += 1
        assembler.reset()
        interim = ""
        interimTranslation = ""
        provider.apiKey = deepgramAPIKey
        provider.start(language: "en", targetLanguage: "zh")
        let provider = self.provider
        audio.onAudioData = { [weak provider] data in provider?.sendAudio(data) }
        do {
            try audio.start()
            isRunning = true
            status = "连接 Deepgram…"
        } catch {
            provider.stop()
            audio.stop()
            status = "麦克风启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        guard isRunning else { return }
        generation += 1
        previewTask?.cancel()
        if let text = assembler.flush() { commit(text) }
        audio.stop()
        provider.stop()
        isRunning = false
        interim = ""
        interimTranslation = ""
        status = "已停止"
    }

    func clear() {
        segments.removeAll()
        interim = ""
        interimTranslation = ""
    }

    private func updateState(_ state: TranscriptionState) {
        switch state {
        case .idle:
            if !isRunning { status = "已停止" }
        case .connecting: status = "连接 Deepgram…"
        case .listening: status = "正在听课"
        case .failed(let message):
            audio.stop()
            isRunning = false
            status = message
        }
    }

    private func consume(_ result: TranscriptResult) {
        guard isRunning else { return }
        let update = assembler.consume(result)
        interim = update.displayText
        if let text = update.committedText {
            previewTask?.cancel()
            interim = ""
            interimTranslation = ""
            commit(text)
        } else if !update.displayText.isEmpty {
            schedulePreview(update.displayText)
        }
    }

    private func schedulePreview(_ text: String) {
        previewTask?.cancel()
        let token = generation
        let translator = makeTranslator()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let self, !Task.isCancelled, self.generation == token, self.interim == text else { return }
            if let output = try? await translator.translate(text),
               !Task.isCancelled, self.generation == token, self.interim == text {
                self.interimTranslation = output
            }
        }
    }

    private func commit(_ text: String) {
        let segment = CaptionSegment(source: text)
        segments.append(segment)
        if segments.count > 200 { segments.removeFirst(segments.count - 200) }
        let translator = makeTranslator()
        Task { @MainActor [weak self] in
            let output: String
            do { output = try await translator.translate(text) }
            catch { output = "翻译失败：\(error.localizedDescription)" }
            guard let self, let index = self.segments.firstIndex(where: { $0.id == segment.id }) else { return }
            self.segments[index].translation = output
        }
    }

    private func makeTranslator() -> any LiveTextTranslator {
        switch translationBackend {
        case .apple: AppleLiveTranslator()
        case .volcengine: VolcengineLiveTranslator(
            accessKeyID: volcengineAccessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: volcengineSecretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        }
    }

    func testDeepgram() async {
        let key = deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { settingsMessage = "请先填写 Deepgram API Key"; return }
        var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/self")!)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            settingsMessage = code == 200 ? "Deepgram 连接成功" : "Deepgram 验证失败（HTTP \(code)）"
        } catch {
            settingsMessage = "Deepgram 无法连接：\(error.localizedDescription)"
        }
    }

    func testTranslation() async {
        do {
            let result = try await makeTranslator().translate("Hello class.")
            settingsMessage = "翻译成功：\(result)"
        } catch {
            settingsMessage = "翻译测试失败：\(error.localizedDescription)"
        }
    }
}

@main
struct LiveTranslateApp: App {
    @StateObject private var model = LiveTranslateModel()

    var body: some Scene {
        WindowGroup("Live Translate") {
            LiveTranslateView()
                .environmentObject(model)
                .frame(minWidth: 670, minHeight: 560)
        }
        .defaultSize(width: 860, height: 680)
    }
}

private struct LiveTranslateView: View {
    @EnvironmentObject private var model: LiveTranslateModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Live Translate", systemImage: "waveform.badge.mic")
                    .font(.title2.bold())
                Spacer()
                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    if model.isRunning { model.stop() }
                    else { Task { await model.start() } }
                } label: {
                    Label(model.isRunning ? "停止" : "开始", systemImage: model.isRunning ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRunning ? .red : .accentColor)
            }
            .padding()
            Picker("", selection: $selectedTab) {
                Label("实时字幕", systemImage: "captions.bubble").tag(0)
                Label("设置", systemImage: "gearshape").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if selectedTab == 0 { captions }
            else { settings }
        }
        .onChange(of: model.status) { _, newValue in
            if newValue.contains("Deepgram API Key") { selectedTab = 1 }
        }
    }

    private var captions: some View {
        VStack(spacing: 0) {
            HStack {
                Text("English → 简体中文").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.translationBackend.label).font(.caption).foregroundStyle(.secondary)
                Button { model.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("清空字幕")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.segments) { segment in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(segment.source).font(.body)
                                Text(segment.translation ?? "翻译中…")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            .id(segment.id)
                        }
                        if !model.interim.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.interim).foregroundStyle(.secondary)
                                if !model.interimTranslation.isEmpty {
                                    Text(model.interimTranslation).foregroundStyle(.tint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("interim")
                        }
                    }
                    .padding()
                }
                .onChange(of: model.segments.count) { _, _ in
                    if let id = model.segments.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
        }
    }

    private var settings: some View {
        Form {
            Section("语音转文字 · Deepgram") {
                SecureField("Deepgram API Key", text: $model.deepgramAPIKey)
                    .textContentType(.password)
                Button("验证 Deepgram") { Task { await model.testDeepgram() } }
                Text("英语麦克风音频直接发送到 Deepgram Nova-3。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("实时译文") {
                Picker("翻译引擎", selection: $model.translationBackend) {
                    ForEach(TranslationBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                Text("默认 Apple System Translate，无需 API Key；需 macOS 26+ 和已安装英中语言包。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.translationBackend == .volcengine {
                    SecureField("火山 Access Key ID", text: $model.volcengineAccessKeyID)
                    SecureField("火山 Secret Access Key", text: $model.volcengineSecretAccessKey)
                }
                Button("测试翻译") { Task { await model.testTranslation() } }
            }
            if !model.settingsMessage.isEmpty {
                Text(model.settingsMessage).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
