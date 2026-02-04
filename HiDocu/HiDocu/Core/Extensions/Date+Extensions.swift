//
//  Date+Extensions.swift
//  HiDocu
//
//  Date formatting extensions for display.
//

import Foundation

extension Date {
    /// Format date for display in recording lists
    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format date for database storage (ISO 8601)
    var databaseString: String {
        ISO8601DateFormatter().string(from: self)
    }
    
    /// Parse date from database string (ISO 8601)
    static func fromDatabaseString(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
