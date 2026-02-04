//
//  NavigationViewModel.swift
//  HiDocu
//
//  Navigation state management for sidebar selection and detail routing.
//

import Foundation

/// Represents a selectable item in the sidebar.
enum SidebarItem: Hashable {
    case allRecordings
    case filteredByStatus(RecordingStatus)

    var title: String {
        switch self {
        case .allRecordings:
            return "All Recordings"
        case .filteredByStatus(let status):
            switch status {
            case .new:         return "New"
            case .downloaded:  return "Downloaded"
            case .transcribed: return "Transcribed"
            }
        }
    }

    var iconName: String {
        switch self {
        case .allRecordings:
            return "waveform"
        case .filteredByStatus(let status):
            switch status {
            case .new:         return "circle.fill"
            case .downloaded:  return "arrow.down.circle.fill"
            case .transcribed: return "text.bubble.fill"
            }
        }
    }

    /// The status filter to pass to the repository, or nil for "all".
    var statusFilter: RecordingStatus? {
        switch self {
        case .allRecordings:
            return nil
        case .filteredByStatus(let status):
            return status
        }
    }
}

/// Manages navigation state: which sidebar item is selected and which recording is active.
@Observable
@MainActor
final class NavigationViewModel {
    var selectedSidebarItem: SidebarItem? = .allRecordings
    var selectedRecordingId: Int64?
    var selectedRecording: Recording?
}
