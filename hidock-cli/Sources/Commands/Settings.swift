import ArgumentParser
import JensenUSB
import Foundation

struct Settings: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Manage device settings",
        subcommands: [
            SettingsGet.self,
            SettingsSetAutoRecord.self,
            SettingsSetAutoPlay.self,
            SettingsSetNotification.self,
            SettingsSetBTTone.self
        ]
    )
}

struct SettingsGet: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "get", abstract: "Get all settings")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        let settings = try jensen.getSettings()
        
        print("Auto Record: \(settings.autoRecord ? "ON" : "OFF")")
        print("Auto Play: \(settings.autoPlay ? "ON" : "OFF")")
        print("Notifications: \(settings.notification ? "ON" : "OFF")")
        print("Bluetooth Tone: \(settings.bluetoothTone ? "ON" : "OFF")")
    }
}

private func parseBool(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "on", "true", "1", "yes": return true
    case "off", "false", "0", "no": return false
    default: return nil
    }
}

struct SettingsSetAutoRecord: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "set-auto-record", abstract: "Enable/disable auto-recording")
    
    @Argument(help: "on/off")
    var value: String
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        guard let enabled = parseBool(value) else {
            throw ValidationError("Invalid value '\(value)'. Use 'on' or 'off'.")
        }
        
        try jensen.setAutoRecord(enabled)
        print("Auto Record: \(enabled ? "ON" : "OFF")")
        print("Setting updated successfully.")
    }
}

struct SettingsSetAutoPlay: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "set-auto-play", abstract: "Enable/disable auto-play")
    
    @Argument(help: "on/off")
    var value: String
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        guard let enabled = parseBool(value) else {
            throw ValidationError("Invalid value '\(value)'. Use 'on' or 'off'.")
        }
        
        try jensen.setAutoPlay(enabled)
        print("Auto Play: \(enabled ? "ON" : "OFF")")
        print("Setting updated successfully.")
    }
}

struct SettingsSetNotification: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "set-notification", abstract: "Enable/disable notifications")
    
    @Argument(help: "on/off")
    var value: String
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        guard let enabled = parseBool(value) else {
            throw ValidationError("Invalid value '\(value)'. Use 'on' or 'off'.")
        }
        
        try jensen.setNotification(enabled)
        print("Notifications: \(enabled ? "ON" : "OFF")")
        print("Setting updated successfully.")
    }
}

struct SettingsSetBTTone: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "set-bt-tone", abstract: "Enable/disable Bluetooth tone")
    
    @Argument(help: "on/off")
    var value: String
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        guard let enabled = parseBool(value) else {
            throw ValidationError("Invalid value '\(value)'. Use 'on' or 'off'.")
        }
        
        try jensen.setBluetoothTone(enabled)
        print("Bluetooth Tone: \(enabled ? "ON" : "OFF")")
        print("Setting updated successfully.")
    }
}
