//
//  RecordingSourceDetailView.swift
//  HiDocu
//
//  Detail view for a recording source. Displays a unified table of recordings
//  that merges device files (when online) with local recordings, showing sync status.
//

import SwiftUI
import QuickLook

struct RecordingSourceDetailView: View {
    var source: RecordingSource
    var viewModel: RecordingSourceViewModel
    var importService: RecordingImportServiceV2
    var deviceController: DeviceController?
    var recordingSourceService: RecordingSourceService
    var documentService: DocumentService
    var fileSystemService: FileSystemService
    var llmQueueState: LLMQueueState
    var onNavigateToDocument: ((Int64) -> Void)?

    @State private var filesToDelete: Set<String> = []
    @State private var filesToDeleteImported: Set<String> = []
    @State private var quickLookURL: URL?

    var body: some View {
        Group {
            if let controller = deviceController {
                deviceBackedContent(controller: controller)
            } else {
                offlineContent
            }
        }
        .navigationTitle(source.name)
        .quickLookPreview($quickLookURL)
    }

    // MARK: - Device-Backed Content

    @ViewBuilder
    private func deviceBackedContent(controller: DeviceController) -> some View {
        switch controller.connectionState {
        case .connected:
            dashboardContent(controller: controller)
        case .connecting(let attempt, let maxAttempts):
            DeviceConnectingView(
                attempt: attempt,
                maxAttempts: maxAttempts,
                modelName: controller.displayName
            )
        case .connectionFailed, .disconnected:
            DeviceConnectionFailedView(deviceController: controller)
        }
    }

    // MARK: - Dashboard Content (Online)

