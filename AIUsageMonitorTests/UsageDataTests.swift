import XCTest
@testable import Shared

final class UsageDataTests: XCTestCase {

    func testDecodesAPIResponse() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 72.0,
                "resets_at": "2026-02-18T15:59:59.943648+00:00"
            },
            "seven_day": {
                "utilization": 35.0,
                "resets_at": "2026-02-22T03:59:59.943679+00:00"
            }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: json)
        XCTAssertEqual(usage.fiveHour.utilization, 72.0)
        XCTAssertEqual(usage.sevenDay.utilization, 35.0)
        XCTAssertNotNil(usage.fiveHour.resetsAt)
        XCTAssertNotNil(usage.sevenDay.resetsAt)
    }

    func testHigherUtilization() {
        let usage = UsageResponse(
            fiveHour: .init(utilization: 72.0, resetsAt: Date()),
            sevenDay: .init(utilization: 35.0, resetsAt: Date())
        )
        XCTAssertEqual(usage.higherUtilization, 72.0)

        let usage2 = UsageResponse(
            fiveHour: .init(utilization: 10.0, resetsAt: Date()),
            sevenDay: .init(utilization: 90.0, resetsAt: Date())
        )
        XCTAssertEqual(usage2.higherUtilization, 90.0)
    }

    func testUsageLevel() {
        XCTAssertEqual(UsageLevel.from(utilization: 30.0), .normal)
        XCTAssertEqual(UsageLevel.from(utilization: 60.0), .normal)
        XCTAssertEqual(UsageLevel.from(utilization: 60.1), .warning)
        XCTAssertEqual(UsageLevel.from(utilization: 85.0), .warning)
        XCTAssertEqual(UsageLevel.from(utilization: 85.1), .critical)
        XCTAssertEqual(UsageLevel.from(utilization: 100.0), .critical)
    }
}
