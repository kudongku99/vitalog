import Foundation
import HealthKit
import Supabase

final class Uploader {
    static let batchSize = 1000
    private static let retryDelays: [UInt64] = [1, 2, 4, 8, 16, 32]

    private var sourceIds: [SourceKey: Int] = [:]

    func sourceIds(for samples: [HKSample]) async throws -> [SourceKey: Int] {
        let missing = Set(samples.map(SourceKey.init(sample:))).subtracting(sourceIds.keys)
        if !missing.isEmpty {
            let records: [SourceRecord] = try await withRetry {
                try await supabase.from("sources")
                    .upsert(Array(missing), onConflict: "user_id,bundle_id,name,product_type,device_model")
                    .select("id,bundle_id,name,product_type,device_model")
                    .execute()
                    .value
            }
            for record in records {
                sourceIds[record.key] = record.id
            }
        }
        return sourceIds
    }

    func upsert<Row: Encodable>(_ rows: [Row], into table: String, onConflict: String) async throws {
        var start = 0
        while start < rows.count {
            let batch = Array(rows[start..<min(start + Self.batchSize, rows.count)])
            try await withRetry {
                try await supabase.from(table)
                    .upsert(batch, onConflict: onConflict, returning: .minimal)
                    .execute()
            }
            start += Self.batchSize
        }
    }

    func delete(uuids: [UUID], from table: String) async throws {
        var start = 0
        while start < uuids.count {
            let batch = uuids[start..<min(start + Self.batchSize, uuids.count)].map(\.uuidString)
            try await withRetry {
                try await supabase.from(table)
                    .delete(returning: .minimal)
                    .in("uuid", values: batch)
                    .execute()
            }
            start += Self.batchSize
        }
    }

    func log(mode: String = "backfill", type: String?, inserted: Int, deleted: Int = 0, error: String? = nil) async {
        let row = SyncLogRow(mode: mode, type: type, inserted: inserted, deleted: deleted, error: error)
        _ = try? await supabase.from("sync_log").insert(row, returning: .minimal).execute()
    }

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        for delay in Self.retryDelays {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
        return try await operation()
    }
}
