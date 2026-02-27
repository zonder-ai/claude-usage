import Foundation

public struct ClaudeActivityEntry: Equatable, Sendable {
    public let timestamp: Date
    public let text: String
    public let projectPath: String?
    public let sessionId: String?

    public init(timestamp: Date, text: String, projectPath: String?, sessionId: String?) {
        self.timestamp = timestamp
        self.text = text
        self.projectPath = projectPath
        self.sessionId = sessionId
    }
}

extension ClaudeActivityEntry: Identifiable {
    public var id: String {
        "\(timestamp.timeIntervalSince1970)-\(sessionId ?? "session")-\(text)"
    }
}

public enum ClaudeQueueTaskEventKind: String, Equatable, Sendable {
    case enqueue
    case remove
}

public struct ClaudeQueueTaskEvent: Equatable, Sendable {
    public let sessionId: String
    public let taskId: String?
    public let description: String?
    public let taskType: String?
    public let timestamp: Date
    public let kind: ClaudeQueueTaskEventKind
    public let cwd: String?

    public init(
        sessionId: String,
        taskId: String?,
        description: String?,
        taskType: String?,
        timestamp: Date,
        kind: ClaudeQueueTaskEventKind,
        cwd: String?
    ) {
        self.sessionId = sessionId
        self.taskId = taskId
        self.description = description
        self.taskType = taskType
        self.timestamp = timestamp
        self.kind = kind
        self.cwd = cwd
    }

    public var taskKey: String? {
        guard let taskId else { return nil }
        return "\(sessionId):\(taskId)"
    }
}

public struct ClaudeQueuePollResult: Equatable, Sendable {
    public let events: [ClaudeQueueTaskEvent]
    public let activeWorkspacePath: String?

    public init(events: [ClaudeQueueTaskEvent], activeWorkspacePath: String?) {
        self.events = events
        self.activeWorkspacePath = activeWorkspacePath
    }
}

// MARK: - Transcript-based session activity

public struct ClaudeSessionActivity: Equatable, Sendable {
    public let sessionId: String
    public let cwd: String?
    public let toolLabel: String
    public let lastSeenAt: Date

    public init(sessionId: String, cwd: String?, toolLabel: String, lastSeenAt: Date) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolLabel = toolLabel
        self.lastSeenAt = lastSeenAt
    }
}

public enum AgentToastStatus: Equatable, Sendable {
    case running
    case done
}

public struct AgentToastItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let taskKey: String
    public let title: String
    public let status: AgentToastStatus
    public let startedAt: Date
    public let finishedAt: Date?
    public let wasDismissedByUser: Bool

    public init(
        id: String,
        taskKey: String,
        title: String,
        status: AgentToastStatus,
        startedAt: Date,
        finishedAt: Date?,
        wasDismissedByUser: Bool
    ) {
        self.id = id
        self.taskKey = taskKey
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.wasDismissedByUser = wasDismissedByUser
    }
}
