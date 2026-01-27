import ArgumentParser
import JensenUSB
import Foundation

struct CardInfo: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Get SD card capacity and usage")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        let info = try jensen.getCardInfo()
        
        // Assuming Formatters is in Utils/Formatters.swift and part of the target
        let capacity = Formatters.formatSize(info.capacity)
        let used = Formatters.formatSize(info.used)
        let free = info.capacity > info.used ? Formatters.formatSize(info.capacity - info.used) : "0 B"
        let percentage = info.capacity > 0 ? Double(info.used) / Double(info.capacity) * 100 : 0
        
        print("Capacity: \(capacity)")
        print("Used: \(used) (\(String(format: "%.1f", percentage))%)")
        print("Free: \(free)")
        print("Status: \(info.status)")
    }
}

struct Battery: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Get battery status (P1/P1 Mini only)")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        let battery = try jensen.getBatteryStatus()
        
        print("Status: \(battery.status)")
        print("Battery Level: \(battery.percentage)%")
        print("Voltage: \(String(format: "%.2f", Double(battery.voltage) / 1000000.0))V")
    }
}

struct Delete: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Delete a recording file")
    
    @Argument(help: "Filename to delete")
    var filename: String

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        print("Deleting file: \(filename)")
        try jensen.deleteFile(name: filename)
        print("File deleted successfully.")
    }
}

struct Recording: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Get current recording file info")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
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
}

struct Count: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Get total file count")
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false
    
    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        let count = try jensen.getFileCount()
        print("Total Files: \(count.count)")
    }
}
