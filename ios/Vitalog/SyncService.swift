import Foundation
import HealthKit

actor SyncService {
    enum Mode: String {
        case observer
        case backgroundTask = "background_task"
        case manual
    }

    static let shared = SyncService()

    private static let pageSize = 500
    private static let catchUpPageSize = 5000
    private static let overlap: TimeInterval = 2 * 24 * 60 * 60
    private static let immediateTypes: Set<HKSampleType> = [.workoutType(), HKCategoryType(.sleepAnalysis)]
    private static let unobservableTypes: Set<HKSampleType> = [.visionPrescriptionType()]

    static var tasks: [any SampleSyncTask] {
        let workouts: [any SampleSyncTask] = [WorkoutsTask()]
        let categories: [any SampleSyncTask] = HealthCatalog.categories.map(CategorySamplesTask.init(spec:))
        let others: [any SampleSyncTask] = OtherSampleTasks.all
        let quantities: [any SampleSyncTask] = HealthCatalog.quantities.map(QuantitySamplesTask.init(spec:))
        return workouts + categories + others + quantities
    }

    private struct TypeResult {
        let name: String
        var inserted = 0
        var deleted = 0
    }

    private nonisolated let observerStore = HKHealthStore()
    private let reader = HealthReader()
    private let uploader = Uploader()
    private let calendar = Calendar.current
    private var current: Task<SyncState, Never>?

    nonisolated func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = Self.tasks.map(\.sampleType).filter { !Self.unobservableTypes.contains($0) }
        let query = HKObserverQuery(
            queryDescriptors: types.map { HKQueryDescriptor(sampleType: $0, predicate: nil) }
        ) { _, updatedTypes, completion, error in
            guard error == nil, let updatedTypes, !updatedTypes.isEmpty else {
                completion()
                return
            }
            Task {
                await self.sync(types: updatedTypes, mode: .observer, budget: 20)
                completion()
            }
        }
        observerStore.execute(query)
        for type in types {
            let frequency: HKUpdateFrequency = Self.immediateTypes.contains(type) ? .immediate : .daily
            observerStore.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }

    @discardableResult
    func sync(types: Set<HKSampleType>? = nil, mode: Mode, budget: TimeInterval) async -> SyncState {
        let previous = current
        let task = Task {
            _ = await previous?.value
            return await perform(types: types, mode: mode, budget: budget)
        }
        current = task
        return await task.value
    }

    private func perform(types: Set<HKSampleType>?, mode: Mode, budget: TimeInterval) async -> SyncState {
        var state = SyncStateStore.load()
        guard (try? await supabase.auth.session) != nil else { return state }

        let deadline = Date().addingTimeInterval(budget)
        var results: [TypeResult] = []
        var changedQuantities: [String: (spec: QuantitySpec, earliest: Date?)] = [:]
        var failure: Error?

        do {
            let catchUpStart = try backfillCutoff().addingTimeInterval(-Self.overlap)
            for task in Self.tasks where types?.contains(task.sampleType) ?? true {
                guard Date() < deadline else { break }
                var result = TypeResult(name: task.name)
                var earliest: Date?
                defer {
                    if result.inserted + result.deleted > 0 {
                        results.append(result)
                    }
                    if let spec = (task as? QuantitySamplesTask)?.spec, earliest != nil || result.deleted > 0 {
                        changedQuantities[spec.name] = (spec, earliest)
                    }
                }
                while true {
                    let isCaughtUp = state.caughtUpTypes.contains(task.id)
                    let limit = isCaughtUp ? Self.pageSize : Self.catchUpPageSize
                    let changes = try await reader.changes(of: task.sampleType, after: state.anchor(for: task.id), limit: limit)
                    let added = isCaughtUp ? changes.added : changes.added.filter { $0.startDate >= catchUpStart }
                    if !added.isEmpty {
                        result.inserted += try await task.upload(added, reader: reader, uploader: uploader)
                        earliest = ([earliest].compactMap { $0 } + added.map(\.startDate)).min()
                    }
                    if !changes.deleted.isEmpty {
                        try await uploader.delete(uuids: changes.deleted, from: task.table)
                        result.deleted += changes.deleted.count
                    }
                    let isLastPage = changes.added.count + changes.deleted.count < limit
                    try state.setAnchor(changes.anchor, for: task.id)
                    if isLastPage {
                        state.caughtUpTypes.insert(task.id)
                    }
                    try SyncStateStore.save(state)
                    if isLastPage || Date() >= deadline { break }
                }
            }
            try await refreshRecentStats(changedQuantities.values.map { $0 })
        } catch {
            failure = error
        }

        if (failure as? HKError)?.code == .errorDatabaseInaccessible {
            return state
        }
        for result in results {
            await uploader.log(mode: mode.rawValue, type: result.name, inserted: result.inserted, deleted: result.deleted)
        }
        if let failure {
            await uploader.log(mode: mode.rawValue, type: nil, inserted: 0, error: failure.localizedDescription)
        } else if results.isEmpty && mode != .manual {
            await uploader.log(mode: mode.rawValue, type: nil, inserted: 0)
        }

        state.lastSyncAt = Date()
        state.lastMode = mode.rawValue
        state.lastError = failure?.localizedDescription
        if !results.isEmpty {
            let change = SyncState.Change(
                at: Date(),
                mode: mode.rawValue,
                inserted: results.reduce(0) { $0 + $1.inserted },
                deleted: results.reduce(0) { $0 + $1.deleted },
                types: results.map(\.name)
            )
            state.recentChanges = Array(([change] + state.recentChanges).prefix(5))
        }
        try? SyncStateStore.save(state)
        await MainActor.run {
            NotificationCenter.default.post(name: .syncStateDidChange, object: nil)
        }
        return state
    }

    private func refreshRecentStats(_ quantities: [(spec: QuantitySpec, earliest: Date?)]) async throws {
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        for (spec, earliest) in quantities {
            let start = min(yesterday, earliest.map(calendar.startOfDay(for:)) ?? yesterday)
            _ = try await DailyStatsTask(spec: spec).run(
                in: DateInterval(start: start, end: now),
                reader: reader,
                uploader: uploader
            )
        }
        _ = try await ActivitySummariesTask().run(
            in: DateInterval(start: yesterday, end: now),
            reader: reader,
            uploader: uploader
        )
    }

    private func backfillCutoff() throws -> Date {
        if let progress = BackfillProgressStore.load() {
            return progress.cutoff
        }
        let progress = BackfillProgress(cutoff: Date())
        try BackfillProgressStore.save(progress)
        return progress.cutoff
    }
}
