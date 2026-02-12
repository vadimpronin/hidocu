import XCTest
@testable import LLMService

final class AntigravityModelFetcherTests: XCTestCase {

    func testFetchAvailableModels() async throws {
        let mockClient = MockHTTPClient()
        let modelsResponse: [String: Any] = [
            "models": [
                "gemini-2.5-flash": ["displayName": "Gemini 2.5 Flash"],
                "claude-sonnet-4-5-20250929": ["displayName": "Claude Sonnet 4.5"],
            ]
        ]
        mockClient.enqueue(.json(modelsResponse))

        let credentials = LLMCredentials(accessToken: "test-token")
        let models = try await AntigravityModelFetcher.fetchAvailableModels(
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(models.count, 2)
        XCTAssertTrue(models.contains(where: { $0.id == "gemini-2.5-flash" }))
        XCTAssertTrue(models.contains(where: { $0.id == "claude-sonnet-4-5-20250929" }))

        // Verify display names are extracted
        let flash = models.first(where: { $0.id == "gemini-2.5-flash" })
        XCTAssertEqual(flash?.displayName, "Gemini 2.5 Flash")

        // Verify request structure
        let captured = mockClient.capturedRequests.first
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.url?.absoluteString, "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")
        XCTAssertEqual(captured?.httpMethod, "POST")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "User-Agent"), "antigravity/1.104.0 darwin/arm64")
        // Should NOT have X-Goog-Api-Client
        XCTAssertNil(captured?.value(forHTTPHeaderField: "X-Goog-Api-Client"))
        // Should NOT have Client-Metadata (Gemini-only header)
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Client-Metadata"))

        // Verify empty body
        if let body = captured?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            XCTAssertTrue(json.isEmpty)
        } else {
            XCTFail("Expected empty JSON body")
        }
    }

    func testSkipsBlocklistedModels() async throws {
        let mockClient = MockHTTPClient()
        let modelsResponse: [String: Any] = [
            "models": [
                "gemini-2.5-flash": ["displayName": "Gemini 2.5 Flash"],
                "chat_20706": ["displayName": "Chat"],
                "chat_23310": ["displayName": "Chat 2"],
            ]
        ]
        mockClient.enqueue(.json(modelsResponse))

        let credentials = LLMCredentials(accessToken: "test")
        let models = try await AntigravityModelFetcher.fetchAvailableModels(
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.id, "gemini-2.5-flash")
    }

    func testFetchReturnsSortedByModelId() async throws {
        let mockClient = MockHTTPClient()
        let modelsResponse: [String: Any] = [
            "models": [
                "gemini-2.5-flash": ["displayName": "Flash"],
                "claude-sonnet-4-5": ["displayName": "Claude"],
                "gemini-2.0-flash": ["displayName": "Flash 2.0"],
            ]
        ]
        mockClient.enqueue(.json(modelsResponse))

        let credentials = LLMCredentials(accessToken: "test")
        let models = try await AntigravityModelFetcher.fetchAvailableModels(
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(models.map(\.id), ["claude-sonnet-4-5", "gemini-2.0-flash", "gemini-2.5-flash"])
    }

    func testFetchThrowsOnNon2xx() async throws {
        let mockClient = MockHTTPClient()
        mockClient.enqueue(.error(403, message: "Forbidden"))

        let credentials = LLMCredentials(accessToken: "bad-token")
        do {
            _ = try await AntigravityModelFetcher.fetchAvailableModels(
                credentials: credentials,
                httpClient: mockClient
            )
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error.statusCode, 403)
        }
    }

    func testFetchThrowsOnMissingModels() async throws {
        let mockClient = MockHTTPClient()
        mockClient.enqueue(.json(["notModels": "wrong"]))

        let credentials = LLMCredentials(accessToken: "test")
        do {
            _ = try await AntigravityModelFetcher.fetchAvailableModels(
                credentials: credentials,
                httpClient: mockClient
            )
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertTrue(error.message.contains("Missing models"))
        }
    }

    func testFetchReturnsEmptyArrayForEmptyModels() async throws {
        let mockClient = MockHTTPClient()
        mockClient.enqueue(.json(["models": [:] as [String: Any]]))

        let credentials = LLMCredentials(accessToken: "test")
        let models = try await AntigravityModelFetcher.fetchAvailableModels(
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertTrue(models.isEmpty)
    }

    func testFetchFallsBackToModelIdForDisplayName() async throws {
        let mockClient = MockHTTPClient()
        let modelsResponse: [String: Any] = [
            "models": [
                "some-model": [:] as [String: Any],  // No displayName
            ]
        ]
        mockClient.enqueue(.json(modelsResponse))

        let credentials = LLMCredentials(accessToken: "test")
        let models = try await AntigravityModelFetcher.fetchAvailableModels(
            credentials: credentials,
            httpClient: mockClient
        )

        XCTAssertEqual(models.first?.displayName, "some-model")
    }
}
