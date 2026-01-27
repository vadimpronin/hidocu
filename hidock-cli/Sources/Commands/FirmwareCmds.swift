import ArgumentParser
import JensenUSB
import Foundation

struct FirmwareCheck: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "firmware-check", abstract: "Check for firmware updates")
    
    @Option(name: .long, help: "Access token for API")
    var accessToken: String
    
    @Option(name: .long, help: "Model override (if no device connected)")
    var model: String?
    
    @Flag(name: .shortAndLong) var verbose: Bool = false

    func run() throws {
        var deviceModel = model
        var currentVersion: String?
        
        let jensen = Jensen(verbose: verbose)
        // Try to connect if model not provided
        if deviceModel == nil {
            try? jensen.connect()
            if jensen.isConnected {
                deviceModel = jensen.model.rawValue
                _ = try? jensen.getDeviceInfo()
                currentVersion = jensen.versionCode
                jensen.disconnect()
            }
        }
        
        guard let modelToUse = deviceModel else {
            print("Error: No device connected and no --model specified.")
            throw ExitCode.failure
        }
        
        print("Checking firmware for \(modelToUse)...")
        let result = FirmwareManager.fetchLatestFirmware(model: modelToUse, accessToken: accessToken)
        
        switch result {
        case .success(let fw):
            print("Latest Version: \(fw.version)")
            if let current = currentVersion {
                if fw.version != current {
                    print("Update available! (Current: \(current))")
                } else {
                    print("Device is up to date.")
                }
            }
            print("To download, run: hidock-cli firmware-download --access-token ...")
            
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

struct FirmwareDownload: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "firmware-download", abstract: "Download firmware from server")
    
    @Argument(help: "Specific version (optional)")
    var version: String?
    
    @Option(name: .long, help: "Access token for API")
    var accessToken: String?
    
    @Option(name: .long, help: "Model override")
    var model: String?
    
    @Option(name: .shortAndLong, help: "Output directory")
    var output: String?
    
    @Flag(name: .long, help: "Install after download")
    var install: Bool = false
    
    @Flag(name: .long, help: "Skip confirmation")
    var confirm: Bool = false
    
    @Flag(name: .shortAndLong) var verbose: Bool = false
    
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        var deviceModel = model
        
        if install {
            // Must connect for install
            try jensen.connect()
            if deviceModel == nil {
                deviceModel = jensen.model.rawValue
            }
        } else if deviceModel == nil {
            // Try to connect to get model
            try? jensen.connect()
            if jensen.isConnected {
                deviceModel = jensen.model.rawValue
                if !install {
                    jensen.disconnect()
                }
            }
        }
        
        guard let modelToUse = deviceModel else {
             print("Error: No device connected and no --model specified.")
             throw ExitCode.failure
        }
        
        guard let token = accessToken else {
            print("Error: --access-token is required.")
             throw ExitCode.failure
        }
        
        print("Fetching latest firmware info for \(modelToUse)...")
        let result = FirmwareManager.fetchLatestFirmware(model: modelToUse, accessToken: token)
        
        guard case .success(let fw) = result else {
            if case .failure(let error) = result {
                print("Error: \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
        
        if let v = version, v != fw.version {
            print("Requested version \(v) does not match latest server version \(fw.version)")
            throw ExitCode.failure
        }
        
        print("Firmware: \(fw.version)")
        print("Size: \(Formatters.formatSize(UInt64(fw.fileLength)))")
        if !fw.remark.isEmpty {
            print("\nRelease Notes:\n\(fw.remark)")
        }
        
        if !confirm && !install && output == nil {
            print("\nProceed with download? (y/n): ", terminator: "")
            fflush(stdout)
            guard let input = readLine()?.lowercased(), input == "y" else {
                print("Operation cancelled.")
                return
            }
        }
        
        print("Downloading...")
        guard let url = URL(string: fw.downloadURL) else { return }
        
        var lastPercent = -1
        let downloadResult = FirmwareManager.download(url: url) { written, total in
            if total > 0 {
                let percent = Int(Double(written) / Double(total) * 100)
                if percent != lastPercent && percent % 10 == 0 {
                    print("  \(percent)%")
                    lastPercent = percent
                }
            }
        }
        
        switch downloadResult {
        case .success(let data):
            print("Downloaded \(Formatters.formatSize(UInt64(data.count)))")
            
            if let outDir = output {
                let expandedPath = (outDir as NSString).expandingTildeInPath
                try FileManager.default.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
                let filename = "firmware-\(modelToUse.replacingOccurrences(of: ":", with: "-"))-\(fw.version).bin"
                let url = URL(fileURLWithPath: expandedPath).appendingPathComponent(filename)
                try data.write(to: url)
                print("Saved to: \(url.path)")
            } else if !install {
                 let filename = "firmware-\(modelToUse.replacingOccurrences(of: ":", with: "-"))-\(fw.version).bin"
                 try data.write(to: URL(fileURLWithPath: filename))
                 print("Saved to: \(filename)")
            }
            
            if install {
                if !jensen.isConnected { try jensen.connect() }
                
                 if jensen.model.rawValue != fw.model {
                    print("Model mismatch! Firmware is for \(fw.model) but connected device is \(jensen.model.rawValue)")
                     throw ExitCode.failure
                 }
                
                 if !confirm {
                     print("\nWARNING: Firmware update can potentially brick your device if interrupted.")
                     print("Type 'UPDATE' to confirm: ", terminator: "")
                     fflush(stdout)
                     guard let input = readLine(), input == "UPDATE" else {
                         print("Operation cancelled.")
                         return
                     }
                 }
                 
                 print("Requesting firmware upgrade...")
                 let upResult = try jensen.requestFirmwareUpgrade(
                     versionNumber: fw.versionNumber,
                     fileSize: UInt32(data.count)
                 )
                
                 if upResult != .accepted {
                     print("Update request failed: \(upResult)")
                     throw ExitCode.failure
                 }
                 
                 print("Request accepted. Uploading firmware...")
                 try jensen.uploadFirmware(data) { current, total in
                     let percent = Int(Double(current) / Double(total) * 100)
                     print("Progress: \(percent)%")
                 }
                 print("Firmware upload complete! Device will restart.")
            }
            
        case .failure(let error):
            print("Download failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
        
        if jensen.isConnected { jensen.disconnect() }
    }
}

struct FirmwareUpdate: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "firmware-update", abstract: "Upload firmware file from local disk")
    
    @Argument(help: "Path to firmware file")
    var filePath: String
    
    @Flag(name: .long, help: "Skip confirmation")
    var confirm: Bool = false
    
    @Flag(name: .shortAndLong) var verbose: Bool = false
    
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        let info = try jensen.getDeviceInfo()
        
        let expandedPath = (filePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
         guard FileManager.default.fileExists(atPath: url.path) else {
            print("File not found: \(url.path)")
            throw ExitCode.failure
        }
        
        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent
        // Simple parser
        let version = FirmwareUpdate.parseVersionFromFilename(filename)
        
        if let v = version {
            if v == info.versionNumber {
                print("WARNING: The firmware file version matches the currently installed version (\(info.versionCode)).")
                print("The device may reject re-flashing the same firmware.")
            } else if v < info.versionNumber {
                 print("WARNING: The firmware file version is older than the currently installed version (\(info.versionCode)).")
                 print("The device may reject downgrading.")
            }
        }
        
        if !confirm {
             print("WARNING: Firmware update can potentially brick your device if interrupted.")
             print("File: \(filename)")
             print("Size: \(Formatters.formatSize(UInt64(data.count)))")
             if let v = version {
                 let vStr = "\(v >> 16).\(v >> 8 & 0xFF).\(v & 0xFF)"
                 print("Version: \(vStr) (Device: \(info.versionCode))")
             }
             print("Type 'UPDATE' to confirm: ", terminator: "")
             fflush(stdout)
             guard let input = readLine(), input == "UPDATE" else {
                 print("Operation cancelled.")
                 return
             }
        }
        
        print("Requesting firmware upgrade...")
        let upResult = try jensen.requestFirmwareUpgrade(
             versionNumber: version ?? 0,
             fileSize: UInt32(data.count)
        )
         if upResult != .accepted {
             print("Update request failed: \(upResult)")
             if upResult == .wrongVersion {
                 print("Reason: The device rejected the version number (likely same or older version).")
             }
             throw ExitCode.failure
         }
         
         try jensen.uploadFirmware(data) { current, total in
             let percent = Int(Double(current) / Double(total) * 100)
             print("Progress: \(percent)%")
         }
         print("Complete.")
    }
    
    static func parseVersionFromFilename(_ filename: String) -> UInt32? {
         let pattern = #"(\d+)\.(\d+)\.(\d+)"#
         guard let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)) else {
             return nil
         }
         
         let nsString = filename as NSString
         guard let major = Int(nsString.substring(with: match.range(at: 1))),
               let minor = Int(nsString.substring(with: match.range(at: 2))),
               let patch = Int(nsString.substring(with: match.range(at: 3))) else {
             return nil
         }
         
         return UInt32((major << 16) | (minor << 8) | patch)
    }
}

