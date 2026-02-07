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
    case allDocuments
    case trash
    case device(id: UInt64)
}

@Observable
@MainActor
final class NavigationViewModelV2 {
    var selectedSidebarItem: SidebarItemV2? = .allDocuments
    var selectedDocumentId: Int64?

    /// Persist selection across relaunches
    @ObservationIgnored
    @AppStorage("selectedSidebarFolderId") private var savedFolderId: Int = -1

    func restoreSelection() {
        if savedFolderId >= 0 {
            selectedSidebarItem = .folder(id: Int64(savedFolderId))
        }
    }

    func saveSelection() {
        if case .folder(let id) = selectedSidebarItem {
            savedFolderId = Int(id)
        } else {
            savedFolderId = -1
        }
    }
}
