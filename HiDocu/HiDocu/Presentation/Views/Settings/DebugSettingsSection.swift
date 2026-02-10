//
//  DebugSettingsSection.swift
//  HiDocu
//
//  SwiftUI section for API debug logging settings.
//

import SwiftUI

/// Reusable settings section for LLM API debug logging.
///
/// Provides controls to enable/disable debug logging, open the logs folder,
/// export logs as a Postman collection, and clear all logs.
struct DebugSettingsSection: View {
    let settingsService: SettingsService
    let debugLogger: APIDebugLogger

    @State private var isDebugEnabled = false
    @State private var logCount = 0
    @State private var logSize: Int64 = 0
    @State private var showClearConfirmation = false
    @State private var isExporting = false

    var body: some View {
        Section {
            Toggle("API Debug Logging", isOn: $isDebugEnabled)
                .onChange(of: isDebugEnabled) { _, newValue in
                    settingsService.updateAPIDebugLogging(newValue)
                    Task {
                        await debugLogger.setEnabled(newValue)
                    }
                }

            if logCount > 0 {
                LabeledContent("Log Files") {
                    Text("\(logCount) files (\(formattedSize))")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Open Logs Folder") {
                    openLogsFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Export Postman Collection") {
                    exportPostmanCollection()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logCount == 0 || isExporting)

                Button("Clear Logs") {
                    showClearConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(logCount == 0)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("When enabled, full API request/response payloads are saved to JSON files for debugging.")
        }
        .confirmationDialog(
            "Clear all debug log files?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task {
                    try? await debugLogger.clearAll()
                    await refreshStats()
                }
            }
        }
        .task {
            isDebugEnabled = settingsService.settings.llm.apiDebugLogging
            await refreshStats()
        }
    }

    // MARK: - Helpers

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: logSize, countStyle: .file)
    }

    private func refreshStats() async {
        let stats = await debugLogger.logDirectoryStats()
        logCount = stats.count
        logSize = stats.totalBytes
    }

    private func openLogsFolder() {
        Task {
            let url = await debugLogger.logDirectoryURL
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func exportPostmanCollection() {
        isExporting = true
        Task {
            let entries = await debugLogger.listEntries()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "HiDocu_Debug_\(dateFormatter.string(from: Date())).postman_collection.json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                let data = try PostmanExporter.generatePostmanCollection(from: entries)
                try data.write(to: tempURL, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([tempURL])
            } catch {
                AppLogger.llm.error("Failed to export Postman collection: \(error.localizedDescription)")
            }

            isExporting = false
            await refreshStats()
        }
    }
}
