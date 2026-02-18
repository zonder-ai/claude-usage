import AppKit
import AuthenticationServices
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
    public let expiresAt: String
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

    private var oauthSession: ASWebAuthenticationSession?

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public override init() { super.init() }

    /// Try Claude Code's Keychain first, then the app's own stored token.
    public func loadToken() {
        if let token = loadFromClaudeCode() {
            state = token
            return
        }
        if let token = loadFromAppKeychain() {
            state = token
            return
        }
        state = .notAuthenticated
    }

    /// Read Claude Code's OAuth credentials from Keychain.
    private func loadFromClaudeCode() -> AuthState? {
        guard let data = keychainData(service: Self.claudeCodeKeychainService) else { return nil }
        guard let creds = try? JSONDecoder().decode(ClaudeCodeCredentials.self, from: data) else { return nil }

        let oauth = creds.claudeAiOauth
        guard let expiresAt = Self.dateFormatter.date(from: oauth.expiresAt) else { return nil }

        return .authenticated(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: expiresAt
        )
    }

    /// Load from this app's own Keychain entry (written after OAuth browser flow).
    private func loadFromAppKeychain() -> AuthState? {
        guard let data = keychainData(service: Self.appKeychainService),
              let stored = try? JSONDecoder().decode(StoredToken.self, from: data) else { return nil }

        return .authenticated(
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            expiresAt: stored.expiresAt
        )
    }

    private func keychainData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Save token to this app's Keychain entry.
    public func saveToken(accessToken: String, refreshToken: String, expiresAt: Date) {
        guard let data = try? JSONEncoder().encode(StoredToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )) else { return }

        deleteKeychainItem(service: Self.appKeychainService)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.appKeychainService,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            state = .error("Keychain write failed (\(status))")
            return
        }
        state = .authenticated(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    /// Start OAuth browser flow as fallback when no Keychain token found.
    /// Opens Anthropic's OAuth page via ASWebAuthenticationSession.
    public func startOAuthFlow() {
        guard let authURL = URL(string: "https://console.anthropic.com/oauth/authorize") else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "aiusagemonitor"
        ) { [weak self] callbackURL, error in
            // clear the retained session after callback
            Task { @MainActor [weak self] in self?.oauthSession = nil }
            guard let self else { return }
            if let error {
                Task { @MainActor in self.state = .error(error.localizedDescription) }
                return
            }
            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let token = components.queryItems?.first(where: { $0.name == "access_token" })?.value
            else {
                Task { @MainActor in self.state = .error("No token received") }
                return
            }
            Task { @MainActor in
                self.saveToken(
                    accessToken: token,
                    refreshToken: "",
                    expiresAt: Date().addingTimeInterval(3600)
                )
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        oauthSession = session
        session.start()
    }

    /// Clear stored credentials and reset to unauthenticated.
    public func signOut() {
        deleteKeychainItem(service: Self.appKeychainService)
        state = .notAuthenticated
    }

    private func deleteKeychainItem(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isKeyWindow })
            ?? NSApp.windows.first
            ?? ASPresentationAnchor()
    }
}

// MARK: - Internal Storage

struct StoredToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}
