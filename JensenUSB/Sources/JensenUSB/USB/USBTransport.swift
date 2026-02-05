import Foundation

public class USBTransport: JensenTransport {
    private var device: USBDevice?
    public let entryID: UInt64?
    
    public var isConnected: Bool {
        return device?.isOpen ?? false
    }
    
    public var model: HiDockModel {
        return device?.model ?? .unknown
    }
    
    public init(entryID: UInt64? = nil) {
        self.entryID = entryID
    }
    
    public func connect() throws {
        if let id = entryID {
            device = try USBDevice.open(entryID: id)
        } else {
            device = try USBDevice.findDevice()
        }
        try device?.open()
    }
    
    public func disconnect() {
        device?.close()
        device = nil
    }
    
    public func send(data: Data) throws {
        guard let device = device else { throw JensenError.notConnected }
        // Endpoint 1 is OUT
        try device.transferOut(endpoint: 1, data: data)
    }
    
    public func receive(timeout: TimeInterval) throws -> Data {
        guard let device = device else { throw JensenError.notConnected }
        // Endpoint 2 is IN, buffer 512KB
        return try device.transferIn(endpoint: 2, length: 512 * 1024, timeout: UInt32(timeout * 1000))
    }
}
