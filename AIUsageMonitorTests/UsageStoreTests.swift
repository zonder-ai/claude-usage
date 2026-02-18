import XCTest
@testable import Shared

final class UsageStoreTests: XCTestCase {

    func testSaveAndLoadUsage() {
        // Use an isolated test suite to avoid polluting UserDefaults.standard
        let suiteName = "test.usage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UsageStore(defaults: defaults)

        let usage = UsageResponse(
            fiveHour: .init(utilization: 55.0, resetsAt: Date()),
            sevenDay: .init(utilization: 30.0, resetsAt: Date())
        )

        store.save(usage)
        let loaded = store.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHour.utilization, 55.0)
        XCTAssertEqual(loaded?.sevenDay.utilization, 30.0)

        // Cleanup
        defaults.removeSuite(named: suiteName)
    }

    func testLoadReturnsNilWhenEmpty() {
        let suiteName = "test.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        let store = UsageStore(defaults: defaults)
        XCTAssertNil(store.load())
    }

    func testSaveOverwritesPreviousValue() {
        let suiteName = "test.overwrite.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removeSuite(named: suiteName) }
        let store = UsageStore(defaults: defaults)

        let first = UsageResponse(
            fiveHour: .init(utilization: 10.0, resetsAt: Date()),
            sevenDay: .init(utilization: 20.0, resetsAt: Date())
        )
        let second = UsageResponse(
            fiveHour: .init(utilization: 80.0, resetsAt: Date()),
            sevenDay: .init(utilization: 90.0, resetsAt: Date())
        )

        store.save(first)
        store.save(second)
        let loaded = store.load()

        XCTAssertEqual(loaded?.fiveHour.utilization, 80.0)
        XCTAssertEqual(loaded?.sevenDay.utilization, 90.0)
    }
}
