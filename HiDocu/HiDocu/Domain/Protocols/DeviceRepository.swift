//
//  DeviceRepository.swift
//  HiDocu
//
//  Protocol defining device interaction operations.
//

import Foundation

/// Information about a connected HiDock device
struct DeviceConnectionInfo: Sendable {
    let serialNumber: String
    let model: String
    let firmwareVersion: String
    let firmwareNumber: UInt32
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
