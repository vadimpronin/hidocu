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
        @Bindable var bindableVM = viewModel

        UnifiedRecordingListView(
            rows: viewModel.sortedRows,
            selection: $bindableVM.selection,
            sortOrder: $bindableVM.sortOrder,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            config: .allRecordings,
            emptyStateTitle: "No Recordings",
            emptyStateSubtitle: "Import recordings from a connected device to get started.",
            onRefresh: { await viewModel.loadData() },
            sourceName: { $0.sourceName },
            primaryAction: { row in
                guard row.syncStatus != .onDeviceOnly, !row.filepath.isEmpty else { return }
                let url = fileSystemService.recordingFileURL(relativePath: row.filepath)
                if FileManager.default.fileExists(atPath: url.path) {
                    quickLookURL = url
                }
            },
            sourceIcon: { row in
                sourceIcon(for: row)
            },
            statusCell: { row in
                AvailabilityStatusIcon(
                    syncStatus: row.syncStatus ?? .onDeviceOnly,
                    isDeviceOnline: row.recordingSourceId.map { connectedSourceIds.contains($0) } ?? false
                )
            },
            documentCell: { row in
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
            },
            contextMenu: { selectedIds in
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
        )
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
        .navigationTitle("All Recordings")
        .quickLookPreview($quickLookURL)
        .task {
            await viewModel.loadData()
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
