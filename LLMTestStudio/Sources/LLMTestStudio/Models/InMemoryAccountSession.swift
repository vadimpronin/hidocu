import Foundation
import LLMService

final class InMemoryAccountSession: LLMAccountSession, @unchecked Sendable {
    private let lock = NSLock()
    private var _info: LLMAccountInfo
    private var _credentials: LLMCredentials

    var info: LLMAccountInfo {
        lock.withLock { _info }
    }

    var isLoggedIn: Bool {
        lock.withLock {
            _credentials.accessToken != nil || _credentials.apiKey != nil
        }
    }

    init(provider: LLMProvider) {
        self._info = LLMAccountInfo(provider: provider)
        self._credentials = LLMCredentials()
    }

    func getCredentials() async throws -> LLMCredentials {
        lock.withLock { _credentials }
    }

    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws {
        lock.withLock {
            self._info = info
            self._credentials = credentials
        }
    }

    func logout() {
        lock.withLock {
            let provider = _info.provider
            self._credentials = LLMCredentials()
            self._info = LLMAccountInfo(provider: provider)
        }
    }
}
