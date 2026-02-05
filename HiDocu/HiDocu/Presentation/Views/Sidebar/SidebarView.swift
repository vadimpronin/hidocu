//
//  SidebarView.swift
//  HiDocu
//
//  Sidebar with library filters and device navigation item.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var navigationVM: NavigationViewModel
    var deviceManager: DeviceManager
    var importService: RecordingImportService

    var body: some View {
        List(selection: $navigationVM.selectedSidebarItem) {

            Section("Library") {
                Label("All Recordings", systemImage: "tray.fill")
                    .tag(SidebarItem.allRecordings)

                Label("Uncategorized", systemImage: "questionmark.folder")
                    .tag(SidebarItem.filteredByStatus(.new))
            }
            
            // Locations section — shown when ANY device is connected
            if !deviceManager.connectedDevices.isEmpty {
                Section("Devices") {
                    ForEach(deviceManager.connectedDevices) { controller in
                        DeviceSidebarRow(
                            controller: controller,
                            importService: importService
                        )
                        .tag(SidebarItem.device(id: controller.id))
                    }
                }
            }

        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}

// MARK: - Device Row

struct DeviceSidebarRow: View {
    let controller: DeviceController
    let importService: RecordingImportService
    
    var body: some View {
        let modelName = controller.displayName
        
        switch controller.connectionState {
        case .connecting:
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(modelName)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            
        case .connected:
            Label {
                HStack {
                    Text(modelName)
                    Spacer()
                    if let battery = controller.batteryInfo {
                        BatteryIndicatorView(battery: battery)
                    }
                }
            } icon: {
                SidebarDeviceIcon(model: controller.connectionInfo?.model, failed: false)
            }
            .contextMenu {
                Button("Import All") {
                    importService.importFromDevice(controller: controller)
                }
                .disabled(importService.session(for: controller.id)?.isImporting ?? false)

                Divider()

                Button("Disconnect") {
                    Task { @MainActor in await controller.disconnect() }
                }
            }
            
        case .connectionFailed, .disconnected:
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(modelName)
                        .foregroundStyle(.secondary)
                } icon: {
                    SidebarDeviceIcon(model: nil, failed: true)
                }
            }
            .contextMenu {
                 Button("Retry") {
                     Task { @MainActor in await controller.connect() }
                 }
            }
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
