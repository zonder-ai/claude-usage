import Foundation
import SwiftUI

public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date
    public let tokensUsed: Int?
    public let tokensLimit: Int?

    public init(utilization: Double, resetsAt: Date, tokensUsed: Int? = nil, tokensLimit: Int? = nil) {
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.tokensUsed = tokensUsed
        self.tokensLimit = tokensLimit
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt    = "resets_at"
        case tokensUsed  = "tokens_used"
        case tokensLimit = "tokens_limit"
    }

    public var tokensRemaining: Int? {
        guard let used = tokensUsed, let limit = tokensLimit else { return nil }
        return max(0, limit - used)
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

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let fiveHourUtilization: Double
    public let sevenDayUtilization: Double

    public init(timestamp: Date, fiveHourUtilization: Double, sevenDayUtilization: Double) {
        self.timestamp = timestamp
        self.fiveHourUtilization = fiveHourUtilization
        self.sevenDayUtilization = sevenDayUtilization
    }
}

extension UsageSnapshot: Identifiable {
    public var id: Date { timestamp }
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

// UsageLevel is derived from utilization at display time — intentionally not Codable.
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
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: dateStr) { return date }
            if let date = plainFormatter.date(from: dateStr) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(dateStr)"
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    /// Encodes `Date` as ISO 8601 with fractional seconds — symmetric with `JSONDecoder.apiDecoder`.
    public static let apiEncoder: JSONEncoder = {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return encoder
    }()
}
