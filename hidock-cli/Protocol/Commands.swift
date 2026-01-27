// Protocol command IDs and Command structure
// Port of JavaScript Command IDs and Command class

import Foundation

// MARK: - Command IDs

enum CommandID: UInt16 {
    case invalid = 0
    case queryDeviceInfo = 1
    case queryDeviceTime = 2
    case setDeviceTime = 3
    case queryFileList = 4
    case transferFile = 5
    case queryFileCount = 6
    case deleteFile = 7
    case requestFirmwareUpgrade = 8
    case firmwareUpload = 9
    case deviceMsgTest = 10  // Also BNC_DEMO_TEST
    case getSettings = 11
    case setSettings = 12
    case getFileBlock = 13
    case readCardInfo = 16
    case formatCard = 17
    case getRecordingFile = 18
    case restoreFactorySettings = 19
    case scheduleInfo = 20
    case transferFilePartial = 21
    case requestToneUpdate = 22
    case toneUpdate = 23
    case requestUACUpdate = 24
    case uacUpdate = 25
    case sendKeyCode = 28
    case realtimeReadSetting = 32
    case realtimeControl = 33
    case realtimeTransfer = 34
    
    // Bluetooth commands
    case bluetoothScan = 4097
    case bluetoothCmd = 4098
    case bluetoothStatus = 4099
    case getBatteryStatus = 4100
    case btScan = 4101
    case btDevList = 4102
    case btGetPairedDevList = 4103
    case btRemovePairedDev = 4104
    
    // Test/Factory commands
    case testSnWrite = 61447
    case recordTestStart = 61448
    case recordTestEnd = 61449
    case factoryReset = 61451
    case enterMassStorage = 61455
    case writeWebusbTimeout = 61456
    case readWebusbTimeout = 61457
    
    var name: String {
        switch self {
        case .invalid: return "invalid"
        case .queryDeviceInfo: return "get-device-info"
        case .queryDeviceTime: return "get-device-time"
        case .setDeviceTime: return "set-device-time"
        case .queryFileList: return "get-file-list"
        case .transferFile: return "transfer-file"
        case .queryFileCount: return "get-file-count"
        case .deleteFile: return "delete-file"
        case .requestFirmwareUpgrade: return "request-firmware-upgrade"
        case .firmwareUpload: return "firmware-upload"
        case .deviceMsgTest: return "device-msg-test"
        case .getSettings: return "get-settings"
        case .setSettings: return "set-settings"
        case .getFileBlock: return "get-file-block"
        case .readCardInfo: return "read-card-info"
        case .formatCard: return "format-card"
        case .getRecordingFile: return "get-recording-file"
        case .restoreFactorySettings: return "restore-factory-settings"
        case .scheduleInfo: return "schedule-info"
        case .transferFilePartial: return "transfer-file-partial"
        case .requestToneUpdate: return "request-tone-update"
        case .toneUpdate: return "tone-update"
        case .requestUACUpdate: return "request-uac-update"
        case .uacUpdate: return "uac-update"
        case .sendKeyCode: return "send-key-code"
        case .realtimeReadSetting: return "realtime-read-setting"
        case .realtimeControl: return "realtime-control"
        case .realtimeTransfer: return "realtime-transfer"
        case .bluetoothScan: return "bluetooth-scan"
        case .bluetoothCmd: return "bluetooth-cmd"
        case .bluetoothStatus: return "bluetooth-status"
        case .getBatteryStatus: return "get-battery-status"
        case .btScan: return "bt-scan"
        case .btDevList: return "bt-dev-list"
        case .btGetPairedDevList: return "bt-get-paired-dev-list"
        case .btRemovePairedDev: return "bt-remove-paired-dev"
        case .testSnWrite: return "test-sn-write"
        case .recordTestStart: return "record-test-start"
        case .recordTestEnd: return "record-test-end"
        case .factoryReset: return "factory-reset"
        case .enterMassStorage: return "enter-mass-storage"
        case .writeWebusbTimeout: return "write-webusb-timeout"
        case .readWebusbTimeout: return "read-webusb-timeout"
        }
    }
}

// MARK: - Command

struct Command {
    let id: CommandID
    var body: [UInt8]
    var sequence: UInt32 = 0
    var expireTime: Date?
    
    init(_ id: CommandID, body: [UInt8] = []) {
        self.id = id
        self.body = body
    }
    
    mutating func setSequence(_ seq: UInt32) {
        self.sequence = seq
    }
    
