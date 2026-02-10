//
//  ImportButton.swift
//  HiDocu
//
//  Import/Stop button with state machine for device import operations.
//  Shared between DeviceDashboardView and RecordingSourceDetailView.
//

import SwiftUI

struct ImportButton: View {
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
        case .preparing: "Preparing..."
        case .importing: "Stop"
        case .stopping: "Stopping..."
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
