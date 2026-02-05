//
//  DeviceDashboardView.swift
//  HiDocu
//
//  Finder-style device dashboard shown when the device is selected in the sidebar.
//  Composed of three sections: device header, file browser table, and sync footer.
//

import SwiftUI

struct DeviceDashboardView: View {
    var deviceService: DeviceConnectionService
    var syncService: RecordingSyncService
    @State var viewModel: DeviceDashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Device Header with inline Sync button
            DeviceHeaderSection(
                deviceService: deviceService,
                syncService: syncService,
                recordingsBytes: recordingsBytes
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // File Browser
            fileBrowser
                .frame(maxHeight: .infinity)

            // Sync Footer (progress only)
            if syncService.isSyncing {
                Divider()
                SyncProgressFooter(syncService: syncService)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .navigationTitle(deviceService.connectionInfo?.model.displayName ?? "Device")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { @MainActor in await deviceService.disconnect() }
                } label: {
                    Label("Eject", systemImage: "eject.fill")
                }
                .help("Safely disconnect device")
            }
        }
        .task {
            await viewModel.loadFiles()
        }
        .onChange(of: syncService.isSyncing) { wasSyncing, isSyncing in
            if wasSyncing && !isSyncing {
                Task { await viewModel.loadFiles() }
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
            Table(viewModel.sortedFiles, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
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

                TableColumn("", sortUsing: KeyPathComparator(\DeviceFileRow.isSynced, comparator: BoolComparator())) { row in
                    SyncStatusIcon(isSynced: row.isSynced)
                }
                .width(28)
            }
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if !selectedIds.isEmpty {
                    Button("Import Selected") {
                        let files = viewModel.deviceFiles(for: selectedIds)
                        syncService.syncFiles(files)
                    }
                    .disabled(syncService.isSyncing)

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
    var deviceService: DeviceConnectionService
    var syncService: RecordingSyncService
    var recordingsBytes: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: deviceService.connectionInfo?.model.sfSymbolName ?? "externaldrive.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 8) {
                Text(deviceService.connectionInfo?.model.displayName ?? "HiDock")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Metadata grid
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    if let info = deviceService.connectionInfo {
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

                    if let battery = deviceService.batteryInfo,
                       deviceService.connectionInfo?.supportsBattery == true {
                        GridRow {
                            Text("Battery:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            BatteryIndicatorView(battery: battery)
                        }
                    }
                }

                // Storage bar with inline Sync button
                if let storage = deviceService.storageInfo {
                    HStack(alignment: .top, spacing: 12) {
                        FinderStorageBar(
                            storage: storage,
                            recordingsBytes: recordingsBytes
                        )

                        SyncButton(syncService: syncService)
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Finder-Style Storage Bar

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
            // The bar
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

            // Legend (single source of space info — no duplicate summary)
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

// MARK: - Sync Status Icon

struct SyncStatusIcon: View {
    let isSynced: Bool

    var body: some View {
        Group {
            if isSynced {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .help(isSynced ? "Downloaded to library" : "On device \u{2014} not yet downloaded")
    }
}

// MARK: - Sync Progress Footer

struct SyncProgressFooter: View {
    var syncService: RecordingSyncService

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if syncService.syncState == .stopping {
                    Text("Stopping after current file…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let file = syncService.currentFile {
                    Text("Syncing \"\(file)\"")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ProgressView(value: syncService.progress)
                    .progressViewStyle(.linear)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(syncService.formattedBytesProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if syncService.bytesPerSecond > 0 {
                    Text(syncService.formattedTelemetry)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .fixedSize()
        }
    }
}

// MARK: - Sync Button

private struct SyncButton: View {
    var syncService: RecordingSyncService

    private var showsSpinner: Bool {
        syncService.syncState == .preparing || syncService.syncState == .stopping
    }

    private var label: String {
        switch syncService.syncState {
        case .idle: "Sync"
        case .preparing: "Preparing…"
        case .syncing: "Stop"
        case .stopping: "Stopping…"
        }
    }

    var body: some View {
        if syncService.syncState == .idle {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button {
            switch syncService.syncState {
            case .idle:
                syncService.syncFromDevice()
            case .preparing, .syncing:
                syncService.cancelSync()
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
        .disabled(syncService.syncState == .stopping)
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
