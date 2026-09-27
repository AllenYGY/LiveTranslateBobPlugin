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
