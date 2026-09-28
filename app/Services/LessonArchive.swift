import Foundation

struct ArchivedSegment: Codable, Identifiable {
    let id: UUID
    let source: String
    var translation: String?
}

struct ArchivedLesson: Codable, Identifiable {
    let id: UUID
    var title: String
    let startedAt: Date
    var endedAt: Date?
    var segments: [ArchivedSegment]
}

struct ArchivedCourse: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var lessons: [ArchivedLesson]
}

struct ArchiveLibrary: Codable {
    let schemaVersion: Int
    var courses: [ArchivedCourse]
    var selectedCourseID: UUID

    static func initial(now: Date = Date()) -> ArchiveLibrary {
        let course = ArchivedCourse(id: UUID(), name: "未分类", createdAt: now, lessons: [])
        return ArchiveLibrary(schemaVersion: 1, courses: [course], selectedCourseID: course.id)
    }

    var selectedCourse: ArchivedCourse? {
        courses.first { $0.id == selectedCourseID }
    }

    @discardableResult
    mutating func addCourse(_ rawName: String, now: Date = Date()) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !courses.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        let course = ArchivedCourse(id: UUID(), name: name, createdAt: now, lessons: [])
        courses.append(course)
        selectedCourseID = course.id
        return course.id
    }

    mutating func selectCourse(_ id: UUID) {
        if courses.contains(where: { $0.id == id }) { selectedCourseID = id }
    }

    @discardableResult
    mutating func renameCourse(_ id: UUID, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = courses.firstIndex(where: { $0.id == id }),
              !courses.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        courses[index].name = name
        return true
    }

    @discardableResult
    mutating func deleteCourse(_ id: UUID) -> Bool {
        guard courses.count > 1, let index = courses.firstIndex(where: { $0.id == id }) else { return false }
        courses.remove(at: index)
        if selectedCourseID == id { selectedCourseID = courses[0].id }
        return true
    }

    @discardableResult
    mutating func beginLesson(now: Date = Date()) -> UUID? {
        guard let index = courses.firstIndex(where: { $0.id == selectedCourseID }) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let number = courses[index].lessons.count + 1
        let lesson = ArchivedLesson(id: UUID(),
                                    title: "第 \(number) 节 · \(formatter.string(from: now))",
                                    startedAt: now,
                                    endedAt: nil,
                                    segments: [])
        courses[index].lessons.append(lesson)
        return lesson.id
    }

    mutating func append(_ segment: ArchivedSegment, to lessonID: UUID) {
        guard let location = lessonLocation(lessonID) else { return }
        courses[location.course].lessons[location.lesson].segments.append(segment)
    }

    mutating func setTranslation(_ text: String, segmentID: UUID, lessonID: UUID) {
        guard let location = lessonLocation(lessonID),
              let segment = courses[location.course].lessons[location.lesson].segments.firstIndex(where: { $0.id == segmentID }) else { return }
        courses[location.course].lessons[location.lesson].segments[segment].translation = text
    }

    mutating func finishLesson(_ id: UUID, now: Date = Date()) {
        guard let location = lessonLocation(id) else { return }
        courses[location.course].lessons[location.lesson].endedAt = now
    }

    @discardableResult
    mutating func renameLesson(_ id: UUID, to rawTitle: String) -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let location = lessonLocation(id) else { return false }
        courses[location.course].lessons[location.lesson].title = title
        return true
    }

    @discardableResult
    mutating func deleteLesson(_ id: UUID) -> Bool {
        guard let location = lessonLocation(id) else { return false }
        courses[location.course].lessons.remove(at: location.lesson)
        return true
    }

    @discardableResult
    mutating func editSegment(_ id: UUID, in lessonID: UUID, source rawSource: String, translation rawTranslation: String) -> Bool {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, let location = lessonLocation(lessonID),
              let index = courses[location.course].lessons[location.lesson].segments.firstIndex(where: { $0.id == id }) else { return false }
        courses[location.course].lessons[location.lesson].segments[index] = ArchivedSegment(
            id: id, source: source, translation: rawTranslation.trimmingCharacters(in: .whitespacesAndNewlines))
        return true
    }

    @discardableResult
    mutating func deleteSegment(_ id: UUID, in lessonID: UUID) -> Bool {
        guard let location = lessonLocation(lessonID),
              let index = courses[location.course].lessons[location.lesson].segments.firstIndex(where: { $0.id == id }) else { return false }
        courses[location.course].lessons[location.lesson].segments.remove(at: index)
        return true
    }

    private func lessonLocation(_ id: UUID) -> (course: Int, lesson: Int)? {
        for course in courses.indices {
            if let lesson = courses[course].lessons.firstIndex(where: { $0.id == id }) {
                return (course, lesson)
            }
        }
        return nil
    }
}

final class ArchiveRepository {
    let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = support.appendingPathComponent("LiveTranslate", isDirectory: true)
                .appendingPathComponent("archives.json")
        }
    }

    func load() throws -> ArchiveLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return .initial() }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(ArchiveLibrary.self, from: data)
        guard library.schemaVersion == 1 else { throw ArchiveRepositoryError.unsupportedVersion }
        guard !library.courses.isEmpty,
              library.courses.contains(where: { $0.id == library.selectedCourseID }) else {
            throw ArchiveRepositoryError.invalidStructure
        }
        return library
    }

    func save(_ library: ArchiveLibrary) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum ArchiveRepositoryError: LocalizedError {
    case unsupportedVersion
    case invalidStructure

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "归档文件版本比当前应用更新，已保留原文件而未覆盖。"
        case .invalidStructure: "归档文件缺少有效课程，已保留原文件而未覆盖。"
        }
    }
}
