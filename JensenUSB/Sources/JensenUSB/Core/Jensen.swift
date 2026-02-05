import Foundation

public class Jensen {
    // MARK: - Properties
    
    internal let transport: JensenTransport
    public var verbose: Bool = false
    
    /// Unique identifier for the connected device (RegistryEntryID for USB)
    public var uniqueID: UInt64? {
        if let usbTransport = transport as? USBTransport {
            return usbTransport.entryID
        }
        return nil
    }
    
    // Feature Controllers
    public lazy var file: FileController = FileController(core: self)
    public lazy var time: TimeController = TimeController(core: self)
    public lazy var settings: SettingsController = SettingsController(core: self)
    public lazy var bluetooth: BluetoothController = BluetoothController(core: self)
    public lazy var system: SystemController = SystemController(core: self)
    
    // Internal State
    internal var sequence: UInt32 = 0
    internal var suppressKeepAlive: Bool = false
    private var keepAliveTimer: Timer?
    
    // MARK: - Public Information
    
    public var isConnected: Bool {
        return transport.isConnected
    }
    
    public var model: HiDockModel {
        return transport.model
    }
    
    public var versionNumber: UInt32?
    public var versionCode: String?
    public var serialNumber: String?
    
    public var capabilities: DeviceCapability {
        return DeviceCapability(model: model, version: versionNumber ?? 0)
    }
    
    public var isLiveMode: Bool {
        return false 
    }
    
    // MARK: - Initialization
    
