//
//  main.swift
//  hidock-cli
//
//  HiDock CLI - Command-line utility for HiDock USB devices
//

import Foundation

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
                } else {
                    printError("Unknown settings subcommand: \(subcommand)")
                    print("Usage:")
                    print("  hidock-cli settings get")
                    print("  hidock-cli settings set-auto-record <on|off>")
                    print("  hidock-cli settings set-auto-play <on|off>")
                    print("  hidock-cli settings set-notification <on|off>")
                    print("  hidock-cli settings set-bt-tone <on|off>")
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
                
            case "download":
                let filename = args.dropFirst().first { !$0.starts(with: "-") }
                let outputDir = getArgValue(args, for: "--output") ?? "."
                let downloadAll = args.contains("--all")
                try runDownload(jensen, filename: filename, downloadAll: downloadAll, outputDir: outputDir)
                
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
        print("\("Name".padding(toLength: 35, withPad: " ", startingAt: 0)) \("Date".padding(toLength: 12, withPad: " ", startingAt: 0)) \("Time".padding(toLength: 10, withPad: " ", startingAt: 0)) \("Duration".padding(toLength: 10, withPad: " ", startingAt: 0)) \("Mode".padding(toLength: 8, withPad: " ", startingAt: 0)) Size")
        print(String(repeating: "-", count: 90))
        
        for file in files {
            let durationStr = formatDuration(file.duration)
            let sizeStr = formatSize(file.length)
            let nameStr = String(file.name.prefix(35)).padding(toLength: 35, withPad: " ", startingAt: 0)
            let dateStr = file.createDate.padding(toLength: 12, withPad: " ", startingAt: 0)
            let timeStr = file.createTime.padding(toLength: 10, withPad: " ", startingAt: 0)
            let durStr = durationStr.padding(toLength: 10, withPad: " ", startingAt: 0)
            let modeStr = file.mode.padding(toLength: 8, withPad: " ", startingAt: 0)
            
            print("\(nameStr) \(dateStr) \(timeStr) \(durStr) \(modeStr) \(sizeStr)")
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
    
    // MARK: - Helpers
    
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
    
    static func formatSize(_ bytes: UInt32) -> String {
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
    
    static func runDownload(_ jensen: Jensen, filename: String?, downloadAll: Bool, outputDir: String) throws {
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
                print("\n[File \(index + 1)/\(files.count)] Downloading: \(file.name)")
                try downloadSingleFile(jensen, file: file, outputDir: outputDir)
            }
            print("\nAll files downloaded successfully.")
            return
        }
        
        // If no filename specified, list available files
        guard let targetFilename = filename else {
            print("\nAvailable files:")
            for (index, file) in files.enumerated() {
                print("  [\(index + 1)] \(file.name) (\(formatSize(file.length)))")
            }
            print("\nUsage:")
            print("  hidock-cli download <filename> [--output <dir>]")
            print("  hidock-cli download --all [--output <dir>]")
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
        
        print("Downloading: \(file.name)")
        try downloadSingleFile(jensen, file: file, outputDir: outputDir)
    }
    
    // Helper for downloading a single file
    static func downloadSingleFile(_ jensen: Jensen, file: FileEntry, outputDir: String) throws {
        print("Size: \(formatSize(file.length))")
        
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
                print("\r[\(bar)] \(progress)% (\(formatSize(UInt32(received))))", terminator: "")
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
        
        let elapsed = Date().timeIntervalSince(startTime)
        let speed = Double(fileData.count) / elapsed / 1024  // KB/s
        
        print("Saved to: \(outputPath)")
        print("Downloaded \(formatSize(UInt32(fileData.count))) in \(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", speed)) KB/s)")
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
            settings get        Get device settings
            card-info           Get SD card information
            recording           Get current recording file
            battery             Get battery status (P1 only)
            bt-status           Get Bluetooth status (P1 only)
        
        OPTIONS:
            --verbose, -v       Enable verbose output
            --output <dir>      Output directory for downloads
            --all               Download all files
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
}

// Run the CLI
HiDockCLI.main()
