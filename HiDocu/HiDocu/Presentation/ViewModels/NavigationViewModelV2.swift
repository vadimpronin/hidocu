//
//  NavigationViewModelV2.swift
//  HiDocu
//
//  Navigation state management for the context management UI.
//

import Foundation
import SwiftUI

enum SidebarItemV2: Hashable {
    case folder(id: Int64)
    case uncategorized
    case allDocuments
    case trash
    case device(id: UInt64)
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
        } else if savedSidebarKey.hasPrefix("folder:"),
                  let id = Int64(savedSidebarKey.dropFirst("folder:".count)) {
            selectedSidebarItem = .folder(id: id)
        } else {
            selectedSidebarItem = .allDocuments
        }
    }

    func saveSelection() {
        switch selectedSidebarItem {
        case .folder(let id): savedSidebarKey = "folder:\(id)"
        case .uncategorized:  savedSidebarKey = "uncategorized"
        case .allDocuments:   savedSidebarKey = "allDocuments"
        case .trash:          savedSidebarKey = "trash"
        case .device, .none:  savedSidebarKey = "allDocuments"
        }
    }
}
