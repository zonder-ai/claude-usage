import Foundation
import SwiftUI

public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
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
