import XCTest
@testable import Shared

final class AuthManagerTests: XCTestCase {

    func testParsesClaudeCodeCredentials() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "test-token-123",
                "refreshToken": "refresh-456",
                "expiresAt": 1771468048147,
                "scopes": ["user:read"],
                "subscriptionType": "pro"
            }
        }
        """.data(using: .utf8)!

        let creds = try JSONDecoder().decode(ClaudeCodeCredentials.self, from: json)
        XCTAssertEqual(creds.claudeAiOauth.accessToken, "test-token-123")
        XCTAssertEqual(creds.claudeAiOauth.refreshToken, "refresh-456")
    }

    func testAuthStateTransitions() {
        var state = AuthState.notAuthenticated
        XCTAssertFalse(state.isAuthenticated)

        state = .authenticated(accessToken: "tok", refreshToken: "ref", expiresAt: Date.distantFuture)
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertEqual(state.accessToken, "tok")
    }

    func testTokenExpired() {
        let expired = AuthState.authenticated(
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date.distantPast
        )
        XCTAssertTrue(expired.isExpired)

        let valid = AuthState.authenticated(
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date.distantFuture
        )
        XCTAssertFalse(valid.isExpired)
    }
}
