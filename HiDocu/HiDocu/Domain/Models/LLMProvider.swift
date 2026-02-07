//
//  LLMProvider.swift
//  HiDocu
//
//  Enumeration of supported LLM providers with display properties.
//

import Foundation
import SwiftUI

/// Supported LLM providers for context generation and interaction.
enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini

    /// Human-readable provider name.
    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    /// Single-letter initial for compact UI display.
    var initial: String {
        switch self {
        case .claude:
            return "A"
        case .codex:
            return "O"
        case .gemini:
            return "G"
        }
    }

    /// Brand color for UI elements.
    var brandColor: Color {
        switch self {
        case .claude:
            return Color(red: 0.8, green: 0.7, blue: 0.6) // Anthropic tan/brown
        case .codex:
            return Color(red: 0.2, green: 0.7, blue: 0.7) // OpenAI teal
        case .gemini:
            return Color(red: 0.26, green: 0.52, blue: 0.96) // Google blue
        }
    }
}
