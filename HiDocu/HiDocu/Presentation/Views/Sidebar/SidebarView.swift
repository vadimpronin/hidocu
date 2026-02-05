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
    var importService: RecordingImportService

    var body: some View {
        List(selection: $navigationVM.selectedSidebarItem) {

            Section("Library") {
                Label("All Recordings", systemImage: "tray.fill")
                    .tag(SidebarItem.allRecordings)

                Label("Uncategorized", systemImage: "questionmark.folder")
                    .tag(SidebarItem.filteredByStatus(.new))
            }
            
            // Locations section — shown when device is connected or connecting
            if shouldShowLocations {
                Section("Import locations") {
                    locationContent
                }
            }

        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }

    // MARK: - Locations Content

    private var shouldShowLocations: Bool {
        switch deviceService.connectionState {
        case .connecting, .connected, .connectionFailed:
            return true
        case .disconnected:
            return false
        }
    }

    @ViewBuilder
    private var locationContent: some View {
        let modelName = deviceService.connectionInfo?.model.displayName
                     ?? deviceService.detectedModel?.displayName
                     ?? "HiDock"

        switch deviceService.connectionState {
        case .connecting(_, _):
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(modelName)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .tag(SidebarItem.device)

        case .connected:
            Label {
                Text(modelName)
            } icon: {
                SidebarDeviceIcon(model: deviceService.connectionInfo?.model ?? deviceService.detectedModel)
            }
            .tag(SidebarItem.device)
            .contextMenu {
                Button("Import All") {
                    importService.importFromDevice()
                }
                .disabled(importService.isImporting)

                Divider()

                Button("Eject \(modelName)") {
                    Task { @MainActor in await deviceService.disconnect() }
                }
            }

        case .connectionFailed(_):
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(modelName)
                        .foregroundStyle(.secondary)
                } icon: {
                    SidebarDeviceIcon(model: deviceService.detectedModel, failed: true)
                }
            }
            .tag(SidebarItem.device)
            .contextMenu {
                Button("Retry Connection") {
                    Task { @MainActor in await deviceService.manualRetry() }
                }
            }
            .help("Device detected but communication failed. Right-click to retry.")

        case .disconnected:
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

// MARK: - Sidebar Device Icon

/// Shows device-specific icon in sidebar, with optional failed state styling.
private struct SidebarDeviceIcon: View {
    let model: DeviceModel?
    var failed: Bool = false

    var body: some View {
        let icon = Group {
            if let imageName = model?.imageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: model?.sfSymbolName ?? "externaldrive")
            }
        }
        .frame(width: 16, height: 16)

        if failed {
            icon.foregroundStyle(.red)
        } else {
            icon // Inherits accent color like other sidebar icons
        }
    }
}
