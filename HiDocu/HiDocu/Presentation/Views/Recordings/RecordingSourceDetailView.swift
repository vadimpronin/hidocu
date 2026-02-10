//
//  RecordingSourceDetailView.swift
//  HiDocu
//
//  Detail view for a recording source. Displays a unified table of recordings
//  that merges device files (when online) with local recordings, showing sync status.
//

import SwiftUI

struct RecordingSourceDetailView: View {
    var source: RecordingSource
    var viewModel: RecordingSourceViewModel
    var importService: RecordingImportServiceV2
    var deviceController: DeviceController?

    @State private var filesToDelete: Set<String> = []

    var body: some View {
        Group {
            if let controller = deviceController {
                // Device-backed source
                deviceBackedContent(controller: controller)
            } else {
                // Offline source (manual import or disconnected device)
                offlineContent
            }
        }
        .navigationTitle(source.name)
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
            // Device Header with inline Import button
            SourceHeaderSection(
                source: source,
                deviceController: controller,
                importService: importService,
                session: session,
                recordingsBytes: recordingsBytes
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // File Browser
            recordingBrowser(controller: controller)
                .frame(maxHeight: .infinity)

            // Import Footer (progress only)
            if let session = session, session.isImporting {
                Divider()
                ImportProgressFooter(session: session)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .task {
            // Only load on first appearance; cached files skip this
            if viewModel.rows.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
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
            // If import finished, refresh import status without re-fetching file list
            if (oldValue == true) && (newValue == false || newValue == nil) {
                Task { await viewModel.refreshImportStatus(sourceId: source.id) }
            }
        }
    }

    // MARK: - Offline Content

    private var offlineContent: some View {
        VStack(spacing: 0) {
            // Offline Header
            OfflineSourceHeaderSection(source: source)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Local recordings browser
            recordingBrowser(controller: nil)
                .frame(maxHeight: .infinity)
        }
        .task {
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
            emptyState
        } else {
            @Bindable var bindableViewModel = viewModel
            Table(viewModel.sortedRows, selection: $bindableViewModel.selection, sortOrder: $bindableViewModel.sortOrder) {
                TableColumn("Date", value: \.sortableDate) { row in
                    if let date = row.createdAt {
                        Text(date.formatted(
                            .dateTime
                                .day(.twoDigits)
                                .month(.abbreviated)
                                .year()
                                .hour(.twoDigits(amPM: .omitted))
                                .minute(.twoDigits)
                                .second(.twoDigits)
                        ))
                        .monospacedDigit()
                    } else {
                        Text("--")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 180, ideal: 190)

                TableColumn("Name", value: \.filename) { row in
                    Text(row.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                }
                .width(min: 150, ideal: 270)

                TableColumn("Duration", value: \.durationSeconds) { row in
                    Text(row.durationSeconds.formattedDurationFull)
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 80)

                TableColumn("Mode", value: \.modeDisplayName) { row in
                    Text(row.modeDisplayName)
                }
                .width(min: 55, ideal: 70)

                TableColumn("Size", value: \.size) { row in
                    Text(row.size.formattedFileSize)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 80)

                TableColumn("", sortUsing: KeyPathComparator(\UnifiedRecordingRow.syncStatus)) { row in
                    SyncStatusIcon(status: row.syncStatus)
                }
                .width(28)
            }
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if !selectedIds.isEmpty {
                    if let ctrl = controller {
                        // Only show import for device-backed sources
                        let selectedRows = viewModel.rows.filter { selectedIds.contains($0.id) }
                        let hasUnimported = selectedRows.contains { $0.syncStatus == .onDeviceOnly }

                        if hasUnimported {
                            Button("Import Selected") {
                                let files = viewModel.deviceFiles(for: selectedIds)
                                importService.importDeviceFiles(files, from: ctrl)
                            }
                            .disabled(importService.session(for: ctrl.id)?.isImporting ?? false)

                            Divider()
                        }

                        Button("Delete from Device", role: .destructive) {
                            filesToDelete = selectedIds
                        }
                    } else {
                        // Offline: show local operations (future)
                        Button("Delete from Library", role: .destructive) {
                            // Future implementation
                        }
                        .disabled(true)
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
                    Task {
                        if let ctrl = controller {
                            await deleteFiles(ids, controller: ctrl)
                        }
                    }
                }
            } message: {
                Text("This will permanently delete \(filesToDelete.count) file\(filesToDelete.count == 1 ? "" : "s") from the device. This cannot be undone.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(deviceController != nil ? "No Recordings on Device" : "No Recordings")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.loadRecordings(sourceId: source.id, deviceController: deviceController) }
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

    // MARK: - Computed

    private var recordingsBytes: Int64 {
        viewModel.rows.reduce(Int64(0)) { $0 + Int64($1.size) }
    }
}

// MARK: - Source Header Section (Online with Device)

private struct SourceHeaderSection: View {
    var source: RecordingSource
    var deviceController: DeviceController
    var importService: RecordingImportServiceV2
    var session: ImportSession?
    var recordingsBytes: Int64

    private var model: DeviceModel {
        deviceController.connectionInfo?.model ?? .unknown
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DeviceIcon(model: model)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(source.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Button {
                        Task {
                            await deviceController.disconnect()
                        }
                    } label: {
                        Image(systemName: "eject.fill")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Safely disconnect device")
                }

                // Metadata grid
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    if let info = deviceController.connectionInfo {
                        GridRow {
                            Text("Serial Number:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(info.serialNumber)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text("Firmware:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(info.firmwareVersion)
                                .font(.caption)
                        }
                    }

                    if let battery = deviceController.batteryInfo,
                       deviceController.connectionInfo?.supportsBattery == true {
                        GridRow {
                            Text("Battery:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            BatteryIndicatorView(battery: battery)
                        }
                    }
                }

                // Storage bar with inline Import button
                if let storage = deviceController.storageInfo {
                    HStack(alignment: .top, spacing: 12) {
                        FinderStorageBar(
                            storage: storage,
                            recordingsBytes: recordingsBytes
                        )

                        ImportButton(
                            importService: importService,
                            controller: deviceController,
                            session: session
                        )
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Offline Source Header Section

private struct OfflineSourceHeaderSection: View {
    var source: RecordingSource

    private var model: DeviceModel {
        if let modelStr = source.deviceModel {
            return DeviceModel(rawValue: modelStr) ?? .unknown
        }
        return .unknown
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DeviceIcon(model: model)

            VStack(alignment: .leading, spacing: 8) {
                Text(source.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Not connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let lastSeen = source.lastSeenAt {
                    Text("Last seen: \(lastSeen.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Device Icon

private struct DeviceIcon: View {
    let model: DeviceModel

    var body: some View {
        Group {
            if let imageName = model.imageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: model.sfSymbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 64, height: 64)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Sync Status Icon

private struct SyncStatusIcon: View {
    let status: RecordingSyncStatus

    var body: some View {
        Group {
            switch status {
            case .onDeviceOnly:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .synced:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .localOnly:
                Image(systemName: "internaldrive")
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 13))
        .help(helpText)
    }

    private var helpText: String {
        switch status {
        case .onDeviceOnly:
            return "On device — not yet downloaded"
        case .synced:
            return "Downloaded to library"
        case .localOnly:
            return "In library — not on device"
        }
    }
}

// MARK: - Import Button

private struct ImportButton: View {
    var importService: RecordingImportServiceV2
    var controller: DeviceController
    var session: ImportSession?

    private var state: ImportState {
        session?.importState ?? .idle
    }

    private var showsSpinner: Bool {
        state == .preparing || state == .stopping
    }

    private var label: String {
        switch state {
        case .idle: "Import"
        case .preparing: "Preparing…"
        case .importing: "Stop"
        case .stopping: "Stopping…"
        }
    }

    var body: some View {
        if state == .idle {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button {
            switch state {
            case .idle:
                importService.importFromDevice(controller: controller)
            case .preparing, .importing:
                importService.cancelImport(for: controller.id)
            case .stopping:
                break
            }
        } label: {
            HStack(spacing: 6) {
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(label)
            }
            .frame(minWidth: 100)
        }
        .controlSize(.regular)
        .disabled(state == .stopping)
    }
}
