import Foundation

public class SettingsController {
    unowned let core: Jensen
    
    init(core: Jensen) { self.core = core }
    
    public func get() throws -> DeviceSettings {
        // Check version requirement
        if let version = core.versionNumber {
            if (core.model == .h1 || core.model == .h1e) && version < 0x00050012 {
                return DeviceSettings(autoRecord: false, autoPlay: false, notification: false, bluetoothTone: true)
            }
        }
        
        var command = Command(.getSettings)
        let response = try core.send(&command)
        
        guard response.body.count >= 16 else {
            throw JensenError.invalidResponse
        }
        
        return DeviceSettings(
            autoRecord: response.body[3] == 1,
            autoPlay: response.body[7] == 1,
            notification: response.body.count >= 12 ? response.body[11] == 1 : false,
            bluetoothTone: response.body[15] != 1  // Inverted logic!
        )
    }
    
    public func setAutoRecord(_ enabled: Bool) throws {
        // Body: [0, 0, 0, <1|2>] where 1=on, 2=off
        let body: [UInt8] = [0, 0, 0, enabled ? 1 : 2]
        var command = Command(.setSettings, body: body)
        _ = try core.send(&command, timeout: 5.0)
    }
    
    public func setAutoPlay(_ enabled: Bool) throws {
        // Body: [0, 0, 0, 0, 0, 0, 0, <1|2>]
        let body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, enabled ? 1 : 2]
        var command = Command(.setSettings, body: body)
        _ = try core.send(&command, timeout: 5.0)
    }
    
    public func setNotification(_ enabled: Bool) throws {
        // Body: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, <1|2>]
        let body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, enabled ? 1 : 2]
        var command = Command(.setSettings, body: body)
        _ = try core.send(&command, timeout: 5.0)
    }
    
    public func setBluetoothTone(_ enabled: Bool) throws {
        // Body: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, <2|1>] - inverted!
        let body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, enabled ? 2 : 1]
        var command = Command(.setSettings, body: body)
        _ = try core.send(&command, timeout: 5.0)
    }
}
