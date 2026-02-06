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
            if let container {
                MainSplitView(container: container)
            } else {
                ProgressView()
            }
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Main Split View

/// The primary app interface with sidebar and detail navigation.
struct MainSplitView: View {
    let container: AppDependencyContainer

    @State private var navigationVM = NavigationViewModel()
    @State private var recordingsVM: RecordingsListViewModel?
    
    // Dashboard VMs keyed by device ID — cached until device disconnects
    @State private var deviceDashboardVMs: [UInt64: DeviceDashboardViewModel] = [:]
    @State private var importError: String?

    var body: some View {
        splitView
        .errorBanner($importError)
        .onAppear {
            handleAppear()
        }
        .onChange(of: navigationVM.selectedSidebarItem) { _, newValue in
            handleSidebarSelectionChange(newValue)
        }
        .onChange(of: navigationVM.selectedRecordingId) { _, newId in
            handleRecordingSelectionChange(newId)
        }
        .onChange(of: container.deviceManager.connectedDevices) { _, newDevices in
            handleDeviceListChange(newDevices)
        }
        .onChange(of: fullyConnectedDeviceIDs) { _, newIDs in
            ensureViewModelsForConnectedDevices(newIDs)
        }
        .onChange(of: container.importService.errorMessage) { _, newError in
             if let newError { importError = newError }
        }
    }
    
    // MARK: - Split View
    
    private var splitView: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailView
        }
    }

    // MARK: - Sidebar Content
    
    @ViewBuilder
    private var sidebarContent: some View {
        SidebarView(
            navigationVM: navigationVM,
            deviceManager: container.deviceManager,
            importService: container.importService
        )
    }

    // MARK: - Detail View Wrapper
    
    @ViewBuilder
    private var detailView: some View {
        detailContent()
    }

    // MARK: - Detail Content Logic

    @ViewBuilder
    private func detailContent() -> some View {
        // Handle Sidebar Item Selection
        if let selection = navigationVM.selectedSidebarItem {
            switch selection {
            case .device(let id):
                if let controller = container.deviceManager.connectedDevices.first(where: { $0.id == id }),
                   let viewModel = deviceDashboardVMs[id] {

                    DeviceDashboardView(
                        deviceController: controller,
                        importService: container.importService,
                        viewModel: viewModel
                    )
                    .id(controller.id)
                } else {
                    DeviceDisconnectedView()
                }

            case .allRecordings, .filteredByStatus:
                if let recordingsVM {
                    NavigationStack {
                        RecordingsListView(
                            viewModel: recordingsVM,
                            selectedRecordingId: $navigationVM.selectedRecordingId,
                            importService: container.importService
                        )
                        .navigationTitle(selection.title)
                        .navigationDestination(item: $navigationVM.selectedRecording) { recording in
                            RecordingDetailView(recording: recording, container: container)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
        } else {
            // No selection
            Text("Select an item")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleAppear() {
        if recordingsVM == nil {
            let vm = RecordingsListViewModel(
                repository: container.recordingRepository
            )
            vm.setFilter(navigationVM.selectedSidebarItem?.statusFilter)
            recordingsVM = vm
        }
    }
    
    private func handleSidebarSelectionChange(_ newValue: SidebarItem?) {
        if let newValue, newValue.isLibraryItem {
            recordingsVM?.setFilter(newValue.statusFilter)
        }
    }
    
    private func handleRecordingSelectionChange(_ newId: Int64?) {
        guard let newId else {
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
    
    private var fullyConnectedDeviceIDs: Set<UInt64> {
        Set(container.deviceManager.connectedDevices.filter(\.isConnected).map(\.id))
    }

    private func ensureViewModelsForConnectedDevices(_ connectedIDs: Set<UInt64>) {
        for id in connectedIDs {
            if deviceDashboardVMs[id] == nil,
               let controller = container.deviceManager.connectedDevices.first(where: { $0.id == id }) {
                let vm = DeviceDashboardViewModel(
                    deviceController: controller,
                    repository: container.recordingRepository
                )
                deviceDashboardVMs[id] = vm
                Task { await vm.loadFiles() }
            }
        }
    }

    private func handleDeviceListChange(_ newDevices: [DeviceController]) {
        // Clean up VMs for disconnected devices
        let connectedIDs = Set(newDevices.map(\.id))
        deviceDashboardVMs = deviceDashboardVMs.filter { connectedIDs.contains($0.key) }

        // Navigate away if selected device was disconnected
        if case .device(let id) = navigationVM.selectedSidebarItem {
            if !newDevices.contains(where: { $0.id == id }) {
                navigationVM.selectedSidebarItem = .allRecordings
            }
        }
    }
}

#Preview {
    ContentView()
}
