import Foundation

public class FileController {
    unowned let core: Jensen
    
    init(core: Jensen) { self.core = core }
    
    public func count() throws -> FileCount {
        var command = Command(.queryFileCount)
        let response = try core.send(&command)
        
        guard response.body.count >= 4 else {
            throw JensenError.invalidResponse
        }
        
        let count = Int(response.body[0]) << 24 |
                   Int(response.body[1]) << 16 |
                   Int(response.body[2]) << 8 |
                   Int(response.body[3])
                   
        return FileCount(count: count)
    }
    
    public func list() throws -> [FileEntry] {
        core.suppressKeepAlive = true
        defer { core.suppressKeepAlive = false }
        
        var expectedCount: Int? = nil
        if let version = core.versionNumber, version <= 0x0005001A {
            let c = try count()
            if c.count == 0 { return [] }
            expectedCount = c.count
        }
        
        var command = Command(.queryFileList)
        command.setSequence(core.nextSequence())
        let packet = command.makePacket()
        
        try core.transport.send(data: packet)
        
        var allData = Data()
        let deadline = Date().addingTimeInterval(30.0)
        
        while Date() < deadline {
            do {
                let chunk = try core.transport.receive(timeout: 5.0)
                allData.append(chunk) // Append raw data, we will parse it later or incrementally
                
                // Optional: We could try to parse incrementally here to return early
                // But parseFileList logic is designed to parse the whole blob.
                // Let's stick to original behavior: append and try parse.
                
                if let files = parseFileList(allData, expectedCount: expectedCount) {
                    return files
                }
            } catch {
                if !allData.isEmpty, let files = parseFileList(allData, expectedCount: expectedCount) {
                    return files
                }
                if Date() >= deadline { break }
            }
        }
        
        return parseFileList(allData, expectedCount: nil) ?? []
    }
    
    public func download(filename: String, expectedSize: UInt32, progressHandler: ((Int, Int) -> Void)? = nil) throws -> Data {
        core.suppressKeepAlive = true
        defer { core.suppressKeepAlive = false }
        
        var filenameBytes: [UInt8] = []
        for char in filename.utf8 { filenameBytes.append(char) }
        
        var command = Command(.transferFile, body: filenameBytes)
        command.setSequence(core.nextSequence())
        let packet = command.makePacket()
        
        try core.transport.send(data: packet)
        
        var fileData = Data()
        let deadline = Date().addingTimeInterval(120.0)
        var lastProgress = 0
        
        var buffer = Data()
        
        while Date() < deadline {
            do {
                let chunk = try core.transport.receive(timeout: 5.0)
                buffer.append(chunk)
                
                let (messages, consumed) = ProtocolDecoder.decodeStream(buffer)
                if consumed > 0 {
                    buffer.removeFirst(consumed)
                }
                
                for message in messages {
                    fileData.append(message.body)
                }
                
                let progress = Int(Double(fileData.count) / Double(expectedSize) * 100)
                if progress > lastProgress && progress % 5 == 0 {
                    progressHandler?(fileData.count, Int(expectedSize))
                    lastProgress = progress
                }
                
                if fileData.count >= expectedSize {
                    // Protocol might send padding/extra bytes in correct packets, 
                    // ProtocolDecoder handles bodies correctly. 
                    // So fileData should be clean.
                    // But if we got more than expected, we truncate? 
                    // Usually we just return what we got if it matches protocol.
                    return fileData
                }
                
            } catch {
                if fileData.count < expectedSize && Date() < deadline { continue }
                break
            }
        }
        
        if fileData.count > 0 { return fileData }
        throw JensenError.commandTimeout
    }
    
    public func delete(name: String) throws {
        var nameBytes: [UInt8] = []
        for char in name.utf8 { nameBytes.append(char) }
        var command = Command(.deleteFile, body: nameBytes)
        
        let response = try core.send(&command)
        if !response.body.isEmpty && response.body[0] != 0 {
             throw JensenError.commandFailed("Delete failed")
        }
    }
    
