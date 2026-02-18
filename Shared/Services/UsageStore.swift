import Foundation

public final class UsageStore: Sendable {
    private let defaults: UserDefaults
    private static let key = "cachedUsageData"

    /// Initialize with a specific `UserDefaults` instance.
    /// - For production: pass `UserDefaults(suiteName: "group.com.aiusagemonitor") ?? .standard`
    /// - For testing: pass a fresh `UserDefaults(suiteName: UUID().uuidString)` to isolate state
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience initializer using the App Group shared defaults.
    /// Falls back to `UserDefaults.standard` if the App Group is not configured
    /// (e.g. unsigned debug builds).
    public convenience init() {
        let defaults = UserDefaults(suiteName: "group.com.aiusagemonitor") ?? .standard
        self.init(defaults: defaults)
    }

    public func save(_ usage: UsageResponse) {
        guard let data = try? JSONEncoder.apiEncoder.encode(usage) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func load() -> UsageResponse? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
    }
}
