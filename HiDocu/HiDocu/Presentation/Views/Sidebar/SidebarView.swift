//
//  SidebarView.swift
//  HiDocu
//
//  Sidebar with library filters and device navigation item.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var navigationVM: NavigationViewModel
    var deviceService: DeviceConnectionService
    var syncService: RecordingSyncService

    var body: some View {
        List(selection: $navigationVM.selectedSidebarItem) {
            // Locations section — shown when device is connected or connecting
            if shouldShowLocations {
                Section("Locations") {
                    locationContent
                }
            }

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
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    // MARK: - Locations Content

    private var shouldShowLocations: Bool {
        switch deviceService.connectionState {
        case .connecting, .connected:
            return true
        case .disconnected, .error:
            return false
        }
    }

    @ViewBuilder
    private var locationContent: some View {
        switch deviceService.connectionState {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .foregroundStyle(.secondary)
            }
        case .connected:
            Label(
                deviceService.connectionInfo?.model.displayName ?? "HiDock",
                systemImage: deviceService.connectionInfo?.model.sfSymbolName ?? "externaldrive.fill"
            )
            .tag(SidebarItem.device)
            .contextMenu {
                Button("Sync All") {
                    Task { await syncService.syncFromDevice() }
                }
                .disabled(syncService.isSyncing)

                Divider()

                Button("Eject \(deviceService.connectionInfo?.model.displayName ?? "Device")") {
                    Task { @MainActor in deviceService.disconnect() }
                }
            }
        default:
            EmptyView()
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
