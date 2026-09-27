import AppKit
import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var model: LiveTranslateModel
    @State private var showingNewCourse = false
    @State private var newCourseName = ""
    @State private var selectedLessonID: UUID?
    @State private var showingRename = false
    @State private var lessonTitle = ""

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
                            Button { lessonTitle = lesson.title; showingRename = true } label: {
                                Image(systemName: "pencil")
                            }
                            .help("重命名课次")
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
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(segment.source).foregroundStyle(.secondary)
                                        Text(segment.translation ?? "翻译中…")
                                            .font(.body.weight(.medium))
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
                if let id = lesson?.id { model.renameLesson(id, to: lessonTitle) }
            }
            Button("取消", role: .cancel) { }
        }
    }

    private func copy(_ lesson: ArchivedLesson) {
        let lines = lesson.segments.map { "\($0.source)\n\($0.translation ?? "翻译中…")" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(lesson.title)\n\n" + lines.joined(separator: "\n\n"), forType: .string)
    }
}
