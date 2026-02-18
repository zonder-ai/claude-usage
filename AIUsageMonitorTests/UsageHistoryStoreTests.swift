import XCTest
@testable import Shared

final class UsageHistoryStoreTests: XCTestCase {

    private func makeStore() -> (UsageHistoryStore, UserDefaults) {
        let suiteName = "test.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        return (UsageHistoryStore(defaults: defaults), defaults)
    }

    func testLoadReturnsEmptyWhenNothingSaved() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testAppendAndLoad() {
        let (store, _) = makeStore()
        let snap = UsageSnapshot(timestamp: Date(), fiveHourUtilization: 42.0, sevenDayUtilization: 18.0)
        store.append(snap)
        let history = store.load()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].fiveHourUtilization, 42.0)
    }

    func testTrimsEntriesOlderThanFiveHours() {
        let (store, _) = makeStore()
        let old = UsageSnapshot(timestamp: Date().addingTimeInterval(-6 * 3600),
                                fiveHourUtilization: 10.0, sevenDayUtilization: 5.0)
        let recent = UsageSnapshot(timestamp: Date(),
                                   fiveHourUtilization: 50.0, sevenDayUtilization: 20.0)
        store.append(old)
        store.append(recent)
        let history = store.load()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].fiveHourUtilization, 50.0)
    }

    func testCapsAtMaxEntries() {
        let (store, _) = makeStore()
        for i in 0..<365 {
            let snap = UsageSnapshot(
                timestamp: Date().addingTimeInterval(TimeInterval(i * 30)),
                fiveHourUtilization: Double(i),
                sevenDayUtilization: 0
            )
            store.append(snap)
        }
        XCTAssertLessThanOrEqual(store.load().count, 360)
    }

    func testPersistsAcrossInstances() {
        let suiteName = "test.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }

        let store1 = UsageHistoryStore(defaults: defaults)
        store1.append(UsageSnapshot(timestamp: Date(), fiveHourUtilization: 77.0, sevenDayUtilization: 33.0))

        let store2 = UsageHistoryStore(defaults: defaults)
        XCTAssertEqual(store2.load().first?.fiveHourUtilization, 77.0)
    }
}
