//
//  DeviceManager.swift
//  HiDocu
//
//  Manages the lifecycle of multiple HiDock device connections.
//  Replaces the old single-device DeviceConnectionService.
//

import Foundation
import JensenUSB
import SwiftUI // For @Observable

@Observable
final class DeviceManager {
    // MARK: - Properties
    
    /// List of connected device controllers
    var connectedDevices: [DeviceController] = []

    /// USB Monitor for hot-plug detection
    private var usbMonitor: USBMonitor?

    /// Recording source service for device-to-source mapping
    private var recordingSourceService: RecordingSourceService?
    
    // MARK: - Initialization
    
    init() {
        AppLogger.usb.info("DeviceManager initialized")
    }

    func setRecordingSourceService(_ service: RecordingSourceService) {
        self.recordingSourceService = service
    }

    func startMonitoring() {
        setupUSBMonitor()
    }
    
    deinit {
        usbMonitor?.stop()
        // Disconnect all devices
        let devices = connectedDevices
        Task {
            for device in devices {
                await device.disconnect()
            }
        }
    }
    
    // MARK: - USB Monitoring
    
    private func setupUSBMonitor() {
        let monitor = USBMonitor()
        
        monitor.deviceDidConnect = { [weak self] id, productID in
            Task { @MainActor [weak self] in
                self?.handleDeviceConnection(entryID: id, productID: productID)
            }
        }
        
        monitor.deviceDidDisconnect = { [weak self] id in
            Task { @MainActor [weak self] in
                self?.handleDeviceDisconnection(entryID: id)
            }
        }
        
        AppLogger.usb.info("Starting USBMonitor...")
        monitor.start()
        self.usbMonitor = monitor
    }
    
