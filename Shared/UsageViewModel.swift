import Foundation
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public var usage: UsageResponse?
    @Published public var error: String?
    @Published public var isLoading = false
    @Published public var notificationThresholds: [Int] = [50, 75, 90, 100]
    @Published public var lastUpdated: Date?
    @Published public var history: [UsageSnapshot] = []
    @Published public var activity: [ClaudeActivityEntry] = []
    @Published public var activityError: String?
    @Published public var agentToasts: [AgentToastItem] = []
    @Published public private(set) var rateLimitedUntil: Date?

    private let apiClient: ClaudeAPIClient
    public let authManager: AuthManager
    private let store: UsageStore
    private let historyStore: UsageHistoryStore
    private let activityStore: ClaudeActivityStore
    private let toastStore: AgentToastStore
    private let pollInterval: TimeInterval
    private let now: () -> Date
    private let jitter: (TimeInterval) -> TimeInterval
    private var timer: Timer?
    private var queueMonitorTimer: Timer?
    private let maxVisibleToasts = 3
    private let queuePollInterval: TimeInterval = 1
    private(set) public var isAgentToastsEnabled = true
    public var onAgentToastsChanged: (([AgentToastItem]) -> Void)?
    private var consecutiveRateLimitFailures = 0

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
        historyStore: UsageHistoryStore? = nil,
        activityStore: ClaudeActivityStore? = nil,
        toastStore: AgentToastStore? = nil,
        pollInterval: TimeInterval = 60,
        now: @escaping () -> Date = Date.init,
        jitter: @escaping (TimeInterval) -> TimeInterval = { base in
            base * Double.random(in: -0.15...0.15)
        }
    ) {
        self.apiClient = apiClient
        self.authManager = authManager ?? AuthManager()
        self.store = store ?? UsageStore()
        self.historyStore = historyStore ?? UsageHistoryStore()
        self.activityStore = activityStore ?? ClaudeActivityStore()
        self.toastStore = toastStore ?? AgentToastStore()
        self.pollInterval = pollInterval
        self.now = now
        self.jitter = jitter

        // Load cached data to show something immediately on launch
        self.usage = self.store.load()
        self.history = self.historyStore.load()
        self.activity = (try? self.activityStore.loadRecent(limit: 6, projectPath: nil)) ?? []

        // Refresh immediately whenever the Mac wakes from sleep or the user
        // logs back in, so the number is never stale after a restart/wake.
        #if canImport(AppKit)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fetchUsage() }
        }
        #endif
    }

    // MARK: - Derived state

    public var menuBarText: String {
        guard let usage else { return "--%"}
        return "\(Int(usage.fiveHour.utilization.rounded()))%"
    }

    public var usageLevel: UsageLevel {
        guard let usage else { return .normal }
        return UsageLevel.from(utilization: usage.fiveHour.utilization)
    }

    public var authSourceDescription: String? {
        authManager.state.sourceDescription
    }

    public func isRateLimited(at date: Date) -> Bool {
        guard let rateLimitedUntil else { return false }
        return rateLimitedUntil > date
    }

    public func statusMessage(at date: Date) -> String? {
        if let cooldown = rateLimitMessage(at: date) {
            return cooldown
        }
        return error
    }

    // MARK: - Polling

    public func startPolling() {
        stopPolling()  // invalidate any existing timer before scheduling a new one
        fetchUsage()
        startQueueMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fetchUsage() }
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
        stopQueueMonitoring()
    }

    public func fetchUsage() {
        Task { @MainActor [weak self] in
            await self?.fetchUsageNow()
        }
    }

    func fetchUsageNow() async {
        refreshActivity()

        let currentTime = now()
        if shouldSkipFetch(at: currentTime) {
            return
        }

        await authManager.ensureValidToken()
        guard case .authenticated(let token, _, _, _) = authManager.state else {
            error = "Not authenticated — sign in via Settings"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.fetchUsage(accessToken: token)
            clearRateLimitState()
            usage = response
            error = nil
            store.save(response)
            recordSnapshot(for: response)
            checkNotificationThresholds(response)
        } catch let apiErr as APIError where apiErr.isAuthError {
            clearRateLimitState()
            authManager.signOut()
            error = "Session expired — please sign in again"
        } catch APIError.rateLimited(let retryAfter) {
            applyRateLimit(retryAfter: retryAfter, at: now())
        } catch let fetchError {
            error = fetchError.localizedDescription
        }
    }

    public func refreshActivity() {
        do {
            self.activity = try self.activityStore.loadRecent(limit: 6, projectPath: nil)
            self.activityError = nil
        } catch {
            self.activityError = "Couldn’t read Claude activity log"
        }
    }

    public func setAgentToastsEnabled(_ enabled: Bool) {
        isAgentToastsEnabled = enabled
        if enabled {
            startQueueMonitoring()
            refreshQueueActivity()
        } else {
            stopQueueMonitoring()
            toastStore.reset()
            publishAgentToasts([])
        }
    }

    public func dismissAgentToast(id: String) {
        toastStore.dismissToast(id: id)
        publishAgentToasts(toastStore.visibleToasts(maxCount: maxVisibleToasts))
    }

    public func refreshQueueActivity() {
        guard isAgentToastsEnabled else {
            publishAgentToasts([])
            return
        }

        // Advance file read offsets (drives both queue and transcript state)
        try? activityStore.pollQueueEvents()

        // Transcript-based activity: one toast per session currently calling tools
        let sessions = activityStore.currentTranscriptActivity(idleTimeout: 10)
        toastStore.apply(sessions: sessions)
        toastStore.tick(now: Date())
        publishAgentToasts(toastStore.visibleToasts(maxCount: maxVisibleToasts))
    }

    private func startQueueMonitoring() {
        stopQueueMonitoring()
        guard isAgentToastsEnabled else { return }
        queueMonitorTimer = Timer.scheduledTimer(withTimeInterval: queuePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshQueueActivity() }
        }
    }

    private func stopQueueMonitoring() {
        queueMonitorTimer?.invalidate()
        queueMonitorTimer = nil
    }

    private func publishAgentToasts(_ toasts: [AgentToastItem]) {
        agentToasts = toasts
        onAgentToastsChanged?(toasts)
    }

    // MARK: - History

    func recordSnapshot(for response: UsageResponse) {
        let snapshot = UsageSnapshot(
            timestamp: now(),
            fiveHourUtilization: response.fiveHour.utilization,
            sevenDayUtilization: response.sevenDay.utilization
        )
        historyStore.append(snapshot)
        history = historyStore.load()
        lastUpdated = now()
    }

    private func shouldSkipFetch(at date: Date) -> Bool {
        guard let rateLimitedUntil else { return false }
        if rateLimitedUntil > date {
            return true
        }
        // Cooldown window elapsed, but keep the 429 streak until a successful fetch.
        self.rateLimitedUntil = nil
        return false
    }

    private func applyRateLimit(retryAfter: TimeInterval?, at date: Date) {
        let delay: TimeInterval
        if let retryAfter, retryAfter > 0 {
            delay = retryAfter
        } else {
            let baseDelay = min(60 * pow(2, Double(consecutiveRateLimitFailures)), 900)
            delay = min(900, max(1, baseDelay + jitter(baseDelay)))
        }

        rateLimitedUntil = date.addingTimeInterval(delay)
        consecutiveRateLimitFailures += 1
        error = nil
    }

    private func clearRateLimitState() {
        rateLimitedUntil = nil
        consecutiveRateLimitFailures = 0
    }

    private func rateLimitMessage(at date: Date) -> String? {
        guard let rateLimitedUntil, rateLimitedUntil > date else { return nil }
        return "Anthropic rate limit reached. Retrying in \(formattedRemainingTime(until: rateLimitedUntil, now: date))."
    }

    private func formattedRemainingTime(until: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(until.timeIntervalSince(now).rounded(.up)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
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
