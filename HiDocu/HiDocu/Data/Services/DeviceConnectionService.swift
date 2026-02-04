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
    
    /// USB Monitor for hot-plug detection
    private var usbMonitor: USBMonitor?

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
        jensen?.disconnect()
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
                self?.disconnect()
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
            // Create Jensen on MainActor - its Timer.scheduledTimer requires an active RunLoop.
            // RunLoop.main is always available on the main thread.
            // Note: connect() is typically fast (IOKit device open), so this won't block UI significantly.
            let device = Jensen()
            try device.connect()

            let model = mapModel(device.model)
            let info = DeviceConnectionInfo(
                serialNumber: device.serialNumber ?? "unknown",
                model: model,
                firmwareVersion: device.versionCode ?? "unknown",
                firmwareNumber: device.versionNumber ?? 0
            )

            // Store reference to keep alive
            self.jensen = device
            self.connectionInfo = info
            self.connectionState = .connected

            AppLogger.usb.info("Connected to \(model.displayName) (SN: \(info.serialNumber))")

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
    func disconnect() {
        guard let device = jensen else { return }

        AppLogger.usb.info("Disconnecting from device...")

        stopBatteryPolling()

        device.disconnect()
        jensen = nil
        connectionInfo = nil
        connectionState = .disconnected
        batteryInfo = nil
        storageInfo = nil

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
        expectedSize: Int,
        toPath: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws {
        guard let device = jensen else {
            throw DeviceServiceError.notConnected
        }

        let data = try await Task.detached {
            try device.file.download(
                filename: filename,
                expectedSize: UInt32(expectedSize),
                progressHandler: { current, total in
                    progress(Int64(current), Int64(total))
                }
            )
        }.value

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

    @MainActor
    private func pollBattery() {
        guard let device = jensen else { return }

        Task {
            do {
                let status = try await Task.detached {
                    try device.system.getBatteryStatus()
                }.value
                self.batteryInfo = DeviceBatteryInfo(
                    percentage: status.percentage,
                    state: self.mapBatteryState(status.status)
                )
            } catch {
                AppLogger.usb.error("Battery poll failed: \(error.localizedDescription)")
            }
        }
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
