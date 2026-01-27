import Foundation

/// Errors that can occur during protocol decoding
enum ProtocolError: Error {
    case malformedHeader
    case incompleteMessage
    case invalidBodyLength
}

/// Handles decoding of raw data into messages
struct ProtocolDecoder {
    
    /// Parse a single response message from raw data
    /// Returns (message, bytesConsumed) or throws if invalid
    /// Returns nil if data is valid but incomplete
    static func decode(_ data: Data, offset: Int = 0) throws -> (Message, Int)? {
        let available = data.count - offset
        
        // Need at least 12 bytes for header
        guard available >= 12 else { return nil }
        
        // Check header
        guard data[offset] == 0x12 && data[offset + 1] == 0x34 else {
            throw ProtocolError.malformedHeader
        }
        
        // Parse command ID
        let commandID = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
        
        // Parse sequence number
        let sequence = UInt32(data[offset + 4]) << 24 |
                       UInt32(data[offset + 5]) << 16 |
                       UInt32(data[offset + 6]) << 8 |
                       UInt32(data[offset + 7])
        
        // Parse body length (24-bit) + padding (8-bit stored in high byte)
        let lengthRaw = UInt32(data[offset + 8]) << 24 |
                        UInt32(data[offset + 9]) << 16 |
                        UInt32(data[offset + 10]) << 8 |
                        UInt32(data[offset + 11])
        
        let padding = (lengthRaw >> 24) & 0xFF
        let bodyLength = Int(lengthRaw & 0x00FFFFFF)
        
        // Check if we have complete message
        let totalLength = 12 + bodyLength + Int(padding)
        guard available >= totalLength else { return nil }
        
        // Extract body
        let bodyStart = offset + 12
        let bodyEnd = bodyStart + bodyLength
        let body = data[bodyStart..<bodyEnd]
        
        let message = Message(id: commandID, sequence: sequence, body: Data(body))
        return (message, totalLength)
    }
    
    /// Decode multiple messages from a stream buffer
    /// Returns decoded messages and the number of bytes consumed
    static func decodeStream(_ data: Data) -> ([Message], Int) {
        var messages: [Message] = []
        var offset = 0
        
        while true {
            do {
                if let (message, consumed) = try decode(data, offset: offset) {
                    messages.append(message)
                    offset += consumed
                } else {
                    // Incomplete message, waiting for more data
                    break
                }
            } catch {
                // If we hit an error (e.g. malformed header), we might need to resync
                // For now, we'll just stop parsing. In a real stream we might search for next header.
                // But given this is USB packet based, errors likely mean corrupt transfer.
                // Simple recovery: skip 1 byte and try again? 
                // For now, let's assume if header is bad at expected position, we stop content here.
                // Or maybe we should skip until we find 0x12 0x34?
                
                // Resync logic: search for next 0x12 0x34
                if let nextHeader = findNextHeader(data, start: offset + 1) {
                    offset = nextHeader
                    continue
                } else {
                    // No more headers found, consume all remaining as garbage
                    offset = data.count
                    break
                }
            }
        }
        
        return (messages, offset)
    }
    
    private static func findNextHeader(_ data: Data, start: Int) -> Int? {
        guard start < data.count - 1 else { return nil }
        for i in start..<(data.count - 1) {
            if data[i] == 0x12 && data[i+1] == 0x34 {
                return i
            }
        }
        return nil
    }
}
