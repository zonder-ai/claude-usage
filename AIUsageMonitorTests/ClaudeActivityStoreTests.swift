import XCTest
@testable import Shared

final class ClaudeActivityStoreTests: XCTestCase {

    private func makeTempHistoryFile(lines: [String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-activity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("history.jsonl")
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    func testLoadRecentReturnsNewestEntriesForProject() throws {
        let projectA = "/Users/example/project-a"
        let projectB = "/Users/example/project-b"
        let lines = [
            #"{"display":"old-a","timestamp":1000,"project":"/Users/example/project-a","sessionId":"s1"}"#,
            #"{"display":"middle-b","timestamp":2000,"project":"/Users/example/project-b","sessionId":"s2"}"#,
            #"{"display":"new-a","timestamp":3000,"project":"/Users/example/project-a","sessionId":"s3"}"#,
            #"{"display":"newest-a","timestamp":4000,"project":"/Users/example/project-a","sessionId":"s4"}"#
        ]
        let fileURL = try makeTempHistoryFile(lines: lines)
        let store = ClaudeActivityStore(historyFileURL: fileURL)

        let entries = try store.loadRecent(limit: 2, projectPath: projectA)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "newest-a")
        XCTAssertEqual(entries[0].projectPath, projectA)
        XCTAssertEqual(entries[1].text, "new-a")
        XCTAssertTrue(entries.allSatisfy { $0.projectPath == projectA })
        XCTAssertFalse(entries.contains { $0.projectPath == projectB })
    }

    func testLoadRecentSkipsInvalidLines() throws {
        let project = "/Users/example/project-a"
        let lines = [
            #"{"display":"valid-1","timestamp":1000,"project":"/Users/example/project-a","sessionId":"s1"}"#,
            "not-json",
            #"{"display":"valid-2","timestamp":2000,"project":"/Users/example/project-a","sessionId":"s2"}"#
        ]
        let fileURL = try makeTempHistoryFile(lines: lines)
        let store = ClaudeActivityStore(historyFileURL: fileURL)

        let entries = try store.loadRecent(limit: 10, projectPath: project)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].text, "valid-2")
        XCTAssertEqual(entries[1].text, "valid-1")
    }

    func testLoadRecentReturnsEmptyWhenFileMissing() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-activity-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let missingFileURL = directory.appendingPathComponent("missing.jsonl")
        let store = ClaudeActivityStore(historyFileURL: missingFileURL)

        let entries = try store.loadRecent(limit: 5, projectPath: nil)

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Queue events

    private func makeTempProjectsRoot(sessionFiles: [(path: String, lines: [String])]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-projects-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        for file in sessionFiles {
            let fileURL = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = file.lines.joined(separator: "\n") + "\n"
            try payload.data(using: .utf8)?.write(to: fileURL)
        }
        return root
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func testPollQueueEventsMapsRemoveToOldestEnqueuedTask() throws {
        let sessionFile = "projectA/session-1.jsonl"
        let lines = [
            #"{"type":"progress","timestamp":"2026-02-25T10:00:00.000Z","cwd":"/Users/example/repo","sessionId":"session-1"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-02-25T10:00:01.000Z","sessionId":"session-1","content":"{\"task_id\":\"task-1\",\"description\":\"Build project\",\"task_type\":\"local_bash\"}"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-02-25T10:00:02.000Z","sessionId":"session-1","content":"{\"task_id\":\"task-2\",\"description\":\"Run tests\",\"task_type\":\"local_bash\"}"}"#,
            #"{"type":"queue-operation","operation":"remove","timestamp":"2026-02-25T10:00:03.000Z","sessionId":"session-1"}"#
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: [(sessionFile, lines)])
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: true
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.events.count, 3)
        XCTAssertEqual(result.activeWorkspacePath, "/Users/example/repo")
        XCTAssertEqual(result.events[0].kind, .enqueue)
        XCTAssertEqual(result.events[0].taskId, "task-1")
        XCTAssertEqual(result.events[1].kind, .enqueue)
        XCTAssertEqual(result.events[1].taskId, "task-2")
        XCTAssertEqual(result.events[2].kind, .remove)
        XCTAssertEqual(result.events[2].taskId, "task-1")
        XCTAssertEqual(result.events[2].description, "Build project")
    }

    func testPollQueueEventsUsesLatestWorkspaceFromProgress() throws {
        let files: [(String, [String])] = [
            (
                "projectA/session-1.jsonl",
                [
                    #"{"type":"progress","timestamp":"2026-02-25T10:00:00.000Z","cwd":"/Users/example/repo-a","sessionId":"session-1"}"#
                ]
            ),
            (
                "projectB/session-2.jsonl",
                [
                    #"{"type":"progress","timestamp":"2026-02-25T10:01:00.000Z","cwd":"/Users/example/repo-b","sessionId":"session-2"}"#
                ]
            )
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: files)
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: true
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.activeWorkspacePath, "/Users/example/repo-b")
    }

    func testPollQueueEventsIgnoresMalformedLines() throws {
        let sessionFile = "projectA/session-1.jsonl"
        let lines = [
            "not-json-at-all",
            #"{"type":"progress","timestamp":"2026-02-25T10:00:00.000Z","cwd":"/Users/example/repo","sessionId":"session-1"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-02-25T10:00:01.000Z","sessionId":"session-1","content":"{\"task_id\":\"task-1\",\"description\":\"One task\",\"task_type\":\"local_bash\"}"}"#
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: [(sessionFile, lines)])
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: true
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.activeWorkspacePath, "/Users/example/repo")
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.kind, .enqueue)
        XCTAssertEqual(result.events.first?.taskId, "task-1")
    }

    func testPollQueueEventsParsesPlainStringContentAndDequeue() throws {
        let sessionFile = "projectA/session-1.jsonl"
        let lines = [
            #"{"type":"progress","timestamp":"2026-02-25T10:00:00.000Z","cwd":"/Users/example/repo","sessionId":"session-1"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-02-25T10:00:01.000Z","sessionId":"session-1","content":"Can you refactor the sidebar?"}"#,
            #"{"type":"queue-operation","operation":"dequeue","timestamp":"2026-02-25T10:00:02.000Z","sessionId":"session-1"}"#
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: [(sessionFile, lines)])
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: true
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events[0].kind, .enqueue)
        XCTAssertEqual(result.events[0].description, "Can you refactor the sidebar?")
        XCTAssertEqual(result.events[1].kind, .remove)
        XCTAssertEqual(result.events[1].description, "Can you refactor the sidebar?")
    }

    func testPollQueueEventsInitialPendingFiltersOutStaleItems() throws {
        let now = Date()
        let stale = iso(now.addingTimeInterval(-7200))
        let fresh = iso(now.addingTimeInterval(-60))
        let sessionFile = "projectA/session-1.jsonl"
        let lines = [
            #"{"type":"progress","timestamp":"\#(fresh)","cwd":"/Users/example/repo","sessionId":"session-1"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"\#(stale)","sessionId":"session-1","content":"{\"task_id\":\"task-old\",\"description\":\"Old task\"}"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"\#(fresh)","sessionId":"session-1","content":"{\"task_id\":\"task-new\",\"description\":\"Fresh task\"}"}"#
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: [(sessionFile, lines)])
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: false,
            initialPendingMaxAge: 30 * 60
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.taskId, "task-new")
        XCTAssertEqual(result.events.first?.description, "Fresh task")
    }

    func testPollQueueEventsUsesCwdFromNonProgressLines() throws {
        let sessionFile = "projectA/session-1.jsonl"
        let lines = [
            #"{"type":"user","timestamp":"2026-02-25T10:00:00.000Z","cwd":"/Users/example/repo","sessionId":"session-1"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-02-25T10:00:01.000Z","sessionId":"session-1","content":"{\"task_id\":\"task-1\",\"description\":\"Build project\"}"}"#
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: [(sessionFile, lines)])
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: true
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.activeWorkspacePath, "/Users/example/repo")
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.cwd, "/Users/example/repo")
        XCTAssertEqual(result.events.first?.description, "Build project")
    }

    func testPollQueueEventsInitialPendingWithoutWorkspaceStillEmitsRecentTask() throws {
        let recent = iso(Date().addingTimeInterval(-60))
        let sessionFile = "projectA/session-1.jsonl"
        let lines = [
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"\#(recent)","sessionId":"session-1","content":"{\"task_id\":\"task-1\",\"description\":\"Build project\"}"}"#
        ]
        let projectsRoot = try makeTempProjectsRoot(sessionFiles: [(sessionFile, lines)])
        let store = ClaudeActivityStore(
            projectsRootURL: projectsRoot,
            emitHistoricalEventsOnFirstPoll: false,
            initialPendingMaxAge: 3600
        )

        let result = try store.pollQueueEvents()

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.taskId, "task-1")
        XCTAssertEqual(result.events.first?.description, "Build project")
    }
}
