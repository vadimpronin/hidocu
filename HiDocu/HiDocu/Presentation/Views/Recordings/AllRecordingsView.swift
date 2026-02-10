//
//  AllRecordingsView.swift
//  HiDocu
//
//  Flat table of ALL recordings across all sources with enriched status columns.
//  Shown when "All Recordings" is selected in the sidebar.
//

import SwiftUI
import QuickLook

struct AllRecordingsView: View {
    var viewModel: AllRecordingsViewModel
    var connectedSourceIds: Set<Int64>
    var documentService: DocumentService
    var fileSystemService: FileSystemService
    var importService: RecordingImportServiceV2
    var onNavigateToDocument: ((Int64) -> Void)?

    @State private var idsToDeleteImported: Set<Int64> = []
    @State private var quickLookURL: URL?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView("Loading recordings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.rows.isEmpty {
                emptyState
            } else {
                recordingTable
            }
        }
        .navigationTitle("All Recordings")
        .quickLookPreview($quickLookURL)
        .task {
            await viewModel.loadData()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh recordings")
                .disabled(viewModel.isLoading)
            }
        }
    }

    // MARK: - Recording Table

    private var recordingTable: some View {
        @Bindable var bindableVM = viewModel
        return Table(viewModel.sortedRows, selection: $bindableVM.selection, sortOrder: $bindableVM.sortOrder) {
            // Source icon column
            TableColumn("") { (row: AllRecordingsRow) in
                sourceIcon(for: row)
            }
            .width(28)

            TableColumn("Source") { (row: AllRecordingsRow) in
                Text(row.sourceName ?? "Unknown")
                    .foregroundStyle(row.sourceName != nil ? .secondary : .tertiary)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Name", value: \.filename) { row in
                Text(row.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
            .width(min: 150, ideal: 250)

            TableColumn("Date", value: \.createdAt) { row in
                Text(row.createdAt.formatted(
                    .dateTime
                        .day(.twoDigits)
                        .month(.abbreviated)
                        .year()
                        .hour(.twoDigits(amPM: .omitted))
                        .minute(.twoDigits)
                        .second(.twoDigits)
                ))
                .monospacedDigit()
            }
            .width(min: 180, ideal: 190)

            TableColumn("Duration") { (row: AllRecordingsRow) in
                if let duration = row.durationSeconds {
                    Text(duration.formattedDurationFull)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Mode") { (row: AllRecordingsRow) in
                Text(row.recordingMode?.displayName ?? "—")
            }
            .width(min: 55, ideal: 70)

            TableColumn("Size") { (row: AllRecordingsRow) in
                if let size = row.fileSizeBytes {
                    Text(size.formattedFileSize)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("") { (row: AllRecordingsRow) in
                AvailabilityStatusIcon(
                    syncStatus: row.syncStatus,
                    isDeviceOnline: row.recordingSourceId.map { connectedSourceIds.contains($0) } ?? false
                )
            }
            .width(28)

            TableColumn("") { (row: AllRecordingsRow) in
                DocumentStatusCell(
                    documentInfo: row.documentInfo,
                    isProcessing: row.isProcessing,
                    onNavigateToDocument: { docId in
                        onNavigateToDocument?(docId)
                    },
                    onCreateDocument: {
                        Task {
                            await createDocument(for: row)
                        }
                    }
                )
            }
            .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: Int64.self) { selectedIds in
            if !selectedIds.isEmpty {
                let selectedRows = viewModel.rows.filter { selectedIds.contains($0.id) }
                let hasLocal = selectedRows.contains { $0.syncStatus != .onDeviceOnly }

                RecordingContextMenu(
                    hasLocalFile: hasLocal,
                    isDeviceOnly: false,
                    isDeviceOnline: false,
                    isImporting: false,
                    onOpen: {
                        if let row = selectedRows.first {
                            openFile(filepath: row.filepath)
                        }
                    },
                    onShowInFinder: {
                        if let row = selectedRows.first {
                            showInFinder(filepath: row.filepath)
                        }
                    },
                    onCreateDocument: {
                        Task {
                            for row in selectedRows where row.documentInfo.isEmpty {
                                await createDocument(for: row)
                            }
                        }
                    },
                    onDeleteImported: {
                        idsToDeleteImported = selectedIds.filter { id in
                            selectedRows.first(where: { $0.id == id })?.syncStatus != .onDeviceOnly
                        }
                    }
                )
            }
        }
        .onKeyPress(.space) {
            if let id = viewModel.selection.first,
               let row = viewModel.rows.first(where: { $0.id == id }),
               row.syncStatus != .onDeviceOnly,
               !row.filepath.isEmpty {
                let url = fileSystemService.recordingFileURL(relativePath: row.filepath)
                if FileManager.default.fileExists(atPath: url.path) {
                    quickLookURL = url
                }
            }
            return .handled
        }
        .confirmationDialog(
            "Delete Imported",
            isPresented: Binding(
                get: { !idsToDeleteImported.isEmpty },
                set: { if !$0 { idsToDeleteImported = [] } }
            )
        ) {
            Button("Delete \(idsToDeleteImported.count) local cop\(idsToDeleteImported.count == 1 ? "y" : "ies")", role: .destructive) {
                let ids = idsToDeleteImported
                idsToDeleteImported = []
                Task {
                    await viewModel.deleteLocalCopies(ids: ids)
                }
            }
        } message: {
            Text("This will remove the local copy. The file will remain on the device if still connected.")
        }
    }

    // MARK: - Source Icon

    @ViewBuilder
    private func sourceIcon(for row: AllRecordingsRow) -> some View {
        if let modelStr = row.sourceDeviceModel,
           let model = DeviceModel(rawValue: modelStr) {
            if let imageName = model.imageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: model.sfSymbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No Recordings")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Import recordings from a connected device to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.loadData() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
            .disabled(viewModel.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openFile(filepath: String) {
        let url = fileSystemService.recordingFileURL(relativePath: filepath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showInFinder(filepath: String) {
        let url = fileSystemService.recordingFileURL(relativePath: filepath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func createDocument(for row: AllRecordingsRow) async {
        do {
            _ = try await documentService.createDocumentWithSource(
                title: row.displayTitle,
                audioRelativePath: row.filepath,
                originalFilename: row.filename,
                durationSeconds: row.durationSeconds,
                fileSizeBytes: row.fileSizeBytes,
                deviceSerial: nil,
                deviceModel: row.sourceDeviceModel,
                recordingMode: row.recordingMode?.rawValue,
                recordedAt: row.createdAt,
                recordingId: row.id
            )
            await viewModel.loadData()
        } catch {
            AppLogger.recordings.error("Failed to create document: \(error.localizedDescription)")
        }
    }
}
