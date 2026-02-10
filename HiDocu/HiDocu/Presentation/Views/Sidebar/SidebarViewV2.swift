//
//  SidebarViewV2.swift
//  HiDocu
//
//  New sidebar with folders, system sections, and devices.
//

import SwiftUI

struct SidebarViewV2: View {
    @Bindable var navigationVM: NavigationViewModelV2
    var folderTreeVM: FolderTreeViewModel
    var deviceManager: DeviceManager
    var recordingSources: [RecordingSource]
    var connectedSourceIds: Set<Int64>
    var contextService: ContextService
    var folderService: FolderService
    var fileSystemService: FileSystemService

    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParentId: Int64?
    @State private var errorMessage: String?

    var body: some View {
        List(selection: $navigationVM.selectedSidebarItem) {

            Section("Library") {
                Label("All Documents", systemImage: "doc.on.doc")
                    .tag(SidebarItemV2.allDocuments)

                Label("Uncategorized", systemImage: "tray")
                    .tag(SidebarItemV2.uncategorized)

                Label("Trash", systemImage: "trash")
                    .tag(SidebarItemV2.trash)
            }

            Section("Folders") {
                ForEach(folderTreeVM.roots) { node in
                    FolderTreeRow(
                        node: node,
                        contextService: contextService,
                        folderService: folderService,
                        fileSystemService: fileSystemService,
                        onCreateSubfolder: { parentId in
                            newFolderParentId = parentId
                            newFolderName = ""
                            isCreatingFolder = true
                        },
                        onCreateRootFolder: {
                            newFolderParentId = nil
                            newFolderName = ""
                            isCreatingFolder = true
                        },
                        onRename: { id, name in
                            Task {
                                do { try await folderTreeVM.renameFolder(id: id, newName: name) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        },
                        onDelete: { id in
                            Task {
                                do { try await folderTreeVM.deleteFolder(id: id) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        },
                        onReorderChildren: { parentId, source, destination in
                            folderTreeVM.reorderChildFolders(parentId: parentId, from: source, to: destination)
                        }
                    )
                }
                .onMove { source, destination in
                    folderTreeVM.reorderRootFolders(from: source, to: destination)
                }
            }

            Section("Recordings") {
                Label("All Recordings", systemImage: "waveform")
                    .tag(SidebarItemV2.allRecordings)

                // Show "Imported" sources first
                ForEach(importSources) { source in
                    RecordingSourceSidebarRow(
                        source: source,
                        isOnline: false,
                        controller: nil
                    )
                    .tag(SidebarItemV2.recordingSource(id: source.id))
                }

                // Then device sources
                ForEach(deviceSources) { source in
                    RecordingSourceSidebarRow(
                        source: source,
                        isOnline: connectedSourceIds.contains(source.id),
                        controller: findController(for: source)
                    )
                    .tag(SidebarItemV2.recordingSource(id: source.id))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 270)
        .sheet(isPresented: $isCreatingFolder) {
            NewFolderSheet(
                name: $newFolderName,
                onConfirm: {
                    Task {
                        do { try await folderTreeVM.createFolder(name: newFolderName, parentId: newFolderParentId) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            )
        }
        .errorBanner($errorMessage)
    }

    private var importSources: [RecordingSource] {
        recordingSources.filter { $0.type == .upload }
    }

    private var deviceSources: [RecordingSource] {
        recordingSources.filter { $0.type != .upload }
    }

    private func findController(for source: RecordingSource) -> DeviceController? {
        deviceManager.connectedDevices.first { controller in
            controller.recordingSourceId == source.id
        }
    }
}

// MARK: - Recording Source Sidebar Row

private struct RecordingSourceSidebarRow: View {
    let source: RecordingSource
    let isOnline: Bool
    let controller: DeviceController?

    private var isImportSource: Bool { source.type == .upload }

    private var model: DeviceModel {
        DeviceModel(rawValue: source.deviceModel ?? "") ?? .unknown
    }

    var body: some View {
        if isImportSource {
            // Upload/Import source
            Label {
                Text(source.name)
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
        } else if isOnline, let controller = controller {
            // Online: show normal state with optional battery indicator
            switch controller.connectionState {
            case .connecting:
                Label {
                    Text(source.name)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }

            case .connected:
                Label {
                    HStack {
                        Text(source.name)
                        Spacer()
                        if let battery = controller.batteryInfo {
                            BatteryIndicatorView(battery: battery)
                        }
                    }
                } icon: {
                    deviceIcon
                }

            case .connectionFailed, .disconnected:
                Label {
                    Text(source.name)
                        .foregroundStyle(.secondary)
                } icon: {
                    deviceIcon
                        .foregroundStyle(.red)
                }
            }
        } else {
            // Offline: show muted state
            Label {
                Text(source.name)
                    .foregroundStyle(.secondary)
            } icon: {
                deviceIcon
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var deviceIcon: some View {
        if let imageName = model.imageName {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: model.sfSymbolName)
        }
    }
}

// MARK: - Folder Tree Row

private struct FolderTreeRow: View {
    let node: FolderNode
    let contextService: ContextService
    let folderService: FolderService
    let fileSystemService: FileSystemService
    let onCreateSubfolder: (Int64) -> Void
    let onCreateRootFolder: () -> Void
    let onRename: (Int64, String) -> Void
    let onDelete: (Int64) -> Void
    let onReorderChildren: (Int64, IndexSet, Int) -> Void

    @State private var isExpanded = true
    @State private var isRenaming = false
    @State private var editedName = ""
    @State private var showSettings = false
    @State private var showDeleteConfirmation = false
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        rowContent
            // Force SwiftUI to recreate the view when leaf/branch state changes,
            // so it properly switches between plain label and DisclosureGroup.
            .id("\(node.id)_\(node.children.isEmpty)")
            .tag(SidebarItemV2.folder(id: node.id))
            .confirmationDialog(
                "Delete Folder",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Delete \"\(node.folder.name)\"", role: .destructive) {
                    onDelete(node.id)
                }
            } message: {
                Text("This will delete the folder \"\(node.folder.name)\" and all its contents. This action cannot be undone.")
            }
            .sheet(isPresented: $showSettings) {
                FolderSettingsSheet(folderId: node.id, folderService: folderService)
            }
    }

    @ViewBuilder
    private var rowContent: some View {
        if node.children.isEmpty {
            labelSection
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    FolderTreeRow(
                        node: child,
                        contextService: contextService,
                        folderService: folderService,
                        fileSystemService: fileSystemService,
                        onCreateSubfolder: onCreateSubfolder,
                        onCreateRootFolder: onCreateRootFolder,
                        onRename: onRename,
                        onDelete: onDelete,
                        onReorderChildren: onReorderChildren
                    )
                }
                .onMove { source, destination in
                    onReorderChildren(node.id, source, destination)
                }
            } label: {
                labelSection
            }
        }
    }

    @ViewBuilder
    private var labelSection: some View {
        if isRenaming {
            Label {
                TextField("Name", text: $editedName, onCommit: {
                    onRename(node.id, editedName)
                    isRenaming = false
                })
                .textFieldStyle(.plain)
                .focused($isRenameFocused)
                .onExitCommand { isRenaming = false }
                .onAppear { isRenameFocused = true }
            } icon: {
                Image(systemName: "folder")
            }
        } else {
            folderLabel
                .contextMenu {
                    Button("New Subfolder") {
                        onCreateSubfolder(node.id)
                    }
                    Button("New Folder") {
                        onCreateRootFolder()
                    }
                    Divider()
                    Button("Rename") {
                        editedName = node.folder.name
                        isRenaming = true
                    }
                    Button("Copy Context") {
                        Task { try? await contextService.copyContextToClipboard(folderId: node.id) }
                    }
                    Button("Reveal in Finder") {
                        revealDataDirectoryInFinder()
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    Divider()
                    Button("Settings...") {
                        showSettings = true
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
        }
    }

    private var folderLabel: some View {
        Label {
            HStack {
                Text(node.folder.name)
                Spacer()
                if node.byteCount > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(node.byteCount), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "folder")
        }
    }

    private func revealDataDirectoryInFinder() {
        let folderURL: URL
        if let diskPath = node.folder.diskPath, !diskPath.isEmpty {
            folderURL = fileSystemService.dataDirectory.appendingPathComponent(diskPath, isDirectory: true)
        } else {
            folderURL = fileSystemService.dataDirectory
        }
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }
}

// MARK: - New Folder Sheet

private struct NewFolderSheet: View {
    @Binding var name: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("New Folder")
                .font(.headline)
            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .focused($isNameFieldFocused)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .onAppear { isNameFieldFocused = true }
    }
}
