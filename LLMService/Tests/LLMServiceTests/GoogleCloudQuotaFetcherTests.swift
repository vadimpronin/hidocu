import XCTest
@testable import LLMService

final class GeminiQuotaFetcherTests: XCTestCase {

    func testFetchAvailableModelIds() async throws {
        let mockClient = MockHTTPClient()
        let quotaResponse: [String: Any] = [
            "buckets": [
                ["modelId": "gemini-2.5-pro", "remainingFraction": 1.0, "tokenType": "REQUESTS"],
                ["modelId": "gemini-2.5-pro_vertex", "remainingFraction": 1.0, "tokenType": "REQUESTS"],
                ["modelId": "gemini-2.5-flash", "remainingFraction": 0.8, "tokenType": "REQUESTS"],
                ["modelId": "gemini-2.5-flash_vertex", "remainingFraction": 0.8, "tokenType": "REQUESTS"],
                ["modelId": "gemini-2.0-flash", "remainingFraction": 1.0, "tokenType": "REQUESTS"],
            ]
        ]
        mockClient.enqueue(.json(quotaResponse))

        let credentials = LLMCredentials(accessToken: "test-token")
        let modelIds = try await GeminiQuotaFetcher.fetchAvailableModelIds(
            projectId: "test-project",
            credentials: credentials,
            httpClient: mockClient
        )

        // Should have 3 unique models (_vertex variants filtered)
        XCTAssertEqual(modelIds.count, 3)
        XCTAssertTrue(modelIds.contains("gemini-2.5-pro"))
        XCTAssertTrue(modelIds.contains("gemini-2.5-flash"))
        XCTAssertTrue(modelIds.contains("gemini-2.0-flash"))
        XCTAssertFalse(modelIds.contains("gemini-2.5-pro_vertex"))

        // Verify request structure
        let captured = mockClient.capturedRequests.first
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.url?.absoluteString, "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
        XCTAssertEqual(captured?.httpMethod, "POST")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "User-Agent"), "google-api-nodejs-client/9.15.1")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-Goog-Api-Client"), "gl-node/22.17.0")

        // Verify request body contains project
        if let body = captured?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            XCTAssertEqual(json["project"] as? String, "test-project")
        } else {
            XCTFail("Expected JSON body with project field")
        }
    }

    func testFetchReturnsSortedIds() async throws {
        let mockClient = MockHTTPClient()
        let quotaResponse: [String: Any] = [
            "buckets": [
                ["modelId": "gemini-2.5-flash", "tokenType": "REQUESTS"],
                ["modelId": "gemini-2.0-flash", "tokenType": "REQUESTS"],
                ["modelId": "gemini-2.5-pro", "tokenType": "REQUESTS"],
            ]
        ]
        mockClient.enqueue(.json(quotaResponse))

        let credentials = LLMCredentials(accessToken: "test")
        let modelIds = try await GeminiQuotaFetcher.fetchAvailableModelIds(
            projectId: "proj",
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(modelIds, ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"])
    }

    func testFetchThrowsOnNon2xx() async throws {
        let mockClient = MockHTTPClient()
        mockClient.enqueue(.error(403, message: "Forbidden"))

        let credentials = LLMCredentials(accessToken: "bad-token")
        do {
            _ = try await GeminiQuotaFetcher.fetchAvailableModelIds(
                projectId: "test",
                credentials: credentials,
                httpClient: mockClient
            )
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error.statusCode, 403)
        }
    }

    func testFetchThrowsOnMissingBuckets() async throws {
        let mockClient = MockHTTPClient()
        mockClient.enqueue(.json(["notBuckets": "wrong"]))

        let credentials = LLMCredentials(accessToken: "test")
        do {
            _ = try await GeminiQuotaFetcher.fetchAvailableModelIds(
                projectId: "test",
                credentials: credentials,
                httpClient: mockClient
            )
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertTrue(error.message.contains("Missing buckets"))
        }
    }

    func testFetchSkipsEmptyModelIds() async throws {
        let mockClient = MockHTTPClient()
        let quotaResponse: [String: Any] = [
            "buckets": [
                ["modelId": "gemini-2.5-pro", "tokenType": "REQUESTS"],
                ["modelId": "", "tokenType": "REQUESTS"],
                ["tokenType": "REQUESTS"],
            ]
        ]
        mockClient.enqueue(.json(quotaResponse))

        let credentials = LLMCredentials(accessToken: "test")
        let modelIds = try await GeminiQuotaFetcher.fetchAvailableModelIds(
            projectId: "proj",
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(modelIds, ["gemini-2.5-pro"])
    }
}

final class AntigravityQuotaFetcherTests: XCTestCase {

    func testFetchAvailableModelIds() async throws {
        let mockClient = MockHTTPClient()
        let quotaResponse: [String: Any] = [
            "buckets": [
                ["modelId": "gemini-2.5-pro", "tokenType": "REQUESTS"],
                ["modelId": "claude-sonnet-4-5-20250929", "tokenType": "REQUESTS"],
            ]
        ]
        mockClient.enqueue(.json(quotaResponse))

        let credentials = LLMCredentials(accessToken: "test-token")
        let modelIds = try await AntigravityQuotaFetcher.fetchAvailableModelIds(
            projectId: "test-project",
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(modelIds.count, 2)

        // Verify Antigravity-specific headers
        let captured = mockClient.capturedRequests.first
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "User-Agent"), "antigravity/1.104.0 darwin/arm64")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-Goog-Api-Client"), "google-cloud-sdk vscode_cloudshelleditor/0.1")
    }
}