    mutating func expireAfter(_ seconds: TimeInterval) {
        self.expireTime = Date().addingTimeInterval(seconds)
    }
    
    var isExpired: Bool {
        guard let expireTime = expireTime else { return false }
        return Date() > expireTime
    }
    
    /// Build the packet to send to the device
    /// Format: Header (2) + CommandID (2) + Sequence (4) + Length (4) + Body
    func makePacket() -> Data {
        var packet = Data(capacity: 12 + body.count)
        
        // Header: 0x12 0x34
        packet.append(0x12)
        packet.append(0x34)
        
        // Command ID (big-endian)
        packet.append(UInt8((id.rawValue >> 8) & 0xFF))
        packet.append(UInt8(id.rawValue & 0xFF))
        
        // Sequence number (big-endian)
        packet.append(UInt8((sequence >> 24) & 0xFF))
        packet.append(UInt8((sequence >> 16) & 0xFF))
        packet.append(UInt8((sequence >> 8) & 0xFF))
        packet.append(UInt8(sequence & 0xFF))
        
        // Body length (big-endian, 24-bit + 8-bit reserved)
        let length = UInt32(body.count)
        packet.append(UInt8((length >> 24) & 0xFF))
        packet.append(UInt8((length >> 16) & 0xFF))
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        
        // Body
        packet.append(contentsOf: body)
        
        return packet
    }
}

// MARK: - Message (Response)

struct Message {
    let id: UInt16
    let sequence: UInt32
    let body: Data
    
    var commandID: CommandID? {
        CommandID(rawValue: id)
    }
}

// MARK: - Message Parser

struct MessageParser {
    /// Parse a response message from raw data
    /// Returns (message, bytesConsumed) or nil if incomplete
    static func parse(_ data: Data, offset: Int = 0) -> (Message, Int)? {
        let available = data.count - offset
        
        // Need at least 12 bytes for header
        guard available >= 12 else { return nil }
        
        // Check header
        guard data[offset] == 0x12 && data[offset + 1] == 0x34 else {
            return nil
        }
        
        // Parse command ID
        let commandID = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
        
        // Parse sequence number
        let sequence = UInt32(data[offset + 4]) << 24 |
                      UInt32(data[offset + 5]) << 16 |
                      UInt32(data[offset + 6]) << 8 |
                      UInt32(data[offset + 7])
        
        // Parse body length (24-bit) + padding (8-bit stored in high byte)
        let lengthRaw = UInt32(data[offset + 8]) << 24 |
                       UInt32(data[offset + 9]) << 16 |
                       UInt32(data[offset + 10]) << 8 |
                       UInt32(data[offset + 11])
        
        let padding = (lengthRaw >> 24) & 0xFF
        let bodyLength = Int(lengthRaw & 0x00FFFFFF)
        
        // Check if we have complete message
        let totalLength = 12 + bodyLength + Int(padding)
        guard available >= totalLength else { return nil }
        
        // Extract body
        let bodyStart = offset + 12
        let bodyEnd = bodyStart + bodyLength
        let body = data[bodyStart..<bodyEnd]
        
        let message = Message(id: commandID, sequence: sequence, body: Data(body))
        return (message, totalLength)
    }
}

// MARK: - BCD Utilities

struct BCDConverter {
    /// Convert a date string "YYYYMMDDHHmmss" to BCD bytes
    static func toBCD(_ dateString: String) -> [UInt8] {
        var result: [UInt8] = []
        let chars = Array(dateString)
        
        for i in stride(from: 0, to: chars.count - 1, by: 2) {
            let high = UInt8(String(chars[i]))! & 0x0F
            let low = UInt8(String(chars[i + 1]))! & 0x0F
            result.append((high << 4) | low)
        }
        
        return result
    }
    
    /// Convert BCD bytes to date string
    static func fromBCD(_ bytes: [UInt8]) -> String {
        var result = ""
        for byte in bytes {
            let high = (byte >> 4) & 0x0F
            let low = byte & 0x0F
            result += "\(high)\(low)"
        }
        return result
    }
    
    /// Format a Date to the device time format
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }
    
    /// Parse device time string to Date
    static func parseDeviceTime(_ timeString: String) -> Date? {
        // Format: YYYYMMDDHHmmss -> YYYY-MM-DD HH:mm:ss
        guard timeString.count == 14, timeString != "00000000000000" else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: timeString)
    }
}
