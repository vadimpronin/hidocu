import Foundation

public class SystemController {
    unowned let core: Jensen
    
    init(core: Jensen) { self.core = core }
    
    public func factoryReset() throws {
        // Check capability
        if let version = core.versionNumber, version < 0x00050009 {
             if core.model == .h1 || core.model == .h1e { throw JensenError.unsupportedDevice }
        }
        
        var command = Command(.factoryReset)
        let response = try core.send(&command, timeout: 5.0)
        
        if !response.body.isEmpty && response.body[0] != 0 {
            throw JensenError.commandFailed("Factory reset failed")
        }
    }
    
    public func restoreFactorySettings() throws {
        // Capability check
        if let version = core.versionNumber {
            if core.model == .h1 && version < 0x00050048 { throw JensenError.unsupportedDevice }
            if core.model == .h1e && version < 0x00060004 { throw JensenError.unsupportedDevice }
        }
        
        var command = Command(.restoreFactorySettings)
        let response = try core.send(&command, timeout: 5.0)
        
        if !response.body.isEmpty && response.body[0] != 0 {
             throw JensenError.commandFailed("Restore factory settings failed")
        }
    }
    
    public func getCardInfo() throws -> CardInfo {
         // Capability check
         if let version = core.versionNumber {
             if (core.model == .h1 || core.model == .h1e) && version < 0x00050025 { throw JensenError.unsupportedDevice }
         }
         
         var command = Command(.readCardInfo)
         let response = try core.send(&command)
         
         guard response.body.count >= 12 else { throw JensenError.invalidResponse }
         
         // Protocol Analysis:
         // Field 0 (4 bytes): Free Space (in MB)
         // Field 1 (4 bytes): Total Capacity (in MB)
         // Field 2 (4 bytes): Status?
         // All Big Endian.
         
         let freeMB = UInt64(response.body[0]) << 24 | UInt64(response.body[1]) << 16 | UInt64(response.body[2]) << 8 | UInt64(response.body[3])
         let capacityMB = UInt64(response.body[4]) << 24 | UInt64(response.body[5]) << 16 | UInt64(response.body[6]) << 8 | UInt64(response.body[7])
         let statusVal = UInt64(response.body[8]) << 24 | UInt64(response.body[9]) << 16 | UInt64(response.body[10]) << 8 | UInt64(response.body[11])
         
         let usedMB = capacityMB > freeMB ? capacityMB - freeMB : 0
         
         let status: String
         switch statusVal {
         case 0: status = "ok"
         case 1: status = "full"
         case 2: status = "error"
         case 3: status = "no_card"
         default: status = String(format: "%x", statusVal)
         }
         
         let mb: UInt64 = 1024 * 1024
         return CardInfo(used: usedMB * mb, capacity: capacityMB * mb, status: status)
    }
    
    public func formatCard() throws {
        var command = Command(.formatCard, body: [0x01, 0x02, 0x03, 0x04])
        command.expireAfter(30.0) // Takes time
        let response = try core.send(&command, timeout: 30.0)
        
        if !response.body.isEmpty && response.body[0] != 0 {
             throw JensenError.commandFailed("Format card failed")
        }
    }
    
    public func getBatteryStatus() throws -> BatteryStatus {
        guard core.model.isP1 else { throw JensenError.unsupportedDevice }
        
        var command = Command(.getBatteryStatus)
        let response = try core.send(&command)
        
        guard response.body.count >= 6 else { throw JensenError.invalidResponse }
        
        let state = response.body[0]
        let status: String
        switch state {
        case 0: status = "idle"
        case 1: status = "charging"
        case 2: status = "full"
        default: status = "unknown"
        }
        
        let percentage = Int(response.body[1])
        let voltage = UInt32(response.body[2]) << 24 | UInt32(response.body[3]) << 16 | UInt32(response.body[4]) << 8 | UInt32(response.body[5])
        
        return BatteryStatus(status: status, percentage: percentage, voltage: voltage)
    }
    
    public func enterMassStorage() throws {
        var command = Command(.enterMassStorage, body: [0x01])
        _ = try core.send(&command)
    }
    
    public func getWebUSBTimeout() throws -> UInt32 {
        var command = Command(.readWebusbTimeout)
        let response = try core.send(&command)
        guard response.body.count >= 4 else { throw JensenError.invalidResponse }
        
        return UInt32(response.body[0]) << 24 | UInt32(response.body[1]) << 16 | UInt32(response.body[2]) << 8 | UInt32(response.body[3])
    }
    
    public func setWebUSBTimeout(_ timeout: UInt32) throws {
        var body: [UInt8] = []
        body.append(UInt8((timeout >> 24) & 0xFF))
        body.append(UInt8((timeout >> 16) & 0xFF))
        body.append(UInt8((timeout >> 8) & 0xFF))
        body.append(UInt8(timeout & 0xFF))
        
        var command = Command(.writeWebusbTimeout, body: body)
        _ = try core.send(&command)
    }
    
    // Firmware Update parts
    public enum FirmwareUpgradeResult: String {
        case accepted, wrongVersion, busy, cardFull, cardError, unknown, lengthMismatch
    }
    
