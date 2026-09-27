import Foundation

/// 一次语音识别结果（含可选的机器翻译）。
struct TranscriptResult: Equatable {
    /// 识别的原文。
    var transcript: String
    /// 实时翻译的译文（未启用翻译时为 nil）。
    var translatedText: String?
    /// true 表示最终结果，false 为中间结果。
    var isFinal: Bool
    /// Deepgram endpointing 判定讲话暂停，当前话语可以提交。
    var speechFinal: Bool = false
    /// Deepgram UtteranceEnd 事件（通常不带 transcript）。
    var utteranceEnd: Bool = false
}

/// 将 Deepgram 的稳定片段与临时片段组成一条适合阅读和翻译的话语。
/// `is_final` 只代表片段稳定，不代表整句话结束。
struct LiveUtteranceAssembler {
    struct Update {
        let displayText: String
        let committedText: String?
        let startedNewUtterance: Bool
    }

    private var finalFragments: [String] = []
    private var interim = ""
    private var isBetweenUtterances = true

    mutating func consume(_ result: TranscriptResult) -> Update {
        let text = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let startedNew = isBetweenUtterances && !text.isEmpty
        if startedNew { isBetweenUtterances = false }

        if result.isFinal {
            if !text.isEmpty { finalFragments.append(text) }
            interim = ""
        } else if !result.utteranceEnd {
            interim = text
        }

        let stable = finalFragments.joined(separator: " ")
        let display = [stable, interim].filter { !$0.isEmpty }.joined(separator: " ")
        let endsSentence = stable.last.map { ".?!。？！".contains($0) } ?? false
        let isLong = stable.split(whereSeparator: \.isWhitespace).count >= 18
        let shouldCommit = result.speechFinal || result.utteranceEnd ||
            (result.isFinal && (endsSentence || isLong))
        if shouldCommit && stable.isEmpty {
            reset()
            return Update(displayText: "", committedText: nil, startedNewUtterance: startedNew)
        }
        guard shouldCommit, !stable.isEmpty else {
            return Update(displayText: display, committedText: nil, startedNewUtterance: startedNew)
        }
        finalFragments.removeAll()
        interim = ""
        isBetweenUtterances = true
        return Update(displayText: stable, committedText: stable, startedNewUtterance: startedNew)
    }

    mutating func flush() -> String? {
        let stable = finalFragments.joined(separator: " ")
        finalFragments.removeAll()
        interim = ""
        isBetweenUtterances = true
        return stable.isEmpty ? nil : stable
    }

    mutating func reset() {
        finalFragments.removeAll()
        interim = ""
        isBetweenUtterances = true
    }
}

/// 流式语音识别连接状态。
enum TranscriptionState: Equatable {
    case idle
    case connecting
    case listening
    case failed(String)
}

/// 流式语音识别 provider：接收 PCM 音频帧，回调识别与翻译结果。
protocol TranscriptionProvider: AnyObject {
    /// 建立流式连接。language / targetLanguage 为 Deepgram 语言码（如 en / zh）。
    func start(language: String, targetLanguage: String)
    /// 发送一帧 16 kHz 单声道 Int16 little-endian PCM。
    func sendAudio(_ data: Data)
    /// 断开连接并清理。
    func stop()

    /// 识别/翻译结果回调（主线程）。
    var onResult: ((TranscriptResult) -> Void)? { get set }
    /// 连接状态回调（主线程）。
    var onStateChange: ((TranscriptionState) -> Void)? { get set }
}