struct ToneUpdate: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "tone-update", abstract: "Update notification tones")
    
    @Argument(help: "Path to tone file")
    var filePath: String
    
    @Flag(name: .shortAndLong) var verbose: Bool = false
    
    func run() throws {
         let jensen = Jensen(verbose: verbose)
         try jensen.connect()
         defer { jensen.disconnect() }
         
         _ = try jensen.getDeviceInfo()
        
         let expandedPath = (filePath as NSString).expandingTildeInPath
         guard FileManager.default.fileExists(atPath: expandedPath) else {
             print("File not found: \(expandedPath)")
             throw ExitCode.failure
         }
         
         let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
         let signature = Crypto.md5Hex(data)
         
         print("Requesting tone update...")
         print("File: \((expandedPath as NSString).lastPathComponent)")
         print("Size: \(Formatters.formatSize(UInt64(data.count)))")
         
         let result = try jensen.requestToneUpdate(signature: signature, size: UInt32(data.count))
         
         if case .accepted = result {
             print("Request accepted. Uploading tone data...")
             try jensen.updateTone(data)
             print("Tone update complete!")
         } else {
             print("Update request failed: \(result)")
             throw ExitCode.failure
         }
    }
}

struct UACUpdate: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "uac-update", abstract: "Update UAC firmware")
    
    @Argument(help: "Path to UAC file")
    var filePath: String
    
    @Flag(name: .shortAndLong) var verbose: Bool = false
    
    func run() throws {
         let jensen = Jensen(verbose: verbose)
         try jensen.connect()
         defer { jensen.disconnect() }
         
         _ = try jensen.getDeviceInfo()
        
         let expandedPath = (filePath as NSString).expandingTildeInPath
         guard FileManager.default.fileExists(atPath: expandedPath) else {
             print("File not found: \(expandedPath)")
             throw ExitCode.failure
         }
         
         let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
         let signature = Crypto.md5Hex(data)
         
         print("Requesting UAC update...")
         print("File: \((expandedPath as NSString).lastPathComponent)")
         print("Size: \(Formatters.formatSize(UInt64(data.count)))")
         
         let result = try jensen.requestUACUpdate(signature: signature, size: UInt32(data.count))
         
         if case .accepted = result {
             print("Request accepted. Uploading UAC data...")
             try jensen.updateUAC(data)
             print("UAC update complete!")
         } else {
             print("Update request failed: \(result)")
             throw ExitCode.failure
         }
    }
}
