import AppKit
import SwiftUI

struct ArchiveView: View {
    private enum DeleteTarget {
        case course(UUID, String, Int)
        case lesson(UUID, String)
        case segment(UUID, UUID)
    }

    @EnvironmentObject private var model: LiveTranslateModel
    @State private var showingNewCourse = false
    @State private var newCourseName = ""
    @State private var selectedLessonID: UUID?
    @State private var showingRename = false
    @State private var lessonTitle = ""
    @State private var renamingLessonID: UUID?
    @State private var showingCourseRename = false
    @State private var courseName = ""
    @State private var renamingCourseID: UUID?
    @State private var deleteTarget: DeleteTarget?
    @State private var showingDelete = false
    @State private var editingSegmentID: UUID?
    @State private var editingLessonID: UUID?
    @State private var segmentSource = ""
    @State private var segmentTranslation = ""

    private var course: ArchivedCourse? { model.archiveLibrary.selectedCourse }

    private var lesson: ArchivedLesson? {
        guard let course else { return nil }
        return course.lessons.first(where: { $0.id == selectedLessonID }) ?? course.lessons.last
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("课程").font(.headline)
                    Spacer()
                    Button { newCourseName = ""; showingNewCourse = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建课程")
                    .disabled(model.isRunning)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                List(model.archiveLibrary.courses) { item in
                    Button {
                        model.selectCourse(item.id)
                        selectedLessonID = nil
                    } label: {
                        HStack {
                            Image(systemName: "books.vertical")
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text("\(item.lessons.count)").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(item.id == model.archiveLibrary.selectedCourseID ? Color.accentColor.opacity(0.18) : Color.clear)
                    .disabled(model.isRunning && item.id != model.archiveLibrary.selectedCourseID)
                    .contextMenu {
                        Button("重命名课程", systemImage: "pencil") {
                            renamingCourseID = item.id
                            courseName = item.name
                            showingCourseRename = true
                        }
                        Button("删除课程", systemImage: "trash", role: .destructive) {
                            deleteTarget = .course(item.id, item.name, item.lessons.count)
                            showingDelete = true
                        }
                        .disabled(model.archiveLibrary.courses.count == 1 || model.isRunning)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 200)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let course {
                    HStack {
                        Label(course.name, systemImage: "archivebox")
                            .font(.title3.bold())
                        Button {
                            renamingCourseID = course.id
                            courseName = course.name
                            showingCourseRename = true
                        } label: { Image(systemName: "pencil") }
                        .help("重命名课程")
                        .disabled(model.isRunning)
                        Button {
                            deleteTarget = .course(course.id, course.name, course.lessons.count)
                            showingDelete = true
                        } label: { Image(systemName: "trash") }
                        .help("删除课程及其所有课次")
                        .disabled(model.isRunning || model.archiveLibrary.courses.count == 1)
                        Spacer()
                        Text("\(course.lessons.count) 节课")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)
                    if !course.lessons.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(course.lessons.reversed())) { item in
                                    Button {
                                        selectedLessonID = item.id
                                    } label: {
                                        Text(item.title)
                                            .lineLimit(1)
                                            .frame(maxWidth: 180)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(item.id == lesson?.id ? .accentColor : .secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Divider()
                    }
                    if let lesson {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(lesson.title).font(.headline)
                                Text("\(lesson.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(lesson.segments.count) 段")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { renamingLessonID = lesson.id; lessonTitle = lesson.title; showingRename = true } label: {
                                Image(systemName: "pencil")
                            }
                            .help("重命名课次")
                            .disabled(model.isRunning)
                            Button {
                                deleteTarget = .lesson(lesson.id, lesson.title)
                                showingDelete = true
                            } label: { Image(systemName: "trash") }
                            .help("删除课次及其所有分段")
                            .disabled(model.isRunning)
                            Button { copy(lesson) } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("复制本节课的双语记录")
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if lesson.segments.isEmpty {
                                    ContentUnavailableView("尚无语音记录", systemImage: "waveform")
                                }
                                ForEach(lesson.segments) { segment in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(segment.source).foregroundStyle(.secondary)
                                            Text(segment.translation ?? "翻译中…")
                                                .font(.body.weight(.medium))
                                        }
                                        Spacer(minLength: 4)
                                        Button {
                                            editingLessonID = lesson.id
                                            editingSegmentID = segment.id
                                            segmentSource = segment.source
                                            segmentTranslation = segment.translation ?? ""
                                        } label: { Image(systemName: "pencil") }
                                        .help("编辑双语分段")
                                        .disabled(model.isRunning)
                                        Button {
                                            deleteTarget = .segment(lesson.id, segment.id)
                                            showingDelete = true
                                        } label: { Image(systemName: "trash") }
                                        .help("删除双语分段")
                                        .disabled(model.isRunning)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .textSelection(.enabled)
                    } else {
                        ContentUnavailableView("还没有课次", systemImage: "text.book.closed",
                                               description: Text("选择这门课程后开始录音，将自动创建并归档新课次。"))
                    }
                }
                if !model.archiveMessage.isEmpty {
                    Text(model.archiveMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("新建课程", isPresented: $showingNewCourse) {
            TextField("课程名称", text: $newCourseName)
            Button("创建") { model.addCourse(newCourseName) }
            Button("取消", role: .cancel) { }
        } message: {
            Text("开始录音前选择课程，每次录音会成为该课程的一节课。")
        }
        .alert("课次名称", isPresented: $showingRename) {
            TextField("课次名称", text: $lessonTitle)
            Button("保存") {
                if let id = renamingLessonID { model.renameLesson(id, to: lessonTitle) }
            }
            Button("取消", role: .cancel) { }
        }
        .alert("课程名称", isPresented: $showingCourseRename) {
            TextField("课程名称", text: $courseName)
            Button("保存") {
                if let id = renamingCourseID { model.renameCourse(id, to: courseName) }
            }
            Button("取消", role: .cancel) { }
        }
        .confirmationDialog(deleteTitle, isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { performDelete() }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("删除后无法撤销。")
        }
        .sheet(isPresented: Binding(get: { editingSegmentID != nil }, set: { if !$0 { editingSegmentID = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("编辑双语分段").font(.headline)
                Text("英文原文")
                TextEditor(text: $segmentSource).frame(height: 90).border(.secondary)
                Text("中文译文")
                TextEditor(text: $segmentTranslation).frame(height: 90).border(.secondary)
                HStack {
                    Spacer()
                    Button("取消") { editingSegmentID = nil }
                    Button("保存") {
                        if let lessonID = editingLessonID, let segmentID = editingSegmentID {
                            model.editSegment(segmentID, in: lessonID, source: segmentSource, translation: segmentTranslation)
                        }
                        editingSegmentID = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(segmentSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRunning)
                }
            }
            .padding(20)
            .frame(width: 480)
        }
    }

    private var deleteTitle: String {
        switch deleteTarget {
        case let .course(_, name, count): "删除课程“\(name)”及其中 \(count) 节课？"
        case let .lesson(_, title): "删除课次“\(title)”及其所有记录？"
        case .segment: "删除这条双语分段？"
        case nil: "确认删除？"
        }
    }

    private func performDelete() {
        guard let target = deleteTarget else { return }
        switch target {
        case let .course(id, _, _):
            model.deleteCourse(id)
            selectedLessonID = nil
        case let .lesson(id, _):
            model.deleteLesson(id)
            if selectedLessonID == id { selectedLessonID = nil }
        case let .segment(lessonID, segmentID):
            model.deleteSegment(segmentID, in: lessonID)
        }
        deleteTarget = nil
    }

    private func copy(_ lesson: ArchivedLesson) {
        let lines = lesson.segments.map { "\($0.source)\n\($0.translation ?? "翻译中…")" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(lesson.title)\n\n" + lines.joined(separator: "\n\n"), forType: .string)
    }
}
