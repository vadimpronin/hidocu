//
//  JensenActor.swift
//  HiDocu
//
//  Serial command execution wrapper for JensenUSB.
//
//  This actor guarantees that only one logical operation (command + response + data stream)
//  is sent to the device at a time. Swift actors automatically serialize method calls,
//  so when a download is in progress, any calls to getBatteryStatus() will suspend and wait
//  until the download completes.
//
//  This solves the race condition where background battery polling would interrupt
//  an ongoing file download, corrupting the USB data stream.
//

import Foundation
import JensenUSB

/// Thread-safe wrapper around the `Jensen` USB driver.
///
/// All device operations are serialized through this actor to prevent concurrent
/// USB commands from corrupting each other. The physical USB interface is stateful
/// and cannot handle interleaved commands.
///
/// - Important: Only one `JensenActor` should exist per application. Multiple actors
///   would defeat the serialization purpose.
actor JensenActor {

    // MARK: - Properties

    /// The underlying Jensen instance (only accessed through this actor)
    private var jensen: Jensen?

    /// Cached connection info
    private var cachedConnectionInfo: DeviceConnectionInfo?

    // MARK: - Connection State

    /// Whether a device is currently connected
    var isConnected: Bool {
        jensen?.isConnected ?? false
    }

    /// Connection info for the current device
    var connectionInfo: DeviceConnectionInfo? {
        cachedConnectionInfo
    }

    /// The device model (for capability checks)
    var model: HiDockModel? {
        jensen?.model
    }

    // MARK: - Connection Operations

    /// Connect to a HiDock device.
    ///
    /// - Important: This must be called from MainActor context because Jensen uses
    ///   `Timer.scheduledTimer` for keep-alive pings, which requires an active RunLoop.
    /// - Returns: Device connection info on success
    /// - Throws: JensenError if connection fails
    func connect() throws -> DeviceConnectionInfo {
        if let existing = jensen, existing.isConnected {
            AppLogger.usb.info("[JensenActor] Already connected")
            if let info = cachedConnectionInfo {
                return info
            }
        }

        AppLogger.usb.info("[JensenActor] Connecting...")

        let device = Jensen()
        try device.connect()

        let info = DeviceConnectionInfo(
            serialNumber: device.serialNumber ?? "unknown",
            model: mapModel(device.model),
            firmwareVersion: device.versionCode ?? "unknown",
            firmwareNumber: device.versionNumber ?? 0
        )

        self.jensen = device
        self.cachedConnectionInfo = info

        AppLogger.usb.info("[JensenActor] Connected to \(info.model.displayName) (SN: \(info.serialNumber))")

        return info
    }

    /// Disconnect from the current device.
    func disconnect() {
        guard let device = jensen else { return }

        AppLogger.usb.info("[JensenActor] Disconnecting...")
        device.disconnect()
        jensen = nil
        cachedConnectionInfo = nil
        AppLogger.usb.info("[JensenActor] Disconnected")
    }

    // MARK: - Battery Operations

    /// Get the current battery status.
    ///
    /// - Note: This method will wait if another operation (like a download) is in progress.
    /// - Throws: DeviceServiceError.notConnected if no device is connected
    /// - Throws: JensenError.unsupportedDevice if the device doesn't support battery status
    func getBatteryStatus() throws -> DeviceBatteryInfo {
        guard let device = jensen, device.isConnected else {
            throw DeviceServiceError.notConnected
        }

        let status = try device.system.getBatteryStatus()

        return DeviceBatteryInfo(
            percentage: status.percentage,
            state: mapBatteryState(status.status)
        )
    }

    // MARK: - Storage Operations

    /// Get device storage info.
    ///
    /// - Returns: Tuple of (total bytes, free bytes)
    /// - Throws: DeviceServiceError.notConnected if no device is connected
    func getStorageInfo() throws -> (total: Int64, free: Int64) {
        guard let device = jensen, device.isConnected else {
            throw DeviceServiceError.notConnected
        }

        let cardInfo = try device.system.getCardInfo()
        let total = Int64(cardInfo.capacity)
        let used = Int64(cardInfo.used)
        let free = total - used
        return (total: total, free: free)
    }

    // MARK: - File Operations

    /// List files on the connected device.
    ///
    /// - Note: This method will wait if another operation is in progress.
    /// - Returns: Array of file information
    /// - Throws: DeviceServiceError.notConnected if no device is connected
    func listFiles() throws -> [DeviceFileInfo] {
        guard let device = jensen, device.isConnected else {
            throw DeviceServiceError.notConnected
        }

        AppLogger.usb.info("[JensenActor] Listing files...")

        let files = try device.file.list()

        AppLogger.usb.info("[JensenActor] Found \(files.count) files")

        return files.map { file in
            DeviceFileInfo(
                filename: file.name,
                size: Int(file.length),
                durationSeconds: Int(file.duration),
                createdAt: file.date,
                mode: RecordingMode(rawValue: file.mode)
            )
        }
    }

    /// Download a file from the device directly to disk.
    ///
    /// This is the critical long-running operation. Because it is an `async` function
    /// on an `actor`, while this runs, any other calls to this actor (like `getBatteryStatus`)
    /// will suspend and wait until this completes. This prevents race conditions.
    ///
    /// - Parameters:
    ///   - filename: Name of the file on the device
    ///   - expectedSize: Expected file size in bytes
    ///   - toPath: Local file URL to write to
    ///   - progress: Progress callback with (bytesDownloaded, totalBytes)
    /// - Throws: DeviceServiceError.notConnected if no device is connected
    func downloadFile(
        filename: String,
        expectedSize: Int,
        toPath: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) throws {
        guard let device = jensen, device.isConnected else {
            throw DeviceServiceError.notConnected
        }

        AppLogger.usb.info("[JensenActor] Starting download: \(filename) (\(expectedSize) bytes)")

        try device.file.downloadToFile(
            filename: filename,
            expectedSize: UInt32(expectedSize),
            toURL: toPath,
            progressHandler: { current, total in
                progress(Int64(current), Int64(total))
            }
        )

        AppLogger.usb.info("[JensenActor] Download complete: \(filename)")
    }

    /// Delete a file from the device.
    ///
    /// - Parameter filename: Name of the file to delete
    /// - Throws: DeviceServiceError.notConnected if no device is connected
    func deleteFile(filename: String) throws {
        guard let device = jensen, device.isConnected else {
            throw DeviceServiceError.notConnected
        }

        AppLogger.usb.info("[JensenActor] Deleting file: \(filename)")
        try device.file.delete(name: filename)
        AppLogger.usb.info("[JensenActor] Deleted: \(filename)")
    }

    // MARK: - Helpers

    private func mapModel(_ jensenModel: HiDockModel) -> DeviceModel {
        switch jensenModel {
        case .h1:      return .h1
        case .h1e:     return .h1e
        case .p1:      return .p1
        case .p1Mini:  return .p1Mini
        case .unknown: return .unknown
        }
    }

    private func mapBatteryState(_ status: String) -> BatteryState {
        switch status {
        case "charging":    return .charging
        case "idle":        return .discharging
        case "full":        return .full
        default:            return .unknown
        }
    }
}
