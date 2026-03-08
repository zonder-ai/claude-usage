import XCTest
@testable import Shared

@MainActor
final class UsageViewModelTests: XCTestCase {
    private struct MutableNow {
        var value: Date
    }

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

    private func makeAuthenticatedViewModel(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data),
        now: MutableNow
    ) -> (UsageViewModel, () -> Int, (Date) -> Void) {
        let suiteName = "test.vm.net.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return try handler(request)
        }

        let client = ClaudeAPIClient(session: URLSession(configuration: config))
        let authManager = AuthManager()
        authManager.state = .authenticated(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date.distantFuture,
            source: .appOAuth
        )

        var mutableNow = now
        let viewModel = UsageViewModel(
            apiClient: client,
            authManager: authManager,
            store: UsageStore(defaults: defaults),
            historyStore: UsageHistoryStore(defaults: defaults),
            pollInterval: 60,
            minFetchInterval: 0,
            now: { mutableNow.value },
            jitter: { _ in 0 }
        )

        return (
            viewModel,
            { requestCount },
            { mutableNow.value = $0 }
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

    func testFetchUsageUsesServerRetryAfterAndSkipsRequestsDuringCooldown() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (vm, requestCount, setNow) = makeAuthenticatedViewModel(
            handler: { _ in
                let response = HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "300"]
                )!
                return (response, Data())
            },
            now: MutableNow(value: now)
        )

        await vm.fetchUsageNow()
        XCTAssertEqual(requestCount(), 1)
        XCTAssertEqual(vm.rateLimitedUntil, now.addingTimeInterval(300))
        XCTAssertEqual(vm.statusMessage(at: now), "Anthropic rate limit reached. Retrying in 5m 0s.")

        setNow(now.addingTimeInterval(30))
        await vm.fetchUsageNow()

        XCTAssertEqual(requestCount(), 1)
        XCTAssertEqual(vm.rateLimitedUntil, now.addingTimeInterval(300))
    }

    func testFetchUsageBackoffDoublesAndCapsAcrossConsecutiveRateLimits() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (vm, _, setNow) = makeAuthenticatedViewModel(
            handler: { _ in
                let response = HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            },
            now: MutableNow(value: start)
        )

        let expectedBackoffs: [TimeInterval] = [60, 120, 240, 480, 900]
        var now = start

        for expected in expectedBackoffs {
            await vm.fetchUsageNow()
            XCTAssertEqual(vm.rateLimitedUntil, now.addingTimeInterval(expected))
            now = now.addingTimeInterval(expected + 1)
            setNow(now)
        }
    }

    func testSuccessfulFetchClearsCooldownAndPreservesLastKnownUsageDuringRateLimit() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let successJSON = """
        {
            "five_hour": { "utilization": 42.0, "resets_at": "2026-02-18T20:00:00+00:00" },
            "seven_day": { "utilization": 21.0, "resets_at": "2026-02-24T00:00:00+00:00" }
        }
        """.data(using: .utf8)!

        var callIndex = 0
        let (vm, _, setNow) = makeAuthenticatedViewModel(
            handler: { _ in
                defer { callIndex += 1 }
                if callIndex == 0 {
                    let response = HTTPURLResponse(
                        url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (response, successJSON)
                }

                let response = HTTPURLResponse(
                    url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "120"]
                )!
                return (response, Data())
            },
            now: MutableNow(value: now)
        )

        await vm.fetchUsageNow()
        XCTAssertEqual(vm.usage?.fiveHour.utilization, 42.0)
        XCTAssertNil(vm.rateLimitedUntil)

        setNow(now.addingTimeInterval(10))
        await vm.fetchUsageNow()
        XCTAssertEqual(vm.usage?.fiveHour.utilization, 42.0)
        XCTAssertEqual(vm.statusMessage(at: now.addingTimeInterval(10)), "Anthropic rate limit reached. Retrying in 2m 0s.")

        setNow(now.addingTimeInterval(131))
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, successJSON)
        }
        await vm.fetchUsageNow()

        XCTAssertNil(vm.rateLimitedUntil)
        XCTAssertNil(vm.statusMessage(at: now.addingTimeInterval(131)))
        XCTAssertEqual(vm.usage?.fiveHour.utilization, 42.0)
    }
}
