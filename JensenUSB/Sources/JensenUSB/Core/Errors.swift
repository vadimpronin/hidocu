import Foundation

public enum JensenError: Error, Equatable {
    case notConnected
    case commandTimeout
    case invalidResponse
    case unsupportedDevice
    case unsupportedFeature(String)
    case commandFailed(String)
    case usbError(String)
}
