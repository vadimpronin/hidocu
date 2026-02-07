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

    var body: some Scene {
        WindowGroup {
            ContentViewV2(container: container, navigationVM: navigationVM)
                .withDependencies(container)
                .task {
                    await container.trashService.autoCleanup()
                    await migrateMetadataYAMLIfNeeded()
                }
                .alert("Import Failed", isPresented: $showImportError) {
                    Button("OK") {}
                } message: {
                    Text(importError ?? "An unknown error occurred.")
                }
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

            #if DEBUG
            CommandMenu("Debug") {
                Button("Simulate Device Connection") {
                    Task { @MainActor in
                        container.deviceManager.simulateDeviceConnection()
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            #endif
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

    private func migrateMetadataYAMLIfNeeded() async {
        let key = "com.hidocu.metadataYAMLMigrated_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        do {
            let folders = try await container.folderRepository.fetchAll()
            for folder in folders {
                do { try container.fileSystemService.writeFolderMetadata(folder) }
                catch { AppLogger.fileSystem.warning("Migration: failed to write folder \(folder.id): \(error.localizedDescription)") }
            }
            let documents = try await container.documentRepository.fetchAllDocuments()
            for doc in documents {
                do { try container.fileSystemService.writeDocumentMetadata(doc) }
                catch { AppLogger.fileSystem.warning("Migration: failed to write document \(doc.id): \(error.localizedDescription)") }
            }
            UserDefaults.standard.set(true, forKey: key)
            AppLogger.general.info("Completed metadata YAML migration")
        } catch {
            AppLogger.general.error("Migration fetch failed, will retry next launch: \(error.localizedDescription)")
        }
    }

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
                let recordings = try await container.importServiceV2.importFiles(urls)
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
