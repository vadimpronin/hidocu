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

    // MARK: - Retry Configuration

    /// Maximum number of connection attempts before giving up
    private let maxRetryAttempts = 3

    /// Delay between retry attempts (exponential backoff)
    private let retryDelaySeconds: [Double] = [1.0, 2.0, 4.0]

    /// Maximum retry attempts for post-connection operations (file list, storage info)
    private let operationRetryAttempts = 3

    /// Shorter delays for operation retries (USB pipe timing)
    private let operationRetryDelays: [Double] = [0.5, 1.0, 2.0]

    /// Whether a device is physically connected via USB (from USBMonitor)
    private(set) var isDevicePhysicallyConnected = false

    /// Task for ongoing retry attempts (can be cancelled)
    private var retryTask: Task<Void, Never>?

    /// Device model detected from USB product ID (available before communication established)
    private(set) var detectedModel: DeviceModel?

    // MARK: - Debug Simulation

    #if DEBUG
    /// When true, connectSingleAttempt() will always throw a timeout error (for testing retry UI)
    var simulateConnectionFailure = false

    /// Simulate a device being connected but not responding to commands.
    /// This triggers the full retry flow and eventually shows connectionFailed state.
    @MainActor
    func simulateUnresponsiveDevice(model: DeviceModel = .p1) async {
        AppLogger.usb.info("[DEBUG] Simulating unresponsive device connection...")

        // Simulate USB detection
        isDevicePhysicallyConnected = true
        detectedModel = model
        simulateConnectionFailure = true

        // Trigger connection with retry (will fail 3 times)
        await connectWithRetry()

        // Reset simulation flag after completion
        simulateConnectionFailure = false
    }

    /// Reset simulation state (simulate device disconnect)
    @MainActor
    func simulateDisconnect() async {
        AppLogger.usb.info("[DEBUG] Simulating device disconnect...")
        isDevicePhysicallyConnected = false
        simulateConnectionFailure = false
        await disconnect()
        detectedModel = nil
    }
    #endif

    // MARK: - Connection State

    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting(attempt: Int, maxAttempts: Int)
        case connected
        case connectionFailed(reason: ConnectionFailureReason)
    }

    enum ConnectionFailureReason: Sendable, Equatable {
        case timeout
        case deviceBusy
        case communicationError(String)

        var userMessage: String {
            switch self {
            case .timeout: return "Device not responding"
            case .deviceBusy: return "Device is busy"
            case .communicationError: return "Unable to communicate"
            }
        }
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
        retryTask?.cancel()
        // Note: The actor will disconnect when it's deallocated
    }

    private func setupUSBMonitor() {
        let monitor = USBMonitor()

        monitor.deviceDidConnect = { [weak self] id, productID in
            AppLogger.usb.info("Monitor reported device connected (ID: \(id), ProductID: \(productID))")
            Task { @MainActor in
                guard let self = self else { return }
                self.isDevicePhysicallyConnected = true
                self.detectedModel = self.mapProductIDToModel(productID)

                if self.isConnected {
                    AppLogger.usb.info("Device already connected, ignoring new connection event")
                    return
                }

                AppLogger.usb.info("Initiating connection with retry from monitor event...")
                await self.connectWithRetry()
            }
        }

        monitor.deviceDidDisconnect = { [weak self] id in
            AppLogger.usb.info("Monitor reported device disconnected (ID: \(id))")
            Task { @MainActor in
                guard let self = self else { return }
                self.isDevicePhysicallyConnected = false
                self.retryTask?.cancel()
                await self.disconnect()
                // Clear detected model after disconnect completes (not during retry)
                self.detectedModel = nil
            }
        }

        AppLogger.usb.info("Starting USBMonitor...")
        monitor.start()
        self.usbMonitor = monitor
    }

    /// Map USB product ID to DeviceModel (same logic as HiDockModel.from(productID:))
    private func mapProductIDToModel(_ productID: UInt16) -> DeviceModel {
        switch productID {
        case 45068, 256, 258: return .h1
        case 45069, 257, 259: return .h1e
        case 45070, 8256: return .p1
        case 45071, 8257: return .p1Mini
        default: return .unknown
        }
    }

    // MARK: - Connection Methods

    /// Connect to the device with automatic retry on failure.
    /// Uses exponential backoff between attempts.
    @MainActor
    func connectWithRetry() async {
        // Cancel and wait for any existing retry task to finish
        retryTask?.cancel()
        await retryTask?.value
        retryTask = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 1...self.maxRetryAttempts {
                // Check if we should stop (device physically disconnected or task cancelled)
                guard self.isDevicePhysicallyConnected, !Task.isCancelled else {
                    AppLogger.usb.info("Device physically disconnected or cancelled, stopping retry")
                    if !self.isConnected {
                        self.connectionState = .disconnected
                    }
                    return
                }

                // Update state to show retry progress
                self.connectionState = .connecting(attempt: attempt, maxAttempts: self.maxRetryAttempts)

                AppLogger.usb.info("Connection attempt \(attempt)/\(self.maxRetryAttempts)")

                do {
                    _ = try await self.connectSingleAttempt()
                    // Success! connectSingleAttempt() already sets .connected state
                    return
                } catch {
                    let message = error.localizedDescription
                    AppLogger.usb.error("Attempt \(attempt) failed: \(message)")

                    // Last attempt?
                    if attempt == self.maxRetryAttempts {
                        let reason = self.mapErrorToFailureReason(error)
                        self.connectionState = .connectionFailed(reason: reason)
                        self.lastError = message
                        AppLogger.usb.error("All \(self.maxRetryAttempts) attempts failed")
                        return
                    }

                    // Wait before next attempt (exponential backoff, clamped to array bounds)
                    let delayIndex = min(attempt - 1, self.retryDelaySeconds.count - 1)
                    let delay = self.retryDelaySeconds[delayIndex]
                    AppLogger.usb.info("Waiting \(delay)s before next attempt...")
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }

        retryTask = task
        await task.value
    }

    /// Manual retry (triggered by user action).
    @MainActor
    func manualRetry() async {
        guard isDevicePhysicallyConnected else {
            AppLogger.usb.warning("Manual retry requested but device not physically connected")
            return
        }
        await connectWithRetry()
    }

    /// Map a connection error to a user-friendly failure reason.
    private func mapErrorToFailureReason(_ error: Error) -> ConnectionFailureReason {
        let description = error.localizedDescription.lowercased()
        if description.contains("timeout") {
            return .timeout
        } else if description.contains("busy") || description.contains("in use") {
            return .deviceBusy
        } else {
            return .communicationError(error.localizedDescription)
        }
    }

    /// Retry an async operation with exponential backoff.
    /// Used for post-connection operations that may fail due to USB timing issues.
    private func performWithRetry<T>(
        operation: String,
        maxAttempts: Int? = nil,
        delays: [Double]? = nil,
        action: () async throws -> T
    ) async throws -> T {
        let attempts = maxAttempts ?? operationRetryAttempts
        let retryDelays = delays ?? operationRetryDelays
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await action()
            } catch {
                lastError = error
                AppLogger.usb.warning(
                    "\(operation) attempt \(attempt)/\(attempts) failed: \(error.localizedDescription)"
                )

                if attempt < attempts {
                    let delayIndex = min(attempt - 1, retryDelays.count - 1)
                    let delay = retryDelays[delayIndex]
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError!
    }

    /// Internal single connection attempt (no retry, no state changes on failure).
    ///
    /// - Important: Jensen uses `Timer.scheduledTimer` for keep-alive pings, which requires
    ///   an active RunLoop. This method runs on MainActor to ensure the timer is attached
    ///   to `RunLoop.main` and will fire correctly.
    /// - Returns: Device connection info on success
    /// - Throws: JensenError if connection fails
    @MainActor
    private func connectSingleAttempt() async throws -> DeviceConnectionInfo {
        lastError = nil

        #if DEBUG
        // Simulate connection timeout for testing retry UI
        if simulateConnectionFailure {
            AppLogger.usb.info("[DEBUG] Simulating connection timeout...")
            try await Task.sleep(for: .seconds(0.5))  // Brief delay to simulate attempt
            throw SimulatedConnectionError.timeout
        }
        #endif

        AppLogger.usb.info("Attempting to connect to device...")

        // Connect through the actor - must be on MainActor for Timer support
        let info = try await driver.connect()

        AppLogger.usb.info("Connected to \(info.model.displayName) (SN: \(info.serialNumber))")

        // Verify connection works by fetching storage info (with retries for USB timing)
        // This ensures the USB pipe is actually ready before we declare success
        let (total, free) = try await performWithRetry(operation: "Storage info verification") {
            try await driver.getStorageInfo()
        }
        let used = total - free
        storageInfo = DeviceStorageInfo(totalBytes: total, usedBytes: used)

        // Connection verified - update state
        self.connectionInfo = info
        self.connectionState = .connected

        // Start battery polling for P1 devices
        if info.supportsBattery {
            startBatteryPolling()
        }

        return info
    }

    /// Disconnect from the current device.
    @MainActor
    func disconnect() async {
        // Cancel any pending retry task
        retryTask?.cancel()
        retryTask = nil

        // Handle based on current state
        switch connectionState {
        case .connected:
            break  // Normal disconnect, proceed below
        case .connecting:
            // Was mid-connection, just reset state
            connectionState = .disconnected
            lastError = nil
            return
        case .connectionFailed:
            // Clear the failed state
            connectionState = .disconnected
            lastError = nil
            return
        case .disconnected:
            return  // Already disconnected
        }

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
    /// Retries on transient USB errors.
    func listFiles() async throws -> [DeviceFileInfo] {
        return try await performWithRetry(operation: "List files") {
            try await driver.listFiles()
        }
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
        progress: @escaping @Sendable (Int64, Int64) -> Void
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
    /// Retries on transient USB errors.
    @MainActor
    func refreshStorageInfo() async {
        do {
            let (total, free) = try await performWithRetry(operation: "Refresh storage info") {
                try await getStorageInfo()
            }
            let used = total - free
            storageInfo = DeviceStorageInfo(totalBytes: total, usedBytes: used)
        } catch {
            AppLogger.usb.error("Failed to refresh storage info after retries: \(error.localizedDescription)")
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
                let status = try await performWithRetry(operation: "Battery poll") {
                    try await driver.getBatteryStatus()
                }
                self.batteryInfo = status
            } catch {
                // Don't spam logs if device just doesn't support battery
                if case DeviceServiceError.notConnected = error {
                    // Device disconnected, stop polling
                    stopBatteryPolling()
                } else {
                    AppLogger.usb.error("Battery poll failed after retries: \(error.localizedDescription)")
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

#if DEBUG
/// Simulated errors for testing connection retry behavior
enum SimulatedConnectionError: LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Simulated timeout - device not responding"
        }
    }
}
#endif
