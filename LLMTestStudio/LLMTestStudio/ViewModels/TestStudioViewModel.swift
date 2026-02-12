import AppKit
import Foundation
import LLMService
import OSLog
import UniformTypeIdentifiers

enum ChatMode: String, CaseIterable {
    case streaming = "Streaming"
    case automatic = "Automatic"
}

@Observable
@MainActor
final class TestStudioViewModel {
    // MARK: - State

    var selectedProvider: LLMProvider = .claudeCode
    var selectedModelId: String?
    var models: [LLMModelInfo] = []
    var chatHistories: [LLMProvider: [ChatMessage]] = [:]
    var isStreaming = false
    var currentStreamingMessage: ChatMessage?
    var debugEnabled = true
    var logEntries: [LogEntry] = []
    var inputText = ""
    var thinkingEnabled = false
    var thinkingBudget: Int = 10000
    var chatMode: ChatMode = .streaming

    // Network Console
    var networkEntries: [NetworkRequestEntry] = []
    var selectedTraceIds: Set<String> = []
    var selectedDetailTraceId: String?
    var networkFilterText: String = ""

    // MARK: - Private

    /// Bumped after login/logout to trigger SwiftUI re-render for `isLoggedIn(for:)`.
    /// `InMemoryAccountSession` is not `@Observable`, so we need a tracked dependency.
    private var authStateVersion = 0

    private var sessions: [LLMProvider: InMemoryAccountSession] = [:]
    private var services: [LLMProvider: LLMService] = [:]
    private let logger = Logger(subsystem: "com.llmteststudio", category: "viewmodel")
    private var streamTask: Task<Void, Never>?
    private var streamGeneration = 0
    private var networkEntriesById: [String: NetworkRequestEntry] = [:]

    // MARK: - Init

    init() {
        for provider in Self.supportedProviders {
            sessions[provider] = InMemoryAccountSession(provider: provider)
            chatHistories[provider] = []
        }
    }

    static let supportedProviders: [LLMProvider] = [.claudeCode, .geminiCLI, .antigravity]

    // MARK: - Session Access

    private func session(for provider: LLMProvider) -> InMemoryAccountSession {
        if let existing = sessions[provider] {
            return existing
        }
        let session = InMemoryAccountSession(provider: provider)
        sessions[provider] = session
        return session
    }

    func isLoggedIn(for provider: LLMProvider) -> Bool {
        _ = authStateVersion // observation dependency
        return session(for: provider).isLoggedIn
    }

    var currentMessages: [ChatMessage] {
        get { chatHistories[selectedProvider] ?? [] }
        set { chatHistories[selectedProvider] = newValue }
    }

    var selectedDetailEntry: NetworkRequestEntry? {
        guard let id = selectedDetailTraceId else { return nil }
        return networkEntriesById[id]
    }

    func networkEntry(byId id: String) -> NetworkRequestEntry? {
        networkEntriesById[id]
    }

    var filteredNetworkEntries: [NetworkRequestEntry] {
        guard !networkFilterText.isEmpty else { return networkEntries }
        let filter = networkFilterText.lowercased()
        return networkEntries.filter { entry in
            entry.fullURL.lowercased().contains(filter)
                || entry.provider.lowercased().contains(filter)
                || entry.httpMethod.lowercased().contains(filter)
                || entry.statusText.lowercased().contains(filter)
        }
    }

    // MARK: - Service Management

    private func service(for provider: LLMProvider) -> LLMService {
        if let existing = services[provider] {
            return existing
        }
        let sess = session(for: provider)
        let config = makeLoggingConfig()
        let svc = LLMService(session: sess, loggingConfig: config)
        services[provider] = svc
        return svc
    }

    private func makeLoggingConfig() -> LLMLoggingConfig {
        let dir: URL? = debugEnabled
            ? FileManager.default.temporaryDirectory.appendingPathComponent("LLMTestStudio_logs")
            : nil
        return LLMLoggingConfig(
            subsystem: "com.llmteststudio",
            storageDirectory: dir,
            shouldMaskTokens: false,
            onTraceSent: { [weak self] entry in
                let viewModel = self
                Task { @MainActor in
                    viewModel?.handleTraceSent(entry)
                }
            },
            onTraceRecorded: { [weak self] entry in
                let viewModel = self
                Task { @MainActor in
                    viewModel?.handleTraceRecorded(entry)
                }
            }
        )
    }

