//
//  AvailableModel.swift
//  HiDocu
//
//  A model available from a specific LLM provider.
//

import Foundation

/// A model available from a specific LLM provider.
struct AvailableModel: Hashable, Identifiable, Sendable {
    let provider: LLMProvider
    let modelId: String

    var id: String { "\(provider.rawValue):\(modelId)" }
    var displayName: String { modelId }
}
