# AI Usage Monitor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that displays Claude subscription usage (5-hour and 7-day limits) with color-coded status and threshold notifications.

**Architecture:** SwiftUI `MenuBarExtra` app with a shared data layer (App Group) for future WidgetKit extension. Auth reads Claude Code's OAuth token from Keychain, with browser OAuth fallback. Polls `api.anthropic.com/api/oauth/usage` every 30 seconds.

**Tech Stack:** Swift 6, SwiftUI, macOS 13+, XCTest, xcodegen (project generation)

---

### Task 1: Install xcodegen and scaffold project structure

**Files:**
- Create: `project.yml` (xcodegen spec)
- Create: `AIUsageMonitor/AIUsageApp.swift` (minimal app entry point)
- Create: `AIUsageMonitor/Info.plist`
- Create: `Shared/Shared.h` (umbrella header placeholder)
- Create: `AIUsageMonitorTests/AIUsageMonitorTests.swift` (placeholder test)

**Step 1: Install xcodegen**

Run: `brew install xcodegen`
Expected: xcodegen available on PATH

**Step 2: Create directory structure**

Run:
```bash
cd "/Users/guilledelolmo/Documents/AI Usage App"
mkdir -p AIUsageMonitor/Views AIUsageMonitor/App
mkdir -p Shared/Models Shared/Services
mkdir -p AIUsageMonitorTests
```

**Step 3: Create `project.yml`**

This is the xcodegen project spec. Key settings:
- App target with `LSUIElement: true` (no dock icon — menu bar only)
- Shared framework target linked to the app
- Test target
- App Group entitlement: `group.com.aiusagemonitor`
- macOS deployment target: 13.0

```yaml
name: AIUsageMonitor
options:
  bundleIdPrefix: com.aiusagemonitor
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "13.0"

targets:
  AIUsageMonitor:
    type: application
    platform: macOS
    sources:
      - path: AIUsageMonitor
    dependencies:
      - target: Shared
    settings:
      base:
        INFOPLIST_FILE: AIUsageMonitor/Info.plist
        CODE_SIGN_ENTITLEMENTS: AIUsageMonitor/AIUsageMonitor.entitlements
        CODE_SIGN_STYLE: Automatic
    entitlements:
      path: AIUsageMonitor/AIUsageMonitor.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
        com.apple.application-groups:
          - group.com.aiusagemonitor
        keychain-access-groups:
          - $(AppIdentifierPrefix)com.aiusagemonitor

  Shared:
    type: framework
    platform: macOS
    sources:
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.aiusagemonitor.Shared

  AIUsageMonitorTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: AIUsageMonitorTests
    dependencies:
      - target: AIUsageMonitor
      - target: Shared
    settings:
      base:
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/AIUsageMonitor.app/Contents/MacOS/AIUsageMonitor"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

**Step 4: Create minimal app entry point**

`AIUsageMonitor/AIUsageApp.swift`:
```swift
import SwiftUI

