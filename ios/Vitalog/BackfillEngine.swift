import Foundation
import HealthKit
import Observation
import UIKit

@MainActor
@Observable
final class BackfillEngine {
    enum Phase: Equatable {
        case idle
        case preparing
        case running(month: Date)
        case stopped
        case waitingForUnlock
        case paused(reason: String)
        case finished
    }

    struct TaskStatus: Identifiable {
        let id: String
        let name: String
        let totalMonths: Int
        var doneMonths: Int
        var uploaded = 0

        var isDone: Bool { doneMonths >= totalMonths }
    }

    private struct Plan {
        let task: any BackfillTask
        let firstMonth: Date
    }

    private(set) var phase: Phase = .idle
    private(set) var statuses: [TaskStatus] = []
    private(set) var remainingMonths = 0
    private(set) var finishedAt: Date?

    var isRunning: Bool { runner != nil }
    var isFinished: Bool { finishedAt != nil }

    private let reader = HealthReader()
    private let uploader = Uploader()
    private let calendar = Calendar.current
    private var runner: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private var tasks: [any BackfillTask] {
        let stats: [any BackfillTask] = HealthCatalog.quantities.map(DailyStatsTask.init(spec:))
        let activity: [any BackfillTask] = [WorkoutsTask(), ActivitySummariesTask()]
        let categories: [any BackfillTask] = HealthCatalog.categories.map(CategorySamplesTask.init(spec:))
        let others: [any BackfillTask] = OtherSampleTasks.all
        let quantities: [any BackfillTask] = HealthCatalog.quantities.map(QuantitySamplesTask.init(spec:))
        return stats + activity + categories + others + quantities
    }

    init() {
        if let progress = BackfillProgressStore.load(), progress.isFinished(taskIDs: Set(tasks.map { $0.id })) {
            finishedAt = progress.finishedAt
        }
        let center = NotificationCenter.default
        for name in [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeIfWaiting() }
            })
        }
    }

    func start() {
        guard runner == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        runner = Task {
            await run()
            runner = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func stop() {
        runner?.cancel()
    }

    func requestPerObjectAccess() async -> String {
        do {
            try await reader.requestPerObjectAccess()
            return "복약과 시력 처방 권한 요청을 마쳤습니다."
        } catch {
            return "복약과 시력 처방 권한 요청 실패: \(error.localizedDescription)"
        }
    }

    private func resumeIfWaiting() {
        guard phase == .waitingForUnlock, UIApplication.shared.isProtectedDataAvailable else { return }
        start()
    }

    private func run() async {
        do {
            phase = .preparing
            try await reader.requestAccess()
            var progress = BackfillProgressStore.load() ?? BackfillProgress(cutoff: Date())
            progress.finishedAt = nil
            progress.finishedTaskIDs = nil
            finishedAt = nil
            try BackfillProgressStore.save(progress)
            try await uploader.upsert([reader.characteristics()], into: "characteristics", onConflict: "user_id")

            let plans = try await makePlans(cutoff: progress.cutoff)
            statuses = plans.map { plan in
                let months = months(from: plan.firstMonth, to: progress.cutoff)
                return TaskStatus(
                    id: plan.task.id,
                    name: plan.task.name,
                    totalMonths: months.count,
                    doneMonths: months.filter { progress.isCompleted(task: plan.task.id, month: $0) }.count
                )
            }

            guard let oldest = plans.map(\.firstMonth).min() else {
                try markFinished(&progress)
                return
            }

            let allMonths = months(from: oldest, to: progress.cutoff).reversed()
            remainingMonths = allMonths.count
            for month in allMonths {
                phase = .running(month: month)
                let interval = DateInterval(start: month, end: min(nextMonth(month), progress.cutoff))
                for (index, plan) in plans.enumerated() where plan.firstMonth <= month {
                    guard !progress.isCompleted(task: plan.task.id, month: month) else { continue }
                    try Task.checkCancellation()
                    let uploaded = try await plan.task.run(in: interval, reader: reader, uploader: uploader)
                    progress.markCompleted(task: plan.task.id, month: month)
                    try BackfillProgressStore.save(progress)
                    statuses[index].doneMonths += 1
                    statuses[index].uploaded += uploaded
                    if month == plan.firstMonth {
                        await uploader.log(type: plan.task.name, inserted: statuses[index].uploaded)
                    }
                }
                remainingMonths -= 1
            }
            try markFinished(&progress)
        } catch {
            if Task.isCancelled || error is CancellationError {
                phase = .stopped
            } else if (error as? HKError)?.code == .errorDatabaseInaccessible {
                phase = .waitingForUnlock
            } else {
                phase = .paused(reason: error.localizedDescription)
                await uploader.log(type: nil, inserted: 0, error: error.localizedDescription)
            }
        }
    }

    private func markFinished(_ progress: inout BackfillProgress) throws {
        progress.finishedAt = Date()
        progress.finishedTaskIDs = Set(tasks.map { $0.id })
        try BackfillProgressStore.save(progress)
        finishedAt = progress.finishedAt
        phase = .finished
    }

    private func makePlans(cutoff: Date) async throws -> [Plan] {
        var plans: [Plan] = []
        for task in tasks {
            try Task.checkCancellation()
            if let earliest = try await task.earliestDate(reader: reader, cutoff: cutoff) {
                plans.append(Plan(task: task, firstMonth: monthStart(earliest)))
            }
        }
        return plans
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    private func nextMonth(_ month: Date) -> Date {
        calendar.date(byAdding: .month, value: 1, to: month)!
    }

    private func months(from first: Date, to cutoff: Date) -> [Date] {
        var result: [Date] = []
        var month = first
        while month < cutoff {
            result.append(month)
            month = nextMonth(month)
        }
        return result
    }
}
