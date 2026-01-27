import Foundation

public protocol JensenTransport {
    var isConnected: Bool { get }
    var model: HiDockModel { get }
    
    func connect() throws
    func disconnect()
    
    func send(data: Data) throws
    func receive(timeout: TimeInterval) throws -> Data
}
