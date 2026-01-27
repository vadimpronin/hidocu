import ArgumentParser
import JensenUSB
import Foundation

struct Download: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Download recording files")
    
    @Argument(help: "Filename to download")
    var filename: String?
    
    @Option(name: [.customShort("o"), .customLong("output")], help: "Output directory")
    var output: String = "."
    
    @Flag(help: "Download all files")
    var all: Bool = false
    
    @Flag(help: "Skip files that exist with matching size")
    var sync: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() throws {
        let jensen = JensenFactory.make(verbose)
        try jensen.connect()
        defer { jensen.disconnect() }
        
        // Expansion of tilde in output path
        let outputDir = (output as NSString).expandingTildeInPath
        
        // connect() already calls getDeviceInfo() to populate version/serial
        
        // Get file list
        print("Loading file list...")
        let files = try jensen.file.list()
        
        guard !files.isEmpty else {
            print("No files on device")
            return
        }
        
        // Handle --all case
        if all {
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
                print("  [\(index + 1)] \(file.name) (\(Formatters.formatSize(UInt64(file.length))))")
            }
            print("\nUsage:")
            print("  hidock-cli download <filename> [--output <dir>] [--sync]")
            print("  hidock-cli download --all [--output <dir>] [--sync]")
            return
        }
        
        // Find the file
        guard let file = files.first(where: { $0.name == targetFilename }) else {
            print("File not found: \(targetFilename)")
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
    
    func checkAndPrepareDownload(file: FileEntry, outputDir: String, sync: Bool) -> Bool {
        let fileManager = FileManager.default
        let outputPath = (outputDir as NSString).appendingPathComponent(file.name)
        
        if !fileManager.fileExists(atPath: outputPath) {
            return true
        }
        
        if !sync {
            return true
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: outputPath)
            let fileSize = attributes[.size] as? UInt64 ?? 0
            
            if fileSize == UInt64(file.length) {
                print("File exists and size matches (\(Formatters.formatSize(UInt64(file.length)))). Skipping.")
                return false
            }
            
            print("File exists but size mismatch (Local: \(Formatters.formatSize(UInt64(fileSize))), Remote: \(Formatters.formatSize(UInt64(file.length)))).")
            
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
            print("Error checking local file: \(error)")
            return true
        }
    }
    
    func downloadSingleFile(_ jensen: Jensen, file: FileEntry, outputDir: String) throws {
        print("Size: \(Formatters.formatSize(UInt64(file.length)))")
        
        let startTime = Date()
        var lastPrintedProgress = -1
        
        let fileData = try jensen.file.download(
            filename: file.name,
            expectedSize: file.length
        ) { received, total in
            let progress = Int(Double(received) / Double(total) * 100)
            if progress != lastPrintedProgress && (progress % 10 == 0 || progress == 100) {
                let bar = String(repeating: "=", count: progress / 5) + String(repeating: " ", count: 20 - progress / 5)
                print("\r[\(bar)] \(progress)% (\(Formatters.formatSize(UInt64(received))))", terminator: "")
                fflush(stdout)
                lastPrintedProgress = progress
            }
        }
        
        print("")
        
        let outputPath: String
        if outputDir == "." {
            outputPath = file.name
        } else {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
            outputPath = (outputDir as NSString).appendingPathComponent(file.name)
        }
        
        try fileData.write(to: URL(fileURLWithPath: outputPath))
        
        if let deviceDate = file.date {
            let attributes: [FileAttributeKey: Any] = [
                .creationDate: deviceDate,
                .modificationDate: deviceDate
            ]
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: outputPath)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let speed = Double(fileData.count) / elapsed / 1024
        
        print("Saved to: \(outputPath)")
        print("Downloaded \(Formatters.formatSize(UInt64(fileData.count))) in \(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", speed)) KB/s)")
    }
}
