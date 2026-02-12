import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: Level
    let message: String

    enum Level: String {
        case info
        case warning
        case error
        case debug
    }
}