    public func requestFirmwareUpgrade(versionNumber: UInt32, fileSize: UInt32) throws -> FirmwareUpgradeResult {
        var body: [UInt8] = []
        body.append(UInt8((versionNumber >> 24) & 0xFF))
        body.append(UInt8((versionNumber >> 16) & 0xFF))
        body.append(UInt8((versionNumber >> 8) & 0xFF))
        body.append(UInt8(versionNumber & 0xFF))
        body.append(UInt8((fileSize >> 24) & 0xFF))
        body.append(UInt8((fileSize >> 16) & 0xFF))
        body.append(UInt8((fileSize >> 8) & 0xFF))
        body.append(UInt8(fileSize & 0xFF))
        
        var command = Command(.requestFirmwareUpgrade, body: body)
        let response = try core.send(&command, timeout: 10.0)
        
        guard !response.body.isEmpty else { throw JensenError.invalidResponse }
        
        switch response.body[0] {
        case 0x00: return .accepted
        case 0x01: return .wrongVersion
        case 0x02: return .busy
        case 0x03: return .cardFull
        case 0x04: return .cardError
        default: return .unknown
        }
    }
    
    public func uploadFirmware(_ data: Data, progressHandler: ((Int, Int) -> Void)? = nil) throws {
        core.suppressKeepAlive = true
        defer { core.suppressKeepAlive = false }
        
        let packetSize = 512
        var offset = 0
        let total = data.count
        
        while offset < total {
            let chunkEnd = min(offset + packetSize, total)
            let chunk = data.subdata(in: offset..<chunkEnd)
            var chunkBytes: [UInt8] = []
            chunkBytes.append(contentsOf: chunk)
            
            var command = Command(.firmwareUpload, body: chunkBytes)
            command.setSequence(core.nextSequence())
            let response = try core.send(&command, timeout: 60.0) 
            if !response.body.isEmpty && response.body[0] != 0 {
                throw JensenError.commandFailed("Upload chunk failed")
            }
            
            offset += chunk.count
            progressHandler?(offset, total)
        }
    }
    
    public func requestToneUpdate(signature: String, size: UInt32) throws -> FirmwareUpgradeResult {
        var body: [UInt8] = []
        // Parse hex signature
        for i in stride(from: 0, to: min(signature.count, 32), by: 2) {
             let start = signature.index(signature.startIndex, offsetBy: i)
             let end = signature.index(start, offsetBy: 2)
             if let byte = UInt8(String(signature[start..<end]), radix: 16) {
                 body.append(byte)
             }
        }
        // Size
        body.append(UInt8((size >> 24) & 0xFF))
        body.append(UInt8((size >> 16) & 0xFF))
        body.append(UInt8((size >> 8) & 0xFF))
        body.append(UInt8(size & 0xFF))
        
        var command = Command(.requestToneUpdate, body: body)
        let response = try core.send(&command, timeout: 10.0)
        
        if response.body.isEmpty { return .unknown }
        switch response.body[0] {
        case 0x00: return .accepted
        case 0x01: return .lengthMismatch
        case 0x02: return .busy
        case 0x03: return .cardFull
        case 0x04: return .cardError
        default: return .unknown
        }
    }
    
    public func updateTone(_ data: Data) throws {
        core.suppressKeepAlive = true
        defer { core.suppressKeepAlive = false }
        
        var body: [UInt8] = []
        body.append(contentsOf: data)
        var command = Command(.toneUpdate, body: body)
        let response = try core.send(&command, timeout: 60.0)
        if !response.body.isEmpty && response.body[0] != 0 {
            throw JensenError.commandFailed("Tone update failed")
        }
    }
    
    public func requestUACUpdate(signature: String, size: UInt32) throws -> FirmwareUpgradeResult {
         var body: [UInt8] = []
         for i in stride(from: 0, to: min(signature.count, 32), by: 2) {
              let start = signature.index(signature.startIndex, offsetBy: i)
              let end = signature.index(start, offsetBy: 2)
              if let byte = UInt8(String(signature[start..<end]), radix: 16) { body.append(byte) }
         }
         body.append(UInt8((size >> 24) & 0xFF))
         body.append(UInt8((size >> 16) & 0xFF))
         body.append(UInt8((size >> 8) & 0xFF))
         body.append(UInt8(size & 0xFF))
         
         var command = Command(.requestUACUpdate, body: body)
         let response = try core.send(&command, timeout: 10.0)
         
         if response.body.isEmpty { return .unknown }
         switch response.body[0] {
         case 0x00: return .accepted
         case 0x01: return .lengthMismatch
         case 0x02: return .busy
         case 0x03: return .cardFull
         case 0x04: return .cardError
         default: return .unknown
         }
    }
    
    public func updateUAC(_ data: Data) throws {
         core.suppressKeepAlive = true
         defer { core.suppressKeepAlive = false }
         var body: [UInt8] = []
         body.append(contentsOf: data)
         var command = Command(.uacUpdate, body: body)
         let response = try core.send(&command, timeout: 60.0)
         if !response.body.isEmpty && response.body[0] != 0 {
             throw JensenError.commandFailed("UAC update failed")
         }
    }
    
    // Send Key
    public func sendKeyCode(mode: UInt8, keyCode: UInt8) throws {
        var command = Command(.sendKeyCode, body: [mode, keyCode])
        let response = try core.send(&command, timeout: 5.0)
        if !response.body.isEmpty && response.body[0] != 0 {
            throw JensenError.commandFailed("Send key failed")
        }
    }
    
    // Record tests
    public func recordTestStart(type: UInt8) throws {
        var command = Command(.recordTestStart, body: [type])
        _ = try core.send(&command)
    }
    public func recordTestEnd(type: UInt8) throws {
        var command = Command(.recordTestEnd, body: [type])
        _ = try core.send(&command)
    }
    
    // BNC
    public func beginBNC() throws {
        var command = Command(.deviceMsgTest, body: [1])
        _ = try core.send(&command)
    }
    public func endBNC() throws {
        var command = Command(.deviceMsgTest, body: [0])
        _ = try core.send(&command)
    }
}
