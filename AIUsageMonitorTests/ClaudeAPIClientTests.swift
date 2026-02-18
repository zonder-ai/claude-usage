import XCTest
@testable import Shared

final class ClaudeAPIClientTests: XCTestCase {

    func testBuildRequest() {
        let client = ClaudeAPIClient()
        let request = client.buildUsageRequest(accessToken: "test-token")

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testParsesValidResponse() throws {
        let json = """
        {
            "five_hour": { "utilization": 45.0, "resets_at": "2026-02-18T20:00:00+00:00" },
            "seven_day": { "utilization": 22.0, "resets_at": "2026-02-24T00:00:00+00:00" }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour.utilization, 45.0)
        XCTAssertEqual(response.sevenDay.utilization, 22.0)
    }

    func testAPIErrorDescriptions() {
        XCTAssertEqual(APIError.noToken.errorDescription, "Not authenticated")
        XCTAssertNotNil(APIError.httpError(statusCode: 401).errorDescription)
        XCTAssertNotNil(APIError.networkError(URLError(.notConnectedToInternet)).errorDescription)
    }
}
