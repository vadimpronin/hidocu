import Foundation
@testable import LLMService

final class MockAccountSession: LLMAccountSession, @unchecked Sendable {
    var info: LLMAccountInfo
    var credentials: LLMCredentials
    var saveCallCount = 0
    var savedInfo: LLMAccountInfo?
    var savedCredentials: LLMCredentials?

    init(provider: LLMProvider, credentials: LLMCredentials = LLMCredentials()) {
        self.info = LLMAccountInfo(provider: provider)
        self.credentials = credentials
    }

    func getCredentials() async throws -> LLMCredentials {
        return credentials
    }

    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws {
        self.info = info
        self.credentials = credentials
        self.savedInfo = info
        self.savedCredentials = credentials
        self.saveCallCount += 1
    }
}
