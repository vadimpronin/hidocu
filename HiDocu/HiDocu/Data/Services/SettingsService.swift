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

    init() {
        self.general = GeneralSettings()
        self.audioImport = AudioImportSettings()
        self.context = ContextSettings()
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
}