@main
struct AIUsageApp: App {
    var body: some Scene {
        MenuBarExtra("AI Usage", systemImage: "chart.bar.fill") {
            Text("Loading...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

**Step 5: Create Info.plist**

`AIUsageMonitor/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

`LSUIElement = true` hides the app from the Dock (menu bar only).

**Step 6: Create placeholder test**

`AIUsageMonitorTests/AIUsageMonitorTests.swift`:
```swift
import XCTest
@testable import Shared

final class AIUsageMonitorTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

**Step 7: Create Shared framework placeholder**

`Shared/Shared.swift`:
```swift
import Foundation

// Shared framework for AI Usage Monitor
// Contains models, services, and view models shared between
// the main app and future widget extension.
```

**Step 8: Generate Xcode project**

Run: `cd "/Users/guilledelolmo/Documents/AI Usage App" && xcodegen generate`
Expected: `AIUsageMonitor.xcodeproj` created

**Step 9: Build to verify project setup**

Run: `xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 10: Run placeholder test**

Run: `xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' test 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

**Step 11: Commit**

```bash
git add -A
git commit -m "feat: scaffold project with xcodegen, menu bar app, shared framework"
```

---

### Task 2: Data models (`UsageData`)

**Files:**
- Create: `Shared/Models/UsageData.swift`
- Create: `AIUsageMonitorTests/UsageDataTests.swift`

**Step 1: Write the failing tests**

`AIUsageMonitorTests/UsageDataTests.swift`:
```swift
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
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | tail -10`
Expected: FAIL — `UsageResponse`, `UsageLevel`, `JSONDecoder.apiDecoder` not found

**Step 3: Write the implementation**

`Shared/Models/UsageData.swift`:
```swift
import Foundation
import SwiftUI

public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public var timeUntilReset: TimeInterval {
        resetsAt.timeIntervalSinceNow
    }

    public var formattedTimeUntilReset: String {
        let remaining = max(0, timeUntilReset)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

public struct UsageResponse: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow

    public init(fiveHour: UsageWindow, sevenDay: UsageWindow) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    public var higherUtilization: Double {
        max(fiveHour.utilization, sevenDay.utilization)
    }
}

public enum UsageLevel: Equatable, Sendable {
    case normal    // 0-60%
    case warning   // 60-85%
    case critical  // 85-100%

    public static func from(utilization: Double) -> UsageLevel {
        switch utilization {
        case ...60.0: return .normal
        case ...85.0: return .warning
        default: return .critical
        }
    }

    public var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

extension JSONDecoder {
    public static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | tail -10`
Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add Shared/Models/UsageData.swift AIUsageMonitorTests/UsageDataTests.swift
git commit -m "feat: add UsageData models with JSON decoding and usage levels"
```

---

### Task 3: AuthManager (Keychain + OAuth)

**Files:**
- Create: `Shared/Services/AuthManager.swift`
- Create: `AIUsageMonitorTests/AuthManagerTests.swift`

**Step 1: Write the failing tests**

`AIUsageMonitorTests/AuthManagerTests.swift`:
```swift
import XCTest
@testable import Shared

final class AuthManagerTests: XCTestCase {

    func testParsesClaudeCodeCredentials() throws {
        let json = """
        {
            "claudeAiOauth": {
                "accessToken": "test-token-123",
                "refreshToken": "refresh-456",
                "expiresAt": "2026-12-31T23:59:59Z",
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
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — types not defined

**Step 3: Write the implementation**

`Shared/Services/AuthManager.swift`:
```swift
import Foundation
import AuthenticationServices

// MARK: - Credential Models

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
public final class AuthManager: ObservableObject {
    @Published public var state: AuthState = .notAuthenticated

    public init() {}

    /// Try to load token from Claude Code's Keychain entry first,
    /// then fall back to the app's own stored token.
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
    /// Claude Code stores them under service name "Claude Code-credentials".
    private func loadFromClaudeCode() -> AuthState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard let creds = try? JSONDecoder().decode(ClaudeCodeCredentials.self, from: data) else {
            return nil
        }

        let oauth = creds.claudeAiOauth
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expiresAt = formatter.date(from: oauth.expiresAt) ?? Date.distantFuture

        return .authenticated(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: expiresAt
        )
    }

    /// Load from this app's own Keychain entry (set after OAuth browser flow).
    private func loadFromAppKeychain() -> AuthState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aiusagemonitor.oauth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode(StoredToken.self, from: data) else {
            return nil
        }

        return .authenticated(
            accessToken: dict.accessToken,
            refreshToken: dict.refreshToken,
            expiresAt: dict.expiresAt
        )
    }

    /// Save token to this app's Keychain entry.
    public func saveToken(accessToken: String, refreshToken: String, expiresAt: Date) {
        let stored = StoredToken(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        guard let data = try? JSONEncoder().encode(stored) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aiusagemonitor.oauth"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aiusagemonitor.oauth",
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        state = .authenticated(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    /// Start the OAuth browser flow as fallback.
    /// Uses ASWebAuthenticationSession to open Anthropic's OAuth page.
    public func startOAuthFlow() {
        // OAuth configuration for Anthropic
        // Note: A real implementation would need a registered OAuth client_id.
        // For now, this is a placeholder that shows the structure.
        let authURL = URL(string: "https://console.anthropic.com/oauth/authorize")!
        let callbackScheme = "aiusagemonitor"

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            if let error = error {
                Task { @MainActor in
                    self.state = .error(error.localizedDescription)
                }
                return
            }
            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let token = components.queryItems?.first(where: { $0.name == "access_token" })?.value else {
                Task { @MainActor in
                    self.state = .error("No token received")
                }
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
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Clear stored credentials and reset state.
    public func signOut() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.aiusagemonitor.oauth"
        ]
        SecItemDelete(query as CFDictionary)
        state = .notAuthenticated
    }
}

// MARK: - Internal Storage

struct StoredToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | tail -10`
Expected: All tests PASS (auth state + credential parsing tests; Keychain tests are integration-level)

**Step 5: Commit**

```bash
git add Shared/Services/AuthManager.swift AIUsageMonitorTests/AuthManagerTests.swift
git commit -m "feat: add AuthManager with Keychain + OAuth browser flow support"
```

---

### Task 4: ClaudeAPIClient

**Files:**
- Create: `Shared/Services/ClaudeAPIClient.swift`
- Create: `AIUsageMonitorTests/ClaudeAPIClientTests.swift`

**Step 1: Write the failing tests**

`AIUsageMonitorTests/ClaudeAPIClientTests.swift`:
```swift
import XCTest
@testable import Shared

final class ClaudeAPIClientTests: XCTestCase {

    func testBuildRequest() throws {
        let client = ClaudeAPIClient()
        let request = client.buildUsageRequest(accessToken: "test-token")

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testParsesValidResponse() async throws {
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
}
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `ClaudeAPIClient` not found

**Step 3: Write the implementation**

`Shared/Services/ClaudeAPIClient.swift`:
```swift
import Foundation

public enum APIError: Error, LocalizedError {
    case noToken
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .noToken: return "Not authenticated"
        case .httpError(let code): return "HTTP error \(code)"
        case .decodingError(let err): return "Failed to decode: \(err.localizedDescription)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

public final class ClaudeAPIClient: Sendable {
    private let baseURL = "https://api.anthropic.com/api/oauth/usage"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func buildUsageRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func fetchUsage(accessToken: String) async throws -> UsageResponse {
        let request = buildUsageRequest(accessToken: accessToken)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: -1)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | tail -10`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shared/Services/ClaudeAPIClient.swift AIUsageMonitorTests/ClaudeAPIClientTests.swift
git commit -m "feat: add ClaudeAPIClient for usage API requests"
```

---

### Task 5: UsageStore (shared UserDefaults)

**Files:**
- Create: `Shared/Services/UsageStore.swift`
- Create: `AIUsageMonitorTests/UsageStoreTests.swift`

**Step 1: Write the failing tests**

`AIUsageMonitorTests/UsageStoreTests.swift`:
```swift
import XCTest
@testable import Shared

final class UsageStoreTests: XCTestCase {

    func testSaveAndLoadUsage() {
        // Use standard UserDefaults for testing (not App Group)
        let defaults = UserDefaults.standard
        let store = UsageStore(defaults: defaults)

        let usage = UsageResponse(
            fiveHour: .init(utilization: 55.0, resetsAt: Date()),
            sevenDay: .init(utilization: 30.0, resetsAt: Date())
        )

        store.save(usage)
        let loaded = store.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fiveHour.utilization, 55.0)
        XCTAssertEqual(loaded?.sevenDay.utilization, 30.0)
    }

    func testLoadReturnsNilWhenEmpty() {
        let defaults = UserDefaults(suiteName: "test.empty.\(UUID().uuidString)")!
        let store = UsageStore(defaults: defaults)
        XCTAssertNil(store.load())
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `UsageStore` not found

**Step 3: Write the implementation**

`Shared/Services/UsageStore.swift`:
```swift
import Foundation

public final class UsageStore: Sendable {
    private let defaults: UserDefaults
    private static let key = "cachedUsageData"

    /// Initialize with specific UserDefaults.
    /// For production, pass `UserDefaults(suiteName: "group.com.aiusagemonitor")`.
    /// For testing, pass `UserDefaults.standard` or a test suite.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience initializer using the App Group shared defaults.
    public convenience init() {
        let defaults = UserDefaults(suiteName: "group.com.aiusagemonitor") ?? .standard
        self.init(defaults: defaults)
    }

    public func save(_ usage: UsageResponse) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func load() -> UsageResponse? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shared/Services/UsageStore.swift AIUsageMonitorTests/UsageStoreTests.swift
git commit -m "feat: add UsageStore with App Group shared UserDefaults"
```

---

### Task 6: UsageViewModel (polling + state)

**Files:**
- Create: `Shared/UsageViewModel.swift`
- Create: `AIUsageMonitorTests/UsageViewModelTests.swift`

**Step 1: Write the failing tests**

`AIUsageMonitorTests/UsageViewModelTests.swift`:
```swift
import XCTest
@testable import Shared

@MainActor
final class UsageViewModelTests: XCTestCase {

    func testMenuBarTextFormatting() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())

        // Simulate usage data
        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 72.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .init(utilization: 35.0, resetsAt: Date().addingTimeInterval(86400))
        )

        XCTAssertEqual(vm.menuBarText, "C: 72%")
        XCTAssertEqual(vm.usageLevel, .warning)
    }

    func testMenuBarTextShowsHigherValue() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())

        vm.usage = UsageResponse(
            fiveHour: .init(utilization: 10.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .init(utilization: 90.0, resetsAt: Date().addingTimeInterval(86400))
        )

        XCTAssertEqual(vm.menuBarText, "C: 90%")
        XCTAssertEqual(vm.usageLevel, .critical)
    }

    func testMenuBarTextWhenNoData() {
        let vm = UsageViewModel(apiClient: ClaudeAPIClient(), authManager: AuthManager())
        XCTAssertEqual(vm.menuBarText, "C: --")
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `UsageViewModel` not found

**Step 3: Write the implementation**

`Shared/UsageViewModel.swift`:
```swift
import Foundation
import Combine
import UserNotifications

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public var usage: UsageResponse?
    @Published public var error: String?
    @Published public var isLoading = false

    private let apiClient: ClaudeAPIClient
    private let authManager: AuthManager
    private let store: UsageStore
    private var timer: Timer?
    private let pollInterval: TimeInterval

    // Notification threshold tracking — fire each threshold only once per reset cycle
    private var firedThresholds5h: Set<Int> = []
    private var firedThresholds7d: Set<Int> = []
    private var lastResetAt5h: Date?
    private var lastResetAt7d: Date?

    @Published public var notificationThresholds: [Int] = [75, 90, 100]

    public init(
        apiClient: ClaudeAPIClient = ClaudeAPIClient(),
        authManager: AuthManager = AuthManager(),
        store: UsageStore = UsageStore(),
        pollInterval: TimeInterval = 30
    ) {
        self.apiClient = apiClient
        self.authManager = authManager
        self.store = store
        self.pollInterval = pollInterval

        // Load cached data
        if let cached = store.load() {
            self.usage = cached
        }
    }

    public var menuBarText: String {
        guard let usage = usage else { return "C: --" }
        let pct = Int(usage.higherUtilization.rounded())
        return "C: \(pct)%"
    }

    public var usageLevel: UsageLevel {
        guard let usage = usage else { return .normal }
        return UsageLevel.from(utilization: usage.higherUtilization)
    }

    public func startPolling() {
        authManager.loadToken()
        fetchUsage()

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchUsage()
            }
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    public func fetchUsage() {
        guard let token = authManager.state.accessToken else {
            error = "Not authenticated"
            return
        }

        if authManager.state.isExpired {
            authManager.loadToken()
            guard let newToken = authManager.state.accessToken else {
                error = "Token expired"
                return
            }
            performFetch(token: newToken)
        } else {
            performFetch(token: token)
        }
    }

    private func performFetch(token: String) {
        isLoading = true
        Task {
            do {
                let response = try await apiClient.fetchUsage(accessToken: token)
                self.usage = response
                self.error = nil
                self.store.save(response)
                self.checkThresholds(response)
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    private func checkThresholds(_ usage: UsageResponse) {
        // Reset fired thresholds if we're in a new cycle
        if lastResetAt5h != usage.fiveHour.resetsAt {
            firedThresholds5h.removeAll()
            lastResetAt5h = usage.fiveHour.resetsAt
        }
        if lastResetAt7d != usage.sevenDay.resetsAt {
            firedThresholds7d.removeAll()
            lastResetAt7d = usage.sevenDay.resetsAt
        }

        for threshold in notificationThresholds {
            let t = Double(threshold)

            if usage.fiveHour.utilization >= t && !firedThresholds5h.contains(threshold) {
                firedThresholds5h.insert(threshold)
                sendNotification(window: "5-hour", utilization: usage.fiveHour.utilization, threshold: threshold)
            }

            if usage.sevenDay.utilization >= t && !firedThresholds7d.contains(threshold) {
                firedThresholds7d.insert(threshold)
                sendNotification(window: "7-day", utilization: usage.sevenDay.utilization, threshold: threshold)
            }
        }
    }

    private func sendNotification(window: String, utilization: Double, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Alert"
        content.body = "\(window) usage has reached \(Int(utilization))% (threshold: \(threshold)%)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage-\(window)-\(threshold)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | tail -10`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Shared/UsageViewModel.swift AIUsageMonitorTests/UsageViewModelTests.swift
git commit -m "feat: add UsageViewModel with polling, caching, and notifications"
```

---

### Task 7: UsageDropdownView (SwiftUI dropdown panel)

**Files:**
- Create: `AIUsageMonitor/Views/UsageDropdownView.swift`

**Step 1: Write the view**

`AIUsageMonitor/Views/UsageDropdownView.swift`:
```swift
import SwiftUI
import Shared

struct UsageDropdownView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)

            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if let usage = viewModel.usage {
                UsageRowView(
                    label: "5-hour",
                    window: usage.fiveHour
                )

                UsageRowView(
                    label: "7-day",
                    window: usage.sevenDay
                )
            } else {
                Text("No data yet")
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Settings...") {
                // Will open settings in Task 8
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260)
    }
}

struct UsageRowView: View {
    let label: String
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .frame(width: 50, alignment: .leading)

                ProgressView(value: min(window.utilization / 100.0, 1.0))
                    .tint(UsageLevel.from(utilization: window.utilization).color)

                Text("\(Int(window.utilization))%")
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }

            Text("Resets in \(window.formattedTimeUntilReset)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 54)
        }
    }
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add AIUsageMonitor/Views/UsageDropdownView.swift
git commit -m "feat: add UsageDropdownView with progress bars and reset timers"
```

---

### Task 8: SettingsView

**Files:**
- Create: `AIUsageMonitor/Views/SettingsView.swift`

**Step 1: Write the view**

`AIUsageMonitor/Views/SettingsView.swift`:
```swift
import SwiftUI
import Shared

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var threshold1: Double = 75
    @State private var threshold2: Double = 90
    @State private var threshold3: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .bold()

            GroupBox("Notification Thresholds") {
                VStack(alignment: .leading, spacing: 8) {
                    ThresholdRow(label: "Warning", value: $threshold1)
                    ThresholdRow(label: "High", value: $threshold2)
                    ThresholdRow(label: "Critical", value: $threshold3)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Account") {
                VStack(alignment: .leading, spacing: 8) {
                    if authManager.state.isAuthenticated {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Button("Sign Out") {
                            authManager.signOut()
                        }
                    } else {
                        Label("Not connected", systemImage: "xmark.circle")
                            .foregroundColor(.red)

                        Button("Sign In with Claude") {
                            authManager.startOAuthFlow()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.notificationThresholds = [
                        Int(threshold1), Int(threshold2), Int(threshold3)
                    ]
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            let thresholds = viewModel.notificationThresholds
            if thresholds.count >= 3 {
                threshold1 = Double(thresholds[0])
                threshold2 = Double(thresholds[1])
                threshold3 = Double(thresholds[2])
            }
        }
    }
}

struct ThresholdRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 60, alignment: .leading)
            Slider(value: $value, in: 50...100, step: 5)
            Text("\(Int(value))%")
                .monospacedDigit()
                .frame(width: 40)
        }
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add AIUsageMonitor/Views/SettingsView.swift
git commit -m "feat: add SettingsView with notification thresholds and auth controls"
```

---

### Task 9: Wire everything together in `AIUsageApp`

**Files:**
- Modify: `AIUsageMonitor/AIUsageApp.swift`

**Step 1: Update the app entry point**

Replace `AIUsageMonitor/AIUsageApp.swift` with:
```swift
import SwiftUI
import Shared
import UserNotifications

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var authManager = AuthManager()
    @State private var showSettings = false

    var body: some Scene {
        MenuBarExtra {
            if showSettings {
                SettingsView(viewModel: viewModel, authManager: authManager)
            } else {
                UsageDropdownView(viewModel: viewModel)
                    .onAppear {
                        // Wire settings button action via environment or callback
                    }
            }
        } label: {
            Text(viewModel.menuBarText)
                .foregroundColor(viewModel.usageLevel.color)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
```

> **Note:** The settings toggle and view wiring may need adjustment during implementation. The `MenuBarExtra` with `.window` style allows showing SwiftUI views in the dropdown. The settings button in `UsageDropdownView` should toggle the `showSettings` state. A cleaner approach may be to use `Window` scene for settings as a separate window — adjust during implementation based on what works best with `MenuBarExtra`.

**Step 2: Start polling on app launch**

Add `.onAppear` to the dropdown view to call `viewModel.startPolling()`:
```swift
UsageDropdownView(viewModel: viewModel)
    .onAppear {
        if !isPolling {
            viewModel.startPolling()
            isPolling = true
        }
    }
```

Add `@State private var isPolling = false` to the app struct.

**Step 3: Build and run**

Run: `xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add AIUsageMonitor/AIUsageApp.swift
git commit -m "feat: wire up app entry point with MenuBarExtra, polling, and notifications"
```

---

### Task 10: Run all tests + final verification

**Step 1: Run full test suite**

Run: `xcodebuild test -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitorTests -destination 'platform=macOS' 2>&1 | tail -15`
Expected: All tests PASS

**Step 2: Build release**

Run: `xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -configuration Release -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Manual smoke test**

Run the app from Xcode or the build directory. Verify:
- Menu bar shows `C: --` (or actual percentage if Claude Code token found)
- Clicking the menu bar item shows the dropdown panel
- Color coding works (may need to test with mock data)

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup and verification"
```
