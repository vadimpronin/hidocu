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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 800, minHeight: 500)
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
            // Cmd+Backspace: delete selected document
            Button("") {
                if navigationVM.activeDocumentId != nil {
                    showDeleteConfirmation = true
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
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
            "Delete Document",
            isPresented: $showDeleteConfirmation
        ) {
            if let docId = navigationVM.activeDocumentId,
               let doc = documentListVM?.documents.first(where: { $0.id == docId }) {
                Button("Delete \"\(doc.title)\"", role: .destructive) {
                    documentDetailVM?.cancelPendingSave()
                    navigationVM.selectedDocumentIds = []
                    Task { try? await container.documentService.deleteDocument(id: docId) }
                }
            }
        } message: {
            Text("This will move the document to the Trash.")
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        if let folderTreeVM {
            SidebarViewV2(
                navigationVM: navigationVM,
                folderTreeVM: folderTreeVM,
                deviceManager: container.deviceManager,
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
                    isAllDocumentsView: navigationVM.selectedSidebarItem == .allDocuments
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
            } else {
                ProgressView()
            }

        case .trash:
            TrashView(trashService: container.trashService)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)

        case .device:
            Color.clear
                .navigationSplitViewColumnWidth(0)
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if case .device(let id) = navigationVM.selectedSidebarItem {
            if let controller = container.deviceManager.connectedDevices.first(where: { $0.id == id }) {
                DeviceDashboardView(
                    deviceController: controller,
                    importService: container.importServiceV2,
                    viewModel: deviceDashboardVMs[id] ?? makeDashboardVM(for: controller)
                )
            } else {
                Text("Device disconnected")
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

        let ddvm = DocumentDetailViewModel(documentService: container.documentService, llmService: container.llmService, settingsService: container.settingsService)
        documentDetailVM = ddvm

        navigationVM.restoreSelection()
    }

    private func handleDisappear() {
        folderTreeVM?.stopObserving()
        documentListVM?.stopObserving()
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
        case .device:
            columnVisibility = .all
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

        if case .device(let id) = navigationVM.selectedSidebarItem {
            if !connectedIDs.contains(id) {
                navigationVM.selectedSidebarItem = .allDocuments
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
