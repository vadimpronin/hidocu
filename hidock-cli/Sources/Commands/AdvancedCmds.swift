import ArgumentParser
import JensenUSB
import Foundation

struct MassStorage: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "mass-storage", abstract: "Enter USB mass storage mode")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        try jensen.enterMassStorage()
        print("Device switching to mass storage mode.")
        print("It will disconnect and reappear as a disk drive.")
    }
}

struct Format: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Format SD card (destructive!)")
    
    @Flag(name: .long, help: "Skip confirmation prompt")
    var confirm: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        
        if !confirm {
            print("WARNING: This will erase ALL data on the SD card.")
            print("Type 'YES' to confirm: ", terminator: "")
            fflush(stdout)
            guard let input = readLine(), input == "YES" else {
                print("Operation cancelled.")
                return
            }
        }
        
        print("Formatting SD card (this may take 30 seconds)...")
        try jensen.formatCard()
        print("Format complete.")
    }
}

struct FactoryReset: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "factory-reset", abstract: "Reset to factory defaults")
    
    @Flag(name: .long, help: "Skip confirmation prompt")
    var confirm: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        
        if !confirm {
            print("WARNING: This will reset all settings to factory defaults.")
            print("Type 'RESET' to confirm: ", terminator: "")
            fflush(stdout)
            guard let input = readLine(), input == "RESET" else {
                print("Operation cancelled.")
                return
            }
        }
        
        print("Performing factory reset...")
        try jensen.factoryReset()
        print("Factory reset complete.")
    }
}

struct RestoreFactory: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "restore-factory", abstract: "Restore factory settings (alt. method)")
    
    @Flag(name: .long, help: "Skip confirmation prompt")
    var confirm: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        
        if !confirm {
            print("WARNING: This will restore factory settings (Command 19).")
            print("Type 'RESTORE' to confirm: ", terminator: "")
            fflush(stdout)
            guard let input = readLine(), input == "RESTORE" else {
                print("Operation cancelled.")
                return
            }
        }
        
        print("Restoring factory settings...")
        try jensen.restoreFactorySettings()
        print("Restore complete.")
    }
}

struct USBTimeout: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "usb-timeout", abstract: "Manage USB timeout", subcommands: [USBTimeoutGet.self, USBTimeoutSet.self])
}

struct USBTimeoutGet: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "get", abstract: "Get USB timeout")
    @Flag(name: .shortAndLong) var verbose: Bool = false
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        let timeout = try jensen.getWebUSBTimeout()
        print("USB Timeout: \(timeout) ms")
    }
}

struct USBTimeoutSet: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "set", abstract: "Set USB timeout")
    @Argument(help: "Timeout in ms") var value: UInt32
    @Flag(name: .shortAndLong) var verbose: Bool = false
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        print("Setting USB timeout to \(value) ms...")
        try jensen.setWebUSBTimeout(value)
        print("Timeout updated.")
        let newTimeout = try jensen.getWebUSBTimeout()
        print("Effective USB Timeout: \(newTimeout) ms")
    }
}

struct BNCStart: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bnc-start", abstract: "Start BNC demo mode")
    @Flag(name: .shortAndLong) var verbose: Bool = false
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        _ = try jensen.getDeviceInfo()
        print("Starting BNC demo mode...")
        try jensen.beginBNC()
        print("BNC demo started.")
    }
}

struct BNCStop: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "bnc-stop", abstract: "Stop BNC demo mode")
    @Flag(name: .shortAndLong) var verbose: Bool = false
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        _ = try jensen.getDeviceInfo()
        print("Stopping BNC demo mode...")
        try jensen.endBNC()
        print("BNC demo stopped.")
    }
}

struct SendKey: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "send-key", abstract: "Send key code to device")
    
    @Argument(help: "Mode: 1=single click, 2=long press, 3=double click")
    var mode: UInt8
    
    @Argument(help: "Key: 3=record, 4=mute, 5=playback")
    var key: UInt8
    
    @Flag(name: .shortAndLong) var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        _ = try jensen.getDeviceInfo()
        
        let modeDesc: String
        switch mode {
        case 1: modeDesc = "single click"
        case 2: modeDesc = "long press"
        case 3: modeDesc = "double click"
        default: modeDesc = "mode \(mode)"
        }
        
        let keyDesc: String
        switch key {
        case 3: keyDesc = "record"
        case 4: keyDesc = "mute"
        case 5: keyDesc = "playback"
        default: keyDesc = "key \(key)"
        }
        
        print("Sending key: \(keyDesc) (\(modeDesc))...")
        try jensen.sendKeyCode(mode: mode, keyCode: key)
        print("Key code sent.")
    }
}

struct RecordTest: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "record-test", abstract: "Record test commands", subcommands: [RecordTestStart.self, RecordTestStop.self])
}

struct RecordTestStart: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "start", abstract: "Start recording test")
    @Argument(help: "Test Type") var type: UInt8
    @Flag(name: .shortAndLong) var verbose: Bool = false
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        _ = try jensen.getDeviceInfo()
        print("Starting recording test (type \(type))...")
        try jensen.recordTestStart(type: type)
        print("Recording test started.")
    }
}

struct RecordTestStop: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "stop", abstract: "Stop recording test")
    @Argument(help: "Test Type") var type: UInt8
    @Flag(name: .shortAndLong) var verbose: Bool = false
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        _ = try jensen.getDeviceInfo()
        print("Stopping recording test (type \(type))...")
        try jensen.recordTestEnd(type: type)
        print("Recording test ended.")
    }
}
