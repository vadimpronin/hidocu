import Foundation

/// Handles encoding of commands into the wire protocol format
struct ProtocolEncoder {
    
    /// Encode a command into a data packet
    /// Format: Header (2) + CommandID (2) + Sequence (4) + Length (4) + Body
    static func encode(_ command: Command) -> Data {
        var packet = Data(capacity: 12 + command.body.count)
        
        // Header: 0x12 0x34
        packet.append(0x12)
        packet.append(0x34)
        
        // Command ID (big-endian)
        packet.append(UInt8((command.id.rawValue >> 8) & 0xFF))
        packet.append(UInt8(command.id.rawValue & 0xFF))
        
        // Sequence number (big-endian)
        packet.append(UInt8((command.sequence >> 24) & 0xFF))
        packet.append(UInt8((command.sequence >> 16) & 0xFF))
        packet.append(UInt8((command.sequence >> 8) & 0xFF))
        packet.append(UInt8(command.sequence & 0xFF))
        
        // Body length (big-endian, 24-bit + 8-bit reserved/padding in high byte)
        // Usually padding is 0 for commands
        let length = UInt32(command.body.count)
        packet.append(UInt8((length >> 24) & 0xFF)) // Reserved/Padding
        packet.append(UInt8((length >> 16) & 0xFF))
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        
        // Body
        packet.append(contentsOf: command.body)
        
        return packet
    }
}
