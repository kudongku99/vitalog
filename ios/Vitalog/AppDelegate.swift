import BackgroundTasks
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        SyncService.shared.startObserving()
        BackgroundSync.register()
        BackgroundSync.scheduleIfNeeded()
        return true
    }
}

enum BackgroundSync {
    static let identifier = "com.kudongku.vitalog.sync"
    private static let interval: TimeInterval = 6 * 60 * 60

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    static func scheduleIfNeeded() {
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            if !requests.contains(where: { $0.identifier == identifier }) {
                schedule()
            }
        }
    }

    private static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let completion = TaskCompletion(task)
        task.expirationHandler = { completion.finish(success: false) }
        Task {
            await SyncService.shared.sync(mode: .backgroundTask, budget: 20)
            completion.finish(success: true)
        }
    }
}

private final class TaskCompletion: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var isFinished = false

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        task.setTaskCompleted(success: success)
    }
}
