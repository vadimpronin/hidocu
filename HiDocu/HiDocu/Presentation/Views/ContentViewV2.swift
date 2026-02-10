//
//  ContentViewV2.swift
//  HiDocu
//
//  Root view for the context management UI.
//

import SwiftUI

struct ContentViewV2: View {
    let container: AppDependencyContainer
    @Bindable var navigationVM: NavigationViewModelV2
    @State private var folderTreeVM: FolderTreeViewModel?
    @State private var documentListVM: DocumentListViewModel?
    @State private var documentDetailVM: DocumentDetailViewModel?
    @State private var deviceDashboardVMs: [UInt64: DeviceDashboardViewModel] = [:]
    @State private var recordingSourceVMs: [Int64: RecordingSourceViewModel] = [:]
    @State private var allRecordingsVM: AllRecordingsViewModel?
    @State private var recordingSources: [RecordingSource] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var recordingSourcesTask: Task<Void, Never>?
    @State private var documentIdsToDelete: Set<Int64> = []
    @State private var pendingDocumentNavigation: Int64?
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ToolbarQuotaIndicatorView(quotaService: container.quotaService)
                ToolbarJobMonitorView(queueState: container.llmQueueState)
            }
        }
        .onAppear { handleAppear() }
        .onDisappear { handleDisappear() }
        .onChange(of: navigationVM.selectedSidebarItem) { _, newValue in
            handleSidebarChange(newValue)
        }
        .onChange(of: container.deviceManager.connectedDevices) { _, newDevices in
            handleDeviceListChange(newDevices)
        }
        .onChange(of: navigationVM.activeDocumentId) { _, newId in
            handleDocumentSelection(newId)
        }
        .background {
            // Cmd+Backspace: delete selected documents
            Button("") {
                if !navigationVM.selectedDocumentIds.isEmpty {
                    documentIdsToDelete = navigationVM.selectedDocumentIds
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .hidden()
            .accessibilityHidden(true)

            // Delete key: same action
            Button("") {
                if !navigationVM.selectedDocumentIds.isEmpty {
                    documentIdsToDelete = navigationVM.selectedDocumentIds
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .hidden()
            .accessibilityHidden(true)

            // Cmd+Shift+C: copy context from current folder
            Button("") {
                if let folderId = currentFolderId {
                    Task { try? await container.contextService.copyContextToClipboard(folderId: folderId) }
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .hidden()
            .accessibilityHidden(true)
        }
        .confirmationDialog(
            documentIdsToDelete.count == 1 ? "Delete Document" : "Delete \(documentIdsToDelete.count) Documents",
            isPresented: Binding(
                get: { !documentIdsToDelete.isEmpty },
                set: { if !$0 { documentIdsToDelete = [] } }
            )
        ) {
            let ids = documentIdsToDelete
            if ids.count == 1,
               let docId = ids.first,
               let doc = documentListVM?.documents.first(where: { $0.id == docId }) {
                Button("Delete \"\(doc.title)\"", role: .destructive) {
                    documentDetailVM?.cancelPendingSave()
                    navigationVM.selectedDocumentIds = []
                    documentIdsToDelete = []
                    Task {
                        do {
                            try await container.documentService.deleteDocument(id: docId)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } else {
                Button("Delete \(ids.count) Documents", role: .destructive) {
                    documentDetailVM?.cancelPendingSave()
                    navigationVM.selectedDocumentIds = []
                    documentIdsToDelete = []
                    Task {
                        let failureCount = await container.documentService.deleteDocuments(ids: ids)
                        if failureCount > 0 {
                            errorMessage = "Failed to delete \(failureCount) of \(ids.count) documents."
                        }
                    }
                }
            }
        } message: {
            if documentIdsToDelete.count == 1,
               let docId = documentIdsToDelete.first,
               let doc = documentListVM?.documents.first(where: { $0.id == docId }) {
                Text("This will move \"\(doc.title)\" to the Trash.")
            } else {
                Text("This will move \(documentIdsToDelete.count) documents to the Trash.")
            }
        }
        .errorBanner($errorMessage)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        if let folderTreeVM {
            SidebarViewV2(
                navigationVM: navigationVM,
                folderTreeVM: folderTreeVM,
                deviceManager: container.deviceManager,
                recordingSources: recordingSources,
                connectedSourceIds: connectedSourceIds,
                contextService: container.contextService,
                folderService: container.folderService,
                fileSystemService: container.fileSystemService
            )
        } else {
            ProgressView()
        }
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        switch navigationVM.selectedSidebarItem {
        case .folder, .allDocuments, .uncategorized, .none:
            if let documentListVM {
                DocumentListView(
                    viewModel: documentListVM,
                    selectedDocumentIds: $navigationVM.selectedDocumentIds,
                    documentService: container.documentService,
                    fileSystemService: container.fileSystemService,
                    folderId: currentFolderId,
                    folders: folderTreeVM?.allFolders ?? [],
                    folderNodes: folderTreeVM?.roots ?? [],
                    folderName: currentFolderName,
                    isAllDocumentsView: navigationVM.selectedSidebarItem == .allDocuments,
                    onBeforeDelete: {
                        documentDetailVM?.cancelPendingSave()
                    }
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
            } else {
                ProgressView()
            }

        case .trash:
            TrashView(trashService: container.trashService)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)

        case .allRecordings, .recordingSource:
            // Recordings: hide content column, show directly in detail
            Color.clear
                .navigationSplitViewColumnWidth(0)
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if case .allRecordings = navigationVM.selectedSidebarItem,
           let allRecVM = allRecordingsVM {
            AllRecordingsView(
                viewModel: allRecVM,
                connectedSourceIds: connectedSourceIds,
                documentService: container.documentService,
                fileSystemService: container.fileSystemService,
                importService: container.importServiceV2,
                onNavigateToDocument: { docId in
                    navigateToDocument(docId)
                }
            )
        } else if case .recordingSource(let sourceId) = navigationVM.selectedSidebarItem {
            if let source = recordingSources.first(where: { $0.id == sourceId }),
               let viewModel = recordingSourceVMs[sourceId] {
                let controller = connectedDeviceController(for: source)
                RecordingSourceDetailView(
                    source: source,
                    viewModel: viewModel,
                    importService: container.importServiceV2,
                    deviceController: controller,
                    recordingSourceService: container.recordingSourceService,
                    documentService: container.documentService,
                    fileSystemService: container.fileSystemService,
                    llmQueueState: container.llmQueueState,
                    onNavigateToDocument: { docId in
                        navigateToDocument(docId)
                    }
                )
            } else {
                Text("Source not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let documentDetailVM, navigationVM.activeDocumentId != nil {
            DocumentDetailView(viewModel: documentDetailVM, container: container)
        } else if case .folder(let id) = navigationVM.selectedSidebarItem {
            FolderSummaryView(
                folderId: id,
                contextService: container.contextService,
                folderService: container.folderService,
                documentRepository: container.documentRepository
            )
        } else {
            Text("Select a folder or document")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private var currentFolderId: Int64? {
        if case .folder(let id) = navigationVM.selectedSidebarItem {
            return id
        }
        return nil
    }

    private func makeDashboardVM(for controller: DeviceController) -> DeviceDashboardViewModel {
        let vm = DeviceDashboardViewModel(
            deviceController: controller,
            sourceRepository: container.sourceRepository
        )
        deviceDashboardVMs[controller.id] = vm
        return vm
    }

    private func ensureRecordingSourceVM(for sourceId: Int64) {
        guard recordingSourceVMs[sourceId] == nil else { return }
        recordingSourceVMs[sourceId] = RecordingSourceViewModel(
            recordingRepository: container.recordingRepositoryV2,
            sourceRepository: container.sourceRepository,
            recordingSourceService: container.recordingSourceService,
            llmQueueState: container.llmQueueState
        )
    }

    private var connectedSourceIds: Set<Int64> {
        Set(container.deviceManager.connectedDevices.compactMap { controller in
            controller.recordingSourceId
        })
    }

    private func connectedDeviceController(for source: RecordingSource) -> DeviceController? {
        container.deviceManager.connectedDevices.first { controller in
            controller.recordingSourceId == source.id
        }
    }

    private func navigateToDocument(_ docId: Int64) {
        if navigationVM.selectedSidebarItem == .allDocuments {
            navigationVM.selectedDocumentIds = [docId]
        } else {
            pendingDocumentNavigation = docId
            navigationVM.selectedSidebarItem = .allDocuments
        }
    }

    private var currentFolderName: String? {
        if case .uncategorized = navigationVM.selectedSidebarItem {
            return "Uncategorized"
        }
        guard let folderId = currentFolderId else { return nil }
        return folderTreeVM?.allFolders.first(where: { $0.id == folderId })?.name
    }

    private func handleAppear() {
        let ftvm = FolderTreeViewModel(
            folderRepository: container.folderRepository,
            folderService: container.folderService,
            contextService: container.contextService
        )
        ftvm.startObserving()
        folderTreeVM = ftvm

        let dlvm = DocumentListViewModel(documentRepository: container.documentRepository, documentService: container.documentService)
        dlvm.observeAllDocuments()
        documentListVM = dlvm

        let ddvm = DocumentDetailViewModel(documentService: container.documentService, llmService: container.llmService, llmQueueService: container.llmQueueService, settingsService: container.settingsService)
        documentDetailVM = ddvm

        allRecordingsVM = AllRecordingsViewModel(
            recordingRepository: container.recordingRepositoryV2,
            recordingSourceRepository: container.recordingSourceRepository,
            sourceRepository: container.sourceRepository,
            recordingSourceService: container.recordingSourceService,
            llmQueueState: container.llmQueueState
        )

        // Observe recording sources
        recordingSourcesTask = Task {
            await observeRecordingSources()
        }

        navigationVM.restoreSelection()

        // Pre-create VM for restored recording source selection
        if case .recordingSource(let id) = navigationVM.selectedSidebarItem {
            ensureRecordingSourceVM(for: id)
        }
    }

    private func observeRecordingSources() async {
        do {
            for try await sources in container.recordingSourceRepository.observeAll() {
                recordingSources = sources
                let validIds = Set(sources.map(\.id))
                recordingSourceVMs = recordingSourceVMs.filter { validIds.contains($0.key) }
            }
        } catch is CancellationError {
            // Normal cleanup on view disappear
        } catch {
            AppLogger.recordings.error("Failed to observe recording sources: \(error.localizedDescription)")
        }
    }

    private func handleDisappear() {
        folderTreeVM?.stopObserving()
        documentListVM?.stopObserving()
        recordingSourcesTask?.cancel()
        recordingSourcesTask = nil
        navigationVM.saveSelection()
    }

    private func handleSidebarChange(_ newValue: SidebarItemV2?) {
        navigationVM.selectedDocumentIds = []

        switch newValue {
        case .folder(let id):
            documentListVM?.observeDocuments(folderId: id)
            columnVisibility = .all
        case .uncategorized:
            documentListVM?.observeDocuments(folderId: nil)
            columnVisibility = .all
        case .allDocuments:
            documentListVM?.observeAllDocuments()
            columnVisibility = .all
            if let docId = pendingDocumentNavigation {
                pendingDocumentNavigation = nil
                navigationVM.selectedDocumentIds = [docId]
            }
        case .allRecordings:
            columnVisibility = .detailOnly
        case .recordingSource(let id):
            columnVisibility = .detailOnly
            ensureRecordingSourceVM(for: id)
        case .trash, .none:
            columnVisibility = .all
        }
    }

    private func handleDocumentSelection(_ newId: Int64?) {
        guard let ddvm = documentDetailVM else { return }
        Task {
            await ddvm.saveIfNeeded()
            if let id = newId,
               let doc = documentListVM?.documents.first(where: { $0.id == id }) {
                ddvm.loadDocument(doc)
            } else {
                ddvm.document = nil
            }
        }
    }

    private func handleDeviceListChange(_ newDevices: [DeviceController]) {
        let connectedIDs = Set(newDevices.map(\.id))
        deviceDashboardVMs = deviceDashboardVMs.filter { connectedIDs.contains($0.key) }

        for controller in newDevices {
            if deviceDashboardVMs[controller.id] == nil {
                let vm = DeviceDashboardViewModel(
                    deviceController: controller,
                    sourceRepository: container.sourceRepository
                )
                deviceDashboardVMs[controller.id] = vm
                if controller.isConnected {
                    Task { await vm.loadFiles() }
                }
            }
        }
    }
}

// MARK: - Folder Summary

struct FolderSummaryView: View {
    let folderId: Int64
    let contextService: ContextService
    let folderService: FolderService
    let documentRepository: any DocumentRepository

    @State private var folderName: String = ""
    @State private var documentCount: Int = 0
    @State private var byteCount: Int = 0
    @State private var isCopying = false
    @State private var copySuccess = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text(folderName)
                .font(.title2.weight(.semibold))

            HStack(spacing: 16) {
                Label("\(documentCount) documents", systemImage: "doc.text")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file), systemImage: "internaldrive")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 200)

            Button {
                Task {
                    isCopying = true
                    defer { isCopying = false }
                    do {
                        try await contextService.copyContextToClipboard(folderId: folderId)
                        copySuccess = true
                        try? await Task.sleep(for: .seconds(2))
                        copySuccess = false
                    } catch {
                        AppLogger.general.error("Failed to copy context: \(error.localizedDescription)")
                    }
                }
            } label: {
                HStack {
                    if isCopying {
                        ProgressView()
                            .controlSize(.small)
                    } else if copySuccess {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "doc.on.doc")
                    }
                    Text(copySuccess ? "Copied!" : "Copy Context")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCopying || byteCount == 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: folderId) {
            if let folder = try? await folderService.fetchFolder(id: folderId) {
                folderName = folder.name
            }
            byteCount = (try? await contextService.calculateByteCount(folderId: folderId)) ?? 0
            let docs = (try? await documentRepository.fetchAllRecursive(folderIds: [folderId])) ?? []
            documentCount = docs.count
        }
    }
}
