import Foundation

public class SafeTransport: JensenTransport {
    private let underlying: JensenTransport
    
    // Command Allow List: Read-only commands
    private let allowedCommandIDs: Set<CommandID> = [
        .queryDeviceInfo,
        .queryDeviceTime,
        .queryFileList,
        .queryFileCount,
        .transferFile,
        .getFileBlock,
        .getRecordingFile,
        .scheduleInfo,
        .transferFilePartial,
        .getSettings,
        .getBatteryStatus,
        .readCardInfo,
        .readWebusbTimeout,
        .bluetoothStatus,
        .btDevList,
        .btGetPairedDevList,
        .btScan
    ]
    
    public var isConnected: Bool {
        return underlying.isConnected
    }
    
    public var model: HiDockModel {
        return underlying.model
    }
    
    public init(wrapping transport: JensenTransport) {
        self.underlying = transport
    }
    
    public func connect() throws {
        try underlying.connect()
    }
    
    public func disconnect() {
        underlying.disconnect()
    }
    
    public func send(data: Data) throws {
        // Inspect CommandID from raw bytes
        // Format: Header(2) + CommandID(2) + ...
        // Index 0,1 are header. Index 2,3 are CommandID.
        
        guard data.count >= 4 else {
            // If data is too short, let underlying handle it or throw invalid packet
             try underlying.send(data: data)
             return
        }
        
        // CommandID is Big Endian
        let commandIDValue = (UInt16(data[2]) << 8) | UInt16(data[3])
        
        // Verify CommandID
        guard let commandID = CommandID(rawValue: commandIDValue) else {
            // Unknown command ID - block it for safety
            throw JensenError.unsupportedFeature("Unknown Command ID blocked by SafeTransport")
        }
        
        if allowedCommandIDs.contains(commandID) {
            try underlying.send(data: data)
        } else {
            throw JensenError.unsupportedFeature("Command \(commandID.name) blocked by SafeTransport")
        }
    }
    
    public func receive(timeout: TimeInterval) throws -> Data {
        return try underlying.receive(timeout: timeout)
    }
}
