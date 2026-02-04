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
            if let recordingsVM, let container {
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
            recordingsVM?.setFilter(newValue?.statusFilter)
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
        .onChange(of: container?.syncService.errorMessage) { _, newError in
            if let newError {
                syncError = newError
            }
        }
    }
}

#Preview {
    ContentView()
}
