import ArgumentParser
import JensenUSB
import Foundation

struct TimeCmd: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "time",
        abstract: "Manage device time",
        subcommands: [TimeGet.self, TimeSet.self]
    )
}

struct TimeGet: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get device time"
    )
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = JensenFactory.make(verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        let time = try jensen.time.get()
        print("Device Time: \(time.timeString)")
    }
}

struct TimeSet: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set device time"
    )
    
    @Argument(help: "Date string (YYYY-MM-DD HH:mm:ss)")
    var dateString: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = JensenFactory.make(verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
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
                    throw ValidationError("Invalid date format. Use: YYYY-MM-DD HH:mm:ss or YYYY-MM-DD")
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
        
        try jensen.time.set(dateToSet)
        print("Time set successfully.")
        
        // Verify by reading back
        let newTime = try jensen.time.get()
        print("Device time now: \(newTime.timeString)")
    }
}
