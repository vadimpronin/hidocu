//
//  LLMSettingsViewModel.swift
//  HiDocu
//
//  Created by Claude on 2026-02-07.
//

import Foundation
import Observation

/// OAuth authentication state for a specific LLM provider.
enum OAuthState: Equatable {
    case idle
    case authenticating
    case error(String)
}

/// View model for LLM/AI settings tab.
///
/// Manages LLM accounts, OAuth authentication, model selection,
/// and prompt template configuration.
@Observable
@MainActor
final class LLMSettingsViewModel {

    // MARK: - Dependencies

    private let llmService: LLMService
    private let settingsService: SettingsService

    // MARK: - Published State

    /// All configured LLM accounts
    var accounts: [LLMAccount] = []

    /// OAuth state per provider
    var oauthState: [LLMProvider: OAuthState] = [:]

    /// Current authentication error message, if any
    var authError: String?

    /// All available models across all providers (read from LLMService cache).
    var availableModels: [AvailableModel] {
        llmService.availableModels
    }

    /// Combined selection identifier ("provider:modelId").
    /// Setting this updates both `defaultProvider` and `defaultModel` in settings.
    var selectedModelId: String {
        get {
            let provider = settingsService.settings.llm.defaultProvider
            let model = settingsService.settings.llm.defaultModel
            guard !model.isEmpty else { return "" }
            return "\(provider):\(model)"
        }
        set {
            let parts = newValue.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                settingsService.updateLLMProvider(String(parts[0]))
                settingsService.updateLLMModel(String(parts[1]))
            }
        }
    }

    /// Summary prompt template
    var summaryPromptTemplate: String {
        get {
            settingsService.settings.llm.summaryPromptTemplate
        }
        set {
            settingsService.updateSummaryPromptTemplate(newValue)
        }
    }

    // MARK: - Initialization

    init(llmService: LLMService, settingsService: SettingsService) {
        self.llmService = llmService
        self.settingsService = settingsService
    }

    // MARK: - Account Management

    func loadAccounts() async {
        do {
            accounts = try await llmService.listAccounts()
        } catch {
            AppLogger.general.error("Failed to load LLM accounts: \(error.localizedDescription)")
            authError = "Failed to load accounts: \(error.localizedDescription)"
        }
    }

    func addAccount(provider: LLMProvider) async {
        oauthState[provider] = .authenticating
        authError = nil

        do {
            _ = try await llmService.addAccount(provider: provider)
            oauthState[provider] = .idle
            await loadAccounts()
            autoSelectModelIfNeeded()
        } catch {
            AppLogger.general.error("Failed to add \(provider.rawValue) account: \(error.localizedDescription)")
            let errorMessage = "Authentication failed: \(error.localizedDescription)"
            oauthState[provider] = .error(errorMessage)
            authError = errorMessage
        }
    }

    func removeAccount(_ account: LLMAccount) async {
        do {
            try await llmService.removeAccount(id: account.id)
            await loadAccounts()
            autoSelectModelIfNeeded()
        } catch {
            AppLogger.general.error("Failed to remove account \(account.id): \(error.localizedDescription)")
            authError = "Failed to remove account: \(error.localizedDescription)"
        }
    }

    // MARK: - Model Management

    /// Force-refreshes the model cache from all providers.
    func refreshModels() async {
        await llmService.refreshAvailableModels()
        autoSelectModelIfNeeded()
    }

    /// Auto-selects the first available model if the current selection is empty or stale.
    private func autoSelectModelIfNeeded() {
        let models = availableModels
        guard !models.isEmpty else { return }
        let currentId = selectedModelId
        if currentId.isEmpty || !models.contains(where: { $0.id == currentId }) {
            selectedModelId = models[0].id
        }
    }
}
