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

/// Model refresh state for fetching available models from provider.
enum RefreshState: Equatable {
    case idle
    case loading
    case error(String)
}

/// A model available from a specific LLM provider.
struct AvailableModel: Hashable, Identifiable {
    let provider: LLMProvider
    let modelId: String

    var id: String { "\(provider.rawValue):\(modelId)" }
    var displayName: String { "\(modelId) (\(provider.displayName))" }
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

    /// Model refresh state
    var modelRefreshState: RefreshState = .idle

    /// All available models across all providers
    var availableModels: [AvailableModel] = []

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
            await refreshModels()
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
            await refreshModels()
        } catch {
            AppLogger.general.error("Failed to remove account \(account.id): \(error.localizedDescription)")
            authError = "Failed to remove account: \(error.localizedDescription)"
        }
    }

    // MARK: - Model Management

    /// Fetches available models from all providers that have accounts.
    /// Updates `availableModels` with results sorted by provider.
    func refreshModels() async {
        modelRefreshState = .loading

        var allModels: [AvailableModel] = []
        var errors: [String] = []

        for provider in LLMProvider.allCases {
            do {
                let models = try await llmService.fetchModels(provider: provider)
                allModels.append(contentsOf: models.map { AvailableModel(provider: provider, modelId: $0) })
            } catch let error as LLMError {
                if case .noAccountsConfigured = error {
                    // No accounts for this provider — skip silently
                } else {
                    errors.append("\(provider.displayName): \(error.localizedDescription)")
                }
            } catch {
                errors.append("\(provider.displayName): \(error.localizedDescription)")
            }
        }

        // Sort by provider name, then model name
        availableModels = allModels.sorted {
            if $0.provider.rawValue != $1.provider.rawValue {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.modelId < $1.modelId
        }

        // Auto-select first model if current selection is empty or missing
        if !availableModels.isEmpty {
            let currentId = selectedModelId
            if currentId.isEmpty || !availableModels.contains(where: { $0.id == currentId }) {
                selectedModelId = availableModels[0].id
            }
        }

        if errors.isEmpty {
            modelRefreshState = .idle
        } else {
            modelRefreshState = .error(errors.joined(separator: "; "))
        }
    }
}
