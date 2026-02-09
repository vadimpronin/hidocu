//
//  AvailableModel.swift
//  HiDocu
//
//  A model available from a specific LLM provider.
//

import Foundation

/// Lightweight DTO returned by providers: model identifier + human-readable name + capabilities.
struct ModelInfo: Sendable, Equatable {
    let id: String
    let displayName: String
    var acceptText: Bool = true
    var acceptAudio: Bool = false
    var acceptImage: Bool = false
}

/// A model available from a specific LLM provider.
/// Identity is determined by `provider` + `modelId` only; `displayName` is presentational.
struct AvailableModel: Hashable, Identifiable, Sendable {
    let provider: LLMProvider
    let modelId: String
    let displayName: String

    /// Number of active accounts for this provider that report this model as available.
    let availableAccountCount: Int

    /// Total number of active accounts for this provider.
    let totalAccountCount: Int

    /// Whether this model accepts text input.
    let acceptText: Bool

    /// Whether this model accepts audio input.
    let acceptAudio: Bool

    /// Whether this model accepts image input.
    let acceptImage: Bool

    var id: String { "\(provider.rawValue):\(modelId)" }

    /// Model is not available on any active account.
    var isUnavailable: Bool { availableAccountCount == 0 }

    /// Model is available on some but not all active accounts (partial round-robin).
    var isPartiallyAvailable: Bool {
        availableAccountCount > 0 && availableAccountCount < totalAccountCount
    }

    /// Model is available on all active accounts.
    var isFullyAvailable: Bool {
        availableAccountCount == totalAccountCount && totalAccountCount > 0
    }

    static func == (lhs: AvailableModel, rhs: AvailableModel) -> Bool {
        lhs.provider == rhs.provider && lhs.modelId == rhs.modelId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(provider)
        hasher.combine(modelId)
    }
}

extension AvailableModel {
    /// Convenience init assuming full availability and text-only (backward compat).
    init(provider: LLMProvider, modelId: String, displayName: String) {
        self.init(
            provider: provider,
            modelId: modelId,
            displayName: displayName,
            availableAccountCount: 1,
            totalAccountCount: 1,
            acceptText: true,
            acceptAudio: false,
            acceptImage: false
        )
    }
}
