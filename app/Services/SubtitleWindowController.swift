import AppKit
import SwiftUI

@MainActor
final class SubtitleWindowController {
    static let shared = SubtitleWindowController()
    private var panel: NSPanel?

    func show(model: LiveTranslateModel) {
        if panel == nil {
            let width: CGFloat = 900
            let height: CGFloat = 250
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let frame = NSRect(x: screen.midX - width / 2,
                               y: screen.minY + 52,
                               width: width,
                               height: height)
            let panel = NSPanel(contentRect: frame,
                                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                backing: .buffered,
                                defer: false)
            panel.title = "课堂字幕"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 600, height: 190)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: SubtitleWindowView().environmentObject(model))
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

private struct SubtitleWindowView: View {
    @EnvironmentObject private var model: LiveTranslateModel
    @AppStorage("subtitleWindowOpacity") private var backgroundOpacity = 0.85

    private var current: (source: String, translation: String)? {
        if !model.interim.isEmpty {
            return (model.interim, model.interimTranslation.isEmpty ? "识别中…" : model.interimTranslation)
        }
        guard let segment = model.segments.last else { return nil }
        return (segment.source, segment.translation ?? "翻译中…")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.isRunning ? "waveform" : "pause.fill")
                    .foregroundStyle(model.isRunning ? .green : .gray)
                Text(model.isRunning ? "LIVE · English → 中文" : "课堂字幕 · 已停止")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Image(systemName: "drop.halffull")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                Slider(value: $backgroundOpacity, in: 0.25...1.0)
                    .frame(width: 110)
                    .controlSize(.small)
                    .tint(.white)
                    .help("调整字幕背景透明度")
                Text("\(Int((backgroundOpacity * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 38, alignment: .trailing)
                Text("拖动 · 缩放")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer(minLength: 0)
            if let current {
                Text(current.source)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(current.translation)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.65)
            } else {
                Text(model.isRunning ? "等待英语语音…" : "点击主窗口「开始」后显示实时字幕")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}
