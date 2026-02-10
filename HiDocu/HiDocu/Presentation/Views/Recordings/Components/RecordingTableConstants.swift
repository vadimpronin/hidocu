//
//  RecordingTableConstants.swift
//  HiDocu
//
//  Shared column widths, date formatting, and small reusable components
//  for the recording table views.
//

import SwiftUI

// MARK: - Column Configuration

enum RecordingTableConstants {
    // Column widths shared across all recording table views
    static let dateColumnWidth: (min: CGFloat, ideal: CGFloat) = (180, 190)
    static let nameColumnWidth: (min: CGFloat, ideal: CGFloat) = (150, 270)
    static let durationColumnWidth: (min: CGFloat, ideal: CGFloat) = (70, 80)
    static let modeColumnWidth: (min: CGFloat, ideal: CGFloat) = (55, 70)
    static let sizeColumnWidth: (min: CGFloat, ideal: CGFloat) = (60, 80)
    static let statusIconColumnWidth: CGFloat = 28
    static let documentColumnWidth: (min: CGFloat, ideal: CGFloat) = (80, 120)
    static let sourceColumnWidth: (min: CGFloat, ideal: CGFloat) = (100, 130)
    static let sourceIconColumnWidth: CGFloat = 28

    /// Shared date format used in all recording tables.
    static let dateFormat: Date.FormatStyle = .dateTime
        .day(.twoDigits)
        .month(.abbreviated)
        .year()
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .second(.twoDigits)
}