    private func parseFileList(_ data: Data, expectedCount: Int?) -> [FileEntry]? {
        let (messages, _) = ProtocolDecoder.decodeStream(data)
        
        var bodyData = Data()
        for message in messages {
            bodyData.append(message.body)
        }
        
        // ProtocolDecoder handles skipping invalid headers/resync logic better than previous manual loop.
        // It consumes all complete messages.
        
        if bodyData.isEmpty {
            return messages.isEmpty ? nil : []
        }
        
        var fileOffset = 0
        var files: [FileEntry] = []
        var totalCount: Int? = expectedCount
        
        if bodyData.count >= fileOffset + 6 {
            if bodyData[fileOffset] == 0xFF && bodyData[fileOffset + 1] == 0xFF {
                totalCount = Int(bodyData[fileOffset + 2]) << 24 |
                            Int(bodyData[fileOffset + 3]) << 16 |
                            Int(bodyData[fileOffset + 4]) << 8 |
                            Int(bodyData[fileOffset + 5])
                fileOffset += 6
            }
        }
        
        while fileOffset < bodyData.count {
            guard fileOffset + 4 < bodyData.count else { break }
            
            let version = bodyData[fileOffset]
            fileOffset += 1
            
            let nameLength = Int(bodyData[fileOffset]) << 16 |
                            Int(bodyData[fileOffset + 1]) << 8 |
                            Int(bodyData[fileOffset + 2])
            fileOffset += 3
            
            guard fileOffset + nameLength + 4 + 6 + 16 <= bodyData.count else { break }
            
            var nameBytes: [UInt8] = []
            for i in 0..<nameLength {
                let byte = bodyData[fileOffset + i]
                if byte > 0 { nameBytes.append(byte) }
            }
            fileOffset += nameLength
            
            let name = String(bytes: nameBytes, encoding: .utf8) ?? ""
            
            let fileSize = UInt32(bodyData[fileOffset]) << 24 |
                          UInt32(bodyData[fileOffset + 1]) << 16 |
                          UInt32(bodyData[fileOffset + 2]) << 8 |
                          UInt32(bodyData[fileOffset + 3])
            fileOffset += 4
            fileOffset += 6 // Reserved
            
            var sigParts: [String] = []
            for i in 0..<16 {
                sigParts.append(String(format: "%02x", bodyData[fileOffset + i]))
            }
            fileOffset += 16
            
            let (dateStr, timeStr, dateObj) = parseFileName(name)
            
            var duration: TimeInterval = 0
            switch version {
            case 1: duration = Double(fileSize) / 32.0 / 1000.0
            case 2: duration = Double(fileSize - 44) / 48.0 / 2.0 / 1000.0
            case 3: duration = Double(fileSize - 44) / 48.0 / 2.0 / 2.0 / 1000.0
            case 5: duration = Double(fileSize) / 12.0 / 1000.0
            case 6: duration = Double(fileSize) / 16.0 / 1000.0
            case 7: duration = Double(fileSize) / 10.0 / 1000.0
            default: duration = Double(fileSize) / 32.0 / 1000.0
            }
            
            var mode = "room"
            if let match = name.range(of: #"-(\w+)\d+\.\w+$"#, options: .regularExpression) {
                let modeStr = String(name[match]).uppercased()
                if modeStr.contains("WHSP") || modeStr.contains("WIP") { mode = "whisper" }
                else if modeStr.contains("CALL") { mode = "call" }
                else if modeStr.contains("REC") { mode = "room" }
            }
            
            if !name.isEmpty {
                files.append(FileEntry(
                    name: name,
                    createDate: dateStr,
                    createTime: timeStr,
                    duration: duration,
                    version: version,
                    length: fileSize,
                    mode: mode,
                    signature: sigParts.joined(),
                    date: dateObj
                ))
            }
        }
        
        if let total = totalCount {
            if files.count >= total { return files }
            return nil
        }
        
        return messages.isEmpty ? nil : files
    }
    
    public func getRecordingFile() throws -> RecordingFile? {
        var command = Command(.getRecordingFile)
        let response = try core.send(&command)
        
        guard response.body.count >= 1 else { return nil }
        
        let name = String(data: response.body, encoding: .utf8) ?? "unknown"
        return RecordingFile(name: name, createDate: "", createTime: "")
    }

    private func parseFileName(_ name: String) -> (date: String, time: String, dateObj: Date?) {
        if let match = name.range(of: #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})REC"#, options: .regularExpression) {
            let matched = String(name[match])
            if matched.count >= 14 {
                let chars = Array(matched)
                let dateStr = "\(chars[0...3].compactMap{String($0)}.joined())/\(chars[4...5].compactMap{String($0)}.joined())/\(chars[6...7].compactMap{String($0)}.joined())"
                let timeStr = "\(chars[8...9].compactMap{String($0)}.joined()):\(chars[10...11].compactMap{String($0)}.joined()):\(chars[12...13].compactMap{String($0)}.joined())"
                let rawDate = "\(chars[0...13].compactMap{String($0)}.joined())"
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMddHHmmss"
                return (dateStr, timeStr, formatter.date(from: rawDate))
            }
        }
        
         if let _ = name.range(of: #"^\d{2,4}\w{3}\d{2}-\d{6}-"#, options: .regularExpression) {
             let components = name.components(separatedBy: "-")
             if components.count >= 2 {
                 let datePart = components[0]
                 let timePart = components[1]
                 var dateFormatted = datePart
                 var dateObj: Date? = nil
                 
                 let formatter = DateFormatter()
                 formatter.locale = Locale(identifier: "en_US_POSIX")
                 
                 if datePart.count == 9 {
                     let y = datePart.prefix(4)
                     let m = datePart.dropFirst(4).prefix(3)
                     let d = datePart.suffix(2)
                     dateFormatted = "\(y)-\(m)-\(d)"
                     formatter.dateFormat = "yyyyMMMdd-HHmmss"
                     dateObj = formatter.date(from: "\(datePart)-\(timePart)")
                 } else if datePart.count == 7 {
                     let y = "20" + datePart.prefix(2)
                     let m = datePart.dropFirst(2).prefix(3)
                     let d = datePart.suffix(2)
                     dateFormatted = "\(y)-\(m)-\(d)"
                     formatter.dateFormat = "yyMMMdd-HHmmss"
                     dateObj = formatter.date(from: "\(datePart)-\(timePart)")
                 }
                 
                 if timePart.count >= 6 {
                     let tChars = Array(timePart)
                     let time = "\(tChars[0...1].compactMap{String($0)}.joined()):\(tChars[2...3].compactMap{String($0)}.joined()):\(tChars[4...5].compactMap{String($0)}.joined())"
                     return (dateFormatted, time, dateObj)
                 }
             }
         }
        
        return ("", "", nil)
    }
}
