import ArgumentParser
import JensenUSB
import Foundation

struct Info: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Get device information")

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = JensenFactory.make(verbose)
        try jensen.connect()
        defer { jensen.disconnect() }

        let info = try jensen.getDeviceInfo()
        
        print("Device Model: \(jensen.model.rawValue)")
        if let code = jensen.versionCode {
             print("Firmware Version: \(code)")
        } else {
             print("Firmware Version: Unknown")
        }
        if let ver = jensen.versionNumber {
            print("Version Number: 0x\(String(format: "%08X", ver))")
        }
        if let sn = jensen.serialNumber {
            print("Serial Number: \(sn)")
        }
    }
}
