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
    @Published private(set) var archiveLibrary: ArchiveLibrary
    @Published private(set) var archiveMessage = ""
    private(set) var sessionID: String?

    private let audio = AudioCaptureManager()
    private let provider = DeepgramTranscriptionProvider(apiKey: "")
    private var assembler = LiveUtteranceAssembler()
    private var previewTask: Task<Void, Never>?
    private var generation = 0
    private let archiveRepository = ArchiveRepository()
    private var archiveWritable = true
    private var activeLessonID: UUID?

    init() {
        deepgramAPIKey = KeychainStore.read("deepgram")
        volcengineAccessKeyID = KeychainStore.read("volcengine-id")
        volcengineSecretAccessKey = KeychainStore.read("volcengine-secret")
        translationBackend = TranslationBackend(
            rawValue: UserDefaults.standard.string(forKey: "translationBackend") ?? "apple"
        ) ?? .apple
        do {
            archiveLibrary = try archiveRepository.load()
        } catch {
            archiveLibrary = .initial()
            archiveWritable = false
            archiveMessage = "归档读取失败，原文件已保留：\(error.localizedDescription)"
        }
        provider.onResult = { [weak self] result in self?.consume(result) }
        provider.onStateChange = { [weak self] state in self?.updateState(state) }
    }

    private func saveKey(_ value: String, _ account: String) {
        if !KeychainStore.save(value, for: account) {
            status = "密钥未能保存到钥匙串"
        }
    }

    func start() async {
        guard !isRunning else { return }
        guard !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请在 Bob → Services → Live Translate 填写 Deepgram API Key"
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
            var library = archiveLibrary
            activeLessonID = library.beginLesson()
            saveArchive(library)
            SubtitleWindowController.shared.show(model: self)
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
        sessionID = nil
        finishActiveLesson()
    }

    func clear() {
        segments.removeAll()
        interim = ""
        interimTranslation = ""
    }

    func addCourse(_ name: String) {
        guard !isRunning else { return }
        var library = archiveLibrary
        if library.addCourse(name) != nil { saveArchive(library) }
    }

    func selectCourse(_ id: UUID) {
        guard !isRunning else { return }
        var library = archiveLibrary
        library.selectCourse(id)
        saveArchive(library)
    }

    func renameLesson(_ id: UUID, to title: String) {
        guard !isRunning else { return }
        var library = archiveLibrary
        if library.renameLesson(id, to: title) { saveArchive(library) }
    }

    func renameCourse(_ id: UUID, to name: String) {
        guard !isRunning else { return }
        var library = archiveLibrary
        if library.renameCourse(id, to: name) { saveArchive(library) }
        else { archiveMessage = "课程名称不能为空，且不能与已有课程重复。" }
    }

    func deleteCourse(_ id: UUID) {
        guard !isRunning else { return }
        var library = archiveLibrary
        if library.deleteCourse(id) { saveArchive(library) }
    }

    func deleteLesson(_ id: UUID) {
        guard !isRunning, id != activeLessonID else { return }
        var library = archiveLibrary
        if library.deleteLesson(id) { saveArchive(library) }
    }

    func editSegment(_ id: UUID, in lessonID: UUID, source: String, translation: String) {
        guard !isRunning, lessonID != activeLessonID else { return }
        var library = archiveLibrary
        if library.editSegment(id, in: lessonID, source: source, translation: translation) { saveArchive(library) }
    }

    func deleteSegment(_ id: UUID, in lessonID: UUID) {
        guard !isRunning, lessonID != activeLessonID else { return }
        var library = archiveLibrary
        if library.deleteSegment(id, in: lessonID) { saveArchive(library) }
    }

    private func saveArchive(_ library: ArchiveLibrary) {
        archiveLibrary = library
        guard archiveWritable else { return }
        do {
            try archiveRepository.save(library)
            archiveMessage = ""
        } catch {
            archiveMessage = "归档保存失败：\(error.localizedDescription)"
        }
    }

    private func finishActiveLesson() {
        guard let id = activeLessonID else { return }
        activeLessonID = nil
        var library = archiveLibrary
        library.finishLesson(id)
        saveArchive(library)
    }

    func configureAndStart(deepgramKey: String, backend: String, accessKeyID: String, secretAccessKey: String) async -> String? {
        guard !deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "请在 Bob 服务设置中填写 Deepgram API Key"
            return nil
        }
        if isRunning { stop() }
        deepgramAPIKey = deepgramKey
        translationBackend = backend == "volcengine" ? .volcengine : .apple
        if !accessKeyID.isEmpty { volcengineAccessKeyID = accessKeyID }
        if !secretAccessKey.isEmpty { volcengineSecretAccessKey = secretAccessKey }
        clear()
        await start()
        guard isRunning else { return nil }
        let id = UUID().uuidString
        sessionID = id
        return id
    }

    func snapshot() -> [String: Any] {
        ["ok": true, "running": isRunning, "status": status,
         "segments": segments.suffix(2).map { ["source": $0.source, "translation": $0.translation ?? ""] },
         "interim": interim, "interimTranslation": interimTranslation]
    }

    func stop(session: String?) {
        guard session == nil || session == sessionID else { return }
        stop()
    }

    private func updateState(_ state: TranscriptionState) {
        switch state {
        case .idle:
            if !isRunning { status = "已停止" }
        case .connecting: status = "连接 Deepgram…"
        case .listening: status = "正在听课"
        case .failed(let message):
            if let text = assembler.flush() { commit(text) }
            audio.stop()
            isRunning = false
            status = message
            finishActiveLesson()
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
        let lessonID = activeLessonID
        if let lessonID {
            var library = archiveLibrary
            library.append(ArchivedSegment(id: segment.id, source: text, translation: nil), to: lessonID)
            saveArchive(library)
        }
        let translator = makeTranslator()
        Task { @MainActor [weak self] in
            let output: String
            do { output = try await translator.translate(text) }
            catch { output = "翻译失败：\(error.localizedDescription)" }
            guard let self else { return }
            if let index = self.segments.firstIndex(where: { $0.id == segment.id }) {
                self.segments[index].translation = output
            }
            if let lessonID {
                var library = self.archiveLibrary
                library.setTranslation(output, segmentID: segment.id, lessonID: lessonID)
                self.saveArchive(library)
            }
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

}

@main
struct LiveTranslateApp: App {
    @StateObject private var model: LiveTranslateModel
    private let bridge: LocalBridge

    init() {
        let model = LiveTranslateModel()
        _model = StateObject(wrappedValue: model)
        bridge = LocalBridge(model: model)
        bridge.start()
    }

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
                    SubtitleWindowController.shared.show(model: model)
                } label: {
                    Label("课堂字幕", systemImage: "captions.bubble")
                }
                .help("打开独立字幕窗口，可拖动并置于课件上方")
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
                Label("实时记录", systemImage: "text.book.closed").tag(0)
                Label("课程归档", systemImage: "archivebox").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            if selectedTab == 0 { history }
            else { ArchiveView().environmentObject(model) }
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            HStack {
                Label("完整记录 · English → 简体中文", systemImage: "text.book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("课程", selection: Binding(
                    get: { model.archiveLibrary.selectedCourseID },
                    set: { model.selectCourse($0) }
                )) {
                    ForEach(model.archiveLibrary.courses) { course in
                        Text(course.name).tag(course.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 190)
                .disabled(model.isRunning)
                Text(model.translationBackend.label).font(.caption).foregroundStyle(.secondary)
                Button { model.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("清空当前显示；已归档课次仍保留")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.segments.isEmpty && model.interim.isEmpty {
                            Label("在 Bob 配置密钥并输入 live，或点击开始。字幕将显示在独立窗口。", systemImage: "captions.bubble")
                                .foregroundStyle(.secondary)
                        }
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
}
