import Foundation

public struct DeviceInfo {
    public let versionCode: String
    public let versionNumber: UInt32
    public let serialNumber: String
}

public struct DeviceTime {
    public let timeString: String  // "YYYY-MM-DD HH:mm:ss" or "unknown"
}

public struct FileCount {
    public let count: Int
}

public struct DeviceSettings {
    public let autoRecord: Bool
    public let autoPlay: Bool
    public let notification: Bool
    public let bluetoothTone: Bool
}

public struct CardInfo {
    public let used: UInt64
    public let capacity: UInt64
    public let status: String
}

public struct BatteryStatus {
    public let status: String  // "idle", "charging", "full"
    public let percentage: Int
    public let voltage: UInt32
}

public struct ScannedDevice {
    public let name: String
    public let mac: String
    public let rssi: Int
    public let cod: UInt32
    public let audio: Bool
}

public struct RecordingFile {
    public let name: String
    public let createDate: String
    public let createTime: String
}

public struct FileEntry {
    public let name: String
    public let createDate: String
    public let createTime: String
    public let duration: TimeInterval
    public let version: UInt8
    public let length: UInt32
    public let mode: String
    public let signature: String
    public let date: Date?
}

public struct PairedDevice {
    public let name: String
    public let mac: String
    public let sequence: UInt8
}
