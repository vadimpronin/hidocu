import Foundation

public struct DeviceCapability {
    let model: HiDockModel
    let version: UInt32
    
    public init(model: HiDockModel, version: UInt32) {
        self.model = model
        self.version = version
    }
    
    public var supportsBatteryStatus: Bool {
        return model.isP1
    }
    
    public var supportsBluetooth: Bool {
        return model.isP1
    }
    
    public var supportsCardInfo: Bool {
        if (model == .h1 || model == .h1e) && version < 0x00050025 { return false }
        return true
    }
    
    public var supportsSettings_AutoRecord: Bool {
        if (model == .h1 || model == .h1e) && version < 0x00050012 { return false }
        return true
    }
    
    public var supportsFactoryReset: Bool {
        if (model == .h1 || model == .h1e) && version < 0x00050009 { return false }
        return true
    }
    
    public var supportsRestoreFactory: Bool {
        if model == .h1 && version < 0x00050048 { return false }
        if model == .h1e && version < 0x00060004 { return false }
        return true
    }
}