    @MainActor
    private func handleDeviceConnection(entryID: UInt64, productID: UInt16) {
        // Check if already connected
        if connectedDevices.contains(where: { $0.id == entryID }) {
            AppLogger.usb.info("Device \(entryID) already managed, ignoring re-connection event")
            return
        }

        AppLogger.usb.info("New device detected (ID: \(entryID))")

        let newController = DeviceController(entryID: entryID)
        connectedDevices.append(newController)

        // Initiate connection, then upsert recording source
        Task { [weak self] in
            await newController.connect()

            // After successful connection, upsert the recording source
            if newController.isConnected, let info = newController.connectionInfo {
                do {
                    let source = try await self?.recordingSourceService?.ensureSourceForDevice(
                        serialNumber: info.serialNumber,
                        model: info.model.rawValue,
                        displayName: info.model.displayName
                    )
                    newController.recordingSourceId = source?.id
                    newController.recordingSourceDirectory = source?.directory
                    AppLogger.usb.info("Linked device \(entryID) to recording source \(source?.id ?? 0)")
                } catch {
                    AppLogger.usb.error("Failed to upsert recording source for device \(entryID): \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    private func handleDeviceDisconnection(entryID: UInt64) {
        guard let index = connectedDevices.firstIndex(where: { $0.id == entryID }) else {
            AppLogger.usb.info("Device \(entryID) disconnected but not found in manager")
            return
        }
        
        let controller = connectedDevices[index]
        AppLogger.usb.info("Device \(entryID) disconnected, removing controller")
        
        // Remove from list immediately to update UI
        connectedDevices.remove(at: index)
        
        // Cleanup controller resources
        Task {
            await controller.disconnect()
        }
    }
    
    // MARK: - Debug/Simulation
    
    #if DEBUG
    @MainActor
    func simulateDeviceConnection() {
        // Simulate a P1 connection with a random ID
        let fakeID = UInt64.random(in: 1000...9999)
        handleDeviceConnection(entryID: fakeID, productID: 45070)
    }
    #endif
}


@Observable
final class DeviceController: Identifiable, DeviceFileProvider, Equatable {
    // MARK: - Properties
    
    static func == (lhs: DeviceController, rhs: DeviceController) -> Bool {
        lhs.id == rhs.id
    }
    
    let id: UInt64
    let driver: JensenActor
    
    var connectionState: ConnectionState = .disconnected
    var connectionInfo: DeviceConnectionInfo?
    var batteryInfo: DeviceBatteryInfo?
    var storageInfo: DeviceStorageInfo?
    var lastError: String?
    var recordingSourceId: Int64?
    var recordingSourceDirectory: String?


    
    // Derived properties
    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }
    
    var displayName: String {
        return connectionInfo?.model.displayName ?? "Unknown Device"
    }
    
    // Internal
    private var batteryPollingTask: Task<Void, Never>?
    private let maxRetryAttempts = 3
    private let retryDelaySeconds: [Double] = [1.0, 2.0, 4.0]
    private let operationRetryAttempts = 3
    private let operationRetryDelays: [Double] = [0.5, 1.0, 2.0]
    
    // MARK: - Enums
    
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
    
    init(entryID: UInt64) {
        self.id = entryID
        // Initialize Jensen with specific transport ID
        let transport = USBTransport(entryID: entryID)
        self.driver = JensenActor(transport: transport)
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.stopBatteryPolling()
        }
        Task { [driver] in
            await driver.disconnect()
        }
    }
    
    // MARK: - Connection
    
    @MainActor
    func connect() async {
        for attempt in 1...maxRetryAttempts {
            connectionState = .connecting(attempt: attempt, maxAttempts: maxRetryAttempts)
            
            do {
                let info = try await driver.connect()
                self.connectionInfo = info
                self.connectionState = .connected
                
                // Post-connection setup
                await refreshStorageInfo()
                if info.supportsBattery {
                    startBatteryPolling()
                }
                return // Success
            } catch {
                self.lastError = error.localizedDescription
                AppLogger.usb.warning("Connection attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < maxRetryAttempts {
                    let delay = (attempt - 1 < retryDelaySeconds.count) ? retryDelaySeconds[attempt - 1] : 4.0
                    try? await Task.sleep(for: .seconds(delay))
                } else {
                    // Final failure
                    let reason: ConnectionFailureReason
                    let errorStr = error.localizedDescription.lowercased()
                    if errorStr.contains("busy") || errorStr.contains("exclusive") {
                        reason = .deviceBusy
                    } else if errorStr.contains("timeout") {
                        reason = .timeout
                    } else {
                        reason = .communicationError(error.localizedDescription)
                    }
                    self.connectionState = .connectionFailed(reason: reason)
                }
            }
        }
    }
    
    @MainActor
    func disconnect() async {
        stopBatteryPolling()
        await driver.disconnect()
        connectionState = .disconnected
        connectionInfo = nil
        batteryInfo = nil
    }
    
    // MARK: - Operations
    
    @MainActor
    func refreshStorageInfo() async {
        do {
            let (total, free) = try await driver.getStorageInfo()
            let used = total - free
            storageInfo = DeviceStorageInfo(totalBytes: total, usedBytes: used)
        } catch {
            print("Failed to refresh storage: \(error)")
        }
    }
    
    func listFiles() async throws -> [DeviceFileInfo] {
        // Retry logic for file listing which can timeout if device is busy
        var lastError: Error?
        
        for attempt in 1...operationRetryAttempts {
            do {
                return try await driver.listFiles()
            } catch {
                lastError = error
                AppLogger.usb.warning("List files attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < operationRetryAttempts {
                    let delay = (attempt - 1 < operationRetryDelays.count) ? operationRetryDelays[attempt - 1] : 2.0
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        
        throw lastError ?? DeviceServiceError.notConnected
    }
    
    func downloadFile(filename: String, expectedSize: Int, toPath: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try await driver.downloadFile(filename: filename, expectedSize: expectedSize, toPath: toPath, progress: progress)
    }
    
    func deleteFile(filename: String) async throws {
        try await driver.deleteFile(filename: filename)
    }
    
    // MARK: - Battery
    
    @MainActor
    private func startBatteryPolling() {
        stopBatteryPolling()
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
        Task {
            do {
                let status = try await driver.getBatteryStatus()
                self.batteryInfo = status
            } catch {
                if case DeviceServiceError.notConnected = error {
                    stopBatteryPolling()
                }
            }
        }
    }
}

enum DeviceServiceError: Error {
    case notConnected
}
