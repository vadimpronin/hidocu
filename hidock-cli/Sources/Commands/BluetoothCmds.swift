import ArgumentParser
import JensenUSB
import Foundation

struct BTStatus: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-status", abstract: "Get Bluetooth connection status")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        guard let status = try jensen.getBluetoothStatus() else {
            print("Status: unavailable (device busy)")
            return
        }
        
        print("Status: \(status["status"] ?? "unknown")")
        
        if let name = status["name"] as? String {
            print("Device: \(name)")
        }
        if let mac = status["mac"] as? String {
            print("MAC: \(mac)")
        }
        if let a2dp = status["a2dp"] as? Bool {
            print("Profiles:")
            print("  A2DP: \(a2dp ? "Yes" : "No")")
            if let hfp = status["hfp"] as? Bool {
                print("  HFP: \(hfp ? "Yes" : "No")")
            }
            if let avrcp = status["avrcp"] as? Bool {
                print("  AVRCP: \(avrcp ? "Yes" : "No")")
            }
        }
        if let battery = status["battery"] as? Int {
            print("Battery: \(battery)%")
        }
    }
}

struct BTPaired: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-paired", abstract: "List paired Bluetooth devices")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        let devices = try jensen.getPairedDevices()
        
        if devices.isEmpty {
            print("No paired devices.")
            return
        }
        
        print("Paired Devices:")
        print("")
        print("\("Name".padding(toLength: 30, withPad: " ", startingAt: 0)) \("MAC Address".padding(toLength: 20, withPad: " ", startingAt: 0)) Seq")
        print(String(repeating: "-", count: 55))
        
        for device in devices {
            let nameStr = device.name.padding(toLength: 30, withPad: " ", startingAt: 0)
            let macStr = device.mac.padding(toLength: 20, withPad: " ", startingAt: 0)
            print("\(nameStr) \(macStr) \(device.sequence)")
        }
    }
}

struct BTScan: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-scan", abstract: "Scan for nearby Bluetooth devices")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        print("Starting Bluetooth scan...")
        try jensen.startBluetoothScan()
        
        print("Scanning for 5 seconds...")
        Thread.sleep(forTimeInterval: 5)
        
        try jensen.stopBluetoothScan()
        Thread.sleep(forTimeInterval: 0.5)
        
        let devices = try jensen.getScanResults()
        
        if devices.isEmpty {
            print("No devices found.")
            return
        }
        
        print("Found \(devices.count) devices:")
        print("")
        print("\("MAC Address".padding(toLength: 18, withPad: " ", startingAt: 0)) \("RSSI".padding(toLength: 6, withPad: " ", startingAt: 0)) \("Type".padding(toLength: 10, withPad: " ", startingAt: 0)) Name")
        print(String(repeating: "-", count: 60))
        
        for dev in devices {
            let macStr = dev.mac.padding(toLength: 18, withPad: " ", startingAt: 0)
            let rssiStr = "\(dev.rssi)".padding(toLength: 6, withPad: " ", startingAt: 0)
            let typeStr = (dev.audio ? "Audio" : "Other").padding(toLength: 10, withPad: " ", startingAt: 0)
            print("\(macStr) \(rssiStr) \(typeStr) \(dev.name)")
        }
    }
}

struct BTConnect: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-connect", abstract: "Connect to device by MAC address")
    
    @Argument(help: "MAC address")
    var mac: String
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        print("Connecting to \(mac)...")
        try jensen.connectBluetooth(mac: mac)
        print("Connection command sent.")
    }
}

struct BTDisconnect: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-disconnect", abstract: "Disconnect current Bluetooth device")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        print("Disconnecting Bluetooth...")
        try jensen.disconnectBluetooth()
        print("Disconnection command sent.")
    }
}

struct BTReconnect: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-reconnect", abstract: "Reconnect to a known device")
    
    @Argument(help: "MAC address")
    var mac: String
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        print("Reconnecting to \(mac)...")
        try jensen.reconnectBluetooth(mac: mac)
        print("Reconnection command sent.")
    }
}

struct BTClearPaired: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bt-clear-paired", abstract: "Clear all paired devices")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        print("Clearing all paired devices...")
        try jensen.clearPairedDevices()
        print("Paired list cleared.")
    }
}
