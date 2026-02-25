import Foundation

public final class AgentToastStore {
    private var toastsByID: [String: AgentToastItem] = [:]
    private var activeToastIDByTaskKey: [String: String] = [:]
    private var dismissedTaskKeys: Set<String> = []
    private let autoHideDoneAfter: TimeInterval

    public init(autoHideDoneAfter: TimeInterval = 4) {
        self.autoHideDoneAfter = autoHideDoneAfter
    }

    public func apply(event: ClaudeQueueTaskEvent) {
        guard let taskKey = event.taskKey else { return }
        let title = normalizedTitle(from: event)

        switch event.kind {
        case .enqueue:
            upsertRunningToast(taskKey: taskKey, title: title, at: event.timestamp)
        case .remove:
            finishToast(taskKey: taskKey, title: title, at: event.timestamp)
        }
    }

    public func dismissToast(id: String) {
        guard let toast = toastsByID.removeValue(forKey: id) else { return }
        if toast.status == .running {
            dismissedTaskKeys.insert(toast.taskKey)
        }
        if activeToastIDByTaskKey[toast.taskKey] == id {
            activeToastIDByTaskKey.removeValue(forKey: toast.taskKey)
        }
    }

    public func tick(now: Date = Date()) {
        for (id, toast) in toastsByID {
            guard toast.status == .done, let finishedAt = toast.finishedAt else { continue }
            if now.timeIntervalSince(finishedAt) >= autoHideDoneAfter {
                toastsByID.removeValue(forKey: id)
            }
        }
    }

    public func reset() {
        toastsByID.removeAll()
        activeToastIDByTaskKey.removeAll()
        dismissedTaskKeys.removeAll()
    }

    public func visibleToasts(maxCount: Int) -> [AgentToastItem] {
        guard maxCount > 0 else { return [] }
        return sortedToasts().prefix(maxCount).map { $0 }
    }

    // MARK: - Internals

    private func upsertRunningToast(taskKey: String, title: String, at timestamp: Date) {
        if let existingID = activeToastIDByTaskKey[taskKey], var existing = toastsByID[existingID] {
            existing = AgentToastItem(
                id: existing.id,
                taskKey: taskKey,
                title: title,
                status: .running,
                startedAt: existing.startedAt,
                finishedAt: nil,
                wasDismissedByUser: false
            )
            toastsByID[existing.id] = existing
            dismissedTaskKeys.remove(taskKey)
            return
        }

        let id = UUID().uuidString
        let item = AgentToastItem(
            id: id,
            taskKey: taskKey,
            title: title,
            status: .running,
            startedAt: timestamp,
            finishedAt: nil,
            wasDismissedByUser: false
        )
        toastsByID[id] = item
        activeToastIDByTaskKey[taskKey] = id
        dismissedTaskKeys.remove(taskKey)
    }

    private func finishToast(taskKey: String, title: String, at timestamp: Date) {
        if let activeID = activeToastIDByTaskKey[taskKey], var active = toastsByID[activeID], !active.wasDismissedByUser {
            active = AgentToastItem(
                id: active.id,
                taskKey: taskKey,
                title: active.title,
                status: .done,
                startedAt: active.startedAt,
                finishedAt: timestamp,
                wasDismissedByUser: false
            )
            toastsByID[activeID] = active
            activeToastIDByTaskKey.removeValue(forKey: taskKey)
            dismissedTaskKeys.remove(taskKey)
            return
        }

        let id = UUID().uuidString
        let done = AgentToastItem(
            id: id,
            taskKey: taskKey,
            title: title,
            status: .done,
            startedAt: timestamp,
            finishedAt: timestamp,
            wasDismissedByUser: false
        )
        toastsByID[id] = done
        activeToastIDByTaskKey.removeValue(forKey: taskKey)
        dismissedTaskKeys.remove(taskKey)
    }

    private func sortedToasts() -> [AgentToastItem] {
        toastsByID.values.sorted { lhs, rhs in
            switch (lhs.status, rhs.status) {
            case (.running, .done):
                return true
            case (.done, .running):
                return false
            case (.running, .running):
                return lhs.startedAt > rhs.startedAt
            case (.done, .done):
                return (lhs.finishedAt ?? lhs.startedAt) > (rhs.finishedAt ?? rhs.startedAt)
            }
        }
    }

    private func normalizedTitle(from event: ClaudeQueueTaskEvent) -> String {
        let text = (event.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        if let taskType = event.taskType, !taskType.isEmpty { return taskType }
        return "Claude task"
    }
}
