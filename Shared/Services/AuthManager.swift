import AppKit
import CryptoKit
import Foundation

// MARK: - Credential Models

/// Matches the JSON structure stored by Claude Code in Keychain
/// under service name "Claude Code-credentials".
public struct ClaudeCodeCredentials: Codable {
    public let claudeAiOauth: OAuthCredential
}

public struct OAuthCredential: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Double   // Unix timestamp in milliseconds
    public let scopes: [String]
    public let subscriptionType: String
}

// MARK: - Auth State

public enum AuthState: Equatable, Sendable {
    case notAuthenticated
    case authenticated(accessToken: String, refreshToken: String, expiresAt: Date)
    case error(String)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    public var accessToken: String? {
        if case .authenticated(let token, _, _) = self { return token }
        return nil
    }

    public var isExpired: Bool {
        guard case .authenticated(_, _, let expiresAt) = self else { return true }
        return expiresAt < Date()
    }

    public static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated): return true
        case let (.authenticated(a1, r1, e1), .authenticated(a2, r2, e2)):
            return a1 == a2 && r1 == r2 && e1 == e2
        case let (.error(m1), .error(m2)): return m1 == m2
        default: return false
        }
    }
}

// MARK: - Auth Manager

@MainActor
public final class AuthManager: NSObject, ObservableObject {
    @Published public var state: AuthState = .notAuthenticated

    private static let claudeCodeKeychainService = "Claude Code-credentials"
    private static let appKeychainService = "com.aiusagemonitor.oauth"

    // OAuth constants extracted from Claude Code binary
    private static let clientID    = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authURL     = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL    = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let redirectURI = "aiusagemonitor://oauth/callback"

    private var pendingCodeVerifier: String?
    private var pendingState: String?

    public override init() { super.init() }

    // MARK: - Load

    /// Quick synchronous load — use on startup for an immediate initial state.
    public func loadToken() {
        if let token = loadFromClaudeCode() { state = token; return }
        if let token = loadFromAppKeychain() { state = token; return }
        state = .notAuthenticated
    }

    /// Async token refresh — call before every API request.
    /// 1. Re-reads Claude Code keychain to pick up any silent refresh it may have done.
    /// 2. If the token is still expired, uses the refresh token to get a new one.
    public func ensureValidToken() async {
        // Re-read Claude Code keychain (fast, local — picks up Claude Code auto-refreshes)
        if let fresh = loadFromClaudeCode() { state = fresh }

        // Token valid for more than 1 minute — nothing else to do
        if case .authenticated(_, _, let exp) = state, exp > Date().addingTimeInterval(60) { return }

        // Expired or nearly expired — find a refresh token
        let rt: String? = {
            if case .authenticated(_, let r, _) = state, !r.isEmpty { return r }
            if let stored = loadFromAppKeychain(), case .authenticated(_, let r, _) = stored, !r.isEmpty { return r }
            return nil
        }()

        guard let rt else { return }
        await refreshAccessToken(using: rt)
    }

    private func refreshAccessToken(using refreshToken: String) async {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     Self.clientID,
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else { return }  // keep existing state on failure; will retry next poll

        let expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        saveToken(accessToken: token.accessToken,
                  refreshToken: token.refreshToken ?? refreshToken,
                  expiresAt: expiresAt)
    }

    private func loadFromClaudeCode() -> AuthState? {
        guard let data = keychainData(service: Self.claudeCodeKeychainService) else { return nil }
        guard let creds = try? JSONDecoder().decode(ClaudeCodeCredentials.self, from: data) else { return nil }
        let oauth = creds.claudeAiOauth
        let expiresAt = Date(timeIntervalSince1970: oauth.expiresAt / 1000)
        return .authenticated(accessToken: oauth.accessToken,
                              refreshToken: oauth.refreshToken,
                              expiresAt: expiresAt)
    }

    private func loadFromAppKeychain() -> AuthState? {
        guard let data = keychainData(service: Self.appKeychainService),
              let stored = try? JSONDecoder().decode(StoredToken.self, from: data) else { return nil }
        return .authenticated(accessToken: stored.accessToken,
                              refreshToken: stored.refreshToken,
                              expiresAt: stored.expiresAt)
    }

    // MARK: - Browser OAuth (PKCE)

    /// Opens the default browser to start a PKCE OAuth flow.
    public func startOAuthFlow() {
        let verifier   = makeCodeVerifier()
        let challenge  = codeChallenge(for: verifier)
        let state      = makeCodeVerifier() // random opaque value
        pendingCodeVerifier = verifier
        pendingState = state

        var components = URLComponents(url: Self.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "app",                   value: "claude-code"),
            URLQueryItem(name: "client_id",             value: Self.clientID),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: Self.redirectURI),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope",                 value: "user:inference user:profile"),
            URLQueryItem(name: "state",                 value: state),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Call this when the app receives `aiusagemonitor://oauth/callback?code=…`.
    public func handleOAuthCallback(url: URL) {
        guard
            let components    = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code          = components.queryItems?.first(where: { $0.name == "code" })?.value,
            let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
            returnedState     == pendingState,
            let verifier      = pendingCodeVerifier
        else {
            state = .error("Invalid OAuth callback")
            return
        }
        pendingCodeVerifier = nil
        pendingState = nil
        Task { await exchangeCode(code: code, codeVerifier: verifier) }
    }

    private func exchangeCode(code: String, codeVerifier: String) async {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  Self.redirectURI,
            "client_id":     Self.clientID,
            "code_verifier": codeVerifier,
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                state = .error("Token exchange failed")
                return
            }
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
            saveToken(accessToken: token.accessToken,
                      refreshToken: token.refreshToken ?? "",
                      expiresAt: expiresAt)
        } catch {
            state = .error("Token exchange error: \(error.localizedDescription)")
        }
    }

    // MARK: - PKCE Helpers

    private func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded
    }

    // MARK: - Keychain

    public func saveToken(accessToken: String, refreshToken: String, expiresAt: Date) {
        guard let data = try? JSONEncoder().encode(StoredToken(accessToken: accessToken,
                                                              refreshToken: refreshToken,
                                                              expiresAt: expiresAt))
        else { return }

        deleteKeychainItem(service: Self.appKeychainService)

        let addQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.appKeychainService,
            kSecValueData as String:   data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            state = .error("Keychain write failed (\(status))")
            return
        }
        state = .authenticated(accessToken: accessToken,
                               refreshToken: refreshToken,
                               expiresAt: expiresAt)
    }

    public func signOut() {
        deleteKeychainItem(service: Self.appKeychainService)
        state = .notAuthenticated
    }

    private func keychainData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeychainItem(service: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Internal Models

private struct StoredToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

private struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case expiresIn    = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Data Extension

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
