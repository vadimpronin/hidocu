//
//  main.swift
//  hidock-cli
//
//  HiDock CLI - Command-line utility for HiDock USB devices
//

import Foundation
import JensenUSB

// MARK: - CLI Entry Point

enum HiDockCLI {
    static func main() {
        let args = CommandLine.arguments.dropFirst()
        
        guard let command = args.first else {
            printUsage()
            exit(0)
        }
        
        let verbose = args.contains("--verbose") || args.contains("-v")
        let accessToken = getArgValue(args, for: "--access-token")
        let modelOverride = getArgValue(args, for: "--model")
        
        // Handle commands that don't require device connection
        if command == "--help" || command == "-h" || command == "help" {
            printUsage()
            exit(0)
        }
        
        if command == "--version" {
            print("hidock-cli 0.2.0")
            exit(0)
        }
        
        // Device-less firmware commands
        if command == "firmware-check" || command == "firmware-download" {
            // These can run without a device if --model is provided
            if modelOverride != nil || accessToken != nil {
                do {
                    let jensen = Jensen(verbose: verbose)
                    // Attempt to connect if not model override
                    if modelOverride == nil {
                        try jensen.connect()
                    }
                    
                    switch command {
                    case "firmware-check":
                        guard let token = accessToken else {
                            printError("Missing --access-token")
                            return
                        }
                        try runFirmwareCheck(jensen, accessToken: token, model: modelOverride)
                        
                    case "firmware-download":
                        let version = getVersionArg(args)
                        let install = args.contains("--install")
                        let confirm = args.contains("--confirm")
                        let rawOutputDir = getArgValue(args, for: "--output")
                        try runFirmwareDownload(jensen, version: version, install: install, confirm: confirm, outputDir: rawOutputDir, accessToken: accessToken, model: modelOverride)
                        
                    default: break
                    }
                    
                    jensen.disconnect()
                    exit(0)
                } catch {
                    // If we failed to connect but have a model override, we might still be able to run
                    if modelOverride != nil && accessToken != nil {
                        // Fall back to device-less path
                    } else {
                        // Regular error handling
                        printError("\(error)")
                        exit(1)
                    }
                }
            }
        }
        
        do {
            let jensen = Jensen(verbose: verbose)
            try jensen.connect()
            
            switch command {
            case "info":
                try runInfo(jensen)
                
            case "time":
                let subcommand = args.dropFirst().first ?? "get"
                if subcommand == "get" {
                    try runTimeGet(jensen)
                } else if subcommand == "set" {
                    // Optional datetime argument after "set"
                    let argsAfterSet = args.dropFirst(2)  // Drop "time" and "set"
                    let dateArg = argsAfterSet.first { !$0.starts(with: "-") }
                    try runTimeSet(jensen, dateString: dateArg)
                } else {
                    printError("Usage: hidock-cli time <get|set> [datetime]")
                }
                
            case "count":
                try runCount(jensen)
                
            case "list":
                try runList(jensen)
                
            case "settings":
                let subcommand = args.dropFirst().first ?? "get"
                if subcommand == "get" {
                    try runSettingsGet(jensen)
                } else if subcommand == "set-auto-record" {
                    let value = args.dropFirst(2).first { !$0.starts(with: "-") }
                    try runSettingsSet(jensen, setting: "auto-record", value: value)
                } else if subcommand == "set-auto-play" {
                    let value = args.dropFirst(2).first { !$0.starts(with: "-") }
                    try runSettingsSet(jensen, setting: "auto-play", value: value)
                } else if subcommand == "set-notification" {
                    let value = args.dropFirst(2).first { !$0.starts(with: "-") }
                    try runSettingsSet(jensen, setting: "notification", value: value)
                } else if subcommand == "set-bt-tone" {
                    let value = args.dropFirst(2).first { !$0.starts(with: "-") }
                    try runSettingsSet(jensen, setting: "bt-tone", value: value)
                } else if subcommand == "--help" || subcommand == "-h" || subcommand == "help" {
                    printSettingsUsage()
                } else {
                    printError("Unknown settings subcommand: \(subcommand)")
                    printSettingsUsage()
                }
                
            case "card-info":
                try runCardInfo(jensen)
                
            case "recording":
                try runRecording(jensen)
                
            case "battery":
                try runBattery(jensen)
                
            case "bt-status":
                try runBluetoothStatus(jensen)
                
            case "bt-paired":
                try runBluetoothPaired(jensen)
                
            case "bt-scan":
                try runBluetoothScan(jensen)
                
            case "bt-connect":
                guard let mac = args.dropFirst().first, !mac.starts(with: "-") else {
                    printError("Missing MAC address. Usage: hidock-cli bt-connect <mac>")
                    return
                }
                try runBluetoothConnect(jensen, mac: mac)
                
            case "bt-disconnect":
                try runBluetoothDisconnect(jensen)
                
            case "bt-clear-paired":
                try runBluetoothClearPaired(jensen)
            
            case "bt-reconnect":
                guard let mac = args.dropFirst().first, !mac.starts(with: "-") else {
                    printError("Missing MAC address. Usage: hidock-cli bt-reconnect <mac>")
                    return
                }
                try runBluetoothReconnect(jensen, mac: mac)

            case "mass-storage":
                try runMassStorage(jensen)

            case "format":
                let confirm = args.contains("--confirm")
                try runFormat(jensen, confirm: confirm)
                
            case "factory-reset":
                let confirm = args.contains("--confirm")
                try runFactoryReset(jensen, confirm: confirm)

            case "restore-factory":
                let confirm = args.contains("--confirm")
                try runRestoreFactory(jensen, confirm: confirm)
                
            case "usb-timeout":
                let subcommand = args.dropFirst().first ?? "get"
                if subcommand == "get" {
                    try runUsbTimeoutGet(jensen)
                } else if subcommand == "set" {
                    guard let valueStr = args.dropFirst(2).first, let value = UInt32(valueStr) else {
                        printError("Missing or invalid value. Usage: hidock-cli usb-timeout set <ms>")
                        return
                    }
                    try runUsbTimeoutSet(jensen, value: value)
                } else {
                    printError("Usage: hidock-cli usb-timeout <get|set> [ms]")
                }

            case "delete":
                guard let filename = args.dropFirst().first, !filename.starts(with: "-") else {
                    printError("Missing filename. Usage: hidock-cli delete <filename>")
                    return
                }
                try runDelete(jensen, filename: filename)
            
            case "bnc-start":
                try runBNCStart(jensen)
            
            case "bnc-stop":
                try runBNCStop(jensen)
            
            case "send-key":
                let argsAfterCommand = Array(args.dropFirst())
                guard argsAfterCommand.count >= 2,
                      let mode = UInt8(argsAfterCommand[0]),
                      let keyCode = UInt8(argsAfterCommand[1]) else {
                    printError("Usage: hidock-cli send-key <mode> <keycode>")
                    print("  Mode: 1=single click, 2=long press, 3=double click")
                    print("  Key:  3=record, 4=mute, 5=playback")
                    return
                }
                try runSendKey(jensen, mode: mode, keyCode: keyCode)
            
            case "record-test":
                let argsAfterCommand = Array(args.dropFirst())
                guard argsAfterCommand.count >= 2,
                      let subcommand = argsAfterCommand.first,
                      let testType = UInt8(argsAfterCommand[1]) else {
                    printError("Usage: hidock-cli record-test <start|stop> <type>")
                    return
                }
                if subcommand == "start" {
                    try runRecordTestStart(jensen, type: testType)
                } else if subcommand == "stop" {
                    try runRecordTestEnd(jensen, type: testType)
                } else {
                    printError("Unknown subcommand. Use 'start' or 'stop'.")
                }
                
            case "download":
                let filename = args.dropFirst().first { !$0.starts(with: "-") }
                let rawOutputDir = getArgValue(args, for: "--output") ?? "."
                let expandedPath = (rawOutputDir as NSString).expandingTildeInPath
                let outputDir = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
                let downloadAll = args.contains("--all")
                let sync = args.contains("--sync")
                try runDownload(jensen, filename: filename, downloadAll: downloadAll, outputDir: outputDir, sync: sync)
            
            case "firmware-update":
                guard let filePath = args.dropFirst().first, !filePath.starts(with: "-") else {
                    printError("Missing firmware file. Usage: hidock-cli firmware-update <file.bin>")
                    return
                }
                let confirm = args.contains("--confirm")
                try runFirmwareUpdate(jensen, filePath: filePath, confirm: confirm)
            
            case "tone-update":
                guard let filePath = args.dropFirst().first, !filePath.starts(with: "-") else {
                    printError("Missing tone file. Usage: hidock-cli tone-update <file.bin>")
                    return
                }
                try runToneUpdate(jensen, filePath: filePath)
            
            case "uac-update":
                guard let filePath = args.dropFirst().first, !filePath.starts(with: "-") else {
                    printError("Missing UAC file. Usage: hidock-cli uac-update <file.bin>")
                    return
                }
                try runUACUpdate(jensen, filePath: filePath)
            
            case "firmware-download":
                let version = getVersionArg(args)
                let install = args.contains("--install")
                let confirm = args.contains("--confirm")
                let rawOutputDir = getArgValue(args, for: "--output")
                try runFirmwareDownload(jensen, version: version, install: install, confirm: confirm, outputDir: rawOutputDir, accessToken: accessToken, model: modelOverride)
            
            case "firmware-check":
                guard let token = accessToken else {
                    printError("Missing --access-token")
                    return
                }
                try runFirmwareCheck(jensen, accessToken: token, model: modelOverride)
                
            case "--help", "-h", "help":
                printUsage()
                
            case "--version":
                print("hidock-cli 0.1.0")
                
            default:
                printError("Unknown command: \(command)")
                printUsage()
                exit(2)
            }
            
            jensen.disconnect()
            
        } catch let error as USBError {
            if case .deviceInUse = error {
                printError("""
                    Device is in use by another application.
                    Common causes:
                      • Chrome or another browser with HiNotes web app open (WebUSB)
                      • Another instance of hidock-cli
                      • HiNotes desktop app
                    Close the application using the device and try again.
                    """)
            } else {
                printError(error.localizedDescription)
            }
            exit(3)
        } catch let error as JensenError {
            printError(error.localizedDescription)
            exit(6)
        } catch {
            printError("Error: \(error)")
            exit(1)
        }
    }
    
