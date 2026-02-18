import Foundation
import UserNotifications

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public var usage: UsageResponse?
    @Published public var error: String?
    @Published public var isLoading = false
    @Published public var notificationThresholds: [Int] = [75, 90, 100]

    private let apiClient: ClaudeAPIClient
    public let authManager: AuthManager
    private let store: UsageStore
    private let pollInterval: TimeInterval
    private var timer: Timer?

    // Track which thresholds have already fired per reset cycle
    private var firedThresholds5h: Set<Int> = []
    private var firedThresholds7d: Set<Int> = []
    private var lastResetAt5h: Date?
    private var lastResetAt7d: Date?

    /// Designated initialiser. All parameters with `@MainActor`-isolated default
    /// constructors are made optional so Swift doesn't need to evaluate them in a
    /// nonisolated context when building the default-argument thunk.
    public init(
        apiClient: ClaudeAPIClient = ClaudeAPIClient(),
        authManager: AuthManager? = nil,
        store: UsageStore? = nil,
        pollInterval: TimeInterval = 30
    ) {
        self.apiClient = apiClient
        self.authManager = authManager ?? AuthManager()
        self.store = store ?? UsageStore()
        self.pollInterval = pollInterval

        // Load cached data to show something immediately on launch
        self.usage = self.store.load()
    }

    // MARK: - Derived state

    public var menuBarText: String {
        guard let usage else { return "C: --" }
        return "C: \(Int(usage.higherUtilization.rounded()))%"
    }

    public var usageLevel: UsageLevel {
        guard let usage else { return .normal }
        return UsageLevel.from(utilization: usage.higherUtilization)
    }

    // MARK: - Polling

    public func startPolling() {
        stopPolling()  // invalidate any existing timer before scheduling a new one
        authManager.loadToken()
        fetchUsage()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fetchUsage() }
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    public func fetchUsage() {
        guard case .authenticated(let token, _, _) = authManager.state else {
            error = "Not authenticated — sign in via Settings"
            return
        }

        if authManager.state.isExpired {
            authManager.loadToken()
            guard case .authenticated(let refreshedToken, _, _) = authManager.state else {
                error = "Session expired — sign in again"
                return
            }
            performFetch(token: refreshedToken)
        } else {
            performFetch(token: token)
        }
    }

    private func performFetch(token: String) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await apiClient.fetchUsage(accessToken: token)
                self.usage = response
                self.error = nil
                self.store.save(response)
                self.checkNotificationThresholds(response)
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    // MARK: - Notifications

    private func checkNotificationThresholds(_ usage: UsageResponse) {
        // Reset fired thresholds when the reset cycle rolls over
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
            if usage.fiveHour.utilization >= t, !firedThresholds5h.contains(threshold) {
                firedThresholds5h.insert(threshold)
                sendNotification(window: "5-hour", utilization: usage.fiveHour.utilization, threshold: threshold)
            }
            if usage.sevenDay.utilization >= t, !firedThresholds7d.contains(threshold) {
                firedThresholds7d.insert(threshold)
                sendNotification(window: "7-day", utilization: usage.sevenDay.utilization, threshold: threshold)
            }
        }
    }

    private func sendNotification(window: String, utilization: Double, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Alert"
        content.body = "\(window) usage reached \(Int(utilization.rounded()))% (threshold: \(threshold)%)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "usage-\(window)-\(threshold)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
