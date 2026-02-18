import XCTest
@testable import Shared

@MainActor
final class UsageViewModelTests: XCTestCase {

    func testMenuBarTextWhenNoData() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        XCTAssertEqual(vm.menuBarText, "C: --")
        XCTAssertEqual(vm.usageLevel, .normal)
    }

    func testMenuBarTextShowsFiveHourWhenHigher() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 72.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .init(utilization: 35.0, resetsAt: Date().addingTimeInterval(86400))
        )
        XCTAssertEqual(vm.menuBarText, "C: 72%")
        XCTAssertEqual(vm.usageLevel, .warning)
    }

    func testMenuBarTextShowsSevenDayWhenHigher() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 10.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .init(utilization: 90.0, resetsAt: Date().addingTimeInterval(86400))
        )
        XCTAssertEqual(vm.menuBarText, "C: 90%")
        XCTAssertEqual(vm.usageLevel, .critical)
    }

    func testMenuBarTextRoundsPercentage() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 72.6, resetsAt: Date()),
            sevenDay: .init(utilization: 10.0, resetsAt: Date())
        )
        XCTAssertEqual(vm.menuBarText, "C: 73%")
    }

    func testUsageLevelNormal() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 50.0, resetsAt: Date()),
            sevenDay: .init(utilization: 40.0, resetsAt: Date())
        )
        XCTAssertEqual(vm.usageLevel, .normal)
    }

    func testUsageLevelCritical() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 95.0, resetsAt: Date()),
            sevenDay: .init(utilization: 50.0, resetsAt: Date())
        )
        XCTAssertEqual(vm.usageLevel, .critical)
    }
}