    // MARK: - Command Implementations
    
    static func runInfo(_ jensen: Jensen) throws {
        let info = try jensen.getDeviceInfo()
        
        print("Device Model: \(jensen.model.rawValue)")
        print("Firmware Version: \(info.versionCode)")
        print("Version Number: 0x\(String(format: "%08X", info.versionNumber))")
        print("Serial Number: \(info.serialNumber)")
    }
    
    static func runTimeGet(_ jensen: Jensen) throws {
        let time = try jensen.getTime()
        print("Device Time: \(time.timeString)")
    }
    
    static func runTimeSet(_ jensen: Jensen, dateString: String?) throws {
        let dateToSet: Date
        
        if let dateStr = dateString {
            // Parse the provided datetime string
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let parsed = formatter.date(from: dateStr) {
                dateToSet = parsed
            } else {
                // Try alternate format
                formatter.dateFormat = "yyyy-MM-dd"
                if let parsed = formatter.date(from: dateStr) {
                    dateToSet = parsed
                } else {
                    printError("Invalid date format. Use: YYYY-MM-DD HH:mm:ss or YYYY-MM-DD")
                    return
                }
            }
            print("Setting device time to: \(dateStr)")
        } else {
            // Use current system time
            dateToSet = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            print("Setting device time to current system time: \(formatter.string(from: dateToSet))")
        }
        
        try jensen.setTime(dateToSet)
        print("Time set successfully.")
        
        // Verify by reading back
        let newTime = try jensen.getTime()
        print("Device time now: \(newTime.timeString)")
    }
    
    static func runCount(_ jensen: Jensen) throws {
        let count = try jensen.getFileCount()
        print("Total Files: \(count.count)")
    }
    
