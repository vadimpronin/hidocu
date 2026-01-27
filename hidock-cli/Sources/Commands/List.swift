import ArgumentParser
import JensenUSB
import Foundation

struct List: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "List all recording files with details")

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = Jensen(verbose: verbose)
        try jensen.connect()
        defer { jensen.disconnect() }

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
            let durationStr = Formatters.formatDuration(file.duration)
            let sizeStr = Formatters.formatSize(UInt64(file.length)).padding(toLength: 12, withPad: " ", startingAt: 0)
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
}
