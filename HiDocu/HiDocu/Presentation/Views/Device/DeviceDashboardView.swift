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
    var importService: RecordingImportService
    var viewModel: DeviceDashboardViewModel

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
            // Device Header with inline Import button
            DeviceHeaderSection(
                deviceController: deviceController,
                importService: importService,
                session: session,
                recordingsBytes: recordingsBytes
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // File Browser
            fileBrowser
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
            // If import finished, refresh import status without re-fetching file list
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
            emptyState
        } else {
            @Bindable var bindableViewModel = viewModel
            Table(viewModel.sortedFiles, selection: $bindableViewModel.selection, sortOrder: $bindableViewModel.sortOrder) {
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

                TableColumn("", sortUsing: KeyPathComparator(\DeviceFileRow.isImported, comparator: BoolComparator())) { row in
                    ImportStatusIcon(isImported: row.isImported)
                }
                .width(28)
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
                        Task { await viewModel.deleteFiles(selectedIds) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No Recordings on Device")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.loadFiles() }
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

    // MARK: - Computed

    private var recordingsBytes: Int64 {
        viewModel.files.reduce(Int64(0)) { $0 + Int64($1.size) }
    }
}

// MARK: - Device Header Section

private struct DeviceHeaderSection: View {
    var deviceController: DeviceController
    var importService: RecordingImportService
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
                Text(deviceController.displayName)
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

                        // Import button needs to hook up to controller
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

// MARK: - Finder-Style Storage Bar
// (Unchanged, included for completeness or reference from previous)
struct FinderStorageBar: View {
    let storage: DeviceStorageInfo
    let recordingsBytes: Int64

    private var otherBytes: Int64 {
        max(storage.usedBytes - recordingsBytes, 0)
    }

    private var segments: [(color: Color, fraction: Double, label: String, bytes: Int64)] {
        guard storage.totalBytes > 0 else { return [] }
        let total = Double(storage.totalBytes)
        var result: [(Color, Double, String, Int64)] = []

        let recFrac = Double(recordingsBytes) / total
        if recFrac > 0.005 {
            result.append((.blue, recFrac, "Recordings", recordingsBytes))
        }

        let otherFrac = Double(otherBytes) / total
        if otherFrac > 0.005 {
            result.append((.gray, otherFrac, "Other", otherBytes))
        }

        let freeFrac = Double(storage.freeBytes) / total
        result.append((Color(nsColor: .separatorColor), freeFrac, "Available", storage.freeBytes))

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(geo.size.width * segment.fraction, 1))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 14)

            HStack(spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)
                        Text("\(segment.label): \(ByteCountFormatter.string(fromByteCount: segment.bytes, countStyle: .file))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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

// MARK: - Import Progress Footer

struct ImportProgressFooter: View {
    var session: ImportSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if session.importState == .stopping {
                    Text("Stopping after current file…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let file = session.currentFile {
                    Text("Importing \"\(file)\"")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ProgressView(value: session.progress)
                    .progressViewStyle(.linear)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.formattedBytesProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if session.bytesPerSecond > 0 {
                    Text(session.formattedTelemetry)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .fixedSize()
        }
    }
}

// MARK: - Import Button

private struct ImportButton: View {
    var importService: RecordingImportService
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
