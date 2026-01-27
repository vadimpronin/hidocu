// Jensen Protocol Handler
// Port of JavaScript Jensen class - handles communication with HiDock devices

import Foundation

// MARK: - Jensen Errors

enum JensenError: Error, LocalizedError {
    case notConnected
    case commandTimeout
    case commandFailed(String)
    case invalidResponse
    case deviceBusy
    case unsupportedFeature(String)
    case unsupportedDevice
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Device not connected"
        case .commandTimeout: return "Command timed out"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .invalidResponse: return "Invalid response from device"
        case .deviceBusy: return "Device is busy"
        case .unsupportedFeature(let msg): return "Unsupported feature: \(msg)"
        case .unsupportedDevice: return "This command is not supported on this device model"
        }
    }
}

// MARK: - Response Types

struct DeviceInfo {
    let versionCode: String
    let versionNumber: UInt32
    let serialNumber: String
}

struct DeviceTime {
    let timeString: String  // "YYYY-MM-DD HH:mm:ss" or "unknown"
}

struct FileCount {
    let count: Int
}

struct DeviceSettings {
    let autoRecord: Bool
    let autoPlay: Bool
    let notification: Bool
    let bluetoothTone: Bool
}

struct CardInfo {
    let used: UInt64
    let capacity: UInt64
    let status: String
}

struct BatteryStatus {
    let status: String  // "idle", "charging", "full"
    let percentage: Int
    let voltage: UInt32
}

struct RecordingFile {
    let name: String
    let createDate: String
    let createTime: String
}

struct FileEntry {
    let name: String
    let createDate: String
    let createTime: String
    let duration: TimeInterval
    let version: UInt8
    let length: UInt32
    let mode: String
    let signature: String
    let date: Date?
}

// MARK: - Jensen

class Jensen {
    private var device: USBDevice?
    private var sequenceIndex: UInt32 = UInt32(Date().timeIntervalSince1970)
    private var receiveBuffer = Data()
    private let verbose: Bool
    
    // Cached device info
    private(set) var versionCode: String?
    private(set) var versionNumber: UInt32?
    private(set) var serialNumber: String?
    private(set) var model: HiDockModel = .unknown
    
    // State flags
    private(set) var isLiveMode: Bool = false
    private(set) var isFileListing: Bool = false
    
    init(verbose: Bool = false) {
        self.verbose = verbose
    }
    
    // MARK: - Connection
    
    func connect() throws {
        device = try USBDevice.findDevice()
        try device?.open()
        model = device?.model ?? .unknown
        
        if verbose {
            print("[Jensen] Connected to \(model.rawValue) (PID: \(device?.productID ?? 0))")
        }
    }
    
    func disconnect() {
        device?.close()
        device = nil
        versionCode = nil
        versionNumber = nil
        serialNumber = nil
    }
    
    var isConnected: Bool {
        device?.isOpen ?? false
    }
    
    // MARK: - Command Execution
    
    private func nextSequence() -> UInt32 {
        sequenceIndex += 1
        return sequenceIndex
    }
    
    private func send(_ command: inout Command, timeout: TimeInterval = 5.0) throws -> Message {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        command.setSequence(nextSequence())
        let packet = command.makePacket()
        
        if verbose {
            print("[Jensen] Sending command: \(command.id.name) (seq: \(command.sequence), \(packet.count) bytes)")
        }
        
        // Send command
        try device.transferOut(endpoint: 1, data: packet)
        
        // Receive response with retry
        receiveBuffer.removeAll()
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            do {
                let chunk = try device.transferIn(endpoint: 2, length: 512 * 1024, timeout: UInt32(timeout * 1000))
                receiveBuffer.append(chunk)
                
                // Try to parse response
                if let (message, _) = MessageParser.parse(receiveBuffer) {
                    if message.id == command.id.rawValue {
                        if verbose {
                            print("[Jensen] Received response: \(command.id.name) (\(message.body.count) bytes)")
                        }
                        return message
                    }
                }
            } catch USBError.timeout {
                // Continue retrying until deadline
                continue
            } catch {
                throw error
            }
        }
        
