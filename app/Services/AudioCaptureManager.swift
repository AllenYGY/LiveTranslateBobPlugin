import AVFoundation
import Foundation

/// 麦克风采集：AVAudioEngine 输入 → 16 kHz 单声道 Int16 little-endian PCM。
/// Deepgram 流式识别需要该格式（encoding=linear16&sample_rate=16000&channels=1）。
final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    /// 每帧转换好的 PCM 数据回调（音频线程）。
    var onAudioData: ((Data) -> Void)?

    var isRunning: Bool { engine.isRunning }

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    /// 请求麦克风权限（Info.plist 需 NSMicrophoneUsageDescription）。
    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        let inputNode = engine.inputNode
        // 幂等：先移除可能残留的旧 tap。重复 installTap 会抛 NSException
        // （AVAE: CreateRecordingTap: (nullptr == Tap())），Swift 无法捕获，直接崩溃。
        inputNode.removeTap(onBus: 0)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw TranscriptionError.audioSetup("无法读取麦克风输入格式，请确认已插入/允许麦克风")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw TranscriptionError.audioSetup("无法创建音频格式转换器")
        }
        self.converter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter,
                  let out = Self.convert(buffer, using: converter, to: self.targetFormat) else {
                return
            }
            self.onAudioData?(Self.toPCM16(out))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        converter = nil
    }

    // MARK: - Conversion helpers

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard buffer.format.sampleRate > 0 else { return nil }
        let ratio = buffer.format.sampleRate / targetFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) / ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }
        var inputDone = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, outStatus in
            if inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputDone = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return out
    }

    private static func toPCM16(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channel = buffer.floatChannelData else { return Data() }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return Data() }
        var samples = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let value = max(-1.0, min(1.0, channel[0][i]))
            samples[i] = Int16(value * 32767.0)
        }
        return samples.withUnsafeBytes { Data($0) }
    }
}

/// 音频/转录相关的本地错误。
enum TranscriptionError: LocalizedError {
    case audioSetup(String)

    var errorDescription: String? {
        switch self {
        case .audioSetup(let message):
            return message
        }
    }
}