    // MARK: - Auth

    func login(provider: LLMProvider) async {
        log("Starting login for \(provider.rawValue)...", level: .info)
        do {
            let svc = service(for: provider)
            try await svc.login()
            authStateVersion += 1
            log("Login succeeded for \(provider.rawValue)", level: .info)
        } catch {
            log("Login failed for \(provider.rawValue): \(error.localizedDescription)", level: .error)
        }
    }

    func logout(provider: LLMProvider) {
        session(for: provider).logout()
        services[provider] = nil
        authStateVersion += 1
        log("Logged out from \(provider.rawValue)", level: .info)
    }

    // MARK: - Models

    func loadModels() async {
        log("Loading models for \(selectedProvider.rawValue)...", level: .info)
        do {
            let svc = service(for: selectedProvider)
            models = try await svc.listModels()
            log("Loaded \(models.count) models for \(selectedProvider.rawValue)", level: .info)
            if selectedModelId == nil, let first = models.first {
                selectedModelId = first.id
            }
        } catch {
            log("Failed to load models: \(error.localizedDescription)", level: .error)
            models = []
        }
    }

    // MARK: - Chat

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard let modelId = selectedModelId else {
            log("No model selected", level: .warning)
            return
        }

        streamTask?.cancel()
        streamGeneration += 1
        let generation = streamGeneration

        let userMessage = ChatMessage(role: .user, text: text)
        currentMessages.append(userMessage)
        inputText = ""
        isStreaming = true
        currentStreamingMessage = ChatMessage(role: .assistant, text: "", isStreaming: true)

        log("Sending message to \(selectedProvider.rawValue) model \(modelId)", level: .info)

        let svc = service(for: selectedProvider)
        let messages = buildLLMMessages()
        let thinking: ThinkingConfig? = thinkingEnabled
            ? .enabled(budgetTokens: thinkingBudget)
            : nil

