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
        // 2026-02-18T15:59:59.943648+00:00 = 1771430399.943648 seconds since epoch
        XCTAssertEqual(usage.fiveHour.resetsAt.timeIntervalSince1970, 1771430399.943648, accuracy: 0.001)
        // 2026-02-22T03:59:59.943679+00:00 = 1771732799.943679 seconds since epoch
        XCTAssertEqual(usage.sevenDay.resetsAt.timeIntervalSince1970, 1771732799.943679, accuracy: 0.001)
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

    func testUsageSnapshotEncodesAndDecodes() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = UsageSnapshot(timestamp: now, fiveHourUtilization: 42.5, sevenDayUtilization: 18.0)
        let data = try JSONEncoder.apiEncoder.encode(snapshot)
        let decoded = try JSONDecoder.apiDecoder.decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.fiveHourUtilization, 42.5)
        XCTAssertEqual(decoded.sevenDayUtilization, 18.0)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testUsageWindowDecodesTokenFieldsWhenPresent() throws {
        let json = """
        {
            "utilization": 55.0,
            "resets_at": "2026-02-18T15:59:59.000000+00:00",
            "tokens_used": 55000,
            "tokens_limit": 100000
        }
        """.data(using: .utf8)!
        let window = try JSONDecoder.apiDecoder.decode(UsageWindow.self, from: json)
        XCTAssertEqual(window.tokensUsed, 55000)
        XCTAssertEqual(window.tokensLimit, 100000)
        XCTAssertEqual(window.tokensRemaining, 45000)
    }

    func testUsageWindowTokenFieldsNilWhenAbsent() throws {
        let json = """
        {
            "utilization": 55.0,
            "resets_at": "2026-02-18T15:59:59.000000+00:00"
        }
        """.data(using: .utf8)!
        let window = try JSONDecoder.apiDecoder.decode(UsageWindow.self, from: json)
        XCTAssertNil(window.tokensUsed)
        XCTAssertNil(window.tokensLimit)
        XCTAssertNil(window.tokensRemaining)
    }
}
