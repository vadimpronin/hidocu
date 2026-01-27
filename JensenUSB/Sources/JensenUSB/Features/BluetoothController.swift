import Foundation

public class BluetoothController {
    unowned let core: Jensen
    
    init(core: Jensen) { self.core = core }
    
    public func getStatus() throws -> [String: Any]? {
        guard core.model.isP1 else {
            throw JensenError.unsupportedFeature("Bluetooth only available on P1 models")
        }
        
        if core.isLiveMode { return nil }
        
        var command = Command(.bluetoothStatus)
        let response = try core.send(&command)
        
        if response.body.isEmpty { return ["status": "disconnected"] }
        
        let statusByte = response.body[0]
        
        switch statusByte {
        case 1: return ["status": "disconnected"]
        case 2: return ["status": "scanning"]
        case 3: return ["status": "connecting"]
        default: break
        }
        
        // Connected - parse more details
        guard response.body.count >= 3 else {
            return ["status": "connected"]
        }
        
        let nameLength = Int(response.body[1]) << 8 | Int(response.body[2])
        var offset = 3
        
        var nameBytes: [UInt8] = []
        for i in 0..<nameLength {
            if offset + i >= response.body.count { break }
            nameBytes.append(response.body[offset + i])
        }
        offset += nameLength
        
        let name = String(bytes: nameBytes, encoding: .utf8) ?? "Unknown"
        
        // Parse MAC address
        var macParts: [String] = []
        for i in 0..<6 {
            if offset + i >= response.body.count { break }
            macParts.append(String(format: "%02X", response.body[offset + i]))
        }
        offset += 6
        
        var result: [String: Any] = [
            "status": "connected",
            "name": name,
            "mac": macParts.joined(separator: "-")
        ]
        
        if offset + 4 <= response.body.count {
            result["a2dp"] = response.body[offset] == 1
            result["hfp"] = response.body[offset + 1] == 1
            result["avrcp"] = response.body[offset + 2] == 1
            result["battery"] = Int(Double(response.body[offset + 3]) / 255.0 * 100)
        }
        
        return result
    }
    
    public func startScan(duration: Int = 30) throws {
        guard core.model.isP1 else { throw JensenError.unsupportedDevice }
        let dur = UInt8(min(max(duration, 0), 255))
        var command = Command(.btScan, body: [1, dur])
        _ = try core.send(&command)
    }
    
    public func stopScan() throws {
        guard core.model.isP1 else { return }
        var command = Command(.btScan, body: [0, 0])
        _ = try core.send(&command)
    }
    
    public func getScanResults() throws -> [ScannedDevice] {
        guard core.model.isP1 else { throw JensenError.unsupportedDevice }
        var command = Command(.btDevList)
        let response = try core.send(&command)
        
        if response.body.isEmpty { return [] }
        guard response.body.count >= 2 else { return [] }
        
        let count = Int(response.body[0]) << 8 | Int(response.body[1])
        var offset = 2
        var devices: [ScannedDevice] = []
        
        for _ in 0..<count {
            if offset + 2 > response.body.count { break }
            let len = Int(response.body[offset]) << 8 | Int(response.body[offset+1])
            offset += 2
            
            if offset + len > response.body.count { break }
            let deviceData = response.body[offset..<(offset+len)]
            let name = String(data: Data(deviceData), encoding: .utf8) ?? "Unknown"
            offset += len
            
            if offset + 10 > response.body.count { break }
            var macParts: [String] = []
            for j in 0..<6 {
                macParts.append(String(format: "%02X", response.body[offset+j]))
            }
            offset += 6
            let rssi = Int(Int8(bitPattern: response.body[offset]))
            offset += 1
            let cod = UInt32(response.body[offset]) << 16 | UInt32(response.body[offset+1]) << 8 | UInt32(response.body[offset+2])
            offset += 3
            
            let isAudio = ((cod & 0x1F00) >> 8) == 4
            devices.append(ScannedDevice(name: name, mac: macParts.joined(separator: "-"), rssi: rssi, cod: cod, audio: isAudio))
        }
        return devices
    }
    
    public func connect(mac: String) throws {
        guard core.model.isP1 else { throw JensenError.unsupportedDevice }
        let parts = mac.split(separator: "-").map { String($0) }
        guard parts.count == 6 else { throw JensenError.commandFailed("Invalid MAC address format") }
        
        var body: [UInt8] = [0] // Subcommand 0
        for part in parts {
            if let byte = UInt8(part, radix: 16) { body.append(byte) }
        }
        var command = Command(.bluetoothCmd, body: body)
        _ = try core.send(&command)
    }
    
    public func disconnect() throws {
        guard core.model.isP1 else { throw JensenError.unsupportedDevice }
        var command = Command(.bluetoothCmd, body: [1])
        _ = try core.send(&command)
    }
    
    public func reconnect(mac: String) throws {
         guard core.model.isP1 else { throw JensenError.unsupportedDevice }
         let parts = mac.split(separator: "-").map { String($0) }
         guard parts.count == 6 else { throw JensenError.commandFailed("Invalid MAC address format") }
         
         var body: [UInt8] = [3] // Subcommand 3
         for part in parts {
             if let byte = UInt8(part, radix: 16) { body.append(byte) }
         }
         var command = Command(.bluetoothCmd, body: body)
         _ = try core.send(&command)
    }
    
    public func clearPaired() throws {
         guard core.model.isP1 else { throw JensenError.unsupportedDevice }
         var command = Command(.btRemovePairedDev, body: [0])
         _ = try core.send(&command)
    }
    
    public func getPairedDevices() throws -> [PairedDevice] {
        guard core.model == .p1 || core.model == .p1Mini else { throw JensenError.unsupportedDevice }
        
        var command = Command(.btGetPairedDevList)
        let response = try core.send(&command, timeout: 5.0)
        
        guard response.body.count >= 2 else { return [] }
        let deviceCount = Int(response.body[0]) << 8 | Int(response.body[1])
        
        var devices: [PairedDevice] = []
        var offset = 2
        for _ in 0..<deviceCount {
             guard offset + 2 <= response.body.count else { break }
             let nameLength = Int(response.body[offset]) << 8 | Int(response.body[offset + 1])
             offset += 2
             guard offset + nameLength <= response.body.count else { break }
             let nameData = response.body[offset..<(offset + nameLength)]
             let name = String(data: Data(nameData), encoding: .utf8) ?? "Unknown"
             offset += nameLength
             guard offset + 6 <= response.body.count else { break }
             var macParts: [String] = []
             for j in 0..<6 { macParts.append(String(format: "%02X", response.body[offset + j])) }
             offset += 6
             guard offset < response.body.count else { break }
             let sequence = response.body[offset]
             offset += 1
             
             if !name.hasPrefix("UUUU") {
                 devices.append(PairedDevice(name: name, mac: macParts.joined(separator: "-"), sequence: sequence))
             }
        }
        return devices
    }
}
