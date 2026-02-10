//
//  RecordingContextMenu.swift
//  HiDocu
//
//  Shared context menu for recording rows across different views.
//

import SwiftUI

struct RecordingContextMenu: View {
    let hasLocalFile: Bool
    let isDeviceOnly: Bool
    let isDeviceOnline: Bool
    let isImporting: Bool
    var onOpen: (() -> Void)?
    var onShowInFinder: (() -> Void)?
    var onImportAndCreateDocument: (() -> Void)?
    var onImportOnly: (() -> Void)?
    var onCreateDocument: (() -> Void)?
    var onDeleteImported: (() -> Void)?

    var body: some View {
        if hasLocalFile {
            Button("Open") {
                onOpen?()
            }
            Button("Show in Finder") {
                onShowInFinder?()
            }
        }

        if isDeviceOnly && isDeviceOnline {
            Button("Import and Create Document") {
                onImportAndCreateDocument?()
            }
            .disabled(isImporting)

            Button("Import Only") {
                onImportOnly?()
            }
            .disabled(isImporting)
        }

        if hasLocalFile {
            Button("Create Document") {
                onCreateDocument?()
            }
        }

        Divider()

        Button("Delete from Device", role: .destructive) {
            // Future implementation
        }
        .disabled(true)

        if hasLocalFile {
            Button("Delete Imported", role: .destructive) {
                onDeleteImported?()
            }
        }
    }
}
