//
//  DeviceRepository.swift
//  HiDocu
//
//  Protocol defining device interaction operations.
//

import Foundation

// MARK: - Device Model

/// Domain-level device model enum (independent of JensenUSB).
/// The Data layer maps `HiDockModel` -> `DeviceModel`.
enum DeviceModel: String, Sendable, CaseIterable {
    case h1
    case h1e
    case p1
    case p1Mini

    case unknown

    var isP1: Bool { self == .p1 || self == .p1Mini }

    var displayName: String {
        switch self {
        case .h1:      return "HiDock H1"
        case .h1e:     return "HiDock H1e"
        case .p1:      return "HiDock P1"
        case .p1Mini:  return "HiDock P1 Mini"
        case .unknown: return "HiDock"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .p1, .p1Mini: return "rectangle.fill.on.rectangle.fill"
        case .h1, .h1e:    return "dock.rectangle"
        case .unknown:      return "externaldrive.fill"
        }
    }
}

// MARK: - Battery & Storage

enum BatteryState: String, Sendable {
    case charging
    case discharging
    case full
    case unknown
}

struct DeviceBatteryInfo: Sendable, Equatable {
    let percentage: Int
    let state: BatteryState
}

struct DeviceStorageInfo: Sendable, Equatable {
    let totalBytes: Int64
    let usedBytes: Int64

    var freeBytes: Int64 { totalBytes - usedBytes }

    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(usedBytes) / Double(totalBytes), 1.0)
    }

    var formattedTotal: String { totalBytes.formattedFileSize }
    var formattedUsed: String { usedBytes.formattedFileSize }
    var formattedFree: String { freeBytes.formattedFileSize }
}

// MARK: - Connection Info

/// Information about a connected HiDock device
struct DeviceConnectionInfo: Sendable {
    let serialNumber: String
    let model: DeviceModel
    let firmwareVersion: String
    let firmwareNumber: UInt32

    var supportsBattery: Bool { model.isP1 }
}

/// Information about a file on the device
struct DeviceFileInfo: Sendable {
    let filename: String
    let size: Int
    let durationSeconds: Int
    let createdAt: Date?
    let mode: RecordingMode?
}

/// Protocol for device interaction operations.
/// Wraps JensenUSB functionality for the Domain layer.
protocol DeviceRepository: Sendable {
    /// Check if a device is currently connected
    var isConnected: Bool { get }
    
    /// Current device info if connected
    var connectionInfo: DeviceConnectionInfo? { get }
    
    /// Connect to a HiDock device
    func connect() async throws -> DeviceConnectionInfo
    
    /// Disconnect from the device
    func disconnect() async
    
    /// List files on the device
    func listFiles() async throws -> [DeviceFileInfo]
    
    /// Download a file from the device to a local path
    func downloadFile(
        filename: String,
        toPath: URL,
        progress: @escaping (Double) -> Void
    ) async throws
    
    /// Delete a file from the device
    func deleteFile(filename: String) async throws
    
    /// Get device storage info
    func getStorageInfo() async throws -> (total: Int64, free: Int64)
}
