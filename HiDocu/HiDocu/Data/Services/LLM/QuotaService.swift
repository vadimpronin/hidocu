//
//  QuotaService.swift
//  HiDocu
//
//  Quota fetching and usage tracking service for LLM providers.
//  Fetches quota from Gemini/Antigravity APIs, tracks usage for all providers,
//  and computes "battery level" per provider.
//

import Foundation
import os

/// Service for fetching quota data and tracking usage across LLM providers.
///
/// This service:
/// - Fetches quota data from provider APIs (Gemini, Antigravity)
/// - Tracks usage for all providers (including Claude, Codex)
/// - Computes "battery level" per provider (0.0 - 1.0)
/// - Handles rate-limit pausing
/// - Provides periodic quota refresh
///
/// Network calls run in background tasks; observable state updates on @MainActor.
@Observable
@MainActor
final class QuotaService {
    // MARK: - Types

    /// Quota information for a provider.
    struct ProviderQuota: Sendable, Identifiable {
        var id: LLMProvider { provider }
        let provider: LLMProvider
        var batteryLevel: Double  // 0.0 - 1.0
        var isLoading: Bool
        var lastUpdated: Date?
        var modelQuotas: [ModelQuota]
    }

    /// Quota information for a model.
    struct ModelQuota: Sendable, Identifiable {
        var id: String { modelId }
        let modelId: String
        var remainingFraction: Double  // 0.0 - 1.0
        var resetAt: Date?
    }

    // MARK: - Observable State

    private(set) var quotas: [LLMProvider: ProviderQuota] = [:]

    // MARK: - Dependencies

    private let tokenManager: TokenManager
    private let accountRepository: any LLMAccountRepository
    private let usageRepository: any LLMUsageRepository
    private let urlSession: URLSession

    // MARK: - Refresh Timer

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization

    init(
        tokenManager: TokenManager,
        accountRepository: any LLMAccountRepository,
        usageRepository: any LLMUsageRepository,
        urlSession: URLSession = .shared
    ) {
        self.tokenManager = tokenManager
        self.accountRepository = accountRepository
        self.usageRepository = usageRepository
        self.urlSession = urlSession
    }

    // MARK: - Public API

    /// Refreshes quota for all providers that have active accounts.
    func refreshAll() async {
        AppLogger.llm.info("Refreshing quota for all providers")

        let allProviders: [LLMProvider] = [.gemini, .antigravity, .claude, .codex]

        await withTaskGroup(of: Void.self) { group in
            for provider in allProviders {
                group.addTask { [weak self] in
                    await self?.refresh(provider: provider)
                }
            }
        }

        AppLogger.llm.info("Quota refresh completed for all providers")
    }

    /// Refreshes quota for a specific provider.
    func refresh(provider: LLMProvider) async {
        do {
            let accounts = try await accountRepository.fetchActive(provider: provider)

            if accounts.isEmpty {
                // No accounts for this provider - hide from UI
                quotas.removeValue(forKey: provider)
                return
            }

            // Set loading state now that we know accounts exist
            if quotas[provider] == nil {
                quotas[provider] = ProviderQuota(
                    provider: provider,
                    batteryLevel: 0.0,
                    isLoading: true,
                    lastUpdated: nil,
                    modelQuotas: []
                )
            } else {
                quotas[provider]?.isLoading = true
            }

            switch provider {
            case .gemini:
                await refreshGeminiQuota(accounts: accounts)
            case .antigravity:
                await refreshAntigravityQuota(accounts: accounts)
            case .claude, .codex:
                await refreshHeuristicQuota(provider: provider, accounts: accounts)
            }
        } catch {
            AppLogger.llm.error("Failed to refresh quota for \(provider.rawValue): \(error.localizedDescription)")
            quotas[provider]?.isLoading = false
        }
    }

