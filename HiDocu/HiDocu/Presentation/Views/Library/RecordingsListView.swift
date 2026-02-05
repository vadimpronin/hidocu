//
//  RecordingsListView.swift
//  HiDocu
//
//  Displays recordings grouped by date with filtering support.
//

import SwiftUI
import UniformTypeIdentifiers

struct RecordingsListView: View {
    var viewModel: RecordingsListViewModel
    @Binding var selectedRecordingId: Int64?
    var importService: RecordingImportService?

    @State private var isDropTargeted = false
    @State private var importError: String?

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.groups.isEmpty {
                emptyView
            } else {
                populatedView
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(8)
                    .padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .errorBanner($importError)
        .task {
            viewModel.startObserving()
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }

    // MARK: - Drag & Drop

    private static let supportedAudioExtensions = ["hda", "mp3", "m4a", "wav", "aac", "flac"]

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let importService else { return }

        Task {
            var urls: [URL] = []
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                    continue
                }
                if let item = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                ) {
                    // loadItem may return Data (URL string bytes) or URL directly
                    let url: URL?
                    if let directURL = item as? URL {
                        url = directURL
                    } else if let data = item as? Data,
                              let path = String(data: data, encoding: .utf8) {
                        url = URL(string: path)
                    } else {
                        url = nil
                    }
                    if let url, Self.supportedAudioExtensions.contains(url.pathExtension.lowercased()) {
                        urls.append(url)
                    }
                }
            }

            guard !urls.isEmpty else {
                await MainActor.run {
                    importError = "No supported audio files found. Supported: \(Self.supportedAudioExtensions.map { ".\($0)" }.joined(separator: ", "))"
                }
                return
            }

            do {
                let recordings = try await importService.importFiles(urls)
                AppLogger.ui.info("Imported \(recordings.count) files via drag & drop")
            } catch {
                AppLogger.ui.error("Import failed: \(error.localizedDescription)")
                await MainActor.run {
                    importError = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading recordings...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Recordings Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect your HiDock device and import, or drag audio files here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Populated

    private var populatedView: some View {
        List(selection: $selectedRecordingId) {
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.recordings) { recording in
                        RecordingRowView(recording: recording)
                            .tag(recording.id)
                            .contextMenu {
                                Button("Copy Title") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        recording.displayTitle,
                                        forType: .string
                                    )
                                }

                                Button("Show in Finder") {
                                    let url = URL(fileURLWithPath: recording.filepath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .disabled(recording.status == .new)

                                Divider()

                                Button("Delete", role: .destructive) {
                                    // Placeholder for future delete implementation
                                }
                            }
                    }
                } header: {
                    Text(group.headerTitle)
                }
            }
        }
    }
}
