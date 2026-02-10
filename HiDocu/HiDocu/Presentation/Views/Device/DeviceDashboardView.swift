//
//  DeviceDashboardView.swift
//  HiDocu
//
//  Finder-style device dashboard shown when the device is selected in the sidebar.
//  Composed of three sections: device header, file browser table, and import footer.
//

import SwiftUI

struct DeviceDashboardView: View {
    var deviceController: DeviceController
    var importService: RecordingImportServiceV2
    var viewModel: DeviceDashboardViewModel

    @State private var filesToDelete: Set<String> = []

    var body: some View {
        Group {
            switch deviceController.connectionState {
            case .connected:
                dashboardContent
            case .connecting(let attempt, let maxAttempts):
                DeviceConnectingView(
                    attempt: attempt,
                    maxAttempts: maxAttempts,
                    modelName: deviceController.displayName
                )
            case .connectionFailed, .disconnected:
                DeviceConnectionFailedView(deviceController: deviceController)
            }
        }
        .navigationTitle(deviceController.displayName)
    }

    // MARK: - Main Dashboard Content

    private var dashboardContent: some View {
        let session = importService.session(for: deviceController.id)

        return VStack(spacing: 0) {
            DeviceHeaderView(
                title: deviceController.displayName,
                model: deviceController.connectionInfo?.model ?? .unknown,
                connectionInfo: deviceController.connectionInfo,
                batteryInfo: deviceController.batteryInfo,
                storageInfo: deviceController.storageInfo,
                recordingsBytes: recordingsBytes,
                importService: importService,
                controller: deviceController,
                session: session,
                onDisconnect: { await deviceController.disconnect() }
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            fileBrowser
                .frame(maxHeight: .infinity)

            if let session = session, session.isImporting {
                Divider()
                ImportProgressFooter(session: session)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .task {
            if viewModel.files.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                await viewModel.loadFiles()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.loadFiles() }
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
                Task { await viewModel.refreshImportStatus() }
            }
        }
    }

    // MARK: - File Browser

    @ViewBuilder
    private var fileBrowser: some View {
        if viewModel.isLoading && viewModel.files.isEmpty {
            ProgressView("Loading files...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.files.isEmpty {
            RecordingEmptyStateView(
                title: "No Recordings on Device",
                errorMessage: viewModel.errorMessage,
                isLoading: viewModel.isLoading,
                onRefresh: { Task { await viewModel.loadFiles() } }
            )
        } else {
            @Bindable var bindableViewModel = viewModel
            Table(viewModel.sortedFiles, selection: $bindableViewModel.selection, sortOrder: $bindableViewModel.sortOrder) {
                TableColumn("Date", value: \.sortableDate) { row in
                    if let date = row.createdAt {
                        Text(date.formatted(RecordingTableConstants.dateFormat))
                            .monospacedDigit()
                    } else {
                        Text("--")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: RecordingTableConstants.dateColumnWidth.min, ideal: RecordingTableConstants.dateColumnWidth.ideal)

                TableColumn("Name", value: \.filename) { row in
                    Text(row.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                }
                .width(min: RecordingTableConstants.nameColumnWidth.min, ideal: RecordingTableConstants.nameColumnWidth.ideal)

                TableColumn("Duration", value: \.durationSeconds) { row in
                    Text(row.durationSeconds.formattedDurationFull)
                        .monospacedDigit()
                }
                .width(min: RecordingTableConstants.durationColumnWidth.min, ideal: RecordingTableConstants.durationColumnWidth.ideal)

                TableColumn("Mode", value: \.modeDisplayName) { row in
                    Text(row.modeDisplayName)
                }
                .width(min: RecordingTableConstants.modeColumnWidth.min, ideal: RecordingTableConstants.modeColumnWidth.ideal)

                TableColumn("Size", value: \.size) { row in
                    Text(row.size.formattedFileSize)
                        .monospacedDigit()
                }
                .width(min: RecordingTableConstants.sizeColumnWidth.min, ideal: RecordingTableConstants.sizeColumnWidth.ideal)

                TableColumn("", sortUsing: KeyPathComparator(\DeviceFileRow.isImported, comparator: BoolComparator())) { row in
                    ImportStatusIcon(isImported: row.isImported)
                }
                .width(RecordingTableConstants.statusIconColumnWidth)
            }
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if !selectedIds.isEmpty {
                    Button("Import Selected") {
                        let files = viewModel.deviceFiles(for: selectedIds)
                        importService.importDeviceFiles(files, from: deviceController)
                    }
                    .disabled(importService.session(for: deviceController.id)?.isImporting ?? false)

                    Divider()

                    Button("Delete from Device", role: .destructive) {
                        filesToDelete = selectedIds
                    }
                }
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
                    Task { await viewModel.deleteFiles(ids) }
                }
            } message: {
                Text("This will permanently delete \(filesToDelete.count) file\(filesToDelete.count == 1 ? "" : "s") from the device. This cannot be undone.")
            }
        }
    }

    // MARK: - Computed

    private var recordingsBytes: Int64 {
        viewModel.files.reduce(Int64(0)) { $0 + Int64($1.size) }
    }
}

// MARK: - Bool Sort Comparator

struct BoolComparator: SortComparator {
    var order: SortOrder = .forward

    func compare(_ lhs: Bool, _ rhs: Bool) -> ComparisonResult {
        switch (lhs, rhs) {
        case (false, true): return order == .forward ? .orderedAscending : .orderedDescending
        case (true, false): return order == .forward ? .orderedDescending : .orderedAscending
        default: return .orderedSame
        }
    }
}

// MARK: - Import Status Icon

struct ImportStatusIcon: View {
    let isImported: Bool

    var body: some View {
        Group {
            if isImported {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .help(isImported ? "Downloaded to library" : "On device \u{2014} not yet downloaded")
    }
}

// MARK: - Device Disconnected Placeholder

struct DeviceDisconnectedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Device Disconnected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect your HiDock device via USB to manage recordings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Device Connecting Placeholder

struct DeviceConnectingView: View {
    let attempt: Int
    let maxAttempts: Int
    var modelName: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting to \(modelName ?? "HiDock")")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Attempt \(attempt) of \(maxAttempts)...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Device Connection Failed Placeholder

struct DeviceConnectionFailedView: View {
    var deviceController: DeviceController

    private var errorMessage: String {
        deviceController.lastError ?? "Unable to communicate with device"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Connection Error")
                .font(.title2)
                .fontWeight(.semibold)

            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)

            Button {
                Task { @MainActor in
                    await deviceController.connect()
                }
            } label: {
                Label("Retry Connection", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
