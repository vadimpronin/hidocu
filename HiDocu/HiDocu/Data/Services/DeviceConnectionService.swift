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
/// All USB operations are serialized through `JensenActor` to prevent race conditions
/// where concurrent commands (e.g., battery polling during a download) would corrupt
/// the USB data stream.
///
/// - Important: Do not allow this to be deallocated while the app is running,
///   as the Jensen instance maintains a keep-alive timer.
@Observable
final class DeviceConnectionService {

    // MARK: - Properties

    /// The serializing wrapper around Jensen (thread-safe)
    private let driver = JensenActor()

    /// USB Monitor for hot-plug detection
    private var usbMonitor: USBMonitor?

    /// Whether a device is currently connected
    var isConnected: Bool {
        // Use a cached value that gets updated by connect/disconnect
        if case .connected = connectionState { return true }
        return false
    }

    /// Connection info for the current device
    private(set) var connectionInfo: DeviceConnectionInfo?

    /// Connection state for UI binding
    private(set) var connectionState: ConnectionState = .disconnected

    /// Error message if connection failed
    private(set) var lastError: String?

    /// Battery info (P1/P1 Mini only, polled every 30s)
    private(set) var batteryInfo: DeviceBatteryInfo?

    /// Storage info (refreshed on demand)
    private(set) var storageInfo: DeviceStorageInfo?

    /// Battery polling task
    private var batteryPollingTask: Task<Void, Never>?

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
        setupUSBMonitor()
    }

    deinit {
        AppLogger.usb.warning("DeviceConnectionService being deallocated - device will disconnect!")
        usbMonitor?.stop()
        batteryPollingTask?.cancel()
        // Note: The actor will disconnect when it's deallocated
    }

    private func setupUSBMonitor() {
        let monitor = USBMonitor()

        monitor.deviceDidConnect = { [weak self] id in
            AppLogger.usb.info("Monitor reported device connected (ID: \(id))")
            Task { @MainActor in
                guard let self = self else { return }
                if self.isConnected {
                     AppLogger.usb.info("Device already connected, ignoring new connection event")
                     return
                }

                AppLogger.usb.info("Initiating connection from monitor event...")
                _ = try? await self.connect()
            }
        }

        monitor.deviceDidDisconnect = { [weak self] id in
            AppLogger.usb.info("Monitor reported device disconnected (ID: \(id))")
            Task { @MainActor in
                await self?.disconnect()
            }
        }

        AppLogger.usb.info("Starting USBMonitor...")
        monitor.start()
        self.usbMonitor = monitor
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
            // Connect through the actor - must be on MainActor for Timer support
            let info = try await driver.connect()

            self.connectionInfo = info
            self.connectionState = .connected

            AppLogger.usb.info("Connected to \(info.model.displayName) (SN: \(info.serialNumber))")

            // Start battery polling for P1 devices
            if info.supportsBattery {
                startBatteryPolling()
            }

            // Refresh storage info
            await refreshStorageInfo()

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
    func disconnect() async {
        guard case .connected = connectionState else { return }

        AppLogger.usb.info("Disconnecting from device...")

        stopBatteryPolling()

        await driver.disconnect()
        connectionInfo = nil
        connectionState = .disconnected
        batteryInfo = nil
        storageInfo = nil

        AppLogger.usb.info("Disconnected")
    }

    // MARK: - Device Operations

    /// List files on the connected device.
    func listFiles() async throws -> [DeviceFileInfo] {
        return try await driver.listFiles()
    }

    /// Download a file from the device directly to disk.
    ///
    /// Uses streaming I/O — data is written to disk as it arrives from USB,
    /// keeping memory usage low and progress updates continuous.
    ///
    /// - Important: While this method is running, other actor operations (like battery polling)
    ///   will wait. This prevents race conditions that would corrupt the download.
    func downloadFile(
        filename: String,
        expectedSize: Int,
        toPath: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws {
        try await driver.downloadFile(
            filename: filename,
            expectedSize: expectedSize,
            toPath: toPath,
            progress: progress
        )
    }

    /// Delete a file from the device.
    func deleteFile(filename: String) async throws {
        try await driver.deleteFile(filename: filename)
    }

    /// Get device storage info.
    func getStorageInfo() async throws -> (total: Int64, free: Int64) {
        return try await driver.getStorageInfo()
    }

    /// Refresh storage info and update the published property.
    @MainActor
    func refreshStorageInfo() async {
        do {
            let (total, free) = try await getStorageInfo()
            let used = total - free
            storageInfo = DeviceStorageInfo(totalBytes: total, usedBytes: used)
        } catch {
            AppLogger.usb.error("Failed to refresh storage info: \(error.localizedDescription)")
        }
    }

    // MARK: - Battery Polling

    @MainActor
    private func startBatteryPolling() {
        stopBatteryPolling()

        // Poll immediately, then every 30 seconds
        pollBattery()

        batteryPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                pollBattery()
            }
        }
    }

    @MainActor
    private func stopBatteryPolling() {
        batteryPollingTask?.cancel()
        batteryPollingTask = nil
    }

    /// Poll battery status from the device.
    ///
    /// - Important: This call goes through `JensenActor`, so if a download is in progress,
    ///   this will wait until the download completes. This is intentional — it prevents
    ///   the battery command from corrupting an ongoing file transfer.
    @MainActor
    private func pollBattery() {
        Task {
            do {
                let status = try await driver.getBatteryStatus()
                self.batteryInfo = status
            } catch {
                // Don't spam logs if device just doesn't support battery
                if case DeviceServiceError.notConnected = error {
                    // Device disconnected, stop polling
                    stopBatteryPolling()
                } else {
                    AppLogger.usb.error("Battery poll failed: \(error.localizedDescription)")
                }
            }
        }
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
