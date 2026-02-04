//
//  ContentView.swift
//  HiDocu
//
//  Main content view wiring sidebar navigation and recordings list.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.container) private var container

    @State private var navigationVM = NavigationViewModel()
    @State private var recordingsVM: RecordingsListViewModel?

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
                        selectedRecordingId: $navigationVM.selectedRecordingId
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

            // Fetch the recording and set it for navigation
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
    }
}

#Preview {
    ContentView()
}
