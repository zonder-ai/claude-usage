import Foundation

/// All mutating methods must be called from the same actor (in practice @MainActor via UsageViewModel).
public final class UsageHistoryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "usageHistory"
    private static let maxEntries = 360
    private static let maxAge: TimeInterval = 5 * 3600

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public convenience init() {
        let defaults = UserDefaults(suiteName: "group.com.aiusagemonitor") ?? .standard
        self.init(defaults: defaults)
    }

    public func append(_ snapshot: UsageSnapshot) {
        var history = load()
        history.append(snapshot)
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        history = history.filter { $0.timestamp > cutoff }
        if history.count > Self.maxEntries {
            history = Array(history.suffix(Self.maxEntries))
        }
        guard let data = try? JSONEncoder.apiEncoder.encode(history) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func load() -> [UsageSnapshot] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder.apiDecoder.decode([UsageSnapshot].self, from: data)) ?? []
    }
}
