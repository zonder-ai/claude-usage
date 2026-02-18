import XCTest
@testable import Shared

final class ClaudeAPIClientTests: XCTestCase {

    func testBuildRequest() {
        let client = ClaudeAPIClient()
        let request = client.buildUsageRequest(accessToken: "test-token")

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testParsesValidResponse() throws {
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

    func testAPIErrorDescriptions() {
        XCTAssertEqual(APIError.noToken.errorDescription, "Not authenticated")
        XCTAssertNotNil(APIError.httpError(statusCode: 401).errorDescription)
        XCTAssertNotNil(APIError.networkError(URLError(.notConnectedToInternet)).errorDescription)
    }
}

// MARK: - Mock URL Protocol

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - fetchUsage integration tests

extension ClaudeAPIClientTests {

    private func makeMockClient() -> ClaudeAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return ClaudeAPIClient(session: URLSession(configuration: config))
    }

    func testFetchUsageSuccess() async throws {
        let json = """
        {
            "five_hour": { "utilization": 50.0, "resets_at": "2026-02-18T20:00:00+00:00" },
            "seven_day": { "utilization": 25.0, "resets_at": "2026-02-24T00:00:00+00:00" }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json)
        }

        let client = makeMockClient()
        let result = try await client.fetchUsage(accessToken: "token")
        XCTAssertEqual(result.fiveHour.utilization, 50.0)
        XCTAssertEqual(result.sevenDay.utilization, 25.0)
    }

    func testFetchUsageHTTPError() async {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = makeMockClient()
        do {
            _ = try await client.fetchUsage(accessToken: "bad-token")
            XCTFail("Expected APIError.httpError")
        } catch APIError.httpError(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchUsageNetworkError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let client = makeMockClient()
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            XCTFail("Expected APIError.networkError")
        } catch APIError.networkError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchUsageDecodingError() async {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "not json".data(using: .utf8)!)
        }

        let client = makeMockClient()
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            XCTFail("Expected APIError.decodingError")
        } catch APIError.decodingError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
