import Foundation

struct BackfillProgress: Codable {
    var cutoff: Date
    var completed: Set<String> = []
    var finishedAt: Date?
    var finishedTaskIDs: Set<String>?

    func isFinished(taskIDs: Set<String>) -> Bool {
        guard finishedAt != nil, let finished = finishedTaskIDs else { return false }
        return taskIDs.isSubset(of: finished)
    }

    static func key(task: String, month: Date) -> String {
        "\(task)|\(monthFormatter.string(from: month))"
    }

    func isCompleted(task: String, month: Date) -> Bool {
        completed.contains(Self.key(task: task, month: month))
    }

    mutating func markCompleted(task: String, month: Date) {
        completed.insert(Self.key(task: task, month: month))
    }

    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

enum BackfillProgressStore {
    private static var fileURL: URL {
        let server = AppConfig.supabaseURL.host() ?? "unknown"
        return URL.applicationSupportDirectory.appending(path: "backfill-progress-\(server).json")
    }

    static func load() -> BackfillProgress? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(BackfillProgress.self, from: data)
    }

    static func save(_ progress: BackfillProgress) throws {
        try FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(progress).write(to: fileURL, options: .atomic)
    }
}
