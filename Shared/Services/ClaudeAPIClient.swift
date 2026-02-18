import Foundation

public enum APIError: Error, LocalizedError {
    case noToken
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .noToken:
            return "Not authenticated"
        case .httpError(let code):
            return "HTTP error \(code)"
        case .decodingError(let err):
            return "Decoding failed: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        }
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

        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
