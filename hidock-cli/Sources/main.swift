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
                
            case "download":
                let filename = args.dropFirst().first { !$0.starts(with: "-") }
                let rawOutputDir = getArgValue(args, for: "--output") ?? "."
                let outputDir = (rawOutputDir as NSString).expandingTildeInPath
                let downloadAll = args.contains("--all")
                let sync = args.contains("--sync")
                try runDownload(jensen, filename: filename, downloadAll: downloadAll, outputDir: outputDir, sync: sync)
                
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
            printError(error.localizedDescription)
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
        
        COMMANDS:
            info                Get device information
            time get            Get device time
            count               Get file count
            list                List all recording files
            download <file>     Download a recording file
            download --all      Download all recording files
            delete <file>       Delete a recording file
            settings get        Get device settings
            settings set-*      Modify settings (see 'settings --help')
            card-info           Get SD card information
            recording           Get current recording file
            battery             Get battery status (P1 only)
            bt-status           Get Bluetooth status (P1 only)
            bt-paired           Get paired Bluetooth devices
            bt-scan             Scan for Bluetooth devices
            bt-connect <mac>    Connect to a Bluetooth device
            bt-disconnect       Disconnect current Bluetooth device
            bt-clear-paired     Clear all paired devices
            bt-clear-paired     Clear all paired devices
            mass-storage        Enter mass storage mode
            format              Format SD card (requires confirmation)
            factory-reset       Reset to factory defaults (Command 61451)
            restore-factory     Restore factory settings (Command 19)
            usb-timeout         Get/Set USB timeout
        
        OPTIONS:
            --verbose, -v       Enable verbose output
            --output <dir>      Output directory for downloads
            --all               Download all files
            --sync              Only download new or changed files (offsets existing to .bak)
            --help, -h          Show this help
            --version           Show version
        
        EXAMPLES:
            hidock-cli info
            hidock-cli list
            hidock-cli download 20250127REC001.hda
            hidock-cli download --all --output ~/recordings
            hidock-cli download 20250127REC001.hda --output ~/recordings
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
