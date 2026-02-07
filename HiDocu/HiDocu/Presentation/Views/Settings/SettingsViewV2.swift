//
//  SettingsViewV2.swift
//  HiDocu
//
//  New settings view with General, Audio Import, and Context tabs.
//

import SwiftUI

struct SettingsViewV2: View {
    @Environment(\.container) private var container

    var body: some View {
        TabView {
            GeneralSettingsTabV2()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AudioImportSettingsTab()
                .tabItem {
                    Label("Audio Import", systemImage: "square.and.arrow.down")
                }

            ContextSettingsTab()
                .tabItem {
                    Label("Context", systemImage: "text.alignleft")
                }
        }
        .frame(width: 500, height: 350)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTabV2: View {
    @Environment(\.container) private var container
    @State private var showAccessError = false
    @State private var accessErrorMessage = ""

    var body: some View {
        Form {
            Section("Data Directory") {
                let currentPath = container?.fileSystemService.dataDirectory.path ?? "Not set"

                LabeledContent("Current Path") {
                    Text(currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: 300, alignment: .trailing)
                }

                HStack {
                    Button("Change...") {
                        chooseDataDirectory()
                    }
                    Button("Reset to Default") {
                        container?.fileSystemService.resetDataDirectory()
                        container?.settingsService.updateDataDirectory(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Access Error", isPresented: $showAccessError) {
            Button("OK") {}
        } message: {
            Text(accessErrorMessage)
        }
    }

    private func chooseDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder to store your documents"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        container?.fileSystemService.setDataDirectory(url)
        container?.settingsService.updateDataDirectory(url.path)
    }
}

// MARK: - Audio Import Tab

private struct AudioImportSettingsTab: View {
    @Environment(\.container) private var container

    var body: some View {
        Form {
            Section("Device Detection") {
                if let settings = container?.settingsService {
                    Toggle("Auto-detect new devices", isOn: Binding(
                        get: { settings.settings.audioImport.autoDetectNewDevices },
                        set: { settings.updateAutoDetectDevices($0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Context Tab

private struct ContextSettingsTab: View {
    @Environment(\.container) private var container

    var body: some View {
        Form {
            Section("Defaults") {
                if let settings = container?.settingsService {
                    Toggle("Default: Prefer Summary", isOn: Binding(
                        get: { settings.settings.context.defaultPreferSummary },
                        set: { settings.updateDefaultPreferSummary($0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }
}
