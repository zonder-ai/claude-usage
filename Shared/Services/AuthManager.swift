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

public enum AuthSource: String, Codable, Equatable, Sendable {
    case appOAuth
    case claudeCodeKeychain

    public var description: String {
        switch self {
        case .appOAuth:
            return "app OAuth"
        case .claudeCodeKeychain:
            return "Claude Code"
        }
    }
}

public enum AuthState: Equatable, Sendable {
    case notAuthenticated
    case authenticated(accessToken: String, refreshToken: String, expiresAt: Date, source: AuthSource)
    case error(String)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    public var accessToken: String? {
        if case .authenticated(let token, _, _, _) = self { return token }
        return nil
    }

    public var isExpired: Bool {
        guard case .authenticated(_, _, let expiresAt, _) = self else { return true }
        return expiresAt < Date()
    }

    public var sourceDescription: String? {
        guard case .authenticated(_, _, _, let source) = self else { return nil }
        return source.description
    }

    public static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated): return true
        case let (.authenticated(a1, r1, e1, s1), .authenticated(a2, r2, e2, s2)):
            return a1 == a2 && r1 == r2 && e1 == e2 && s1 == s2
        case let (.error(m1), .error(m2)): return m1 == m2
        default: return false
        }
    }
}

// MARK: - Auth Manager

@MainActor
public final class AuthManager: NSObject, ObservableObject {
    enum OAuthCallbackDecision: Equatable {
        case exchange(code: String, verifier: String)
        case failure(String)
    }

    @Published public var state: AuthState = .notAuthenticated

    private static let claudeCodeKeychainService = "Claude Code-credentials"
    private static let appKeychainService = "com.aiusagemonitor.oauth"
    private static let pendingOAuthDefaultsKey = "com.aiusagemonitor.oauth.pending"
    private static let pendingOAuthTTL: TimeInterval = 15 * 60

    // Public OAuth client ID from Claude Code (not a secret — public clients
    // don't have client secrets; PKCE protects the authorization flow instead).
    private static let clientID    = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authURL     = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL    = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let redirectURI = "aiusagemonitor://oauth/callback"

    private var pendingCodeVerifier: String?
    private var pendingState: String?
    private let openURL: (URL) -> Void
    private let userDefaults: UserDefaults

    public override init() {
        self.openURL = { url in
            NSWorkspace.shared.open(url)
        }
        self.userDefaults = .standard
        super.init()
    }

    init(openURL: @escaping (URL) -> Void, userDefaults: UserDefaults) {
        self.openURL = openURL
        self.userDefaults = userDefaults
        super.init()
    }

    // MARK: - Load

    /// Quick synchronous load — use on startup for an immediate initial state.
    public func loadToken() {
        if let token = loadFromAppKeychain() { state = token; return }
        if let token = loadFromClaudeCode() { state = token; return }
        state = .notAuthenticated
    }

