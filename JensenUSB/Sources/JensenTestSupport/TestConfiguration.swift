import Foundation
import JensenUSB

public struct TestConfiguration {
    public static var isRealDeviceMode: Bool {
        return ProcessInfo.processInfo.environment["TEST_MODE"] == "REAL"
    }
    
    public static func createTransport() -> JensenTransport {
        if isRealDeviceMode {
            return SafeTransport(wrapping: USBTransport())
        } else {
            return MockTransport()
        }
    }
}
