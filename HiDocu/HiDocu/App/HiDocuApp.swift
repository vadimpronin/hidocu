//
//  HiDocuApp.swift
//  HiDocu
//
//  Main entry point for the HiDocu application.
//

import SwiftUI
import UniformTypeIdentifiers

/// Main application entry point.
/// Initializes the dependency container and provides it to all views.
@main
struct HiDocuApp: App {

    /// The app's dependency container (initialized once, lives for app lifetime)
    @State private var container = AppDependencyContainer()
    @State private var importError: String?
    @State private var showImportError = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .withDependencies(container)
                .alert("Import Failed", isPresented: $showImportError) {
                    Button("OK") {}
                } message: {
                    Text(importError ?? "An unknown error occurred.")
                }
        }
        .commands {
            // Replace "New" with Import
            CommandGroup(replacing: .newItem) {
                Button("Import Audio Files...") {
                    importFiles()
                }
                .keyboardShortcut("o")
            }
        }

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .withDependencies(container)
        }
    }

    // MARK: - Menu Actions

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .audio,
            .mp3,
            .mpeg4Audio,
            .wav,
            UTType(filenameExtension: "hda") ?? .audio
        ]
        panel.prompt = "Import"
        panel.message = "Select audio files to import"

        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        Task {
            do {
                let recordings = try await container.syncService.importFiles(urls)
                AppLogger.ui.info("Imported \(recordings.count) files via menu")
            } catch {
                AppLogger.ui.error("Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    importError = error.localizedDescription
                    showImportError = true
                }
            }
        }
    }
}
