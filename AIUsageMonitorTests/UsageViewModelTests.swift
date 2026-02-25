import XCTest
@testable import Shared

@MainActor
final class UsageViewModelTests: XCTestCase {

    // MARK: - Helpers

    @discardableResult
    private func makeIsolatedVM() -> UsageViewModel {
        let suiteName = "test.vm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        return UsageViewModel(
            apiClient: ClaudeAPIClient(),
            authManager: AuthManager(),
            store: UsageStore(defaults: defaults),
            historyStore: UsageHistoryStore(defaults: defaults)
        )
    }

    // MARK: - menuBarText tests

    func testMenuBarTextWhenNoData() {
        let vm = makeIsolatedVM()
        XCTAssertEqual(vm.menuBarText, "--%")
        XCTAssertEqual(vm.usageLevel, .normal)
    }

    func testMenuBarTextShowsFiveHourWhenHigher() {
        let vm = makeIsolatedVM()
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 72.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .init(utilization: 35.0, resetsAt: Date().addingTimeInterval(86400))
        )
        XCTAssertEqual(vm.menuBarText, "72%")
        XCTAssertEqual(vm.usageLevel, .warning)
    }

    func testMenuBarTextShowsFiveHourUsage() {
        let vm = makeIsolatedVM()
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 10.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .init(utilization: 90.0, resetsAt: Date().addingTimeInterval(86400))
        )
        XCTAssertEqual(vm.menuBarText, "10%")
        XCTAssertEqual(vm.usageLevel, .normal)
    }

    func testMenuBarTextRoundsPercentage() {
        let vm = makeIsolatedVM()
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 72.6, resetsAt: Date()),
            sevenDay: .init(utilization: 10.0, resetsAt: Date())
        )
        XCTAssertEqual(vm.menuBarText, "73%")
    }

    func testUsageLevelNormal() {
        let vm = makeIsolatedVM()
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 50.0, resetsAt: Date()),
            sevenDay: .init(utilization: 40.0, resetsAt: Date())
        )
        XCTAssertEqual(vm.usageLevel, .normal)
    }

    func testUsageLevelCritical() {
        let vm = makeIsolatedVM()
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 95.0, resetsAt: Date()),
            sevenDay: .init(utilization: 50.0, resetsAt: Date())
        )
        XCTAssertEqual(vm.usageLevel, .critical)
    }

    // MARK: - New Task 3 tests

    func testLastUpdatedNilOnInit() {
        let vm = makeIsolatedVM()
        XCTAssertNil(vm.lastUpdated)
    }

    func testHistoryEmptyOnInit() {
        let suiteName = "test.vm.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        let store = UsageHistoryStore(defaults: defaults)
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager(), historyStore: store)
        XCTAssertTrue(vm.history.isEmpty)
    }

    func testRecordSnapshotAppendsToHistory() {
        let suiteName = "test.vm.snap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        let store = UsageHistoryStore(defaults: defaults)
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager(), historyStore: store)

        let response = UsageResponse(
            fiveHour: .init(utilization: 42.0, resetsAt: Date()),
            sevenDay: .init(utilization: 18.0, resetsAt: Date())
        )
        vm.recordSnapshot(for: response)

        XCTAssertEqual(vm.history.count, 1)
        XCTAssertEqual(vm.history[0].fiveHourUtilization, 42.0)
        XCTAssertNotNil(vm.lastUpdated)
    }

    func testAgentToastsDisabledPreventsQueueToasts() throws {
        let suiteName = "test.vm.toasts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }

        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-vm-toasts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let sessionFile = root.appendingPathComponent("projectA/session-1.jsonl")
        try FileManager.default.createDirectory(at: sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = [
            #"{"type":"progress","timestamp":"2026-02-25T10:00:00.000Z","cwd":"/Users/example/repo","sessionId":"session-1"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-02-25T10:00:01.000Z","sessionId":"session-1","content":"{\"task_id\":\"task-1\",\"description\":\"Build project\",\"task_type\":\"local_bash\"}"}"#
        ]
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.data(using: .utf8)?.write(to: sessionFile)

        let activityStore = ClaudeActivityStore(
            projectsRootURL: root,
            emitHistoricalEventsOnFirstPoll: true
        )
        let vm = UsageViewModel(
            apiClient: ClaudeAPIClient(),
            authManager: AuthManager(),
            store: UsageStore(defaults: defaults),
            historyStore: UsageHistoryStore(defaults: defaults),
            activityStore: activityStore
        )

        vm.setAgentToastsEnabled(false)
        vm.refreshQueueActivity()

        XCTAssertTrue(vm.agentToasts.isEmpty)
    }
}
