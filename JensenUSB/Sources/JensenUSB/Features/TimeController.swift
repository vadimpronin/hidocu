import Foundation

public class TimeController {
    unowned let core: Jensen
    
    init(core: Jensen) { self.core = core }
    
    public func get() throws -> DeviceTime {
        var command = Command(.queryDeviceTime)
        let response = try core.send(&command)
        
        guard response.body.count >= 7 else {
            throw JensenError.invalidResponse
        }
        
        // Parse BCD time
        var bcdBytes: [UInt8] = []
        for i in 0..<7 {
            bcdBytes.append(response.body[i])
        }
        
        let timeString = BCDConverter.fromBCD(bcdBytes)
        
        if timeString == "00000000000000" {
            return DeviceTime(timeString: "unknown")
        }
        
        // Format as YYYY-MM-DD HH:mm:ss
        let formatted = timeString.replacingOccurrences(
            of: #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$"#,
            with: "$1-$2-$3 $4:$5:$6",
            options: .regularExpression
        )
        
        return DeviceTime(timeString: formatted)
    }
    
    public func set(_ date: Date = Date()) throws {
        // Format date as YYYYMMDDHHmmss
        let dateString = BCDConverter.formatDate(date)
        
        // Convert to BCD
        let bcdBytes = BCDConverter.toBCD(dateString)
        
        var command = Command(.setDeviceTime, body: bcdBytes)
        _ = try core.send(&command, timeout: 5.0)
    }
}
