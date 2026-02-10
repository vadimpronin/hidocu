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
                RecordingEmptyStateView(
                    title: "No Recordings",
                    subtitle: "Import recordings from a connected device to get started.",
                    errorMessage: viewModel.errorMessage,
                    isLoading: viewModel.isLoading,
                    onRefresh: { Task { await viewModel.loadData() } }
                )
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
            TableColumn("") { (row: AllRecordingsRow) in
                sourceIcon(for: row)
            }
            .width(RecordingTableConstants.sourceIconColumnWidth)

            TableColumn("Source") { (row: AllRecordingsRow) in
                Text(row.sourceName ?? "Unknown")
                    .foregroundStyle(row.sourceName != nil ? .secondary : .tertiary)
            }
            .width(min: RecordingTableConstants.sourceColumnWidth.min, ideal: RecordingTableConstants.sourceColumnWidth.ideal)

            TableColumn("Name", value: \.filename) { row in
                Text(row.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
            .width(min: RecordingTableConstants.nameColumnWidth.min, ideal: RecordingTableConstants.nameColumnWidth.ideal)

            TableColumn("Date", value: \.createdAt) { row in
                Text(row.createdAt.formatted(RecordingTableConstants.dateFormat))
                    .monospacedDigit()
            }
            .width(min: RecordingTableConstants.dateColumnWidth.min, ideal: RecordingTableConstants.dateColumnWidth.ideal)

            TableColumn("Duration") { (row: AllRecordingsRow) in
                if let duration = row.durationSeconds {
                    Text(duration.formattedDurationFull)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: RecordingTableConstants.durationColumnWidth.min, ideal: RecordingTableConstants.durationColumnWidth.ideal)

            TableColumn("Mode") { (row: AllRecordingsRow) in
                Text(row.recordingMode?.displayName ?? "\u{2014}")
            }
            .width(min: RecordingTableConstants.modeColumnWidth.min, ideal: RecordingTableConstants.modeColumnWidth.ideal)

            TableColumn("Size") { (row: AllRecordingsRow) in
                if let size = row.fileSizeBytes {
                    Text(size.formattedFileSize)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: RecordingTableConstants.sizeColumnWidth.min, ideal: RecordingTableConstants.sizeColumnWidth.ideal)

            TableColumn("") { (row: AllRecordingsRow) in
                AvailabilityStatusIcon(
                    syncStatus: row.syncStatus,
                    isDeviceOnline: row.recordingSourceId.map { connectedSourceIds.contains($0) } ?? false
                )
            }
            .width(RecordingTableConstants.statusIconColumnWidth)

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
            .width(min: RecordingTableConstants.documentColumnWidth.min, ideal: RecordingTableConstants.documentColumnWidth.ideal)
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
            DeviceIconView(model: model, size: 16)
        } else {
            DeviceIconView(model: nil, size: 16)
        }
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
        guard row.syncStatus != .onDeviceOnly, !row.filepath.isEmpty else { return }
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
