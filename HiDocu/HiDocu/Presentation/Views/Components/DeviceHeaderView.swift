//
//  DeviceHeaderView.swift
//  HiDocu
//
//  Unified device/source header component.
//  Supports online mode (with device info, storage bar, import button)
//  and offline mode (with "Not connected" + last seen).
//

import SwiftUI

struct DeviceHeaderView: View {
    let title: String
    let model: DeviceModel
    var connectionInfo: DeviceConnectionInfo?
    var batteryInfo: DeviceBatteryInfo?
    var storageInfo: DeviceStorageInfo?
    var recordingsBytes: Int64 = 0
    var importService: RecordingImportServiceV2?
    var controller: DeviceController?
    var session: ImportSession?
    var lastSeenAt: Date?
    var isUploadSource: Bool = false
    var onDisconnect: (() async -> Void)?

    private var isOnline: Bool { connectionInfo != nil }
    private var supportsBattery: Bool { connectionInfo?.supportsBattery ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DeviceIconView(model: model)

            VStack(alignment: .leading, spacing: 8) {
                // Title + optional eject button
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if isOnline, let onDisconnect {
                        Button {
                            Task { await onDisconnect() }
                        } label: {
                            Image(systemName: "eject.fill")
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderless)
                        .help("Safely disconnect device")
                    }
                }

                if isOnline {
                    onlineMetadata
                } else {
                    offlineMetadata
                }
            }

            Spacer()
        }
    }

    // MARK: - Online Metadata

    @ViewBuilder
    private var onlineMetadata: some View {
        // Metadata grid
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            if let info = connectionInfo {
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

            if let battery = batteryInfo, supportsBattery {
                GridRow {
                    Text("Battery:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BatteryIndicatorView(battery: battery)
                }
            }
        }

        // Storage bar with inline Import button
        if let storage = storageInfo {
            HStack(alignment: .top, spacing: 12) {
                FinderStorageBar(
                    storage: storage,
                    recordingsBytes: recordingsBytes
                )

                if let importService, let controller {
                    ImportButton(
                        importService: importService,
                        controller: controller,
                        session: session
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Offline Metadata

    @ViewBuilder
    private var offlineMetadata: some View {
        if !isUploadSource {
            Text("Not connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let lastSeen = lastSeenAt {
                Text("Last seen: \(lastSeen.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
