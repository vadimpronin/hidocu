//
//  NavigationViewModelV2.swift
//  HiDocu
//
//  Navigation state management for the context management UI.
//

import Foundation
import SwiftUI

enum SidebarItemV2: Hashable {
    // Library
    case allDocuments
    case uncategorized
    case trash
    // Recording Sources
    case allRecordings
    case recordingSource(id: Int64)
    // Folders
    case folder(id: Int64)
}

@Observable
@MainActor
final class NavigationViewModelV2 {
    var selectedSidebarItem: SidebarItemV2? = .allDocuments
    var selectedDocumentIds: Set<Int64> = []

    /// The document shown in detail pane (only when exactly one is selected)
    var activeDocumentId: Int64? {
        selectedDocumentIds.count == 1 ? selectedDocumentIds.first : nil
    }

    /// Persist selection across relaunches
    @ObservationIgnored
    @AppStorage("selectedSidebarKey") private var savedSidebarKey: String = "allDocuments"

    func restoreSelection() {
        if savedSidebarKey == "uncategorized" {
            selectedSidebarItem = .uncategorized
        } else if savedSidebarKey == "trash" {
            selectedSidebarItem = .trash
        } else if savedSidebarKey == "allRecordings" {
            selectedSidebarItem = .allRecordings
        } else if savedSidebarKey.hasPrefix("folder:"),
                  let id = Int64(savedSidebarKey.dropFirst("folder:".count)) {
            selectedSidebarItem = .folder(id: id)
        } else if savedSidebarKey.hasPrefix("recordingSource:"),
                  let id = Int64(savedSidebarKey.dropFirst("recordingSource:".count)) {
            selectedSidebarItem = .recordingSource(id: id)
        } else {
            selectedSidebarItem = .allDocuments
        }
    }

    func saveSelection() {
        switch selectedSidebarItem {
        case .folder(let id):              savedSidebarKey = "folder:\(id)"
        case .uncategorized:               savedSidebarKey = "uncategorized"
        case .allDocuments:                savedSidebarKey = "allDocuments"
        case .trash:                       savedSidebarKey = "trash"
        case .allRecordings:               savedSidebarKey = "allRecordings"
        case .recordingSource(let id):     savedSidebarKey = "recordingSource:\(id)"
        case .none:                        savedSidebarKey = "allDocuments"
        }
    }
}
