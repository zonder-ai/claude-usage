import XCTest
@testable import Shared

final class MenuBarStyleTests: XCTestCase {

    func testAllCasesExist() {
        let all = MenuBarStyle.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(.percentage))
        XCTAssertTrue(all.contains(.circle))
        XCTAssertTrue(all.contains(.bar))
    }

    func testRawValuesAreStableStrings() {
        // rawValues are stored in UserDefaults — must never change
        XCTAssertEqual(MenuBarStyle.percentage.rawValue, "percentage")
        XCTAssertEqual(MenuBarStyle.circle.rawValue,     "circle")
        XCTAssertEqual(MenuBarStyle.bar.rawValue,        "bar")
    }

    func testRoundTripsViaRawValue() {
        for style in MenuBarStyle.allCases {
            XCTAssertEqual(MenuBarStyle(rawValue: style.rawValue), style)
        }
    }
}