    /// Records usage after a successful API call. Updates local counters.
    func recordUsage(accountId: Int64, modelId: String, inputTokens: Int, outputTokens: Int) async {
        do {
            // Fetch or create usage record
            let usage = try await usageRepository.fetchForAccountAndModel(accountId: accountId, modelId: modelId)

            var updated: LLMUsage
            if let existing = usage {
                updated = existing
            } else {
                updated = LLMUsage(
                    id: 0,
                    accountId: accountId,
                    modelId: modelId,
                    remainingFraction: nil,
                    resetAt: nil,
                    lastCheckedAt: Date(),
                    inputTokensUsed: 0,
                    outputTokensUsed: 0,
                    requestCount: 0,
                    periodStart: Date()
                )
            }

            // Update counters
            updated.inputTokensUsed += inputTokens
            updated.outputTokensUsed += outputTokens
            updated.requestCount += 1

            _ = try await usageRepository.upsert(updated)

            AppLogger.llm.debug("Recorded usage for account \(accountId), model \(modelId): +\(inputTokens) in, +\(outputTokens) out")
        } catch {
            AppLogger.llm.error("Failed to record usage: \(error.localizedDescription)")
        }
    }

    /// Records a rate-limit event. Sets paused_until on the account.
    func recordRateLimit(accountId: Int64, provider: LLMProvider, retryAfter: TimeInterval?) async {
        do {
            let pausedUntil = Date(timeIntervalSinceNow: retryAfter ?? 3600) // Default to 1 hour
            try await accountRepository.updatePausedUntil(id: accountId, pausedUntil: pausedUntil)

            AppLogger.llm.warning("Account \(accountId) (\(provider.rawValue)) rate-limited until \(pausedUntil)")

            // Refresh quota for the provider to update battery level
            await refresh(provider: provider)
        } catch {
            AppLogger.llm.error("Failed to record rate limit: \(error.localizedDescription)")
        }
    }

    /// Returns the best available account for a provider (highest remaining quota).
    /// Returns nil if no accounts have quota data.
    func bestAccount(for provider: LLMProvider) async -> LLMAccount? {
        do {
            let accounts = try await accountRepository.fetchActive(provider: provider)

            // Filter out paused accounts
            let availableAccounts = accounts.filter { account in
                if let pausedUntil = account.pausedUntil {
                    return pausedUntil < Date()
                }
                return true
            }

            if availableAccounts.isEmpty {
                return nil
            }

            // For providers with quota API, choose account with highest remaining quota
            if provider == .gemini || provider == .antigravity {
                var bestAccount: LLMAccount?
                var bestQuota: Double = -1.0

                for account in availableAccounts {
                    let usageRecords = try await usageRepository.fetchForAccount(accountId: account.id)

                    // Compute average remaining fraction for this account
                    let fractions = usageRecords.compactMap { $0.remainingFraction }
                    if !fractions.isEmpty {
                        let avgQuota = fractions.reduce(0.0, +) / Double(fractions.count)
                        if avgQuota > bestQuota {
                            bestQuota = avgQuota
                            bestAccount = account
                        }
                    }
                }

                return bestAccount ?? availableAccounts.first
            } else {
                // For Claude/Codex, return first available account
                return availableAccounts.first
            }
        } catch {
            AppLogger.llm.error("Failed to find best account for \(provider.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    /// Starts periodic quota refresh.
    func startPeriodicRefresh() {
        stopPeriodicRefresh()

        refreshTask = Task { [weak self] in
            guard let self = self else { return }

            // Initial refresh
            await self.refreshAll()

            // Periodic refresh
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))

                if Task.isCancelled {
                    break
                }

                await self.refreshAll()
            }
        }

        AppLogger.llm.info("Started periodic quota refresh (interval: \(Int(self.refreshInterval))s)")
    }

