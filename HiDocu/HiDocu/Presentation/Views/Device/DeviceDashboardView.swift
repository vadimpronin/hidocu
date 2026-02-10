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
        .onChange(of: session?.isImporting) { oldValue, newValue in
            if (oldValue == true) && (newValue == false || newValue == nil) {
                Task { await viewModel.refreshImportStatus() }
            }
        }
    }

    // MARK: - File Browser

    private var fileBrowser: some View {
        @Bindable var bindableViewModel = viewModel

        return UnifiedRecordingListView(
            rows: viewModel.sortedFiles,
            selection: $bindableViewModel.selection,
            sortOrder: $bindableViewModel.sortOrder,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            config: .deviceDashboard,
            emptyStateTitle: "No Recordings on Device",
            emptyStateSubtitle: "Record something on your HiDock and refresh the list.",
            onRefresh: { await viewModel.loadFiles() },
            statusSortComparator: KeyPathComparator(\DeviceFileRow.isImported, comparator: BoolComparator()),
            sourceIcon: { _ in
                EmptyView()
            },
            statusCell: { row in
                ImportStatusIcon(isImported: row.isImported)
            },
            documentCell: { _ in
                EmptyView()
            },
            contextMenu: { selectedIds in
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
        )
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