        let mode = chatMode
        streamTask = Task {
            do {
                switch mode {
                case .streaming:
                    let stream = svc.chatStream(
                        modelId: modelId,
                        messages: messages,
                        thinking: thinking
                    )

                    for try await chunk in stream {
                        guard generation == self.streamGeneration else { return }
                        switch chunk.partType {
                        case .text:
                            currentStreamingMessage?.text += chunk.delta
                        case .thinking:
                            currentStreamingMessage?.thinkingText += chunk.delta
                        case .toolCall(let id, let function):
                            currentStreamingMessage?.text += "\n[Tool call: \(function) (id: \(id))]\n\(chunk.delta)"
                        }
                    }

                case .automatic:
                    let response = try await svc.chat(
                        modelId: modelId,
                        messages: messages,
                        thinking: thinking
                    )

                    guard generation == self.streamGeneration else { return }
                    for part in response.content {
                        switch part {
                        case .text(let text):
                            currentStreamingMessage?.text += text
                        case .thinking(let text):
                            currentStreamingMessage?.thinkingText += text
                        case .toolCall(let id, let function, let arguments):
                            currentStreamingMessage?.text += "\n[Tool call: \(function) (id: \(id))]\n\(arguments)"
                        }
                    }
                }

                guard generation == self.streamGeneration else { return }
                if var msg = currentStreamingMessage {
                    msg.isStreaming = false
                    currentMessages.append(msg)
                    log("Response received (\(msg.text.count) chars)", level: .info)
                }
            } catch is CancellationError {
                guard generation == self.streamGeneration else { return }
                if var msg = currentStreamingMessage, !msg.text.isEmpty {
                    msg.isStreaming = false
                    currentMessages.append(msg)
                }
                log("Stream cancelled", level: .warning)
            } catch {
                guard generation == self.streamGeneration else { return }
                if var msg = currentStreamingMessage, !msg.text.isEmpty {
                    msg.isStreaming = false
                    currentMessages.append(msg)
                }
                if let svcError = error as? LLMServiceError {
                    log("Stream error [\(svcError.statusCode ?? 0)]: \(svcError.message)", level: .error)
                } else {
                    log("Stream error: \(error.localizedDescription)", level: .error)
                }
            }
            guard generation == self.streamGeneration else { return }
            currentStreamingMessage = nil
            isStreaming = false
            streamTask = nil
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func buildLLMMessages() -> [LLMMessage] {
        currentMessages.map { msg in
            switch msg.role {
            case .user:
                return LLMMessage(role: .user, content: [.text(msg.text)])
            case .assistant:
                var content: [LLMContent] = []
                if !msg.thinkingText.isEmpty {
                    content.append(.thinking(msg.thinkingText, signature: nil))
                }
                if !msg.text.isEmpty {
                    content.append(.text(msg.text))
                }
                return LLMMessage(role: .assistant, content: content)
            }
        }
    }

    // MARK: - Debug

    func toggleDebug() {
        debugEnabled.toggle()
        services.removeAll()
        clearNetworkEntries()
        log("Debug logging \(debugEnabled ? "enabled" : "disabled") — services recreated", level: .info)
    }

    func exportHAR(lastMinutes: Int) async -> Data? {
        log("Exporting HAR (last \(lastMinutes) min)...", level: .info)
        do {
            let svc = service(for: selectedProvider)
            let data = try await svc.exportHAR(lastMinutes: lastMinutes)
            log("HAR exported (\(data.count) bytes)", level: .info)
            return data
        } catch {
            log("HAR export failed: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    // MARK: - Logging

    func log(_ message: String, level: LogEntry.Level) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logEntries.append(entry)
        switch level {
        case .info: logger.info("\(message)")
        case .warning: logger.warning("\(message)")
        case .error: logger.error("\(message)")
        case .debug: logger.debug("\(message)")
        }
    }

    func clearLog() {
        logEntries.removeAll()
    }

    // MARK: - Network Console

    func handleTraceSent(_ entry: LLMTraceEntry) {
        let networkEntry = NetworkRequestEntry(trace: entry)
        // Only insert if not already present — guards against race where recorded arrives first
        guard networkEntriesById[networkEntry.id] == nil else { return }
        networkEntries.append(networkEntry)
        networkEntriesById[networkEntry.id] = networkEntry
    }

    func handleTraceRecorded(_ entry: LLMTraceEntry) {
        let networkEntry = NetworkRequestEntry(trace: entry)
        if let index = networkEntries.firstIndex(where: { $0.id == networkEntry.id }) {
            networkEntries[index] = networkEntry
        } else {
            networkEntries.append(networkEntry)
        }
        networkEntriesById[networkEntry.id] = networkEntry
    }

    func clearNetworkEntries() {
        networkEntries.removeAll()
        networkEntriesById.removeAll()
        selectedTraceIds.removeAll()
        selectedDetailTraceId = nil
    }

    func copyAsCURL(_ entry: NetworkRequestEntry) {
        let curl = CURLExporter.generateCURL(from: entry.trace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curl, forType: .string)
        log("cURL copied to clipboard", level: .info)
    }

    func exportSelectedAsHAR() {
        let entriesToExport: [LLMTraceEntry]
        if selectedTraceIds.isEmpty {
            entriesToExport = networkEntries.map(\.trace)
        } else {
            entriesToExport = networkEntries
                .filter { selectedTraceIds.contains($0.id) }
                .map(\.trace)
        }

        guard !entriesToExport.isEmpty else {
            log("No entries to export", level: .warning)
            return
        }

        do {
            let data = try HARExporter.export(entries: entriesToExport)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "har", conformingTo: .json) ?? .json]
            panel.nameFieldStringValue = "llm_network_\(entriesToExport.count)_requests.har"

            Task {
                guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
                    log("No window available for save panel", level: .warning)
                    return
                }
                let response = await panel.beginSheetModal(for: window)
                if response == .OK, let url = panel.url {
                    do {
                        try data.write(to: url)
                        log("HAR saved to \(url.lastPathComponent) (\(entriesToExport.count) entries)", level: .info)
                    } catch {
                        log("Failed to save HAR: \(error.localizedDescription)", level: .error)
                    }
                }
            }
        } catch {
            log("HAR export failed: \(error.localizedDescription)", level: .error)
        }
    }
}
