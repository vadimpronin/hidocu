//
//  AvailableModel.swift
//  HiDocu
//
//  A model available from a specific LLM provider.
//

import Foundation

/// Lightweight DTO returned by providers: model identifier + human-readable name.
struct ModelInfo: Sendable, Equatable {
    let id: String
    let displayName: String
}

/// A model available from a specific LLM provider.
/// Identity is determined by `provider` + `modelId` only; `displayName` is presentational.
struct AvailableModel: Hashable, Identifiable, Sendable {
    let provider: LLMProvider
    let modelId: String
    let displayName: String

    var id: String { "\(provider.rawValue):\(modelId)" }

    static func == (lhs: AvailableModel, rhs: AvailableModel) -> Bool {
        lhs.provider == rhs.provider && lhs.modelId == rhs.modelId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(provider)
        hasher.combine(modelId)
    }
}
