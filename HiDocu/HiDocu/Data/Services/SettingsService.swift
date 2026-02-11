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
        var defaultTranscriptionProvider: String = ""
        var defaultTranscriptionModel: String = ""
        var defaultJudgeProvider: String = ""
        var defaultJudgeModel: String = ""
        var apiDebugLogging: Bool = false
        var summaryPromptTemplate: String = Self.defaultPromptTemplate

        static let defaultPromptTemplate: String = """
            # IDENTITY and PURPOSE
            You are an AI assistant specialized in analyzing meeting transcripts and extracting key information. Your goal is to provide comprehensive yet concise summaries that capture the essential elements of meetings in a structured format.

            # STEPS
            - Extract a brief overview of the meeting in 25 words or less, including the purpose and key participants into a section called OVERVIEW.
            - Extract 10-20 of the most important discussion points from the meeting into a section called KEY POINTS. Focus on core topics, debates, and significant ideas discussed.
            - Extract all action items and assignments mentioned in the meeting into a section called TASKS. Include responsible parties and deadlines where specified.
            - Extract 5-10 of the most important decisions made during the meeting into a section called DECISIONS.
            - Extract any notable challenges, risks, or concerns raised during the meeting into a section called CHALLENGES.
            - Extract all deadlines, important dates, and milestones mentioned into a section called TIMELINE.
            - Extract all references to documents, tools, projects, or resources mentioned into a section called REFERENCES.
            - Extract 5-10 of the most important follow-up items or next steps into a section called NEXT STEPS.

            # OUTPUT INSTRUCTIONS
            - Only output Markdown.
            - Write the KEY POINTS bullets as exactly 16 words.
            - Write the TASKS bullets as exactly 16 words.
            - Write the DECISIONS bullets as exactly 16 words.
            - Write the NEXT STEPS bullets as exactly 16 words.
            - Use bulleted lists for all sections, not numbered lists.
            - Do not repeat information across sections.
            - Do not start items with the same opening words.
            - If information for a section is not available in the transcript, write "No information available".
            - Do not include warnings or notes; only output the requested sections.
            - Format each section header in bold using markdown.

            # INPUT
            <TITLE>{{document_title}}</TITLE>
            <BODY>
            {{document_body}}
            </BODY>
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

    func updateTranscriptionProvider(_ provider: String) {
        settings.llm.defaultTranscriptionProvider = provider
        save()
    }

    func updateTranscriptionModel(_ model: String) {
        settings.llm.defaultTranscriptionModel = model
        save()
    }

    func updateJudgeProvider(_ provider: String) {
        settings.llm.defaultJudgeProvider = provider
        save()
    }

    func updateJudgeModel(_ model: String) {
        settings.llm.defaultJudgeModel = model
        save()
    }

    func updateAPIDebugLogging(_ enabled: Bool) {
        settings.llm.apiDebugLogging = enabled
        save()
    }
}
