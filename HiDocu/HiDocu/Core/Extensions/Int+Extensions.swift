//
//  Int+Extensions.swift
//  HiDocu
//
//  Integer formatting extensions.
//

import Foundation

extension Int {
    /// Format seconds as HH:MM:SS duration string
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Format seconds as HH:MM:SS duration string (always shows hours)
    var formattedDurationFull: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Format bytes as human-readable file size (KB, MB, GB)
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(self))
    }
}

extension Int64 {
    /// Format bytes as human-readable file size (KB, MB, GB)
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
