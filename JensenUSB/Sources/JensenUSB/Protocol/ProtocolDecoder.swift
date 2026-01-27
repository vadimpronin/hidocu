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
        
        // Calculate absolute index base
        let base = data.startIndex + offset
        
        // Check header
        // Use base for indexing
        guard data[base] == 0x12 && data[base + 1] == 0x34 else {
            throw ProtocolError.malformedHeader
        }
        
        // Parse command ID
        let commandID = UInt16(data[base + 2]) << 8 | UInt16(data[base + 3])
        
        // Parse sequence number
        let sequence = UInt32(data[base + 4]) << 24 |
                       UInt32(data[base + 5]) << 16 |
                       UInt32(data[base + 6]) << 8 |
                       UInt32(data[base + 7])
        
        // Parse body length (24-bit) + padding (8-bit stored in high byte)
        let lengthRaw = UInt32(data[base + 8]) << 24 |
                        UInt32(data[base + 9]) << 16 |
                        UInt32(data[base + 10]) << 8 |
                        UInt32(data[base + 11])
        
        let padding = (lengthRaw >> 24) & 0xFF
        let bodyLength = Int(lengthRaw & 0x00FFFFFF)
        
        // Check if we have complete message
        let totalLength = 12 + bodyLength + Int(padding)
        guard available >= totalLength else { return nil }
        
        // Extract body
        let bodyStart = base + 12
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
                // Resync: search for next 0x12 0x34
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
        // start is relative offset
        let count = data.count
        guard start < count - 1 else { return nil }
        
        let absStart = data.startIndex + start
        // Scan until the second-to-last byte (since we check i and i+1)
        let absEnd = data.startIndex + count - 1
        
        // Scan using absolute indices
        for i in absStart..<absEnd {
            if data[i] == 0x12 && data[i+1] == 0x34 {
                // Return relative offset
                return i - data.startIndex
            }
        }
        return nil
    }
}
