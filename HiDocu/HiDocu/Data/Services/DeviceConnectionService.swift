//
//  DeviceConnectionService.swift
//  HiDocu
//
//  Wrapper around JensenUSB for device communication.
//  IMPORTANT: This service must remain alive for the app's lifetime
//  to maintain the USB connection and keep-alive timer.
//

import Foundation
import JensenUSB

/// Manages connection to HiDock USB devices.
/// This is a long-lived singleton that wraps JensenUSB.
///
/// - Important: Do not allow this to be deallocated while the app is running,
///   as the Jensen instance maintains a keep-alive timer.
@Observable
final class DeviceConnectionService {
    
    // MARK: - Properties
    
    /// The underlying Jensen instance (kept alive)
    private var jensen: Jensen?
    
    /// Whether a device is currently connected
    var isConnected: Bool {
        jensen?.isConnected ?? false
    }
    
    /// Connection info for the current device
    private(set) var connectionInfo: DeviceConnectionInfo?
    
    /// Connection state for UI binding
    private(set) var connectionState: ConnectionState = .disconnected
    
    /// Error message if connection failed
    private(set) var lastError: String?
    
    // MARK: - Connection State
    
    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    // MARK: - Initialization
    
    init() {
        AppLogger.usb.info("DeviceConnectionService initialized")
    }
    
    deinit {
        AppLogger.usb.warning("DeviceConnectionService being deallocated - device will disconnect!")
        jensen?.disconnect()
    }
    
    // MARK: - Connection Methods
    
    /// Connect to a HiDock device.
    /// 
    /// - Important: Jensen uses `Timer.scheduledTimer` for keep-alive pings, which requires
    ///   an active RunLoop. This method runs on MainActor to ensure the timer is attached
    ///   to `RunLoop.main` and will fire correctly.
    /// - Returns: Device connection info on success
    /// - Throws: JensenError if connection fails
    @MainActor
    func connect() async throws -> DeviceConnectionInfo {
        connectionState = .connecting
        lastError = nil
        
        AppLogger.usb.info("Attempting to connect to device...")
        
        do {
            // Create Jensen on MainActor - its Timer.scheduledTimer requires an active RunLoop.
            // RunLoop.main is always available on the main thread.
            // Note: connect() is typically fast (IOKit device open), so this won't block UI significantly.
            let device = Jensen()
            try device.connect()
            
            let deviceInfo = try device.getDeviceInfo()
            let info = DeviceConnectionInfo(
                serialNumber: deviceInfo.serialNumber,
                model: determineModel(from: deviceInfo),
                firmwareVersion: deviceInfo.versionCode,
                firmwareNumber: deviceInfo.versionNumber
            )
            
            // Store reference to keep alive
            self.jensen = device
            self.connectionInfo = info
            self.connectionState = .connected
            
            AppLogger.usb.info("Connected to \(info.model) (SN: \(info.serialNumber))")
            
            return info
            
        } catch {
            let message = "Connection failed: \(error.localizedDescription)"
            connectionState = .error(message)
            lastError = message
            AppLogger.usb.error("\(message)")
            throw error
        }
    }
    
    /// Disconnect from the current device.
    @MainActor
    func disconnect() {
        guard let device = jensen else { return }
        
        AppLogger.usb.info("Disconnecting from device...")
        
        device.disconnect()
        jensen = nil
        connectionInfo = nil
        connectionState = .disconnected
        
        AppLogger.usb.info("Disconnected")
    }
    
    // MARK: - Device Operations
    
    /// List files on the connected device.
    func listFiles() async throws -> [DeviceFileInfo] {
        guard let device = jensen else {
            throw DeviceServiceError.notConnected
        }
        
        return try await Task.detached {
            let files = try device.file.list()
            
            return files.map { file in
                DeviceFileInfo(
                    filename: file.name,
                    size: Int(file.length),
                    durationSeconds: Int(file.duration),
                    createdAt: file.date,
                    mode: RecordingMode(rawValue: file.mode)
                )
            }
        }.value
    }
    
    /// Download a file from the device.
    func downloadFile(
        filename: String,
        toPath: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard let device = jensen else {
            throw DeviceServiceError.notConnected
        }
        
        // Get file size first for progress reporting
        let files = try device.file.list()
        guard let fileEntry = files.first(where: { $0.name == filename }) else {
            throw DeviceServiceError.downloadFailed("File not found on device")
        }
        
        let data = try device.file.download(
            filename: filename,
            expectedSize: fileEntry.length,
            progressHandler: { current, total in
                let pct = total > 0 ? Double(current) / Double(total) : 0
                Task { @MainActor in progress(pct) }
            }
        )
        
        try data.write(to: toPath)
    }
    
    /// Delete a file from the device.
    func deleteFile(filename: String) async throws {
        guard let device = jensen else {
            throw DeviceServiceError.notConnected
        }
        
        try device.file.delete(name: filename)
    }
    
    /// Get device storage info.
    func getStorageInfo() async throws -> (total: Int64, free: Int64) {
        guard let device = jensen else {
            throw DeviceServiceError.notConnected
        }
        
        let cardInfo = try device.system.getCardInfo()
        let total = Int64(cardInfo.capacity)
        let used = Int64(cardInfo.used)
        let free = total - used
        return (total: total, free: free)
    }
    
    // MARK: - Helpers
    
    private func determineModel(from info: DeviceInfo) -> String {
        // Determine model from version code or serial number pattern
        // This is a placeholder - actual logic depends on device specifics
        if info.versionCode.contains("H1") {
            return "H1"
        } else if info.versionCode.contains("P1") {
            return info.versionCode.contains("Mini") ? "P1 Mini" : "P1"
        }
        return "HiDock"
    }
    
    private func parseRecordingMode(from filename: String) -> RecordingMode? {
        // Parse recording mode from filename pattern
        // e.g., "CALL_20240101_120000.hda" -> .call
        let lowered = filename.lowercased()
        if lowered.hasPrefix("call") {
            return .call
        } else if lowered.hasPrefix("room") {
            return .room
        } else if lowered.hasPrefix("whisper") {
            return .whisper
        }
        return nil
    }
}

// MARK: - DeviceFileProvider Conformance

extension DeviceConnectionService: DeviceFileProvider {}

// MARK: - Errors

enum DeviceServiceError: LocalizedError {
    case notConnected
    case downloadFailed(String)
    case deleteFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No device connected"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .deleteFailed(let reason):
            return "Delete failed: \(reason)"
        }
    }
}
