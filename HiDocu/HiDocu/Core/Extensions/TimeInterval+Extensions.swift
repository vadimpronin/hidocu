//
//  TimeInterval+Extensions.swift
//  HiDocu
//
//  Formatting utilities for TimeInterval (used for audio playback timestamps).
//

import Foundation

extension TimeInterval {
    /// Format as timestamp: "MM:SS" or "HH:MM:SS"
    ///
    /// Examples:
    /// - 65 seconds → "1:05"
    /// - 3665 seconds → "1:01:05"
    /// - 0 seconds → "0:00"
    var formattedTimestamp: String {
        guard !self.isNaN && !self.isInfinite else {
            return "--:--"
        }

        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
