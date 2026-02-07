//
//  SettingsService.swift
//  HiDocu
//
//  Manages app settings stored as JSON.
//

import Foundation

struct AppSettings: Codable, Sendable {
    var general: GeneralSettings
    var audioImport: AudioImportSettings
    var context: ContextSettings
    var llm: LLMSettings

    init() {
        self.general = GeneralSettings()
        self.audioImport = AudioImportSettings()
        self.context = ContextSettings()
        self.llm = LLMSettings()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = try container.decode(GeneralSettings.self, forKey: .general)
        self.audioImport = try container.decode(AudioImportSettings.self, forKey: .audioImport)
        self.context = try container.decode(ContextSettings.self, forKey: .context)
        self.llm = try container.decodeIfPresent(LLMSettings.self, forKey: .llm) ?? LLMSettings()
    }

    struct GeneralSettings: Codable, Sendable {
        var dataDirectory: String?
    }

    struct AudioImportSettings: Codable, Sendable {
        var autoDetectNewDevices: Bool = true
    }

    struct ContextSettings: Codable, Sendable {
        var defaultPreferSummary: Bool = true
    }

    struct LLMSettings: Codable, Sendable {
        var defaultProvider: String = "claude"
        var defaultModel: String = ""
        var summaryPromptTemplate: String = Self.defaultPromptTemplate

        static let defaultPromptTemplate: String = """
            You are an expert summarizer. Given the following document, produce a concise summary \
            that captures the key points, decisions, and action items. Use markdown formatting. \
            Keep the summary under 500 words.

            Document:
            {{body}}
            """
    }
}

@Observable
final class SettingsService {

    private(set) var settings: AppSettings

    private let settingsURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let hidocuDir = appSupport.appendingPathComponent("HiDocu", isDirectory: true)
        self.settingsURL = hidocuDir.appendingPathComponent("settings.json")

        // Load existing or create defaults
        if FileManager.default.fileExists(atPath: settingsURL.path),
           let data = try? Data(contentsOf: settingsURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = loaded
        } else {
            self.settings = AppSettings()
        }
    }

    func save() {
        do {
            let dir = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            AppLogger.general.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    func updateDataDirectory(_ path: String?) {
        settings.general.dataDirectory = path
        save()
    }

    func updateAutoDetectDevices(_ enabled: Bool) {
        settings.audioImport.autoDetectNewDevices = enabled
        save()
    }

    func updateDefaultPreferSummary(_ prefer: Bool) {
        settings.context.defaultPreferSummary = prefer
        save()
    }

    func updateLLMProvider(_ provider: String) {
        settings.llm.defaultProvider = provider
        save()
    }

    func updateLLMModel(_ model: String) {
        settings.llm.defaultModel = model
        save()
    }

    func updateSummaryPromptTemplate(_ template: String) {
        settings.llm.summaryPromptTemplate = template
        save()
    }
}