    static func runList(_ jensen: Jensen) throws {
        print("Loading file list...")
        let files = try jensen.listFiles()
        
        if files.isEmpty {
            print("No files found.")
            return
        }
        
        // Print header
        print("")
        print("\("Name".padding(toLength: 35, withPad: " ", startingAt: 0)) \("Date".padding(toLength: 12, withPad: " ", startingAt: 0)) \("Time".padding(toLength: 10, withPad: " ", startingAt: 0)) \("Duration".padding(toLength: 10, withPad: " ", startingAt: 0)) \("Mode".padding(toLength: 8, withPad: " ", startingAt: 0)) \("Ver".padding(toLength: 4, withPad: " ", startingAt: 0)) Size         Signature")
        print(String(repeating: "-", count: 120))
        
        for file in files {
            let durationStr = formatDuration(file.duration)
            let sizeStr = formatSize(UInt64(file.length)).padding(toLength: 12, withPad: " ", startingAt: 0)
            let nameStr = String(file.name.prefix(35)).padding(toLength: 35, withPad: " ", startingAt: 0)
            let dateStr = file.createDate.padding(toLength: 12, withPad: " ", startingAt: 0)
            let timeStr = file.createTime.padding(toLength: 10, withPad: " ", startingAt: 0)
            let durStr = durationStr.padding(toLength: 10, withPad: " ", startingAt: 0)
            let modeStr = file.mode.padding(toLength: 8, withPad: " ", startingAt: 0)
            let verStr = String(file.version).padding(toLength: 4, withPad: " ", startingAt: 0)
            
            print("\(nameStr) \(dateStr) \(timeStr) \(durStr) \(modeStr) \(verStr) \(sizeStr) \(file.signature)")
        }
        
        print("")
        print("Total: \(files.count) file(s)")
    }
    
    static func runSettingsGet(_ jensen: Jensen) throws {
        // Get device info first to cache version
        _ = try jensen.getDeviceInfo()
        
        let settings = try jensen.getSettings()
        
        print("Auto Record: \(settings.autoRecord ? "ON" : "OFF")")
        print("Auto Play: \(settings.autoPlay ? "ON" : "OFF")")
        print("Notifications: \(settings.notification ? "ON" : "OFF")")
        print("Bluetooth Tone: \(settings.bluetoothTone ? "ON" : "OFF")")
    }
    
    static func runSettingsSet(_ jensen: Jensen, setting: String, value: String?) throws {
        // Get device info first to cache version
        _ = try jensen.getDeviceInfo()
        
        guard let valueStr = value?.lowercased() else {
            printError("Missing value. Usage: hidock-cli settings set-\(setting) <on|off>")
            return
        }
        
        let enabled: Bool
        switch valueStr {
        case "on", "true", "1", "yes":
            enabled = true
        case "off", "false", "0", "no":
            enabled = false
        default:
            printError("Invalid value '\(valueStr)'. Use 'on' or 'off'.")
            return
        }
        
        switch setting {
        case "auto-record":
            try jensen.setAutoRecord(enabled)
            print("Auto Record: \(enabled ? "ON" : "OFF")")
        case "auto-play":
            try jensen.setAutoPlay(enabled)
            print("Auto Play: \(enabled ? "ON" : "OFF")")
        case "notification":
            try jensen.setNotification(enabled)
            print("Notifications: \(enabled ? "ON" : "OFF")")
        case "bt-tone":
            try jensen.setBluetoothTone(enabled)
            print("Bluetooth Tone: \(enabled ? "ON" : "OFF")")
        default:
            printError("Unknown setting: \(setting)")
        }
        
        print("Setting updated successfully.")
    }
    
    static func runCardInfo(_ jensen: Jensen) throws {
        // Get device info first to cache version
        _ = try jensen.getDeviceInfo()
        
        let info = try jensen.getCardInfo()
        
        let capacity = formatSize(info.capacity)
        let used = formatSize(info.used)
        let free = info.capacity > info.used ? formatSize(info.capacity - info.used) : "0 B"
        let percentage = info.capacity > 0 ? Double(info.used) / Double(info.capacity) * 100 : 0
        
        print("Capacity: \(capacity)")
        print("Used: \(used) (\(String(format: "%.1f", percentage))%)")
        print("Free: \(free)")
        print("Status: \(info.status)")
    }
    
    static func runRecording(_ jensen: Jensen) throws {
        // Get device info first to cache version
        _ = try jensen.getDeviceInfo()
        
        if let recording = try jensen.getRecordingFile() {
            print("Currently Recording:")
            print("  Name: \(recording.name)")
            if !recording.createDate.isEmpty {
                print("  Started: \(recording.createDate) \(recording.createTime)")
            }
        } else {
            print("No active recording.")
        }
    }
    
    static func runBattery(_ jensen: Jensen) throws {
        let battery = try jensen.getBatteryStatus()
        
        print("Status: \(battery.status)")
        print("Battery Level: \(battery.percentage)%")
        print("Voltage: \(String(format: "%.2f", Double(battery.voltage) / 1000000.0))V")
    }
    
