public protocol LLMAccountSession: AnyObject, Sendable {
    var info: LLMAccountInfo { get }
    func getCredentials() async throws -> LLMCredentials
    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws
}
