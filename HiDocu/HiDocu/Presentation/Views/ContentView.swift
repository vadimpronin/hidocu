//
//  ContentView.swift
//  HiDocu
//
//  Main content view - placeholder for the library interface.
//

import SwiftUI

/// Main content view for the HiDocu application.
/// Will be replaced with the full library interface in future epics.
struct ContentView: View {
    @Environment(\.container) private var container
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("Library") {
                    Label("All Recordings", systemImage: "waveform")
                    Label("New", systemImage: "circle.fill")
                    Label("Downloaded", systemImage: "arrow.down.circle.fill")
                    Label("Transcribed", systemImage: "text.bubble.fill")
                }
                
                Section("Device") {
                    Label("HiDock", systemImage: "cable.connector")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            // Main content area
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                
                Text("HiDocu")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Local-first audio recorder management")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let container = container {
                    DeviceStatusView(deviceService: container.deviceService)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Shows the current device connection status
struct DeviceStatusView: View {
    let deviceService: DeviceConnectionService
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            if !deviceService.isConnected {
                Button("Connect Device") {
                    Task {
                        do {
                            _ = try await deviceService.connect()
                        } catch {
                            // Error is shown via connectionState
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Disconnect") {
                    Task { @MainActor in
                        deviceService.disconnect()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var statusColor: Color {
        switch deviceService.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch deviceService.connectionState {
        case .connected:
            if let info = deviceService.connectionInfo {
                return "Connected to \(info.model)"
            }
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "No device connected"
        case .error(let message):
            return message
        }
    }
}

#Preview {
    ContentView()
}