    static func runBluetoothStatus(_ jensen: Jensen) throws {
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
    
    static func runMassStorage(_ jensen: Jensen) throws {
        // Get device info first
        _ = try jensen.getDeviceInfo()
        
        try jensen.enterMassStorage()
        print("Device switching to mass storage mode.")
        print("It will disconnect and reappear as a disk drive.")
    }
    
    static func runBluetoothPaired(_ jensen: Jensen) throws {
        // Get device info first
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
    
    static func runBluetoothScan(_ jensen: Jensen) throws {
        // Get device info first (checks compatibility)
        _ = try jensen.getDeviceInfo()
        
        print("Starting Bluetooth scan...")
        try jensen.startBluetoothScan()
        
        print("Scanning for 5 seconds...")
        Thread.sleep(forTimeInterval: 5)
        
        try jensen.stopBluetoothScan()
        
        // Give a moment for results to be ready?
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
    
    static func runBluetoothConnect(_ jensen: Jensen, mac: String) throws {
        _ = try jensen.getDeviceInfo()
        print("Connecting to \(mac)...")
        try jensen.connectBluetooth(mac: mac)
        print("Connection command sent.")
    }
    
    static func runBluetoothDisconnect(_ jensen: Jensen) throws {
        _ = try jensen.getDeviceInfo()
        print("Disconnecting Bluetooth...")
        try jensen.disconnectBluetooth()
        print("Disconnection command sent.")
    }
    
    static func runBluetoothClearPaired(_ jensen: Jensen) throws {
        _ = try jensen.getDeviceInfo()
        print("Clearing all paired devices...")
        try jensen.clearPairedDevices()
        print("Paired list cleared.")
    }
    
    static func runBluetoothReconnect(_ jensen: Jensen, mac: String) throws {
        _ = try jensen.getDeviceInfo()
        print("Reconnecting to \(mac)...")
        try jensen.reconnectBluetooth(mac: mac)
        print("Reconnection command sent.")
    }
    
    // MARK: - BNC Demo Commands
    
    static func runBNCStart(_ jensen: Jensen) throws {
        _ = try jensen.getDeviceInfo()
        print("Starting BNC demo mode...")
        try jensen.beginBNC()
        print("BNC demo started.")
    }
    
    static func runBNCStop(_ jensen: Jensen) throws {
        _ = try jensen.getDeviceInfo()
        print("Stopping BNC demo mode...")
        try jensen.endBNC()
        print("BNC demo stopped.")
    }
    
    // MARK: - Send Key Command
    
    static func runSendKey(_ jensen: Jensen, mode: UInt8, keyCode: UInt8) throws {
        _ = try jensen.getDeviceInfo()
        
        let modeDesc: String
        switch mode {
        case 1: modeDesc = "single click"
        case 2: modeDesc = "long press"
        case 3: modeDesc = "double click"
        default: modeDesc = "mode \(mode)"
        }
        
        let keyDesc: String
        switch keyCode {
        case 3: keyDesc = "record"
        case 4: keyDesc = "mute"
        case 5: keyDesc = "playback"
        default: keyDesc = "key \(keyCode)"
        }
        
        print("Sending key: \(keyDesc) (\(modeDesc))...")
        try jensen.sendKeyCode(mode: mode, keyCode: keyCode)
        print("Key code sent.")
    }
    
    // MARK: - Recording Test Commands
    
    static func runRecordTestStart(_ jensen: Jensen, type: UInt8) throws {
        _ = try jensen.getDeviceInfo()
        print("Starting recording test (type \(type))...")
        try jensen.recordTestStart(type: type)
        print("Recording test started.")
    }
    
    static func runRecordTestEnd(_ jensen: Jensen, type: UInt8) throws {
        _ = try jensen.getDeviceInfo()
        print("Stopping recording test (type \(type))...")
        try jensen.recordTestEnd(type: type)
        print("Recording test ended.")
    }

    static func runFormat(_ jensen: Jensen, confirm: Bool) throws {
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
    
    static func runFactoryReset(_ jensen: Jensen, confirm: Bool) throws {
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
    
    static func runRestoreFactory(_ jensen: Jensen, confirm: Bool) throws {
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
    
    static func runUsbTimeoutGet(_ jensen: Jensen) throws {
        let timeout = try jensen.getWebUSBTimeout()
        print("USB Timeout: \(timeout) ms")
    }
    
    static func runUsbTimeoutSet(_ jensen: Jensen, value: UInt32) throws {
        print("Setting USB timeout to \(value) ms...")
        try jensen.setWebUSBTimeout(value)
        print("Timeout updated.")
        
        // Verify
        let newTimeout = try jensen.getWebUSBTimeout()
        print("Effective USB Timeout: \(newTimeout) ms")
    }
    
    // MARK: - Firmware API
    
    struct FirmwareAPIResponse: Codable {
        let error: Int
        let message: String
        let data: FirmwareData?
        
        struct FirmwareData: Codable {
            let id: String
            let model: String
            let versionCode: String
            let versionNumber: Int
            let signature: String
            let fileName: String
            let fileLength: Int
            let remark: String?
            let createTime: Int64?
            let state: String?
        }
    }
    
    struct FirmwareInfo {
        let id: String
        let model: String
        let version: String
        let versionNumber: UInt32
        let signature: String
        let fileName: String
        let fileLength: Int
        let remark: String
        
        var downloadURL: String {
            return "https://hinotes.hidock.com/v2/device/firmware/get?id=\(id)"
        }
    }
    
    static let supportedModels = [
        "hidock-p1",
        "hidock-p1:mini",
        "hidock-h1",
        "hidock-h1e"
    ]
    
    static func fetchLatestFirmware(model: String, accessToken: String) -> Result<FirmwareInfo, Error> {
        let urlString = "https://hinotes.hidock.com/v2/device/firmware/latest"
        guard let url = URL(string: urlString) else {
            return .failure(NSError(domain: "FirmwareAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(accessToken, forHTTPHeaderField: "AccessToken")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "version=-1&model=\(model)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<FirmwareInfo, Error> = .failure(NSError(domain: "FirmwareAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "No response"]))
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = .failure(error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                result = .failure(NSError(domain: "FirmwareAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                result = .failure(NSError(domain: "HTTP", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                return
            }
            
            guard let data = data else {
                result = .failure(NSError(domain: "FirmwareAPI", code: 4, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            
            do {
                let apiResponse = try JSONDecoder().decode(FirmwareAPIResponse.self, from: data)
                
                guard apiResponse.error == 0, let fwData = apiResponse.data else {
                    let msg = apiResponse.message.isEmpty ? "No firmware available" : apiResponse.message
                    result = .failure(NSError(domain: "FirmwareAPI", code: apiResponse.error, userInfo: [NSLocalizedDescriptionKey: msg]))
                    return
                }
                
                let firmware = FirmwareInfo(
                    id: fwData.id,
                    model: fwData.model,
                    version: fwData.versionCode,
                    versionNumber: UInt32(fwData.versionNumber),
                    signature: fwData.signature,
                    fileName: fwData.fileName,
                    fileLength: fwData.fileLength,
                    remark: fwData.remark ?? ""
                )
                
                result = .success(firmware)
            } catch {
                result = .failure(error)
            }
        }
        
        task.resume()
        semaphore.wait()
        
        return result
    }
    
    static func parseVersionCode(_ version: String) -> UInt32 {
        let parts = version.split(separator: ".")
        guard parts.count == 3,
              let major = UInt32(parts[0]),
              let minor = UInt32(parts[1]),
              let patch = UInt32(parts[2]) else {
            return 0
        }
        return (major << 16) | (minor << 8) | patch
    }
    
    static func formatVersionNumber(_ versionNumber: UInt32) -> String {
        let major = (versionNumber >> 16) & 0xFF
        let minor = (versionNumber >> 8) & 0xFF
        let patch = versionNumber & 0xFF
        return "\(major).\(minor).\(patch)"
    }
    
    static func compareVersions(_ v1: String, _ v2: String) -> Int {
        let num1 = parseVersionCode(v1)
        let num2 = parseVersionCode(v2)
        if num1 > num2 { return 1 }
        if num1 < num2 { return -1 }
        return 0
    }
    
    static func runFirmwareCheck(_ jensen: Jensen, accessToken: String, model: String?) throws {
        let modelToUse = model ?? jensen.model.rawValue
        
        print("Checking for updates for \(modelToUse)...")
        
        let result = fetchLatestFirmware(model: modelToUse, accessToken: accessToken)
        
        switch result {
        case .success(let fw):
            print("Latest Version: \(fw.version)")
            print("Create Time: \(fw.fileName)") // fileName here is often a timestamp-like ID or partial filename
            if !fw.remark.isEmpty {
                print("Release Notes:\n\(fw.remark)")
            }
            
            // Compare if we have a device
            if let deviceInfo = try? jensen.getDeviceInfo() {
                let comparison = compareVersions(fw.version, deviceInfo.versionCode)
                if comparison > 0 {
                    print("\nUpdate available! (Current: \(deviceInfo.versionCode))")
                } else if comparison < 0 {
                    print("\nDevice firmware (\(deviceInfo.versionCode)) is newer than server version.")
                } else {
                    print("\nDevice is up to date.")
                }
            } else {
                print("\nTo download this firmware, run:")
                print("  hidock-cli firmware-download --model \(modelToUse) --access-token \(accessToken)")
            }
            
        case .failure(let error):
            printError("Failed to fetch firmware: \(error.localizedDescription)")
        }
    }
    
    static func runFirmwareDownload(_ jensen: Jensen, version: String?, install: Bool, confirm: Bool, outputDir: String?, accessToken: String?, model: String?) throws {
        let modelToUse = model ?? jensen.model.rawValue
        let currentVersion = (try? jensen.getDeviceInfo())?.versionCode
        
        guard let token = accessToken else {
            printError("Missing --access-token required for dynamic download")
            return
        }
        
        print("Fetching latest firmware info for \(modelToUse)...")
        let result = fetchLatestFirmware(model: modelToUse, accessToken: token)
        
        guard case .success(let fw) = result else {
            if case .failure(let error) = result {
                printError("Failed to fetch firmware info: \(error.localizedDescription)")
            }
            return
        }
        
        // If user specified a version, verify it matcheslatest (API only gives latest)
        if let v = version, v != fw.version {
            printError("Requested version \(v) does not match latest server version \(fw.version)")
            return
        }
        
        let selectedFirmware = fw
        
        if let current = currentVersion {
            let comp = compareVersions(selectedFirmware.version, current)
            if comp > 0 {
                print("Update Available: \(current) -> \(selectedFirmware.version)")
            } else if comp < 0 {
                print("Downgrade: \(current) -> \(selectedFirmware.version)")
            } else {
                print("Re-flashing current version: \(selectedFirmware.version)")
            }
        } else {
            print("Firmware: \(selectedFirmware.version)")
        }
        
        print("Size: \(formatSize(UInt64(selectedFirmware.fileLength)))")
        
        if !selectedFirmware.remark.isEmpty {
            print("\nRelease Notes:\n\(selectedFirmware.remark)")
        }
        
        if !confirm && !install && outputDir == nil {
            print("\nProceed with download? (y/n): ", terminator: "")
            fflush(stdout)
            guard let input = readLine()?.lowercased(), input == "y" else {
                print("Operation cancelled.")
                return
            }
        }
        
        print("Downloading...")
        let url = URL(string: selectedFirmware.downloadURL)!
        
        let semaphore = DispatchSemaphore(value: 0)
        var downloadedData: Data?
        var downloadError: Error?
        
        // Use a download delegate for progress
        class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
            var completion: ((URL?, Error?) -> Void)?
            var progressHandler: ((Int64, Int64) -> Void)?
            
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                completion?(location, nil)
            }
            
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error = error {
                    completion?(nil, error)
                }
            }
            
            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
                progressHandler?(totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
        
        let delegate = DownloadDelegate()
        var lastPercent = -1
        
        delegate.progressHandler = { written, total in
            if total > 0 {
                let percent = Int(Double(written) / Double(total) * 100)
                if percent != lastPercent && percent % 10 == 0 {
                    print("  \(percent)% (\(formatSize(UInt64(written))) / \(formatSize(UInt64(total))))")
                    lastPercent = percent
                }
            }
        }
        
        delegate.completion = { location, error in
            if let error = error {
                downloadError = error
            } else if let location = location {
                downloadedData = try? Data(contentsOf: location)
            }
            semaphore.signal()
        }
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        task.resume()
        semaphore.wait()
        
        // Check for HTTP errors
        if let response = task.response as? HTTPURLResponse, response.statusCode != 200 {
            downloadError = NSError(domain: "HTTP", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(response.statusCode)"])
        }
        
        if let error = downloadError {
            printError("Download failed: \(error.localizedDescription)")
            return
        }
        
        guard let data = downloadedData, !data.isEmpty else {
            printError("Downloaded empty file")
            return
        }
        
        print("Downloaded \(formatSize(UInt64(data.count)))")
        
        // Save to file if output directory specified or not installing
        if let outputDir = outputDir {
            let expandedPath = (outputDir as NSString).expandingTildeInPath
            let resolvedDir = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
            
            // Create directory if needed
            try? FileManager.default.createDirectory(atPath: resolvedDir, withIntermediateDirectories: true)
            
            let filename = "firmware-\(modelToUse.replacingOccurrences(of: ":", with: "-"))-\(selectedFirmware.version).bin"
            let outputPath = (resolvedDir as NSString).appendingPathComponent(filename)
            
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("Saved to: \(outputPath)")
        }
        
        if install {
            // Safety check: ensure connected device matches firmware model
            if jensen.model.rawValue != selectedFirmware.model {
                printError("Model mismatch! Firmware is for \(selectedFirmware.model) but connected device is \(jensen.model.rawValue)")
                return
            }
            
            // Install the firmware
            if !confirm {
                print("")
                print("WARNING: Firmware update can potentially brick your device if interrupted.")
                print("Version: \(selectedFirmware.version)")
                print("Size: \(formatSize(UInt64(data.count)))")
                print("Type 'UPDATE' to confirm: ", terminator: "")
                fflush(stdout)
                guard let input = readLine(), input == "UPDATE" else {
                    print("Operation cancelled.")
                    return
                }
            }
            
            print("Requesting firmware upgrade...")
            let result = try jensen.requestFirmwareUpgrade(
                versionNumber: selectedFirmware.versionNumber,
                fileSize: UInt32(data.count)
            )
            
            switch result {
            case .accepted:
                print("Request accepted. Uploading firmware...")
            case .wrongVersion:
                printError("Wrong version - device rejected the firmware")
                return
            case .busy:
                printError("Device is busy - try again later")
                return
            case .cardFull:
                printError("SD card is full")
                return
            case .cardError:
                printError("SD card error")
                return
            case .unknown:
                printError("Unknown error from device")
                return
            }
            
            try jensen.uploadFirmware(data) { current, total in
                let percent = Int(Double(current) / Double(total) * 100)
                print("Progress: \(percent)%")
            }
            
            print("Firmware upload complete!")
            print("The device will restart to apply the update.")
        } else if outputDir == nil {
            // No install and no output dir - just save to current directory
            let filename = "firmware-\(modelToUse.replacingOccurrences(of: ":", with: "-"))-\(selectedFirmware.version).bin"
            try data.write(to: URL(fileURLWithPath: filename))
            print("Saved to: ./\(filename)")
            print("")
            print("To install this firmware, run:")
            print("  hidock-cli firmware-update \(filename)")
        }
    }
    
    // MARK: - Firmware Update Commands
    
    static func runFirmwareUpdate(_ jensen: Jensen, filePath: String, confirm: Bool) throws {
        _ = try jensen.getDeviceInfo()
        
        // Resolve path
        let expandedPath = (filePath as NSString).expandingTildeInPath
        let resolvedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            printError("File not found: \(resolvedPath)")
            return
        }
        
        // Read file
        guard let data = FileManager.default.contents(atPath: resolvedPath) else {
            printError("Cannot read file: \(resolvedPath)")
            return
        }
        
        // Parse version from filename (e.g., "firmware_1.3.10.bin" -> 0x0001030A)
        let filename = (resolvedPath as NSString).lastPathComponent
        let version = parseVersionFromFilename(filename)
        
        if !confirm {
            print("WARNING: Firmware update can potentially brick your device if interrupted.")
            print("File: \(filename)")
            print("Size: \(formatSize(UInt64(data.count)))")
            if let v = version {
                print("Version: \(formatVersionCode(v))")
            }
            print("Type 'UPDATE' to confirm: ", terminator: "")
            fflush(stdout)
            guard let input = readLine(), input == "UPDATE" else {
                print("Operation cancelled.")
                return
            }
        }
        
        print("Requesting firmware upgrade...")
        let result = try jensen.requestFirmwareUpgrade(
            versionNumber: version ?? 0,
            fileSize: UInt32(data.count)
        )
        
        switch result {
        case .accepted:
            print("Request accepted. Uploading firmware...")
        case .wrongVersion:
            printError("Wrong version - device rejected the firmware")
            return
        case .busy:
            printError("Device is busy - try again later")
            return
        case .cardFull:
            printError("SD card is full")
            return
        case .cardError:
            printError("SD card error")
            return
        case .unknown:
            printError("Unknown error from device")
            return
        }
        
        try jensen.uploadFirmware(data) { current, total in
            let percent = Int(Double(current) / Double(total) * 100)
            print("Progress: \(percent)%")
        }
        
        print("Firmware upload complete!")
        print("The device will restart to apply the update.")
    }
    
    static func runToneUpdate(_ jensen: Jensen, filePath: String) throws {
        _ = try jensen.getDeviceInfo()
        
        // Resolve path
        let expandedPath = (filePath as NSString).expandingTildeInPath
        let resolvedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            printError("File not found: \(resolvedPath)")
            return
        }
        
        // Read file
        guard let data = FileManager.default.contents(atPath: resolvedPath) else {
            printError("Cannot read file: \(resolvedPath)")
            return
        }
        
        // Calculate MD5 signature
        let signature = md5Hex(data)
        
        print("Requesting tone update...")
        print("File: \((resolvedPath as NSString).lastPathComponent)")
        print("Size: \(formatSize(UInt64(data.count)))")
        
        let result = try jensen.requestToneUpdate(signature: signature, size: UInt32(data.count))
        
        switch result {
        case .success:
            print("Request accepted. Uploading tone data...")
        case .lengthMismatch:
            printError("Length mismatch")
            return
        case .busy:
            printError("Device is busy - try again later")
            return
        case .cardFull:
            printError("SD card is full")
            return
        case .cardError:
            printError("SD card error")
            return
        case .unknown:
            printError("Unknown error from device")
            return
        }
        
        try jensen.updateTone(data)
        print("Tone update complete!")
    }
    
    static func runUACUpdate(_ jensen: Jensen, filePath: String) throws {
        _ = try jensen.getDeviceInfo()
        
        // Resolve path
        let expandedPath = (filePath as NSString).expandingTildeInPath
        let resolvedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            printError("File not found: \(resolvedPath)")
            return
        }
        
        // Read file
        guard let data = FileManager.default.contents(atPath: resolvedPath) else {
            printError("Cannot read file: \(resolvedPath)")
            return
        }
        
        // Calculate MD5 signature
        let signature = md5Hex(data)
        
        print("Requesting UAC update...")
        print("File: \((resolvedPath as NSString).lastPathComponent)")
        print("Size: \(formatSize(UInt64(data.count)))")
        
        let result = try jensen.requestUACUpdate(signature: signature, size: UInt32(data.count))
        
        switch result {
        case .success:
            print("Request accepted. Uploading UAC data...")
        case .lengthMismatch:
            printError("Length mismatch")
            return
        case .busy:
            printError("Device is busy - try again later")
            return
        case .cardFull:
            printError("SD card is full")
            return
        case .cardError:
            printError("SD card error")
            return
        case .unknown:
            printError("Unknown error from device")
            return
        }
        
        try jensen.updateUAC(data)
        print("UAC update complete!")
    }
    
    static func parseVersionFromFilename(_ filename: String) -> UInt32? {
        // Try to match patterns like "1.3.10" or "v1.3.10" in the filename
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)) else {
            return nil
        }
        
        guard let majorRange = Range(match.range(at: 1), in: filename),
              let minorRange = Range(match.range(at: 2), in: filename),
              let patchRange = Range(match.range(at: 3), in: filename),
              let major = UInt32(filename[majorRange]),
              let minor = UInt32(filename[minorRange]),
              let patch = UInt32(filename[patchRange]) else {
            return nil
        }
        
        // Encode as 0x00MMNNPP (major.minor.patch)
        return (major << 16) | (minor << 8) | patch
    }
    
    static func formatVersionCode(_ version: UInt32) -> String {
        let major = (version >> 16) & 0xFF
        let minor = (version >> 8) & 0xFF
        let patch = version & 0xFF
        return "\(major).\(minor).\(patch)"
    }
    
    static func md5Hex(_ data: Data) -> String {
        // Simple MD5 using CommonCrypto via Insecure module
        // Since we can't easily import CommonCrypto, we'll use a shell command
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try data.write(to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/md5")
            process.arguments = ["-q", tempFile.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            if let result = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return result
            }
        } catch {
            // Fallback: return empty (will likely fail the request)
        }
        return ""
    }
    
    // MARK: - Helpers
    
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
    
    static func formatSize(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        }
        return "\(bytes) B"
    }
    
    static func printError(_ message: String) {
        fputs("Error: \(message)\n", stderr)
    }
    
    static func getArgValue(_ args: Array<String>.SubSequence, for flag: String) -> String? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        let valueIndex = args.index(after: index)
        guard valueIndex < args.endIndex else { return nil }
        return args[valueIndex]
    }
    
    static func getVersionArg(_ args: Array<String>.SubSequence) -> String? {
        var skipNext = false
        // Skip first because it's the command
        for arg in args.dropFirst() {
            if skipNext {
                skipNext = false
                continue
            }
            if arg.starts(with: "-") {
                // Known flags with values
                if arg == "--model" || arg == "--access-token" || arg == "--output" || arg == "-o" {
                    skipNext = true
                }
                continue
            }
            return arg
        }
        return nil
    }
    
    // MARK: - Download Command
    
    static func runDownload(_ jensen: Jensen, filename: String?, downloadAll: Bool, outputDir: String, sync: Bool) throws {
        // Get device info first for version checking
        _ = try jensen.getDeviceInfo()
        
        // Get file list
        print("Loading file list...")
        let files = try jensen.listFiles()
        
        guard !files.isEmpty else {
            printError("No files on device")
            return
        }
        
        // Handle --all case
        if downloadAll {
            print("Downloading all \(files.count) files to '\(outputDir)'...")
            for (index, file) in files.enumerated() {
                print("\n[File \(index + 1)/\(files.count)] Processing: \(file.name)")
                if checkAndPrepareDownload(file: file, outputDir: outputDir, sync: sync) {
                    try downloadSingleFile(jensen, file: file, outputDir: outputDir)
                }
            }
            print("\nAll files processed.")
            return
        }
        
        // If no filename specified, list available files
        guard let targetFilename = filename else {
            print("\nAvailable files:")
            for (index, file) in files.enumerated() {
                print("  [\(index + 1)] \(file.name) (\(formatSize(UInt64(file.length))))")
            }
            print("\nUsage:")
            print("  hidock-cli download <filename> [--output <dir>] [--sync]")
            print("  hidock-cli download --all [--output <dir>] [--sync]")
            return
        }
        
        // Find the file
        guard let file = files.first(where: { $0.name == targetFilename }) else {
            printError("File not found: \(targetFilename)")
            print("Available files:")
            for file in files.prefix(10) {
                print("  - \(file.name)")
            }
            if files.count > 10 {
                print("  ... and \(files.count - 10) more")
            }
            return
        }
        
        if checkAndPrepareDownload(file: file, outputDir: outputDir, sync: sync) {
            print("Downloading: \(file.name)")
            try downloadSingleFile(jensen, file: file, outputDir: outputDir)
        }
    }
    
    // Helper to check file existence and handle sync/backup logic
    // Returns true if download should proceed
    static func checkAndPrepareDownload(file: FileEntry, outputDir: String, sync: Bool) -> Bool {
        let fileManager = FileManager.default
        let outputPath = (outputDir as NSString).appendingPathComponent(file.name)
        
        // If file doesn't exist, always download
        if !fileManager.fileExists(atPath: outputPath) {
            return true
        }
        
        // If sync is not enabled, overwrite (default behavior) logic handled by caller (downloadSingleFile overwrites)
        // But if we want to mimic "ask to overwrite" generally we might check here, but CLI usually overwrites.
        // Requirement says: "--sync ... only download the missing files"
        
        if !sync {
            // If not syncing, we just proceed to download (will overwrite)
            // Or maybe we should warn? But standard behavior implies force.
            // Let's assume standard behavior remains 'download and overwrite' if sync is NOT passed.
            return true
        }
        
        // Sync is enabled, check size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: outputPath)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            
            if fileSize == UInt64(file.length) {
                print("File exists and size matches (\(formatSize(UInt64(file.length)))). Skipping.")
                return false
            }
            
            // Size mismatch - backup and redownload
            print("File exists but size mismatch (Local: \(formatSize(UInt64(fileSize))), Remote: \(formatSize(UInt64(file.length)))).")
            
            // Find a free backup name
            var backupPath = outputPath + ".bak"
            var counter = 1
            while fileManager.fileExists(atPath: backupPath) {
                backupPath = outputPath + ".bak\(counter)"
                counter += 1
            }
            
            print("Renaming local file to: \( (backupPath as NSString).lastPathComponent )")
            try fileManager.moveItem(atPath: outputPath, toPath: backupPath)
            
            return true
            
        } catch {
            printError("Error checking local file: \(error)")
            // If error checking, safe to try download? Or fail? 
            // Better to try download.
            return true
        }
    }
    
    // Helper for downloading a single file
    static func downloadSingleFile(_ jensen: Jensen, file: FileEntry, outputDir: String) throws {
        print("Size: \(formatSize(UInt64(file.length)))")
        
        // Download the file with progress
        let startTime = Date()
        var lastPrintedProgress = -1
        
        let fileData = try jensen.downloadFile(
            filename: file.name,
            expectedSize: file.length
        ) { received, total in
            let progress = Int(Double(received) / Double(total) * 100)
            if progress != lastPrintedProgress && (progress % 10 == 0 || progress == 100) {
                let bar = String(repeating: "=", count: progress / 5) + String(repeating: " ", count: 20 - progress / 5)
                print("\r[\(bar)] \(progress)% (\(formatSize(UInt64(received))))", terminator: "")
                fflush(stdout)
                lastPrintedProgress = progress
            }
        }
        
        print("")  // Newline after progress
        
        // Save to file
        let outputPath: String
        if outputDir == "." {
            outputPath = file.name
        } else {
            // Create output directory if needed
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
            outputPath = (outputDir as NSString).appendingPathComponent(file.name)
        }
        
        try fileData.write(to: URL(fileURLWithPath: outputPath))
        
        // Update filesystem timestamps if date is available
        if let deviceDate = file.date {
            let attributes: [FileAttributeKey: Any] = [
                .creationDate: deviceDate,
                .modificationDate: deviceDate
            ]
            do {
                try FileManager.default.setAttributes(attributes, ofItemAtPath: outputPath)
            } catch {
                print("Warning: Could not set file timestamps: \(error)")
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let speed = Double(fileData.count) / elapsed / 1024  // KB/s
        
        print("Saved to: \(outputPath)")
        print("Downloaded \(formatSize(UInt64(fileData.count))) in \(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", speed)) KB/s)")
    }
    
    // MARK: - Delete Command
    
    static func runDelete(_ jensen: Jensen, filename: String) throws {
        // Get device info first
        _ = try jensen.getDeviceInfo()
        
        print("Deleting file: \(filename)")
        try jensen.deleteFile(name: filename)
        print("File deleted successfully.")
    }
    
    static func printUsage() {
        print("""
        hidock-cli - Command-line utility for HiDock USB devices
        
        USAGE:
            hidock-cli <command> [options]
        
        DEVICE INFO:
            info                                Get device model, firmware version, serial number
            battery                             Get battery status (P1/P1 Mini only)
            card-info                           Get SD card capacity and usage
        
        TIME MANAGEMENT:
            time get                            Get device time
            time set [YYYY-MM-DD HH:MM:SS]      Set device time (defaults to current time)
        
        FILE MANAGEMENT:
            count                               Get total file count
            list                                List all recording files with details
            download <file> [options]           Download a specific file
            download --all [options]            Download all files
            delete <filename>                   Delete a recording file
            recording                           Get current recording file info
        
        DOWNLOAD OPTIONS:
            --output <dir>                      Output directory (default: current dir)
            --sync                              Skip files that exist with matching size
        
        SETTINGS:
            settings get                        Get all device settings
            settings set-auto-record <on|off>   Enable/disable auto-recording
            settings set-auto-play <on|off>     Enable/disable auto-play
            settings set-notification <on|off>  Enable/disable notifications
            settings set-bt-tone <on|off>       Enable/disable Bluetooth tone
        
        BLUETOOTH (P1/P1 Mini only):
            bt-status                           Get Bluetooth connection status
            bt-paired                           List paired Bluetooth devices
            bt-scan                             Scan for nearby Bluetooth devices
            bt-connect <mac>                    Connect to device by MAC address
            bt-disconnect                       Disconnect current Bluetooth device
            bt-reconnect <mac>                  Reconnect to a known device
            bt-clear-paired                     Clear all paired devices
        
        DEVICE MODES:
            mass-storage                        Enter USB mass storage mode
            bnc-start                           Start BNC demo mode
            bnc-stop                            Stop BNC demo mode
        
        FIRMWARE UPDATES (use with caution):
            firmware-download [version]         Download firmware from server
                --output <dir>                  Save to directory instead of current
                --install                       Install after download
                --confirm                       Skip confirmation prompt
            firmware-update <file> [--confirm]  Upload firmware file (dangerous!)
            tone-update <file>                  Update notification tones
            uac-update <file>                   Update USB Audio Class firmware
        
        ADVANCED/FACTORY:
            format [--confirm]                  Format SD card (destructive!)
            factory-reset [--confirm]           Reset to factory defaults
            restore-factory [--confirm]         Restore factory settings (alt. method)
            usb-timeout get                     Get USB timeout value
            usb-timeout set <ms>                Set USB timeout in milliseconds
            send-key <mode> <keycode>           Send key code to device
                                                  mode: 1=single, 2=long, 3=double
                                                  key:  3=record, 4=mute, 5=playback
            record-test <start|stop> <type>     Start/stop recording test
        
        GLOBAL OPTIONS:
            --verbose, -v                       Enable verbose USB debug output
            --help, -h                          Show this help
            --version                           Show version
        
        EXAMPLES:
            hidock-cli info
            hidock-cli time set
            hidock-cli time set "2026-01-27 12:00:00"
            hidock-cli list
            hidock-cli download REC001.hda
            hidock-cli download --all --output ~/recordings
            hidock-cli download --all --output ./recs --sync
            hidock-cli settings set-auto-record on
            hidock-cli bt-connect AA:BB:CC:DD:EE:FF
            hidock-cli firmware-download 1.3.6 --install
            hidock-cli format --confirm
        """)
    }
    
    static func printSettingsUsage() {
        print("Usage:")
        print("  hidock-cli settings get                        Get all settings")
        print("  hidock-cli settings set-auto-record <on|off>   Enable/Disable auto-recording")
        print("  hidock-cli settings set-auto-play <on|off>     Enable/Disable auto-play")
        print("  hidock-cli settings set-notification <on|off>  Enable/Disable notifications")
        print("  hidock-cli settings set-bt-tone <on|off>       Enable/Disable Bluetooth tone")
    }
}

// Run the CLI
HiDockCLI.main()
