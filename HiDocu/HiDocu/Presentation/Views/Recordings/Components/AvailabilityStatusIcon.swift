//
//  AvailabilityStatusIcon.swift
//  HiDocu
//
//  Status icon showing recording availability (on device, synced, local, importing).
//

import SwiftUI

struct AvailabilityStatusIcon: View {
    let syncStatus: RecordingSyncStatus
    var isDeviceOnline: Bool = false
    var isImporting: Bool = false

    var body: some View {
        Group {
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                    .help("Importing...")
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .help(helpText)
            }
        }
        .font(.system(size: 13))
    }

    private var iconName: String {
        switch syncStatus {
        case .onDeviceOnly:
            return isDeviceOnline ? "externaldrive.fill" : "bolt.slash"
        case .synced:
            return "checkmark.circle.fill"
        case .localOnly:
            return "internaldrive"
        }
    }

    private var iconColor: Color {
        switch syncStatus {
        case .onDeviceOnly:
            return .secondary
        case .synced:
            return .green
        case .localOnly:
            return .secondary
        }
    }

    private var helpText: String {
        switch syncStatus {
        case .onDeviceOnly:
            return isDeviceOnline ? "On device — not yet downloaded" : "On device — device offline"
        case .synced:
            return "Downloaded to library"
        case .localOnly:
            return "In library — not on device"
        }
    }
}
