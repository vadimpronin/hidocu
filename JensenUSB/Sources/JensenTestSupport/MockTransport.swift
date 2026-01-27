import Foundation
import JensenUSB

public class MockTransport: JensenTransport {
    // Properties to configure mock behavior
    public var shouldConnect: Bool = true
    public var mockModel: HiDockModel = .h1
    
    // Response queue - FIFO
    public var responseQueue: [Data] = []
    
    // Command tracking
    public var sentCommands: [Data] = []
    
    // Timing configuration
    public var receiveDelay: TimeInterval = 0
    
    // Connection state
    private var _isConnected: Bool = false
    public var isConnected: Bool { _isConnected }
    
    public var model: HiDockModel { mockModel }
    
    // Error injection
    public var nextReceiveError: Error?
    
    public init() {}
    
    public func connect() throws {
        if shouldConnect {
            _isConnected = true
        } else {
            throw JensenError.usbError("Device not found")
        }
    }
    
    public func disconnect() {
        _isConnected = false
    }
    
    public func send(data: Data) throws {
        guard _isConnected else { throw JensenError.notConnected }
        sentCommands.append(data)
    }
    
    public func receive(timeout: TimeInterval) throws -> Data {
        guard _isConnected else { throw JensenError.notConnected }
        
        if let error = nextReceiveError {
            nextReceiveError = nil
            throw error
        }
        
        if receiveDelay > 0 {
            Thread.sleep(forTimeInterval: receiveDelay)
        }
        
        if responseQueue.isEmpty {
            throw JensenError.commandTimeout
        }
        
        return responseQueue.removeFirst()
    }
    
    // MARK: - Helper Methods
    
    public func addResponse(_ message: Message) {
        // Encode message into protocol frame for tests
        
        var packet = Data()
        packet.append(0x12)
        packet.append(0x34)
        
        packet.append(UInt8((message.id >> 8) & 0xFF))
        packet.append(UInt8(message.id & 0xFF))
        
        packet.append(UInt8((message.sequence >> 24) & 0xFF))
        packet.append(UInt8((message.sequence >> 16) & 0xFF))
        packet.append(UInt8((message.sequence >> 8) & 0xFF))
        packet.append(UInt8(message.sequence & 0xFF))
        
        let length = UInt32(message.body.count)
        packet.append(UInt8((length >> 24) & 0xFF))
        packet.append(UInt8((length >> 16) & 0xFF))
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        
        packet.append(message.body)
        
        responseQueue.append(packet)
    }
    
    public func addRawResponse(_ data: Data) {
        responseQueue.append(data)
    }
    
    public func clearResponses() {
        responseQueue.removeAll()
    }
    
    public func clearSentCommands() {
        sentCommands.removeAll()
    }
    
    public func getLastSentCommand() -> Command? {
        guard let data = sentCommands.last else { return nil }
        return nil
    }
    
    public func getAllSentCommands() -> [Data] {
        return sentCommands
    }
}