    /// Async token refresh — call before every API request.
    /// 1. Re-reads Claude Code keychain to pick up any silent refresh it may have done.
    /// 2. If the token is still expired, uses the refresh token to get a new one.
    public func ensureValidToken() async {
        // 1. In-memory token still valid — nothing to do
        if case .authenticated(_, _, let exp, _) = state, exp > Date().addingTimeInterval(60) { return }

        // 2. Try our own app keychain (no ACL prompt — we created this item)
        if let stored = loadFromAppKeychain(),
           case .authenticated(_, _, let exp, _) = stored,
           exp > Date().addingTimeInterval(60) {
            state = stored
            return
        }

        // 3. Try refresh token (silent network call, no keychain prompt)
        let rt: String? = {
            if case .authenticated(_, let r, _, _) = state, !r.isEmpty { return r }
            if let stored = loadFromAppKeychain(), case .authenticated(_, let r, _, _) = stored, !r.isEmpty { return r }
            return nil
        }()
        if let rt {
            await refreshAccessToken(using: rt)
            if case .authenticated(_, _, let exp, _) = state, exp > Date().addingTimeInterval(60) { return }
        }

        // 4. Last resort: Claude Code keychain (may show one-time password prompt)
        //    After the user clicks "Always Allow" this becomes silent forever.
        if let fresh = loadFromClaudeCode() { state = fresh }
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
                              expiresAt: expiresAt,
                              source: .claudeCodeKeychain)
    }

    private func loadFromAppKeychain() -> AuthState? {
        guard let data = keychainData(service: Self.appKeychainService),
              let stored = try? JSONDecoder().decode(StoredToken.self, from: data) else { return nil }
        return .authenticated(accessToken: stored.accessToken,
                              refreshToken: stored.refreshToken,
                              expiresAt: stored.expiresAt,
                              source: .appOAuth)
    }

    // MARK: - Browser OAuth (PKCE)

    /// Opens the default browser to start a PKCE OAuth flow.
    public func startOAuthFlow() {
        let verifier   = makeCodeVerifier()
        let challenge  = codeChallenge(for: verifier)
        let state      = makeCodeVerifier() // random opaque value
        pendingCodeVerifier = verifier
        pendingState = state
        persistPendingOAuth(state: state, verifier: verifier)

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
        openURL(url)
    }

    /// Call this when the app receives `aiusagemonitor://oauth/callback?code=…`.
    public func handleOAuthCallback(url: URL) {
        switch processOAuthCallback(url: url) {
        case .exchange(let code, let verifier):
            Task { await exchangeCode(code: code, codeVerifier: verifier) }
        case .failure(let message):
            state = .error(message)
        }
    }

    func processOAuthCallback(url: URL) -> OAuthCallbackDecision {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            clearPendingOAuthState()
            return .failure("Invalid OAuth callback URL")
        }
        let query = parameterDictionary(from: components.percentEncodedQuery)
        let fragment = parameterDictionary(from: components.percentEncodedFragment)

        if let providerError = nonEmpty(query["error"]) ?? nonEmpty(fragment["error"]) {
            clearPendingOAuthState()
            let description = nonEmpty(query["error_description"]) ?? nonEmpty(fragment["error_description"])
            return .failure(humanMessageForOAuthError(error: providerError, description: description))
        }

        guard let code = nonEmpty(query["code"]) ?? nonEmpty(fragment["code"]) else {
            clearPendingOAuthState()
            return .failure("OAuth callback missing authorization code")
        }

        guard let returnedState = nonEmpty(query["state"]) ?? nonEmpty(fragment["state"]) else {
            clearPendingOAuthState()
            return .failure("OAuth callback missing state")
        }

        if pendingState == nil || pendingCodeVerifier == nil {
            restorePendingOAuthState()
        }

        guard let expectedState = pendingState,
              let verifier = pendingCodeVerifier else {
            clearPendingOAuthState()
            return .failure("Sign-in session expired. Please try again.")
        }

        guard returnedState == expectedState else {
            clearPendingOAuthState()
            return .failure("OAuth state mismatch. Please try signing in again.")
        }

        clearPendingOAuthState()
        return .exchange(code: code, verifier: verifier)
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

    private func humanMessageForOAuthError(error: String, description: String?) -> String {
        switch error {
        case "access_denied":
            if let description {
                return "Sign-in was canceled: \(description)"
            }
            return "Sign-in was canceled or denied."
        case "invalid_request":
            if let description {
                return "Invalid sign-in request: \(description)"
            }
            return "Invalid sign-in request. Please try again."
        default:
            if let description {
                return "OAuth error (\(error)): \(description)"
            }
            return "OAuth error: \(error)"
        }
    }

    private func persistPendingOAuth(state: String, verifier: String) {
        let payload = PendingOAuthPayload(
            state: state,
            verifier: verifier,
            createdAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: Self.pendingOAuthDefaultsKey)
    }

    private func restorePendingOAuthState() {
        guard let data = userDefaults.data(forKey: Self.pendingOAuthDefaultsKey),
              let payload = try? JSONDecoder().decode(PendingOAuthPayload.self, from: data)
        else { return }

        if Date().timeIntervalSince(payload.createdAt) > Self.pendingOAuthTTL {
            userDefaults.removeObject(forKey: Self.pendingOAuthDefaultsKey)
            return
        }

        pendingState = payload.state
        pendingCodeVerifier = payload.verifier
    }

    private func clearPendingOAuthState() {
        pendingState = nil
        pendingCodeVerifier = nil
        userDefaults.removeObject(forKey: Self.pendingOAuthDefaultsKey)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func parameterDictionary(from percentEncodedQuery: String?) -> [String: String] {
        guard let percentEncodedQuery, !percentEncodedQuery.isEmpty else { return [:] }

        var parser = URLComponents(string: "https://localhost")!
        parser.percentEncodedQuery = percentEncodedQuery
        let items = parser.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
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
                               expiresAt: expiresAt,
                               source: .appOAuth)
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

private struct PendingOAuthPayload: Codable {
    let state: String
    let verifier: String
    let createdAt: Date
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