    private func dashboardContent(controller: DeviceController) -> some View {
        let session = importService.session(for: controller.id)

        return VStack(spacing: 0) {
            DeviceHeaderView(
                title: source.name,
                model: controller.connectionInfo?.model ?? .unknown,
                connectionInfo: controller.connectionInfo,
                batteryInfo: controller.batteryInfo,
                storageInfo: controller.storageInfo,
                recordingsBytes: recordingsBytes,
                importService: importService,
                controller: controller,
                session: session,
                onDisconnect: { await controller.disconnect() }
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            recordingBrowser(controller: controller)
                .frame(maxHeight: .infinity)

            if let session = session, session.isImporting {
                Divider()
                ImportProgressFooter(session: session)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .task(id: source.id) {
            let needsLoad = viewModel.rows.isEmpty || !viewModel.lastLoadIncludedDevice
            if needsLoad && !viewModel.isLoading && viewModel.errorMessage == nil {
                await viewModel.loadRecordings(sourceId: source.id, deviceController: controller)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadRecordings(sourceId: source.id, deviceController: controller) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh file list")
                .disabled(viewModel.isLoading)
            }
        }
        .onChange(of: session?.isImporting) { oldValue, newValue in
            if (oldValue == true) && (newValue == false || newValue == nil) {
                Task { await viewModel.refreshImportStatus(sourceId: source.id) }
            }
        }
    }

    // MARK: - Offline Content

    private var offlineContent: some View {
        VStack(spacing: 0) {
            DeviceHeaderView(
                title: source.name,
                model: DeviceModel(rawValue: source.deviceModel ?? "") ?? .unknown,
                lastSeenAt: source.lastSeenAt
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            recordingBrowser(controller: nil)
                .frame(maxHeight: .infinity)
        }
        .task(id: source.id) {
            if viewModel.rows.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                await viewModel.loadRecordings(sourceId: source.id, deviceController: nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadRecordings(sourceId: source.id, deviceController: nil) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh list")
                .disabled(viewModel.isLoading)
            }
        }
    }

    // MARK: - Recording Browser

    @ViewBuilder
    private func recordingBrowser(controller: DeviceController?) -> some View {
        if viewModel.isLoading && viewModel.rows.isEmpty {
            ProgressView("Loading recordings...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.rows.isEmpty {
            RecordingEmptyStateView(
                title: deviceController != nil ? "No Recordings on Device" : "No Recordings",
                errorMessage: viewModel.errorMessage,
                isLoading: viewModel.isLoading,
                onRefresh: { Task { await viewModel.loadRecordings(sourceId: source.id, deviceController: deviceController) } }
            )
        } else {
            @Bindable var bindableViewModel = viewModel
            Table(viewModel.sortedRows, selection: $bindableViewModel.selection, sortOrder: $bindableViewModel.sortOrder) {
                TableColumn("Date", value: \.sortableDate) { row in
                    Group {
                        if let date = row.createdAt {
                            Text(date.formatted(RecordingTableConstants.dateFormat))
                                .monospacedDigit()
                        } else {
                            Text("--")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .opacity(row.dimmedWhenOffline(controller))
                }
                .width(min: RecordingTableConstants.dateColumnWidth.min, ideal: RecordingTableConstants.dateColumnWidth.ideal)

                TableColumn("Name", value: \.filename) { row in
                    Text(row.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                        .opacity(row.dimmedWhenOffline(controller))
                }
                .width(min: RecordingTableConstants.nameColumnWidth.min, ideal: RecordingTableConstants.nameColumnWidth.ideal)

                TableColumn("Duration", value: \.durationSeconds) { row in
                    Text(row.durationSeconds.formattedDurationFull)
                        .monospacedDigit()
                        .opacity(row.dimmedWhenOffline(controller))
                }
                .width(min: RecordingTableConstants.durationColumnWidth.min, ideal: RecordingTableConstants.durationColumnWidth.ideal)

                TableColumn("Mode", value: \.modeDisplayName) { row in
                    Text(row.modeDisplayName)
                        .opacity(row.dimmedWhenOffline(controller))
                }
                .width(min: RecordingTableConstants.modeColumnWidth.min, ideal: RecordingTableConstants.modeColumnWidth.ideal)

                TableColumn("Size", value: \.size) { row in
                    Text(row.size.formattedFileSize)
                        .monospacedDigit()
                        .opacity(row.dimmedWhenOffline(controller))
                }
                .width(min: RecordingTableConstants.sizeColumnWidth.min, ideal: RecordingTableConstants.sizeColumnWidth.ideal)

                TableColumn("", sortUsing: KeyPathComparator(\UnifiedRecordingRow.syncStatus)) { row in
                    AvailabilityStatusIcon(
                        syncStatus: row.syncStatus,
                        isDeviceOnline: controller != nil
                    )
                    .opacity(row.dimmedWhenOffline(controller))
                }
                .width(RecordingTableConstants.statusIconColumnWidth)

                TableColumn("") { (row: UnifiedRecordingRow) in
                    DocumentStatusCell(
                        documentInfo: row.documentInfo,
                        isProcessing: row.isProcessing,
                        onNavigateToDocument: { docId in
                            onNavigateToDocument?(docId)
                        },
                        onCreateDocument: {
                            Task {
                                await viewModel.createDocuments(
                                    filenames: [row.filename],
                                    sourceId: source.id,
                                    documentService: documentService,
                                    importService: importService
                                )
                            }
                        }
                    )
                }
                .width(min: RecordingTableConstants.documentColumnWidth.min, ideal: RecordingTableConstants.documentColumnWidth.ideal)
            }
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if !selectedIds.isEmpty {
                    let selectedRows = viewModel.rows.filter { selectedIds.contains($0.id) }
                    let hasLocal = selectedRows.contains { $0.syncStatus != .onDeviceOnly }
                    let hasUnimported = selectedRows.contains { $0.syncStatus == .onDeviceOnly }
                    let isDeviceOnline = controller != nil
                    let isImporting = controller.flatMap { importService.session(for: $0.id)?.isImporting } ?? false

                    RecordingContextMenu(
                        hasLocalFile: hasLocal,
                        isDeviceOnly: hasUnimported,
                        isDeviceOnline: isDeviceOnline,
                        isImporting: isImporting,
                        onOpen: {
                            if let row = selectedRows.first, row.syncStatus != .onDeviceOnly {
                                openRecording(row)
                            }
                        },
                        onShowInFinder: {
                            if let row = selectedRows.first, row.syncStatus != .onDeviceOnly {
                                showInFinder(row)
                            }
                        },
                        onImport: {
                            if let ctrl = controller {
                                let files = viewModel.deviceFiles(for: selectedIds)
                                importService.importDeviceFiles(files, from: ctrl)
                            }
                        },
                        onCreateDocument: {
                            Task {
                                await viewModel.createDocuments(
                                    filenames: selectedIds,
                                    sourceId: source.id,
                                    documentService: documentService,
                                    importService: importService
                                )
                            }
                        },
                        onDeleteImported: {
                            filesToDeleteImported = selectedIds.filter { id in
                                selectedRows.first(where: { $0.id == id })?.syncStatus != .onDeviceOnly
                            }
                        }
                    )
                }
            }
            .onKeyPress(.space) {
                if let filename = viewModel.selection.first,
                   let row = viewModel.rows.first(where: { $0.filename == filename }),
                   row.syncStatus != .onDeviceOnly,
                   let filepath = row.filepath {
                    let url = fileSystemService.recordingFileURL(relativePath: filepath)
                    if FileManager.default.fileExists(atPath: url.path) {
                        quickLookURL = url
                    }
                }
                return .handled
            }
            .confirmationDialog(
                "Delete from Device",
                isPresented: Binding(
                    get: { !filesToDelete.isEmpty },
                    set: { if !$0 { filesToDelete = [] } }
                )
            ) {
                Button("Delete \(filesToDelete.count) file\(filesToDelete.count == 1 ? "" : "s")", role: .destructive) {
                    let ids = filesToDelete
                    filesToDelete = []
                    Task {
                        if let ctrl = controller {
                            await deleteFiles(ids, controller: ctrl)
                        }
                    }
                }
            } message: {
                Text("This will permanently delete \(filesToDelete.count) file\(filesToDelete.count == 1 ? "" : "s") from the device. This cannot be undone.")
            }
            .confirmationDialog(
                "Delete Imported",
                isPresented: Binding(
                    get: { !filesToDeleteImported.isEmpty },
                    set: { if !$0 { filesToDeleteImported = [] } }
                )
            ) {
                Button("Delete \(filesToDeleteImported.count) local cop\(filesToDeleteImported.count == 1 ? "y" : "ies")", role: .destructive) {
                    let ids = filesToDeleteImported
                    filesToDeleteImported = []
                    Task {
                        await viewModel.deleteLocalCopies(filenames: ids, sourceId: source.id)
                    }
                }
            } message: {
                Text("This will remove the local copy. The file will remain on the device if still connected.")
            }
        }
    }

    // MARK: - Actions

    private func deleteFiles(_ filenames: Set<String>, controller: DeviceController) async {
        for filename in filenames {
            do {
                try await controller.deleteFile(filename: filename)
            } catch {
                AppLogger.recordings.error("Failed to delete \(filename): \(error.localizedDescription)")
            }
        }

        viewModel.selection.removeAll()
        await viewModel.loadRecordings(sourceId: source.id, deviceController: controller)
        await controller.refreshStorageInfo()
    }

    private func openRecording(_ row: UnifiedRecordingRow) {
        guard let filepath = row.filepath else { return }
        let url = fileSystemService.recordingFileURL(relativePath: filepath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showInFinder(_ row: UnifiedRecordingRow) {
        guard let filepath = row.filepath else { return }
        let url = fileSystemService.recordingFileURL(relativePath: filepath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Computed

    private var recordingsBytes: Int64 {
        viewModel.rows.reduce(Int64(0)) { $0 + Int64($1.size) }
    }
}
