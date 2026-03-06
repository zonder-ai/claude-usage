import Foundation

public enum APIError: Error, LocalizedError {
    case noToken
    case httpError(statusCode: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)

    public var isAuthError: Bool {
        if case .apiError(let msg) = self {
            let lower = msg.lowercased()
            return lower.contains("invalid") || lower.contains("token") || lower.contains("authentication")
        }
        if case .httpError(let code) = self { return code == 401 || code == 403 }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .noToken:
            return "Not authenticated"
        case .httpError(let code):
            return "HTTP error \(code)"
        case .rateLimited:
            return "Anthropic rate limit reached"
        case .apiError(let message):
            return message
        case .decodingError(let err):
            return "Decoding failed: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
    }
}

/// The API returns HTTP 200 even for auth errors, with this body shape.
private struct APIErrorResponse: Codable {
    let type: String
    let error: APIErrorDetail

    struct APIErrorDetail: Codable {
        let type: String
        let message: String
    }
}

public final class ClaudeAPIClient: Sendable {
    private let usageURL: URL
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        self.session = session
    }

    public func buildUsageRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
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

        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: -1)
        }

        if http.statusCode == 429 {
            throw APIError.rateLimited(retryAfter: retryAfterInterval(from: http))
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        // The API returns HTTP 200 even for auth errors — check for error body first.
        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           errorResponse.type == "error" {
            throw APIError.apiError(errorResponse.error.message)
        }

        do {
            return try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(rawValue), seconds > 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: rawValue) else { return nil }

        let interval = date.timeIntervalSinceNow
        return interval > 0 ? interval : nil
    }
}
