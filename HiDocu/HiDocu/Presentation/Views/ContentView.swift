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
            if let recordingsVM {
                RecordingsListView(
                    viewModel: recordingsVM,
                    selectedRecordingId: $navigationVM.selectedRecordingId
                )
                .navigationTitle(navigationVM.selectedSidebarItem?.title ?? "Recordings")
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
    }
}

#Preview {
    ContentView()
}
