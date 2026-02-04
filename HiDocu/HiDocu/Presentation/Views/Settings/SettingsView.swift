//
//  SettingsView.swift
//  HiDocu
//
//  Application settings window with storage configuration.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.container) private var container

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 500, height: 300)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {
    @Environment(\.container) private var container
    @State private var showAccessError = false
    @State private var accessErrorMessage = ""

    var body: some View {
        Form {
            Section {
                storageSection
            } header: {
                Text("Storage Location")
            } footer: {
                Text("Recordings are stored in this folder. Changing this does not move existing files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
                LabeledContent("License") {
                    Text("MIT")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Access Denied", isPresented: $showAccessError) {
            Button("OK") {}
        } message: {
            Text(accessErrorMessage)
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        let currentPath = container?.fileSystemService.storageDirectory?.path ?? "Not set"

        LabeledContent("Current Path") {
            Text(currentPath)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: 300, alignment: .trailing)
        }

        HStack {
            Button("Change Location...") {
                chooseStorageLocation()
            }

            Button("Reset to Default") {
                container?.fileSystemService.resetToDefaultDirectory()
                AppLogger.ui.info("Storage reset to default")
            }
        }
    }

    private func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder to store your recordings"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try container?.fileSystemService.setStorageDirectory(url)
            AppLogger.ui.info("Storage directory changed to: \(url.path)")
        } catch {
            accessErrorMessage = "Cannot access the selected folder: \(error.localizedDescription)"
            showAccessError = true
            AppLogger.ui.error("Failed to set storage directory: \(error.localizedDescription)")
        }
    }
}