        throw JensenError.commandTimeout
    }
    
    // MARK: - Device Info Commands
    
    func getDeviceInfo() throws -> DeviceInfo {
        var command = Command(.queryDeviceInfo)
        let response = try send(&command)
        
        // At minimum we need 4 bytes for version
        guard response.body.count >= 4 else {
            throw JensenError.invalidResponse
        }
        
        // Parse version: 4 bytes
        var versionParts: [String] = []
        var versionNum: UInt32 = 0
        for i in 0..<4 {
            let byte = response.body[i]
            if i > 0 {
                versionParts.append(String(byte))
            }
            versionNum |= UInt32(byte) << (8 * (3 - i))
        }
        
        // Parse serial number: up to 16 bytes (or end of body)
        var snBytes: [UInt8] = []
        let snEnd = min(20, response.body.count)
        for i in 4..<snEnd {
            let byte = response.body[i]
            if byte > 0 {
                snBytes.append(byte)
            }
        }
        let sn = String(bytes: snBytes, encoding: .utf8) ?? ""
        
        // Cache values
        self.versionCode = versionParts.joined(separator: ".")
        self.versionNumber = versionNum
        self.serialNumber = sn
        
        return DeviceInfo(
            versionCode: versionParts.joined(separator: "."),
            versionNumber: versionNum,
            serialNumber: sn
        )
    }
    
    func getTime() throws -> DeviceTime {
        var command = Command(.queryDeviceTime)
        let response = try send(&command)
        
        guard response.body.count >= 7 else {
            throw JensenError.invalidResponse
        }
        
        // Parse BCD time
        var bcdBytes: [UInt8] = []
        for i in 0..<7 {
            bcdBytes.append(response.body[i])
        }
        
        let timeString = BCDConverter.fromBCD(bcdBytes)
        
        if timeString == "00000000000000" {
            return DeviceTime(timeString: "unknown")
        }
        
        // Format as YYYY-MM-DD HH:mm:ss
        let formatted = timeString.replacingOccurrences(
            of: #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$"#,
            with: "$1-$2-$3 $4:$5:$6",
            options: .regularExpression
        )
        
        return DeviceTime(timeString: formatted)
    }
    
    /// Set device time
    /// - Parameter date: The date to set (defaults to current system time)
    func setTime(_ date: Date = Date()) throws {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Format date as YYYYMMDDHHmmss
        let dateString = BCDConverter.formatDate(date)
        
        if verbose {
            print("[Jensen] Setting time to: \(dateString)")
        }
        
        // Convert to BCD
        let bcdBytes = BCDConverter.toBCD(dateString)
        
        var command = Command(.setDeviceTime, body: bcdBytes)
        let response = try send(&command, timeout: 5.0)
        
        if verbose {
            print("[Jensen] Set time response: \(response.body.count) bytes")
        }
    }
    
    func getFileCount() throws -> FileCount {
        var command = Command(.queryFileCount)
        let response = try send(&command)
        
        if response.body.isEmpty {
            return FileCount(count: 0)
        }
        
        guard response.body.count >= 4 else {
            throw JensenError.invalidResponse
        }
        
        let count = Int(response.body[0]) << 24 |
                   Int(response.body[1]) << 16 |
                   Int(response.body[2]) << 8 |
                   Int(response.body[3])
        
        return FileCount(count: count)
    }
    
    func getSettings() throws -> DeviceSettings {
        // Check version requirement
        if let version = versionNumber {
            if (model == .h1 || model == .h1e) && version < 0x00050012 {
                return DeviceSettings(autoRecord: false, autoPlay: false, notification: false, bluetoothTone: true)
            }
        }
        
        var command = Command(.getSettings)
        let response = try send(&command)
        
        guard response.body.count >= 16 else {
            throw JensenError.invalidResponse
        }
        
        return DeviceSettings(
            autoRecord: response.body[3] == 1,
            autoPlay: response.body[7] == 1,
            notification: response.body.count >= 12 ? response.body[11] == 1 : false,
            bluetoothTone: response.body[15] != 1  // Inverted logic!
        )
    }
    
    /// Set auto-record setting
    func setAutoRecord(_ enabled: Bool) throws {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Body: [0, 0, 0, <1|2>] where 1=on, 2=off
        let body: [UInt8] = [0, 0, 0, enabled ? 1 : 2]
        var command = Command(.setSettings, body: body)
        _ = try send(&command, timeout: 5.0)
        
        if verbose {
            print("[Jensen] Set auto-record: \(enabled ? "ON" : "OFF")")
        }
    }
    
    /// Set auto-play setting
    func setAutoPlay(_ enabled: Bool) throws {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Body: [0, 0, 0, 0, 0, 0, 0, <1|2>]
        let body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, enabled ? 1 : 2]
        var command = Command(.setSettings, body: body)
        _ = try send(&command, timeout: 5.0)
        
        if verbose {
            print("[Jensen] Set auto-play: \(enabled ? "ON" : "OFF")")
        }
    }
    
    /// Set notification setting
    func setNotification(_ enabled: Bool) throws {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Body: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, <1|2>]
        let body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, enabled ? 1 : 2]
        var command = Command(.setSettings, body: body)
        _ = try send(&command, timeout: 5.0)
        
        if verbose {
            print("[Jensen] Set notification: \(enabled ? "ON" : "OFF")")
        }
    }
    
    /// Set Bluetooth tone setting
    /// Note: Has inverted protocol logic (2=on, 1=off)
    func setBluetoothTone(_ enabled: Bool) throws {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Body: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, <2|1>] - inverted!
        let body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, enabled ? 2 : 1]
        var command = Command(.setSettings, body: body)
        _ = try send(&command, timeout: 5.0)
        
        if verbose {
            print("[Jensen] Set Bluetooth tone: \(enabled ? "ON" : "OFF")")
        }
    }
    

    
    func getCardInfo() throws -> CardInfo {
        // Check version requirement
        if let version = versionNumber, (model == .h1 || model == .h1e) && version < 0x00050025 {
            throw JensenError.unsupportedFeature("Firmware too old")
        }
        
        var command = Command(.readCardInfo)
        let response = try send(&command)
        
        guard response.body.count >= 12 else {
            throw JensenError.invalidResponse
        }
        
        var offset = 0
        // Value is in MB, convert to Bytes
        let freeMB = UInt64(response.body[offset]) << 24 |
                     UInt64(response.body[offset + 1]) << 16 |
                     UInt64(response.body[offset + 2]) << 8 |
                     UInt64(response.body[offset + 3])
        offset += 4
        
        let capacityMB = UInt64(response.body[offset]) << 24 |
                         UInt64(response.body[offset + 1]) << 16 |
                         UInt64(response.body[offset + 2]) << 8 |
                         UInt64(response.body[offset + 3])
        offset += 4
        
        let statusNum = UInt32(response.body[offset]) << 24 |
                       UInt32(response.body[offset + 1]) << 16 |
                       UInt32(response.body[offset + 2]) << 8 |
                       UInt32(response.body[offset + 3])
        
        // Calculate used space (Capacity - Free)
        let usedMB = capacityMB > freeMB ? capacityMB - freeMB : 0
        
        return CardInfo(
            used: usedMB * 1024 * 1024,
            capacity: capacityMB * 1024 * 1024,
            status: String(format: "0x%08X", statusNum)
        )
    }
    
    func deleteFile(name: String) throws {
        // Build command body: filename as ASCII bytes
        var filenameBytes: [UInt8] = []
        for char in name.utf8 {
            filenameBytes.append(char)
        }
        
        var command = Command(.deleteFile, body: filenameBytes)
        _ = try send(&command, timeout: 5.0)
        
        if verbose {
            print("[Jensen] Deleted file: \(name)")
        }
    }
    
    func getBatteryStatus() throws -> BatteryStatus {
        guard model.isP1 else {
            throw JensenError.unsupportedFeature("Battery status only available on P1 models")
        }
        
        var command = Command(.getBatteryStatus)
        let response = try send(&command)
        
        guard response.body.count >= 6 else {
            throw JensenError.invalidResponse
        }
        
        let statusByte = response.body[0]
        let status: String
        switch statusByte {
        case 0: status = "idle"
        case 1: status = "charging"
        case 2: status = "full"
        default: status = "unknown"
        }
        
        let percentage = Int(response.body[1])
        
        let voltage = UInt32(response.body[2]) << 24 |
                     UInt32(response.body[3]) << 16 |
                     UInt32(response.body[4]) << 8 |
                     UInt32(response.body[5])
        
        return BatteryStatus(status: status, percentage: percentage, voltage: voltage)
    }
    
    func enterMassStorage() throws {
        var command = Command(.enterMassStorage)
        
        // This command causes the device to disconnect/reboot into mass storage mode.
        // It may not send a response, or the response might be interrupted.
        do {
            _ = try send(&command, timeout: 2.0)
        } catch {
            // Log but don't fail if it's a timeout/disconnection, as that's expected
            if verbose {
                print("[Jensen] Mass storage switch initiated (error ignored: \(error))")
            }
        }
    }
    
    func getRecordingFile() throws -> RecordingFile? {
        // Check version requirement
        if let version = versionNumber, (model == .h1 || model == .h1e) && version < 0x00050025 {
            throw JensenError.unsupportedFeature("Firmware too old")
        }
        
        var command = Command(.getRecordingFile)
        let response = try send(&command)
        
        if response.body.isEmpty {
            return nil
        }
        
        // Parse filename
        var nameBytes: [UInt8] = []
        for byte in response.body {
            if byte > 0 {
                nameBytes.append(byte)
            }
        }
        
        guard !nameBytes.isEmpty, let name = String(bytes: nameBytes, encoding: .utf8) else {
            return nil
        }
        
        // Parse date/time from filename
        let (date, time, _) = parseFileName(name)
        
        return RecordingFile(name: name, createDate: date, createTime: time)
    }
    
    // MARK: - Bluetooth Commands (P1 only)
    
    func getBluetoothStatus() throws -> [String: Any]? {
        guard model.isP1 else {
            throw JensenError.unsupportedFeature("Bluetooth only available on P1 models")
        }
        
        if isLiveMode {
            return nil
        }
        
        var command = Command(.bluetoothStatus)
        let response = try send(&command)
        
        if response.body.isEmpty {
            return ["status": "disconnected"]
        }
        
        let statusByte = response.body[0]
        
        switch statusByte {
        case 1: return ["status": "disconnected"]
        case 2: return ["status": "scanning"]
        case 3: return ["status": "connecting"]
        default: break
        }
        
        // Connected - parse more details
        guard response.body.count >= 3 else {
            return ["status": "connected"]
        }
        
        let nameLength = Int(response.body[1]) << 8 | Int(response.body[2])
        var offset = 3
        
        var nameBytes: [UInt8] = []
        for i in 0..<nameLength {
            if offset + i >= response.body.count { break }
            nameBytes.append(response.body[offset + i])
        }
        offset += nameLength
        
        let name = String(bytes: nameBytes, encoding: .utf8) ?? "Unknown"
        
        // Parse MAC address
        var macParts: [String] = []
        for i in 0..<6 {
            if offset + i >= response.body.count { break }
            macParts.append(String(format: "%02X", response.body[offset + i]))
        }
        offset += 6
        
        var result: [String: Any] = [
            "status": "connected",
            "name": name,
            "mac": macParts.joined(separator: "-")
        ]
        
        if offset + 4 <= response.body.count {
            result["a2dp"] = response.body[offset] == 1
            result["hfp"] = response.body[offset + 1] == 1
            result["avrcp"] = response.body[offset + 2] == 1
            result["battery"] = Int(Double(response.body[offset + 3]) / 255.0 * 100)
        }
        
        return result
    }
    
    // MARK: - Paired Devices
    
    struct PairedDevice {
        let name: String
        let mac: String
        let sequence: UInt8
    }
    
    /// Get list of paired Bluetooth devices (P1/P1 Mini only)
    func getPairedDevices() throws -> [PairedDevice] {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // P1/P1 Mini only
        guard model == .p1 || model == .p1Mini else {
            throw JensenError.unsupportedDevice
        }
        
        var command = Command(.btGetPairedDevList)
        let response = try send(&command, timeout: 5.0)
        
        guard response.body.count >= 2 else {
            return []
        }
        
        // Parse device count
        let deviceCount = Int(response.body[0]) << 8 | Int(response.body[1])
        
        if verbose {
            print("[Jensen] Paired device count: \(deviceCount)")
        }
        
        var devices: [PairedDevice] = []
        var offset = 2
        
        for i in 0..<deviceCount {
            guard offset + 2 <= response.body.count else { break }
            
            // Name length
            let nameLength = Int(response.body[offset]) << 8 | Int(response.body[offset + 1])
            offset += 2
            
            guard offset + nameLength <= response.body.count else { break }
            
            // Name
            let nameData = response.body[offset..<(offset + nameLength)]
            let name = String(data: Data(nameData), encoding: .utf8) ?? "Unknown"
            offset += nameLength
            
            guard offset + 6 <= response.body.count else { break }
            
            // MAC address (6 bytes)
            var macParts: [String] = []
            for j in 0..<6 {
                macParts.append(String(format: "%02X", response.body[offset + j]))
            }
            offset += 6
            
            guard offset < response.body.count else { break }
            
            // Sequence number
            let sequence = response.body[offset]
            offset += 1
            
            // Filter out placeholder names
            if !name.hasPrefix("UUUU") {
                devices.append(PairedDevice(name: name, mac: macParts.joined(separator: "-"), sequence: sequence))
                
                if verbose {
                    print("[Jensen] Paired device \(i): \(name) (\(macParts.joined(separator: "-"))) seq=\(sequence)")
                }
            }
        }
        
        return devices
    }
    
    // MARK: - File Listing
    
    func listFiles() throws -> [FileEntry] {
        isFileListing = true
        defer { isFileListing = false }
        
        // Get file count first for older firmwares
        var expectedCount: Int? = nil
        if let version = versionNumber, version <= 0x0005001A {
            let count = try getFileCount()
            if verbose {
                print("[Jensen] File count for old firmware: \(count.count)")
            }
            if count.count == 0 {
                return []
            }
            expectedCount = count.count
        }
        
        var command = Command(.queryFileList)
        
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        command.setSequence(nextSequence())
        let packet = command.makePacket()
        
        if verbose {
            print("[Jensen] Sending file list command")
        }
        
        try device.transferOut(endpoint: 1, data: packet)
        
        // Collect all response chunks
        var allData = Data()
        let deadline = Date().addingTimeInterval(30.0)  // 30s timeout for file listing
        
        while Date() < deadline {
            do {
                let chunk = try device.transferIn(endpoint: 2, length: 512 * 1024, timeout: 5000)
                allData.append(chunk)
                
                if verbose {
                    print("[Jensen] Received chunk: \(chunk.count) bytes, total: \(allData.count)")
                }
                
                // Check if we have a complete response
                if let files = parseFileList(allData, expectedCount: expectedCount) {
                    if verbose {
                        print("[Jensen] Parsed \(files.count) files")
                    }
                    return files
                }
            } catch USBError.timeout {
                if verbose {
                    print("[Jensen] Timeout, allData size: \(allData.count)")
                }
                // If we have data and timed out, try to parse what we have
                if !allData.isEmpty {
                    if let files = parseFileList(allData, expectedCount: expectedCount) {
                        return files
                    }
                }
                break
            } catch {
                throw error
            }
        }
        
        // Final attempt to parse
        return parseFileList(allData, expectedCount: nil) ?? []
    }
    
    // MARK: - File Download
    
    /// Download a file from the device
    /// - Parameters:
    ///   - filename: Name of the file to download
    ///   - expectedSize: Expected size of the file in bytes
    ///   - progressHandler: Optional callback for progress updates (bytesReceived, totalBytes)
    /// - Returns: The downloaded file data
    func downloadFile(filename: String, expectedSize: UInt32, progressHandler: ((Int, Int) -> Void)? = nil) throws -> Data {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Build command body: filename as ASCII bytes
        var filenameBytes: [UInt8] = []
        for char in filename.utf8 {
            filenameBytes.append(char)
        }
        
        var command = Command(.transferFile, body: filenameBytes)
        command.setSequence(nextSequence())
        let packet = command.makePacket()
        
        if verbose {
            print("[Jensen] Downloading file: \(filename) (expected \(expectedSize) bytes)")
        }
        
        // Send download command
        try device.transferOut(endpoint: 1, data: packet)
        
        // Receive file data chunks
        var fileData = Data()
        let deadline = Date().addingTimeInterval(120.0)  // 2 minute timeout for large files
        var lastProgress = 0
        
        while Date() < deadline {
            do {
                let chunk = try device.transferIn(endpoint: 2, length: 512 * 1024, timeout: 5000)
                
                // Parse message(s) from chunk and extract body data
                var offset = 0
                while offset + 12 <= chunk.count {
                    // Check for message header
                    if chunk[offset] == 0x12 && chunk[offset + 1] == 0x34 {
                        // Parse body length
                        let lengthField = UInt32(chunk[offset + 8]) << 24 |
                                         UInt32(chunk[offset + 9]) << 16 |
                                         UInt32(chunk[offset + 10]) << 8 |
                                         UInt32(chunk[offset + 11])
                        
                        let bodyLength = Int(lengthField & 0x00FFFFFF)
                        let padding = Int((lengthField >> 24) & 0xFF)
                        
                        let bodyStart = offset + 12
                        let bodyEnd = bodyStart + bodyLength
                        
                        if bodyEnd <= chunk.count {
                            fileData.append(chunk[bodyStart..<bodyEnd])
                            offset = bodyEnd + padding
                        } else {
                            break
                        }
                    } else {
                        // Not a message header - might be raw data
                        fileData.append(chunk[offset...])
                        break
                    }
                }
                
                // Progress reporting
                let progress = Int(Double(fileData.count) / Double(expectedSize) * 100)
                if progress > lastProgress && progress % 5 == 0 {
                    progressHandler?(fileData.count, Int(expectedSize))
                    lastProgress = progress
                }
                
                if verbose && progress > lastProgress {
                    print("[Jensen] Download progress: \(fileData.count) / \(expectedSize) bytes (\(progress)%)")
                    lastProgress = progress
                }
                
                // Check if download complete
                if fileData.count >= expectedSize {
                    if verbose {
                        print("[Jensen] Download complete: \(fileData.count) bytes")
                    }
                    return fileData
                }
                
            } catch USBError.timeout {
                if verbose {
                    print("[Jensen] Timeout during download, retrying... (\(fileData.count) bytes so far)")
                }
                // Continue if we haven't received enough data
                if fileData.count < expectedSize {
                    continue
                }
                break
            } catch {
                throw error
            }
        }
        
        // If we got here but have data, return what we got
        if fileData.count > 0 {
            if verbose {
                print("[Jensen] Download incomplete: got \(fileData.count) of \(expectedSize) bytes")
            }
            return fileData
        }
        
        throw JensenError.commandTimeout
    }
    
    /// Download a partial file range from the device
    /// - Parameters:
    ///   - filename: Name of the file to download
    ///   - offset: Starting byte offset
    ///   - length: Number of bytes to download
    /// - Returns: The downloaded partial data
    func downloadFilePartial(filename: String, offset: UInt32, length: UInt32) throws -> Data {
        guard let device = device, device.isOpen else {
            throw JensenError.notConnected
        }
        
        // Build command body: offset (4) + length (4) + filename
        var body: [UInt8] = []
        
        // Offset (big-endian)
        body.append(UInt8((offset >> 24) & 0xFF))
        body.append(UInt8((offset >> 16) & 0xFF))
        body.append(UInt8((offset >> 8) & 0xFF))
        body.append(UInt8(offset & 0xFF))
        
        // Length (big-endian)
        body.append(UInt8((length >> 24) & 0xFF))
        body.append(UInt8((length >> 16) & 0xFF))
        body.append(UInt8((length >> 8) & 0xFF))
        body.append(UInt8(length & 0xFF))
        
        // Filename
        for char in filename.utf8 {
            body.append(char)
        }
        
        var command = Command(.transferFilePartial, body: body)
        let response = try send(&command, timeout: 30.0)
        
        return response.body
    }
    
    private func parseFileList(_ data: Data, expectedCount: Int?) -> [FileEntry]? {
        // File list comes as multiple message responses concatenated
        // We need to extract the body from each message first
        var bodyData = Data()
        var offset = 0
        
        while offset + 12 <= data.count {
            // Check for message header
            if data[offset] == 0x12 && data[offset + 1] == 0x34 {
                // Parse body length from bytes 8-11 (24-bit length + 8-bit padding)
                let lengthField = UInt32(data[offset + 8]) << 24 | 
                                 UInt32(data[offset + 9]) << 16 | 
                                 UInt32(data[offset + 10]) << 8 | 
                                 UInt32(data[offset + 11])
                
                let bodyLength = Int(lengthField & 0x00FFFFFF)
                let padding = Int((lengthField >> 24) & 0xFF)
                
                let bodyStart = offset + 12
                let bodyEnd = bodyStart + bodyLength
                
                if bodyEnd <= data.count {
                    bodyData.append(data[bodyStart..<bodyEnd])
                    offset = bodyEnd + padding
                    if verbose {
                        print("[Jensen] Extracted message body: \(bodyLength) bytes, total body: \(bodyData.count)")
                    }
                } else {
                    // Incomplete message
                    break
                }
            } else {
                // Not a message header, treat rest as raw body data
                bodyData.append(data[offset...])
                break
            }
        }
        
        if bodyData.isEmpty {
            return nil
        }
        
        if verbose && bodyData.count >= 10 {
            let hexBytes = bodyData.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[Jensen] Body first 20 bytes: \(hexBytes)")
        }
        
        var fileOffset = 0
        var files: [FileEntry] = []
        var totalCount: Int? = expectedCount
        
        // Check for count header (0xFF 0xFF prefix)
        if bodyData.count >= fileOffset + 6 {
            if bodyData[fileOffset] == 0xFF && bodyData[fileOffset + 1] == 0xFF {
                totalCount = Int(bodyData[fileOffset + 2]) << 24 |
                            Int(bodyData[fileOffset + 3]) << 16 |
                            Int(bodyData[fileOffset + 4]) << 8 |
                            Int(bodyData[fileOffset + 5])
                if verbose {
                    print("[Jensen] Count header found: \(totalCount ?? 0) files")
                }
                fileOffset += 6
            }
        }
        
        // Parse file entries
        var debugCount = 0
        while fileOffset < bodyData.count {
            guard fileOffset + 4 < bodyData.count else { 
                if verbose {
                    print("[Jensen] Breaking: fileOffset \(fileOffset) + 4 >= bodyData.count \(bodyData.count)")
                }
                break 
            }
            
            let version = bodyData[fileOffset]
            fileOffset += 1
            
            let nameLength = Int(bodyData[fileOffset]) << 16 |
                            Int(bodyData[fileOffset + 1]) << 8 |
                            Int(bodyData[fileOffset + 2])
            fileOffset += 3
            
            if verbose && debugCount < 3 {
                print("[Jensen] File \(debugCount): version=\(version), nameLength=\(nameLength), offset=\(fileOffset)")
            }
            
            guard fileOffset + nameLength + 4 + 6 + 16 <= bodyData.count else { 
                if verbose {
                    print("[Jensen] Breaking: need \(fileOffset + nameLength + 4 + 6 + 16), have \(bodyData.count)")
                }
                break 
            }
            
            // Read filename
            var nameBytes: [UInt8] = []
            for i in 0..<nameLength {
                let byte = bodyData[fileOffset + i]
                if byte > 0 {
                    nameBytes.append(byte)
                }
            }
            fileOffset += nameLength
            
            let name = String(bytes: nameBytes, encoding: .utf8) ?? ""
            
            if verbose && debugCount < 3 {
                print("[Jensen] File \(debugCount): name='\(name)'")
                debugCount += 1
            }
            
            // Read file size
            let fileSize = UInt32(bodyData[fileOffset]) << 24 |
                          UInt32(bodyData[fileOffset + 1]) << 16 |
                          UInt32(bodyData[fileOffset + 2]) << 8 |
                          UInt32(bodyData[fileOffset + 3])
            fileOffset += 4
            
            // Skip reserved bytes
            fileOffset += 6
            
            // Read MD5 signature
            var sigParts: [String] = []
            for i in 0..<16 {
                sigParts.append(String(format: "%02x", bodyData[fileOffset + i]))
            }
            fileOffset += 16
            
            // Parse date/time from filename
            let (dateStr, timeStr, dateObj) = parseFileName(name)
            
            // Calculate duration based on version (result in milliseconds converted to seconds)
            var duration: TimeInterval = 0
            switch version {
            case 1: duration = Double(fileSize) / 32.0 / 1000.0
            case 2: duration = Double(fileSize - 44) / 48.0 / 2.0 / 1000.0
            case 3: duration = Double(fileSize - 44) / 48.0 / 2.0 / 2.0 / 1000.0
            case 5: duration = Double(fileSize) / 12.0 / 1000.0
            case 6: duration = Double(fileSize) / 16.0 / 1000.0
            case 7: duration = Double(fileSize) / 10.0 / 1000.0
            default: duration = Double(fileSize) / 32.0 / 1000.0
            }
            
            // Detect mode from filename
            var mode = "room"
            if let match = name.range(of: #"-(\w+)\d+\.\w+$"#, options: .regularExpression) {
                let modeStr = String(name[match]).uppercased()
                if modeStr.contains("WHSP") || modeStr.contains("WIP") {
                    mode = "whisper"
                } else if modeStr.contains("CALL") {
                    mode = "call"
                } else if modeStr.contains("REC") {
                    mode = "room"
                }
            }
            
            if !name.isEmpty {
                files.append(FileEntry(
                    name: name,
                    createDate: dateStr,
                    createTime: timeStr,
                    duration: duration,
                    version: version,
                    length: fileSize,
                    mode: mode,
                    signature: sigParts.joined(),
                    date: dateObj
                ))
            }
        }
        
        if verbose {
            print("[Jensen] Parsed \(files.count) files, expected \(totalCount ?? -1)")
        }
        
        // Check if we have all files
        if let total = totalCount {
            if files.count >= total {
                return files
            }
            return nil  // Need more data
        }
        
        return files.isEmpty ? nil : files
    }
    
    private func parseFileName(_ name: String) -> (date: String, time: String, dateObj: Date?) {
        // Pattern 1: YYYYMMDDHHMMSSREC###.wav
        if let match = name.range(of: #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})REC"#, options: .regularExpression) {
            let matched = String(name[match])
            if matched.count >= 14 {
                let chars = Array(matched)
                let dateStr = "\(chars[0...3].map{String($0)}.joined())/\(chars[4...5].map{String($0)}.joined())/\(chars[6...7].map{String($0)}.joined())"
                let timeStr = "\(chars[8...9].map{String($0)}.joined()):\(chars[10...11].map{String($0)}.joined()):\(chars[12...13].map{String($0)}.joined())"
                
                let rawDate = "\(chars[0...13].map{String($0)}.joined())"
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMddHHmmss"
                let dateObj = formatter.date(from: rawDate)
                
                return (dateStr, timeStr, dateObj)
            }
        }
        
        // Pattern 2: (YY)YYMMDDDHH-HHMMSS-MODE###.{hda|wav}
        // Matches both 2025Oct09 (4-digit year) and 25Oct09 (2-digit year)
        if let _ = name.range(of: #"^\d{2,4}\w{3}\d{2}-\d{6}-"#, options: .regularExpression) {
            // Parse like "2025Oct09-133426-Rec00.hda" or "23Jan27-143530-ROOM001.hda"
            let components = name.components(separatedBy: "-")
            if components.count >= 2 {
                let datePart = components[0]
                let timePart = components[1]  // "143530"
                
                var dateFormatted = datePart
                var dateObj: Date? = nil
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                if datePart.count == 9 { // YYYYMMMDD
                    let y = datePart.prefix(4)
                    let m = datePart.dropFirst(4).prefix(3)
                    let d = datePart.suffix(2)
                    dateFormatted = "\(y)-\(m)-\(d)"
                    
                    formatter.dateFormat = "yyyyMMMdd-HHmmss"
                    dateObj = formatter.date(from: "\(datePart)-\(timePart)")
                } else if datePart.count == 7 { // YYMMMDD
                    let y = "20" + datePart.prefix(2)
                    let m = datePart.dropFirst(2).prefix(3)
                    let d = datePart.suffix(2)
                    dateFormatted = "\(y)-\(m)-\(d)"
                    
                    formatter.dateFormat = "yyMMMdd-HHmmss"
                    dateObj = formatter.date(from: "\(datePart)-\(timePart)")
                }
                
                if timePart.count >= 6 {
                    let tChars = Array(timePart)
                    let time = "\(tChars[0...1].map{String($0)}.joined()):\(tChars[2...3].map{String($0)}.joined()):\(tChars[4...5].map{String($0)}.joined())"
                    return (dateFormatted, time, dateObj)
                }
            }
        }
        
        return ("", "", nil)
    }
}
