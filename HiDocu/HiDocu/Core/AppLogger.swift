//
//  AppLogger.swift
//  HiDocu
//
//  Centralized logging with OSLog subsystems for different components.
//

import OSLog

/// Centralized logging for HiDocu application.
/// Each category maps to a component for easy filtering in Console.app.
///
/// Usage:
/// ```swift
/// AppLogger.usb.info("Device connected")
/// AppLogger.database.error("Failed to migrate: \(error)")
/// ```
enum AppLogger {
    private static let subsystem = "com.hidocu.app"
    
    /// USB device communication (JensenUSB)
    static let usb = Logger(subsystem: subsystem, category: "usb")
    
    /// Database operations (GRDB, migrations)
    static let database = Logger(subsystem: subsystem, category: "database")
    
    /// File system operations (downloads, storage)
    static let fileSystem = Logger(subsystem: subsystem, category: "filesystem")
    
    /// UI and presentation layer
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// General application events
    static let general = Logger(subsystem: subsystem, category: "general")
    
    /// Transcription operations (future BYOK AI integration)
    static let transcription = Logger(subsystem: subsystem, category: "transcription")

    /// Document operations
    static let document = Logger(subsystem: subsystem, category: "document")

    /// Context building and management
    static let context = Logger(subsystem: subsystem, category: "context")

    /// Trash operations
    static let trash = Logger(subsystem: subsystem, category: "trash")

    /// Folder operations
    static let folder = Logger(subsystem: subsystem, category: "folder")
}