    /// Stops periodic refresh.
    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        AppLogger.llm.info("Stopped periodic quota refresh")
    }

    // MARK: - Formatters

    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Private Helpers

    /// Fetches quota for Gemini provider using the retrieveUserQuota endpoint.
    private func refreshGeminiQuota(accounts: [LLMAccount]) async {
        // Use the first active account to fetch quota (quota is per-user, not per-account)
        guard let account = accounts.first else {
            return
        }

        do {
            let (accessToken, tokenData) = try await tokenManager.getValidAccessToken(for: account)

            guard let projectId = tokenData.projectId else {
                AppLogger.llm.error("Gemini account \(account.id) missing projectId")
                quotas[.gemini] = ProviderQuota(
                    provider: .gemini,
                    batteryLevel: 0.0,
                    isLoading: false,
                    lastUpdated: Date(),
                    modelQuotas: []
                )
                return
            }

            // Fetch quota from API
            let modelQuotas = try await fetchGeminiQuota(
                accessToken: accessToken,
                projectId: projectId
            )

            // Update usage records in database
            for modelQuota in modelQuotas {
                let existing = try await usageRepository.fetchForAccountAndModel(
                    accountId: account.id,
                    modelId: modelQuota.modelId
                )

                var record: LLMUsage
                if let existing {
                    record = existing
                    record.remainingFraction = modelQuota.remainingFraction
                    record.resetAt = modelQuota.resetAt
                    record.lastCheckedAt = Date()
                } else {
                    record = LLMUsage(
                        id: 0,
                        accountId: account.id,
                        modelId: modelQuota.modelId,
                        remainingFraction: modelQuota.remainingFraction,
                        resetAt: modelQuota.resetAt,
                        lastCheckedAt: Date(),
                        inputTokensUsed: 0,
                        outputTokensUsed: 0,
                        requestCount: 0,
                        periodStart: Date()
                    )
                }

                _ = try await usageRepository.upsert(record)
            }

            // Compute battery level (minimum remaining fraction across models)
            let batteryLevel = modelQuotas.map { $0.remainingFraction }.min() ?? 0.0

            quotas[.gemini] = ProviderQuota(
                provider: .gemini,
                batteryLevel: batteryLevel,
                isLoading: false,
                lastUpdated: Date(),
                modelQuotas: modelQuotas
            )

            AppLogger.llm.info("Gemini quota refreshed: battery=\(String(format: "%.1f%%", batteryLevel * 100)), models=\(modelQuotas.count)")
        } catch {
            AppLogger.llm.error("Failed to refresh Gemini quota: \(error.localizedDescription)")
            quotas[.gemini]?.isLoading = false
        }
    }

    /// Fetches quota for Antigravity provider using the fetchAvailableModels endpoint.
    private func refreshAntigravityQuota(accounts: [LLMAccount]) async {
        guard let account = accounts.first else {
            return
        }

        do {
            let (accessToken, tokenData) = try await tokenManager.getValidAccessToken(for: account)

            guard let projectId = tokenData.projectId else {
                AppLogger.llm.error("Antigravity account \(account.id) missing projectId")
                quotas[.antigravity] = ProviderQuota(
                    provider: .antigravity,
                    batteryLevel: 0.0,
                    isLoading: false,
                    lastUpdated: Date(),
                    modelQuotas: []
                )
                return
            }

            // Fetch quota from API
            let modelQuotas = try await fetchAntigravityQuota(
                accessToken: accessToken,
                projectId: projectId
            )

            // Update usage records in database
            for modelQuota in modelQuotas {
                let existing = try await usageRepository.fetchForAccountAndModel(
                    accountId: account.id,
                    modelId: modelQuota.modelId
                )

                var record: LLMUsage
                if let existing {
                    record = existing
                    record.remainingFraction = modelQuota.remainingFraction
                    record.resetAt = modelQuota.resetAt
                    record.lastCheckedAt = Date()
                } else {
                    record = LLMUsage(
                        id: 0,
                        accountId: account.id,
                        modelId: modelQuota.modelId,
                        remainingFraction: modelQuota.remainingFraction,
                        resetAt: modelQuota.resetAt,
                        lastCheckedAt: Date(),
                        inputTokensUsed: 0,
                        outputTokensUsed: 0,
                        requestCount: 0,
                        periodStart: Date()
                    )
                }

                _ = try await usageRepository.upsert(record)
            }

            // Compute battery level (minimum remaining fraction across models)
            let batteryLevel = modelQuotas.map { $0.remainingFraction }.min() ?? 0.0

            quotas[.antigravity] = ProviderQuota(
                provider: .antigravity,
                batteryLevel: batteryLevel,
                isLoading: false,
                lastUpdated: Date(),
                modelQuotas: modelQuotas
            )

            AppLogger.llm.info("Antigravity quota refreshed: battery=\(String(format: "%.1f%%", batteryLevel * 100)), models=\(modelQuotas.count)")
        } catch {
            AppLogger.llm.error("Failed to refresh Antigravity quota: \(error.localizedDescription)")
            quotas[.antigravity]?.isLoading = false
        }
    }

    /// Computes heuristic quota for providers without quota API (Claude, Codex).
    private func refreshHeuristicQuota(provider: LLMProvider, accounts: [LLMAccount]) async {
        // Compute battery level: 1.0 if not rate-limited, 0.0 if all accounts paused
        let now = Date()
        let availableAccounts = accounts.filter { account in
            if let pausedUntil = account.pausedUntil {
                return pausedUntil < now
            }
            return true
        }

        let batteryLevel = availableAccounts.isEmpty ? 0.0 : 1.0

        quotas[provider] = ProviderQuota(
            provider: provider,
            batteryLevel: batteryLevel,
            isLoading: false,
            lastUpdated: Date(),
            modelQuotas: []
        )

        AppLogger.llm.debug("\(provider.rawValue) quota (heuristic): battery=\(String(format: "%.1f%%", batteryLevel * 100))")
    }

    /// Fetches quota from Gemini retrieveUserQuota API.
    private func fetchGeminiQuota(accessToken: String, projectId: String) async throws -> [ModelQuota] {
        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("google-api-nodejs-client/9.15.1", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = ["project": projectId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(provider: .gemini, statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["buckets"] as? [[String: Any]] else {
            throw LLMError.invalidResponse(detail: "Missing buckets in retrieveUserQuota response")
        }

        var modelQuotas: [ModelQuota] = []
        for bucket in buckets {
            guard let modelId = bucket["modelId"] as? String,
                  let remainingFraction = bucket["remainingFraction"] as? Double else {
                continue
            }

            let resetAt: Date?
            if let resetTimeStr = bucket["resetTime"] as? String {
                resetAt = Self.isoFormatter.date(from: resetTimeStr)
            } else {
                resetAt = nil
            }

            modelQuotas.append(ModelQuota(
                modelId: modelId,
                remainingFraction: remainingFraction,
                resetAt: resetAt
            ))
        }

        return modelQuotas
    }

    /// Fetches quota from Antigravity fetchAvailableModels API.
    private func fetchAntigravityQuota(accessToken: String, projectId: String) async throws -> [ModelQuota] {
        let url = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.104.0 darwin/arm64", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = ["project": projectId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(provider: .antigravity, statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Missing models in fetchAvailableModels response")
        }

        var modelQuotas: [ModelQuota] = []
        for (modelId, modelData) in models {
            guard let modelInfo = modelData as? [String: Any],
                  let quotaInfo = modelInfo["quotaInfo"] as? [String: Any],
                  let remainingFraction = quotaInfo["remainingFraction"] as? Double else {
                continue
            }

            let resetAt: Date?
            if let resetTimeStr = quotaInfo["resetTime"] as? String {
                resetAt = Self.isoFormatter.date(from: resetTimeStr)
            } else {
                resetAt = nil
            }

            modelQuotas.append(ModelQuota(
                modelId: modelId,
                remainingFraction: remainingFraction,
                resetAt: resetAt
            ))
        }

        return modelQuotas
    }
}
