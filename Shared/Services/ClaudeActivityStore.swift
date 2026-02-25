import Foundation

public final class ClaudeActivityStore {
    private struct RawHistoryEntry: Decodable {
        let display: String
        let timestamp: Double
        let project: String?
        let sessionId: String?
    }

    private let historyFileURL: URL
    private let projectsRootURL: URL
    private let emitHistoricalEventsOnFirstPoll: Bool
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private var didPrimeQueueReader = false
    private var queueFileOffsets: [String: UInt64] = [:]
    private var trailingBufferByFile: [String: String] = [:]
    private var queuedTasksBySession: [String: [QueuedTask]] = [:]
    private var latestWorkspaceBySession: [String: WorkspaceState] = [:]
    private let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct WorkspaceState {
        let path: String
        let timestamp: Date
    }

    private struct QueuedTask {
        let taskId: String
        let description: String?
        let taskType: String?
        let timestamp: Date
        let cwd: String?
    }

    private struct QueueContent: Decodable {
        let taskId: String?
        let description: String?
        let taskType: String?
        let toolUseID: String?

        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case description
            case taskType = "task_type"
            case toolUseID = "tool_use_id"
        }
    }

    private struct ParsedQueuePayload {
        let taskId: String?
        let description: String?
        let taskType: String?
        let toolUseID: String?
    }

    public init(
        historyFileURL: URL = ClaudeActivityStore.defaultHistoryFileURL,
        projectsRootURL: URL = ClaudeActivityStore.defaultProjectsRootURL,
        emitHistoricalEventsOnFirstPoll: Bool = false
    ) {
        self.historyFileURL = historyFileURL
        self.projectsRootURL = projectsRootURL
        self.emitHistoricalEventsOnFirstPoll = emitHistoricalEventsOnFirstPoll
    }

    public func loadRecent(limit: Int, projectPath: String?) throws -> [ClaudeActivityEntry] {
        guard limit > 0 else { return [] }
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return [] }

        let data = try Data(contentsOf: historyFileURL, options: [.mappedIfSafe])
        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            return []
        }

        var entries: [ClaudeActivityEntry] = []
        entries.reserveCapacity(limit)

        for line in content.split(whereSeparator: \.isNewline).reversed() {
            guard let lineData = line.data(using: .utf8),
                  let raw = try? decoder.decode(RawHistoryEntry.self, from: lineData) else {
                continue
            }

            if let projectPath, raw.project != projectPath {
                continue
            }

            let text = raw.display.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let timestamp = Date(timeIntervalSince1970: raw.timestamp / 1000.0)
            entries.append(
                ClaudeActivityEntry(
                    timestamp: timestamp,
                    text: text,
                    projectPath: raw.project,
                    sessionId: raw.sessionId
                )
            )

            if entries.count == limit {
                break
            }
        }

        return entries
    }

    public static var defaultHistoryFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/history.jsonl", isDirectory: false)
    }

    public static var defaultProjectsRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public func pollQueueEvents() throws -> ClaudeQueuePollResult {
        let files = sessionLogFiles()
        var emittedEvents: [ClaudeQueueTaskEvent] = []
        let shouldEmitLiveEvents = didPrimeQueueReader || emitHistoricalEventsOnFirstPoll

        for fileURL in files {
            processQueueFile(fileURL, emitEvents: shouldEmitLiveEvents, emittedEvents: &emittedEvents)
        }

        let activeWorkspacePath = currentActiveWorkspacePath()

        if !didPrimeQueueReader, !emitHistoricalEventsOnFirstPoll {
            emittedEvents = initialPendingEvents(activeWorkspacePath: activeWorkspacePath)
        }

        didPrimeQueueReader = true

        return ClaudeQueuePollResult(
            events: emittedEvents.sorted(by: { $0.timestamp < $1.timestamp }),
            activeWorkspacePath: activeWorkspacePath
        )
    }

    // MARK: - Queue monitoring internals

    private func sessionLogFiles() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: projectsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    private func processQueueFile(_ fileURL: URL, emitEvents: Bool, emittedEvents: inout [ClaudeQueueTaskEvent]) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        let path = fileURL.path
        let endOffset = handle.seekToEndOfFile()
        var startOffset = queueFileOffsets[path] ?? 0

        if startOffset > endOffset {
            startOffset = 0
            trailingBufferByFile[path] = nil
        }
        if startOffset == endOffset {
            queueFileOffsets[path] = endOffset
            return
        }

        handle.seek(toFileOffset: startOffset)
        let chunk = handle.readDataToEndOfFile()
        queueFileOffsets[path] = endOffset

        let prefix = trailingBufferByFile[path] ?? ""
        let combined = prefix + String(decoding: chunk, as: UTF8.self)
        let rawLines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        let hasTrailingNewline = combined.hasSuffix("\n")
        let completeCount = hasTrailingNewline ? rawLines.count : max(rawLines.count - 1, 0)

        for index in 0..<completeCount {
            let line = String(rawLines[index])
            if line.isEmpty { continue }
            processQueueLine(line, emitEvents: emitEvents, emittedEvents: &emittedEvents)
        }

        if hasTrailingNewline {
            trailingBufferByFile[path] = nil
        } else {
            trailingBufferByFile[path] = String(rawLines.last ?? "")
        }
    }

    private func processQueueLine(_ line: String, emitEvents: Bool, emittedEvents: inout [ClaudeQueueTaskEvent]) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "progress":
            processProgressLine(json)
        case "queue-operation":
            processQueueOperationLine(json, emitEvents: emitEvents, emittedEvents: &emittedEvents)
        default:
            break
        }
    }

    private func processProgressLine(_ json: [String: Any]) {
        guard let cwd = json["cwd"] as? String,
              !cwd.isEmpty,
              let sessionId = json["sessionId"] as? String,
              let timestampString = json["timestamp"] as? String,
              let timestamp = parseISO8601(timestampString) else {
            return
        }
        latestWorkspaceBySession[sessionId] = WorkspaceState(path: cwd, timestamp: timestamp)
    }

    private func processQueueOperationLine(
        _ json: [String: Any],
        emitEvents: Bool,
        emittedEvents: inout [ClaudeQueueTaskEvent]
    ) {
        guard let operation = json["operation"] as? String,
              let sessionId = json["sessionId"] as? String,
              let timestampString = json["timestamp"] as? String,
              let timestamp = parseISO8601(timestampString) else {
            return
        }

        let workspacePath = latestWorkspaceBySession[sessionId]?.path
        let payload = parseQueuePayload(json["content"])

        switch operation {
        case "enqueue":
            let taskId = payload?.taskId ?? payload?.toolUseID ?? generatedTaskID(sessionId: sessionId, timestamp: timestamp)
            let task = QueuedTask(
                taskId: taskId,
                description: payload?.description,
                taskType: payload?.taskType,
                timestamp: timestamp,
                cwd: workspacePath
            )
            queuedTasksBySession[sessionId, default: []].append(task)

            if emitEvents {
                emittedEvents.append(
                    ClaudeQueueTaskEvent(
                        sessionId: sessionId,
                        taskId: task.taskId,
                        description: task.description,
                        taskType: task.taskType,
                        timestamp: timestamp,
                        kind: .enqueue,
                        cwd: task.cwd
                    )
                )
            }

        case "remove", "dequeue":
            var removedTask: QueuedTask?
            if let explicitTaskID = payload?.taskId {
                removedTask = removeQueuedTask(sessionId: sessionId, matchingTaskID: explicitTaskID)
            } else {
                removedTask = popOldestQueuedTask(sessionId: sessionId)
            }

            guard emitEvents else { return }
            emittedEvents.append(
                ClaudeQueueTaskEvent(
                    sessionId: sessionId,
                    taskId: removedTask?.taskId ?? payload?.taskId,
                    description: removedTask?.description ?? payload?.description,
                    taskType: removedTask?.taskType ?? payload?.taskType,
                    timestamp: timestamp,
                    kind: .remove,
                    cwd: removedTask?.cwd ?? workspacePath
                )
            )

        default:
            break
        }
    }

    private func removeQueuedTask(sessionId: String, matchingTaskID taskID: String) -> QueuedTask? {
        guard var queued = queuedTasksBySession[sessionId] else { return nil }
        guard let index = queued.firstIndex(where: { $0.taskId == taskID }) else {
            return nil
        }
        let removed = queued.remove(at: index)
        queuedTasksBySession[sessionId] = queued
        return removed
    }

    private func popOldestQueuedTask(sessionId: String) -> QueuedTask? {
        guard var queued = queuedTasksBySession[sessionId], !queued.isEmpty else {
            return nil
        }
        let removed = queued.removeFirst()
        queuedTasksBySession[sessionId] = queued
        return removed
    }

    private func parseQueuePayload(_ raw: Any?) -> ParsedQueuePayload? {
        if let dict = raw as? [String: Any] {
            return ParsedQueuePayload(
                taskId: dict["task_id"] as? String,
                description: sanitizedTaskDescription(dict["description"] as? String),
                taskType: dict["task_type"] as? String,
                toolUseID: dict["tool_use_id"] as? String
            )
        }

        guard let text = raw as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.first == "{",
           let data = trimmed.data(using: .utf8),
           let decoded = try? decoder.decode(QueueContent.self, from: data) {
            return ParsedQueuePayload(
                taskId: decoded.taskId,
                description: sanitizedTaskDescription(decoded.description),
                taskType: decoded.taskType,
                toolUseID: decoded.toolUseID
            )
        }

        return ParsedQueuePayload(
            taskId: nil,
            description: sanitizedTaskDescription(trimmed),
            taskType: nil,
            toolUseID: nil
        )
    }

    private func sanitizedTaskDescription(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let flattened = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return nil }
        if flattened.count <= 120 { return flattened }
        return String(flattened.prefix(117)) + "..."
    }

    private func generatedTaskID(sessionId: String, timestamp: Date) -> String {
        let millis = Int(timestamp.timeIntervalSince1970 * 1000)
        return "generated-\(sessionId)-\(millis)"
    }

    private func parseISO8601(_ value: String) -> Date? {
        if let date = fractionalFormatter.date(from: value) { return date }
        return plainFormatter.date(from: value)
    }

    private func currentActiveWorkspacePath() -> String? {
        latestWorkspaceBySession.values
            .sorted { $0.timestamp > $1.timestamp }
            .first?.path
    }

    private func initialPendingEvents(activeWorkspacePath: String?) -> [ClaudeQueueTaskEvent] {
        let pending = queuedTasksBySession.flatMap { (sessionId, queued) in
            queued.map { task in
                ClaudeQueueTaskEvent(
                    sessionId: sessionId,
                    taskId: task.taskId,
                    description: task.description,
                    taskType: task.taskType,
                    timestamp: task.timestamp,
                    kind: .enqueue,
                    cwd: task.cwd
                )
            }
        }

        guard let activeWorkspacePath else { return [] }
        return pending.filter { $0.cwd == activeWorkspacePath }
    }
}
