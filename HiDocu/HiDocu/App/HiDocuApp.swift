//
//  HiDocuApp.swift
//  HiDocu
//
//  Main entry point for the HiDocu application.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct HiDocuApp: App {

    @State private var container = AppDependencyContainer()
    @State private var navigationVM = NavigationViewModelV2()
    @State private var importError: String?
    @State private var showImportError = false
    @State private var isAPIDebugEnabled = false
    #if DEBUG
    @State private var showClearStorageConfirmation = false
    #endif

    var body: some Scene {
        WindowGroup {
            ContentViewV2(container: container, navigationVM: navigationVM)
                .withDependencies(container)
                .task {
                    isAPIDebugEnabled = container.settingsService.settings.llm.apiDebugLogging
                    await container.trashService.autoCleanup()
                    await container.llmService.reloadModelsFromDB()
                    await container.llmService.refreshAvailableModels()
                }
                .onChange(of: isAPIDebugEnabled) { _, newValue in
                    container.settingsService.updateAPIDebugLogging(newValue)
                    Task {
                        await container.apiDebugLogger.setEnabled(newValue)
                    }
                }
                .alert("Import Failed", isPresented: $showImportError) {
                    Button("OK") {}
                } message: {
                    Text(importError ?? "An unknown error occurred.")
                }
                #if DEBUG
                .confirmationDialog(
                    "Clear All Local Storage",
                    isPresented: $showClearStorageConfirmation
                ) {
                    Button("Delete Everything", role: .destructive) {
                        Task { await clearAllLocalStorage() }
                    }
                } message: {
                    Text("This will delete the database, all recordings, documents, Keychain tokens, and settings. The app will quit.")
                }
                #endif
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    newDocument()
                }
                .keyboardShortcut("n")

                Button("New Folder") {
                    newFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Import Audio Files...") {
                    importFiles()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Debug") {
                Toggle("API Debug Logging", isOn: $isAPIDebugEnabled)
                    .keyboardShortcut("l", modifiers: [.command, .shift, .option])

                Button("Open Debug Logs") {
                    Task {
                        let url = await container.apiDebugLogger.logDirectoryURL
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }

                #if DEBUG
                Divider()

                Button("Simulate Device Connection") {
                    Task { @MainActor in
                        container.deviceManager.simulateDeviceConnection()
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button("Clear All Local Storage...") {
                    showClearStorageConfirmation = true
                }
                #endif
            }
        }

        Settings {
            SettingsViewV2()
                .withDependencies(container)
        }
    }

    // MARK: - Menu Actions

    private func newDocument() {
        Task { @MainActor in
            do {
                let folderId: Int64?
                if case .folder(let id) = navigationVM.selectedSidebarItem {
                    folderId = id
                } else {
                    folderId = nil
                }
                let doc = try await container.documentService.createDocument(
                    title: "Untitled",
                    folderId: folderId
                )
                navigationVM.selectedDocumentIds = [doc.id]
            } catch {
                AppLogger.ui.error("Failed to create document: \(error.localizedDescription)")
            }
        }
    }

    private func newFolder() {
        Task { @MainActor in
            do {
                let folder = try await container.folderService.createFolder(
                    name: "New Folder",
                    parentId: nil
                )
                navigationVM.selectedSidebarItem = .folder(id: folder.id)
            } catch {
                AppLogger.ui.error("Failed to create folder: \(error.localizedDescription)")
            }
        }
    }

    #if DEBUG
    private func clearAllLocalStorage() async {
        // 1. Stop background services
        await container.llmQueueService.stopProcessing()
        container.quotaService.stopPeriodicRefresh()
        try? await Task.sleep(for: .milliseconds(200))

        // 2. Close database
        try? container.databaseManager.close()

        // 3. Delete Application Support/HiDocu (database + settings)
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let hidocuAppSupport = appSupport.appendingPathComponent("HiDocu", isDirectory: true)
        try? FileManager.default.removeItem(at: hidocuAppSupport)

        // 4. Delete data directory (recordings, documents)
        let dataDir = container.fileSystemService.dataDirectory
        try? FileManager.default.removeItem(at: dataDir)

        // 5. Clear Keychain tokens
        container.keychainService.deleteAll()

        // 6. Clear UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // 7. Quit
        NSApplication.shared.terminate(nil)
    }
    #endif

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
                let documents = try await container.importServiceV2.importFiles(urls)
                AppLogger.ui.info("Imported \(documents.count) files via menu")
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
