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

    @MainActor
    func testOAuthCallbackSurfacesProviderErrorDescription() {
        let manager = AuthManager(openURL: { _ in }, userDefaults: makeDefaults())
        let callback = URL(string: "aiusagemonitor://oauth/callback?error=access_denied&error_description=User%20denied%20access")!

        let result = manager.processOAuthCallback(url: callback)

        XCTAssertEqual(result, .failure("Sign-in was canceled: User denied access"))
    }

    @MainActor
    func testOAuthCallbackRestoresPendingStateFromDefaultsAfterRestart() {
        let defaults = makeDefaults()
        var openedURL: URL?
        let manager1 = AuthManager(openURL: { openedURL = $0 }, userDefaults: defaults)
        manager1.startOAuthFlow()

        let authURL = try! XCTUnwrap(openedURL)
        let state = try! XCTUnwrap(URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "state" })?
            .value)

        let manager2 = AuthManager(openURL: { _ in }, userDefaults: defaults)
        let callback = URL(string: "aiusagemonitor://oauth/callback?code=auth-code&state=\(state)")!

        let result = manager2.processOAuthCallback(url: callback)

        guard case .exchange(let code, let verifier) = result else {
            return XCTFail("Expected exchange decision, got \(result)")
        }
        XCTAssertEqual(code, "auth-code")
        XCTAssertFalse(verifier.isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "auth-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