    public init(transport: JensenTransport? = nil, verbose: Bool = false) {
        self.transport = transport ?? USBTransport()
        self.verbose = verbose
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection
    
    public func connect() throws {
        if verbose { print("[Jensen] Connecting...") }
        try transport.connect()
        
        // Get device info to populate version/serial
        _ = try getDeviceInfo()
        
        startKeepAlive()
        if verbose { print("[Jensen] Connected to \(model) (v\(versionCode ?? "unknown"))") }
    }
    
    public func disconnect() {
        stopKeepAlive()
        transport.disconnect()
        if verbose { print("[Jensen] Disconnected") }
    }
    
    // MARK: - Command Sending
    
    internal func nextSequence() -> UInt32 {
        sequence &+= 1
        return sequence
    }
    
    internal func send(_ command: inout Command, timeout: TimeInterval = 5.0) throws -> Message {
        guard transport.isConnected else { throw JensenError.notConnected }
        
        command.setSequence(nextSequence())
        let packet = command.makePacket()
        
        if verbose {
            print("[Jensen] Sending command: \(command.id.name) (seq: \(command.sequence))")
        }
        
        try transport.send(data: packet)
        
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let data = try transport.receive(timeout: timeout)
                if let (message, _) = try MessageParser.parse(data) {
                    if message.id == command.id.rawValue {
                        if verbose {
                            print("[Jensen] Received response: \(command.id.name) (seq: \(message.sequence))")
                        }
                        return message
                    } else {
                        if verbose {
                            print("[Jensen] Ignoring unsolicited/mismatched message: ID \(message.id) (seq: \(message.sequence))")
                        }
                        // Continue waiting
                    }
                }
            } catch let error as ProtocolError {
                if verbose { print("[Jensen] Protocol Error: \(error)") }
                if Date() >= deadline { throw JensenError.invalidResponse }
                // Continue waiting
            } catch {
                if Date() >= deadline { throw JensenError.commandTimeout }
                throw JensenError.commandTimeout
            }
        }
        throw JensenError.commandTimeout
    }
    
    // MARK: - Keep Alive
    
    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected, !self.suppressKeepAlive else { return }
            var command = Command(.queryDeviceInfo)
            do {
                _ = try self.send(&command, timeout: 1.0)
            } catch {
                // Ignore error in keepalive
            }
        }
    }
    
    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    // MARK: - Legacy / Wrapper Methods (Deprecated)
    
    public func getDeviceInfo() throws -> DeviceInfo {
        var command = Command(.queryDeviceInfo)
        let response = try send(&command)
        let body = response.body
        // Logic adapted from jensen.js (Jensen.registerHandler(QUERY_DEVICE_INFO))
        // Fixed structure: 4 bytes version + 16 bytes serial number
        guard body.count >= 4 else { throw JensenError.invalidResponse }
        
        // 1. Version Number (4 bytes big-endian)
        let vNum = UInt32(body[0]) << 24 | UInt32(body[1]) << 16 | UInt32(body[2]) << 8 | UInt32(body[3])
        
        // 2. Version Code (bytes 1, 2, 3 joined by dots)
        // jensen.js: loops 0..3, pushes if i > 0
        let verStr = "\(body[1]).\(body[2]).\(body[3])"
        
        // 3. Serial Number (Next 16 bytes, filtering > 0)
        var snStr = "unknown"
        if body.count > 4 {
            let snStart = 4
            let snEnd = min(body.count, 20) // 4 + 16
            let snIsBytes = body[snStart..<snEnd].filter { $0 > 0 }
            if let str = String(data: snIsBytes, encoding: .utf8) {
                snStr = str
            }
        }
        
        self.versionCode = verStr
        self.versionNumber = vNum
        self.serialNumber = snStr
        
        return DeviceInfo(versionCode: verStr, versionNumber: vNum, serialNumber: snStr)
    }
    
    @available(*, deprecated, message: "Use time.get() instead")
    public func getTime() throws -> DeviceTime { return try time.get() }
    
    @available(*, deprecated, message: "Use time.set() instead")
    public func setTime(_ date: Date) throws { try time.set(date) }
    
    @available(*, deprecated, message: "Use file.list() instead")
    public func listFiles() throws -> [FileEntry] { return try file.list() }
    
    @available(*, deprecated, message: "Use file.download() instead")
    public func downloadFile(filename: String, expectedSize: UInt32, progressHandler: ((Int, Int) -> Void)? = nil) throws -> Data {
        return try file.download(filename: filename, expectedSize: expectedSize, progressHandler: progressHandler)
    }
    
    @available(*, deprecated, message: "Use file.delete() instead")
    public func deleteFile(name: String) throws { try file.delete(name: name) }
    
    @available(*, deprecated, message: "Use file.count() instead")
    public func getFileCount() throws -> FileCount { return try file.count() }
    
    @available(*, deprecated, message: "Use file.getRecordingFile() instead")
    public func getRecordingFile() throws -> RecordingFile? { return try file.getRecordingFile() }
    
    @available(*, deprecated, message: "Use settings.get() instead")
    public func getSettings() throws -> DeviceSettings { return try settings.get() }
    
    @available(*, deprecated, message: "Use settings.setAutoRecord() instead")
    public func setAutoRecord(_ enabled: Bool) throws { try settings.setAutoRecord(enabled) }
    
    @available(*, deprecated, message: "Use settings.setAutoPlay() instead")
    public func setAutoPlay(_ enabled: Bool) throws { try settings.setAutoPlay(enabled) }
    
    @available(*, deprecated, message: "Use settings.setNotification() instead")
    public func setNotification(_ enabled: Bool) throws { try settings.setNotification(enabled) }
    
    @available(*, deprecated, message: "Use settings.setBluetoothTone() instead")
    public func setBluetoothTone(_ enabled: Bool) throws { try settings.setBluetoothTone(enabled) }
    
    @available(*, deprecated, message: "Use bluetooth.getStatus() instead")
    public func getBluetoothStatus() throws -> [String: Any]? { return try bluetooth.getStatus() }
    
    @available(*, deprecated, message: "Use bluetooth.getPairedDevices() instead")
    public func getPairedDevices() throws -> [PairedDevice] { return try bluetooth.getPairedDevices() }
    
    @available(*, deprecated, message: "Use bluetooth.startScan() instead")
    public func startBluetoothScan(_ duration: Int = 30) throws { try bluetooth.startScan(duration: duration) }
    
    @available(*, deprecated, message: "Use bluetooth.stopScan() instead")
    public func stopBluetoothScan() throws { try bluetooth.stopScan() }
    
    @available(*, deprecated, message: "Use bluetooth.getScanResults() instead")
    public func getScanResults() throws -> [ScannedDevice] { return try bluetooth.getScanResults() }
    
    @available(*, deprecated, message: "Use bluetooth.connect() instead")
    public func connectBluetooth(mac: String) throws { try bluetooth.connect(mac: mac) }
    
    @available(*, deprecated, message: "Use bluetooth.disconnect() instead")
    public func disconnectBluetooth() throws { try bluetooth.disconnect() }
    
    @available(*, deprecated, message: "Use bluetooth.reconnect() instead")
    public func reconnectBluetooth(mac: String) throws { try bluetooth.reconnect(mac: mac) }
    
    public func clearPairedDevices() throws { try bluetooth.clearPaired() }
    
    // System Helpers
    public func factoryReset() throws { try system.factoryReset() }
    public func restoreFactorySettings() throws { try system.restoreFactorySettings() }
    public func getCardInfo() throws -> CardInfo { return try system.getCardInfo() }
    public func formatCard() throws { try system.formatCard() }
    public func getBatteryStatus() throws -> BatteryStatus { return try system.getBatteryStatus() }
    public func enterMassStorage() throws { try system.enterMassStorage() }
    public func getWebUSBTimeout() throws -> UInt32 { return try system.getWebUSBTimeout() }
    public func setWebUSBTimeout(_ timeout: UInt32) throws { try system.setWebUSBTimeout(timeout) }
    public func requestFirmwareUpgrade(versionNumber: UInt32, fileSize: UInt32) throws -> SystemController.FirmwareUpgradeResult {
        return try system.requestFirmwareUpgrade(versionNumber: versionNumber, fileSize: fileSize)
    }
    public func uploadFirmware(_ data: Data, progressHandler: ((Int, Int) -> Void)? = nil) throws {
        try system.uploadFirmware(data, progressHandler: progressHandler)
    }
    public func requestToneUpdate(signature: String, size: UInt32) throws -> SystemController.FirmwareUpgradeResult {
        return try system.requestToneUpdate(signature: signature, size: size)
    }
    public func updateTone(_ data: Data) throws { try system.updateTone(data) }
    public func requestUACUpdate(signature: String, size: UInt32) throws -> SystemController.FirmwareUpgradeResult {
        return try system.requestUACUpdate(signature: signature, size: size)
    }
    public func updateUAC(_ data: Data) throws { try system.updateUAC(data) }
    public func sendKeyCode(mode: UInt8, keyCode: UInt8) throws { try self.system.sendKeyCode(mode: mode, keyCode: keyCode) }
    public func recordTestStart(type: UInt8) throws { try self.system.recordTestStart(type: type) }
    public func recordTestEnd(type: UInt8) throws { try self.system.recordTestEnd(type: type) }
    public func beginBNC() throws { try self.system.beginBNC() }
    public func endBNC() throws { try self.system.endBNC() }
}
