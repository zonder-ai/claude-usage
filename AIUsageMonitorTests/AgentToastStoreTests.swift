import XCTest
@testable import Shared

final class AgentToastStoreTests: XCTestCase {

    private func makeEnqueue(taskId: String, title: String, timestamp: Date) -> ClaudeQueueTaskEvent {
        ClaudeQueueTaskEvent(
            sessionId: "session-1",
            taskId: taskId,
            description: title,
            taskType: "local_bash",
            timestamp: timestamp,
            kind: .enqueue,
            cwd: "/Users/example/repo"
        )
    }

    private func makeRemove(taskId: String, title: String, timestamp: Date) -> ClaudeQueueTaskEvent {
        ClaudeQueueTaskEvent(
            sessionId: "session-1",
            taskId: taskId,
            description: title,
            taskType: "local_bash",
            timestamp: timestamp,
            kind: .remove,
            cwd: "/Users/example/repo"
        )
    }

    func testEnqueueThenRemoveUpdatesSameToastToDone() {
        let store = AgentToastStore()
        let start = Date()
        let enqueue = makeEnqueue(taskId: "task-1", title: "Build", timestamp: start)

        store.apply(event: enqueue)
        let running = store.visibleToasts(maxCount: 3)
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(running[0].status, .running)

        store.apply(event: makeRemove(taskId: "task-1", title: "Build", timestamp: start.addingTimeInterval(1)))
        let done = store.visibleToasts(maxCount: 3)
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done[0].id, running[0].id)
        XCTAssertEqual(done[0].status, .done)
    }

    func testDismissRunningThenRemoveCreatesNewDoneToast() {
        let store = AgentToastStore()
        let start = Date()

        store.apply(event: makeEnqueue(taskId: "task-1", title: "Build", timestamp: start))
        let running = store.visibleToasts(maxCount: 3)
        XCTAssertEqual(running.count, 1)
        store.dismissToast(id: running[0].id)
        XCTAssertTrue(store.visibleToasts(maxCount: 3).isEmpty)

        store.apply(event: makeRemove(taskId: "task-1", title: "Build", timestamp: start.addingTimeInterval(2)))
        let done = store.visibleToasts(maxCount: 3)
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done[0].status, .done)
        XCTAssertNotEqual(done[0].id, running[0].id)
    }

    func testDoneToastAutoHidesAfterDelay() {
        let store = AgentToastStore(autoHideDoneAfter: 4)
        let start = Date()

        store.apply(event: makeEnqueue(taskId: "task-1", title: "Build", timestamp: start))
        store.apply(event: makeRemove(taskId: "task-1", title: "Build", timestamp: start.addingTimeInterval(1)))
        XCTAssertEqual(store.visibleToasts(maxCount: 3).count, 1)

        store.tick(now: start.addingTimeInterval(6))
        XCTAssertTrue(store.visibleToasts(maxCount: 3).isEmpty)
    }

    func testVisibleToastsCapsAtMaxWithNewestRunningFirst() {
        let store = AgentToastStore()
        let start = Date()

        store.apply(event: makeEnqueue(taskId: "task-1", title: "One", timestamp: start))
        store.apply(event: makeEnqueue(taskId: "task-2", title: "Two", timestamp: start.addingTimeInterval(1)))
        store.apply(event: makeEnqueue(taskId: "task-3", title: "Three", timestamp: start.addingTimeInterval(2)))
        store.apply(event: makeEnqueue(taskId: "task-4", title: "Four", timestamp: start.addingTimeInterval(3)))

        let visible = store.visibleToasts(maxCount: 3)
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(visible.map(\.title), ["Four", "Three", "Two"])
        XCTAssertTrue(visible.allSatisfy { $0.status == .running })
    }
}
