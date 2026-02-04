//
//  SidebarView.swift
//  HiDocu
//
//  Sidebar with library filters and device status section.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var navigationVM: NavigationViewModel
    var deviceService: DeviceConnectionService
    var syncService: RecordingSyncService

    var body: some View {
        List(selection: $navigationVM.selectedSidebarItem) {
            Section("Library") {
                Label("All Recordings", systemImage: "waveform")
                    .tag(SidebarItem.allRecordings)

                Label("New", systemImage: "circle.fill")
                    .foregroundStyle(.blue)
                    .tag(SidebarItem.filteredByStatus(.new))

                Label("Downloaded", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                    .tag(SidebarItem.filteredByStatus(.downloaded))

                Label("Transcribed", systemImage: "text.bubble.fill")
                    .foregroundStyle(.purple)
                    .tag(SidebarItem.filteredByStatus(.transcribed))
            }

            Section("Device") {
                DeviceSidebarView(
                    deviceService: deviceService,
                    syncService: syncService
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

// MARK: - Device Sidebar View

struct DeviceSidebarView: View {
    var deviceService: DeviceConnectionService
    var syncService: RecordingSyncService

    var body: some View {
        switch deviceService.connectionState {
        case .disconnected:
            disconnectedView
        case .connecting:
            connectingView
        case .connected:
            connectedView
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No Device", systemImage: "cable.connector")
                .foregroundStyle(.secondary)

            Button("Connect") {
                Task {
                    do {
                        _ = try await deviceService.connect()
                    } catch {
                        // Error shown via connectionState
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Connecting

    private var connectingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Connecting...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connected

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Device name
            Label(
                deviceService.connectionInfo?.model.displayName ?? "HiDock",
                systemImage: "cable.connector"
            )
            .fontWeight(.medium)

            // Battery (P1 only)
            if let battery = deviceService.batteryInfo,
               deviceService.connectionInfo?.supportsBattery == true {
                BatteryIndicatorView(battery: battery)
            }

            // Storage bar
            if let storage = deviceService.storageInfo {
                StorageBarView(storage: storage)
            }

            // Sync button / progress
            if syncService.isSyncing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: syncService.progress)
                        .progressViewStyle(.linear)
                    if let file = syncService.currentFile {
                        Text(file)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Button("Sync") {
                    Task {
                        await syncService.syncFromDevice()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Disconnect
            Button("Disconnect") {
                Task { @MainActor in
                    deviceService.disconnect()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .controlSize(.small)

            // Sync stats
            if let stats = syncService.syncStats, !syncService.isSyncing {
                Text("\(stats.downloaded) downloaded, \(stats.skipped) skipped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Error
            if let error = syncService.errorMessage, !syncService.isSyncing {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connection Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Retry") {
                Task {
                    do {
                        _ = try await deviceService.connect()
                    } catch {
                        // Error shown via connectionState
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

// MARK: - Battery Indicator

struct BatteryIndicatorView: View {
    let battery: DeviceBatteryInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIconName)
                .foregroundStyle(batteryColor)
            Text("\(battery.percentage)%")
                .font(.caption)
                .foregroundStyle(.secondary)
            if battery.state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var batteryIconName: String {
        switch battery.percentage {
        case 0..<15:   return "battery.0percent"
        case 15..<40:  return "battery.25percent"
        case 40..<60:  return "battery.50percent"
        case 60..<85:  return "battery.75percent"
        default:       return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        if battery.percentage < 15 { return .red }
        if battery.percentage < 30 { return .orange }
        return .green
    }
}

// MARK: - Storage Bar

struct StorageBarView: View {
    let storage: DeviceStorageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * storage.usedPercentage, height: 6)
                }
            }
            .frame(height: 6)

            Text("\(storage.formattedFree) free of \(storage.formattedTotal)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var barColor: Color {
        if storage.usedPercentage > 0.9 { return .red }
        if storage.usedPercentage > 0.75 { return .orange }
        return .blue
    }
}
