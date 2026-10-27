import Foundation
import HealthKit

extension Notification.Name {
    static let syncStateDidChange = Notification.Name("syncStateDidChange")
}

struct SyncState: Codable {
    struct Change: Codable, Identifiable {
        let at: Date
        let mode: String
        let inserted: Int
        let deleted: Int
        let types: [String]

        var id: Date { at }
    }

    var anchors: [String: Data] = [:]
    var caughtUpTypes: Set<String> = []
    var lastSyncAt: Date?
    var lastMode: String?
    var lastError: String?
    var recentChanges: [Change] = []

    func anchor(for key: String) throws -> HKQueryAnchor? {
        guard let data = anchors[key] else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    mutating func setAnchor(_ anchor: HKQueryAnchor, for key: String) throws {
        anchors[key] = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }
}

enum SyncStateStore {
    private static var fileURL: URL {
        let server = AppConfig.supabaseURL.host() ?? "unknown"
        return URL.applicationSupportDirectory.appending(path: "sync-state-\(server).json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    static func save(_ state: SyncState) throws {
        try FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }
}
