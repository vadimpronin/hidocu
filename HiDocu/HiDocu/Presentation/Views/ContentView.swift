//
//  ContentView.swift
//  HiDocu
//
//  Root view that shows onboarding on first launch, then main content.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.container) private var container
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainSplitView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Main Split View

/// The primary app interface with sidebar and detail navigation.
struct MainSplitView: View {
    @Environment(\.container) private var container

    @State private var navigationVM = NavigationViewModel()
    @State private var recordingsVM: RecordingsListViewModel?
    @State private var deviceDashboardVM: DeviceDashboardViewModel?
    @State private var syncError: String?

    var body: some View {
        NavigationSplitView {
            if let container {
                SidebarView(
                    navigationVM: navigationVM,
                    deviceService: container.deviceService,
                    syncService: container.syncService
                )
            }
        } detail: {
            if let container {
                detailContent(container: container)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .errorBanner($syncError)
        .onAppear {
            if recordingsVM == nil, let container {
                let vm = RecordingsListViewModel(
                    repository: container.recordingRepository
                )
                vm.setFilter(navigationVM.selectedSidebarItem?.statusFilter)
                recordingsVM = vm
            }
        }
        .onChange(of: navigationVM.selectedSidebarItem) { _, newValue in
            guard let container else { return }

            if let newValue, newValue.isLibraryItem {
                recordingsVM?.setFilter(newValue.statusFilter)
            }

            // Create device dashboard VM on demand
            if newValue == .device, deviceDashboardVM == nil {
                deviceDashboardVM = DeviceDashboardViewModel(
                    deviceService: container.deviceService,
                    repository: container.recordingRepository
                )
            }
        }
        .onChange(of: navigationVM.selectedRecordingId) { _, newId in
            guard let newId, let container else {
                navigationVM.selectedRecording = nil
                return
            }

            Task {
                do {
                    let recording = try await container.recordingRepository.fetchById(newId)
                    await MainActor.run {
                        navigationVM.selectedRecording = recording
                    }
                } catch {
                    AppLogger.ui.error("Failed to fetch recording: \(error.localizedDescription)")
                }
            }
        }
        .onChange(of: container?.deviceService.isConnected) { wasConnected, isConnected in
            // Auto-navigate away from device dashboard on disconnect
            if wasConnected == true && isConnected != true {
                if navigationVM.selectedSidebarItem == .device {
                    navigationVM.selectedSidebarItem = .allRecordings
                }
                deviceDashboardVM = nil
            }
        }
        .onChange(of: container?.syncService.errorMessage) { _, newError in
            if let newError {
                syncError = newError
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(container: AppDependencyContainer) -> some View {
        switch navigationVM.selectedSidebarItem {
        case .device:
            if container.deviceService.isConnected, let deviceDashboardVM {
                DeviceDashboardView(
                    deviceService: container.deviceService,
                    syncService: container.syncService,
                    viewModel: deviceDashboardVM
                )
            } else {
                DeviceDisconnectedView()
            }

        case .allRecordings, .filteredByStatus:
            if let recordingsVM {
                NavigationStack {
                    RecordingsListView(
                        viewModel: recordingsVM,
                        selectedRecordingId: $navigationVM.selectedRecordingId,
                        syncService: container.syncService
                    )
                    .navigationTitle(navigationVM.selectedSidebarItem?.title ?? "Recordings")
                    .navigationDestination(item: $navigationVM.selectedRecording) { recording in
                        RecordingDetailView(recording: recording, container: container)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case nil:
            Text("Select an item")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

#Preview {
    ContentView()
}
