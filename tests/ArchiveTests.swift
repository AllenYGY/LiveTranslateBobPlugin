import Foundation

@main
struct ArchiveTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = ArchiveRepository(url: folder.appendingPathComponent("archives.json"))
        var library = try repo.load()
        precondition(library.courses.count == 1)
        precondition(library.selectedCourse?.name == "未分类")
        let courseID = library.addCourse("  生物学  ")!
        precondition(library.selectedCourseID == courseID)
        precondition(library.addCourse("生物学") == nil)
        let lessonID = library.beginLesson()!
        let segmentID = UUID()
        library.append(ArchivedSegment(id: segmentID, source: "Hello class.", translation: nil), to: lessonID)
        try repo.save(library) // Checkpoint before translation completes.
        library.setTranslation("同学们好。", segmentID: segmentID, lessonID: lessonID)
        library.finishLesson(lessonID)
        library.renameLesson(lessonID, to: "第一讲")
        try repo.save(library)
        let restored = try repo.load()
        let lesson = restored.selectedCourse!.lessons[0]
        precondition(lesson.title == "第一讲")
        precondition(lesson.endedAt != nil)
        precondition(lesson.segments[0].source == "Hello class.")
        precondition(lesson.segments[0].translation == "同学们好。")
        precondition(library.renameCourse(courseID, to: "  生物学导论  "))
        precondition(!library.renameCourse(courseID, to: "未分类"))
        precondition(!library.renameCourse(courseID, to: "   "))
        precondition(library.editSegment(segmentID, in: lessonID, source: "  Welcome.  ", translation: "  欢迎。  "))
        precondition(!library.editSegment(segmentID, in: lessonID, source: " ", translation: ""))
        try repo.save(library)
        let edited = try repo.load()
        precondition(edited.selectedCourse?.name == "生物学导论")
        precondition(edited.selectedCourse?.lessons[0].segments[0].source == "Welcome.")
        precondition(edited.selectedCourse?.lessons[0].segments[0].translation == "欢迎。")
        precondition(library.deleteSegment(segmentID, in: lessonID))
        precondition(!library.deleteSegment(segmentID, in: lessonID))
        precondition(library.selectedCourse?.lessons[0].segments.isEmpty == true)
        let secondSegment = UUID()
        library.append(ArchivedSegment(id: secondSegment, source: "Next.", translation: "下一段。"), to: lessonID)
        precondition(library.deleteLesson(lessonID))
        precondition(!library.deleteLesson(lessonID))
        precondition(library.selectedCourse?.lessons.isEmpty == true)
        let anotherLesson = library.beginLesson()!
        library.append(ArchivedSegment(id: UUID(), source: "Cascade.", translation: nil), to: anotherLesson)
        precondition(library.deleteCourse(courseID))
        precondition(library.selectedCourse?.name == "未分类")
        precondition(!library.deleteCourse(library.selectedCourseID))
        try repo.save(library)
        let afterDelete = try repo.load()
        precondition(afterDelete.courses.count == 1)
        precondition(afterDelete.selectedCourse?.lessons.isEmpty == true)
        let permissions = try FileManager.default.attributesOfItem(atPath: repo.url.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        try Data("not json".utf8).write(to: repo.url)
        do {
            _ = try repo.load()
            preconditionFailure("Corrupt archive must not load silently")
        } catch { /* original file remains untouched */ }
        let original = try Data(contentsOf: repo.url)
        precondition(String(data: original, encoding: .utf8) == "not json")
        print("Archive persistence tests passed")
    }
}
