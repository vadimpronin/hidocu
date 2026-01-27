// HiDock USB Device abstraction using IOKit
// Handles USB device discovery, connection, and bulk transfers

import Foundation
import IOKit
import IOKit.usb

// MARK: - IOKit UUID Constants
// These are not directly available in Swift, so we define them manually

let kIOUSBDeviceUserClientTypeUUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

let kIOUSBInterfaceUserClientTypeUUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4,
    0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

let kIOCFPlugInInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

let kIOUSBDeviceInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
    0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

let kIOUSBInterfaceInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4,
    0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

// MARK: - USB Error Types

enum USBError: Error, LocalizedError {
    case deviceNotFound
    case connectionFailed(String)
    case transferFailed(String)
    case deviceNotOpen
    case interfaceNotClaimed
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No HiDock device found"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .transferFailed(let msg):
            return "Transfer failed: \(msg)"
        case .deviceNotOpen:
            return "Device not open"
        case .interfaceNotClaimed:
            return "USB interface not claimed"
        case .timeout:
            return "USB transfer timeout"
        }
    }
}

// MARK: - Device Model

enum HiDockModel: String {
    case h1 = "hidock-h1"
    case h1e = "hidock-h1e"
    case p1 = "hidock-p1"
    case p1Mini = "hidock-p1:mini"
    case unknown = "unknown"
    
    static func from(productID: UInt16) -> HiDockModel {
        switch productID {
        case 45068, 256, 258: return .h1
        case 45069, 257, 259: return .h1e
        case 45070, 8256: return .p1
        case 45071, 8257: return .p1Mini
        default: return .unknown
        }
    }
    
    var isP1: Bool {
        self == .p1 || self == .p1Mini
    }
}

// MARK: - USB Device

class USBDevice {
    // HiDock vendor IDs
    static let vendorIDs: [UInt16] = [4310, 14471]
    
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?
    private var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?
    
    let productID: UInt16
    let vendorID: UInt16
    let model: HiDockModel
    
    private(set) var isOpen: Bool = false
    private(set) var isInterfaceClaimed: Bool = false
    
    init(productID: UInt16, vendorID: UInt16, deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?) {
        self.productID = productID
        self.vendorID = vendorID
        self.deviceInterface = deviceInterface
        self.model = HiDockModel.from(productID: productID)
    }
    
    deinit {
        close()
    }
    
    // MARK: - Device Discovery
    
    static func findDevice() throws -> USBDevice {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        guard result == kIOReturnSuccess else {
            throw USBError.deviceNotFound
        }
        
        defer { IOObjectRelease(iterator) }
        
        var service: io_service_t = IOIteratorNext(iterator)
        while service != 0 {
            defer { 
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            // Get vendor and product ID
            var vendorID: UInt16 = 0
            var productID: UInt16 = 0
            
            if let vendorRef = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0) {
                vendorID = (vendorRef.takeRetainedValue() as? NSNumber)?.uint16Value ?? 0
            }
            
            if let productRef = IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0) {
                productID = (productRef.takeRetainedValue() as? NSNumber)?.uint16Value ?? 0
            }
            
            // Check if this is a HiDock device
            if Self.vendorIDs.contains(vendorID) {
                // Get device interface
                var score: Int32 = 0
                var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
                
                let kr = IOCreatePlugInInterfaceForService(
                    service,
                    kIOUSBDeviceUserClientTypeUUID,
                    kIOCFPlugInInterfaceUUID,
                    &plugInInterface,
                    &score
                )
                
                guard kr == kIOReturnSuccess, let plugIn = plugInInterface else {
                    continue
                }
                
                defer { _ = plugIn.pointee?.pointee.Release(plugIn) }
                
                var deviceInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?
                let queryResult = withUnsafeMutablePointer(to: &deviceInterfacePtr) { ptr in
                    plugIn.pointee?.pointee.QueryInterface(
                        plugIn,
                        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceUUID),
                        UnsafeMutablePointer<LPVOID?>(OpaquePointer(ptr))
                    )
                }
                
                guard queryResult == S_OK, let deviceInterface = deviceInterfacePtr else {
                    continue
                }
                
                return USBDevice(productID: productID, vendorID: vendorID, deviceInterface: deviceInterface)
            }
        }
        
        throw USBError.deviceNotFound
    }
    
    // MARK: - Connection Management
    
    func open() throws {
        guard let device = deviceInterface?.pointee?.pointee else {
            throw USBError.connectionFailed("No device interface")
        }
        
        let result = device.USBDeviceOpen(deviceInterface)
        guard result == kIOReturnSuccess else {
            throw USBError.connectionFailed("USBDeviceOpen failed: \(result)")
        }
        
        isOpen = true
        
        // Configure device
        try configureDevice()
        try claimInterface()
    }
    
    private func configureDevice() throws {
        guard let device = deviceInterface?.pointee?.pointee else {
            throw USBError.deviceNotOpen
        }
        
        // Set configuration 1
        let result = device.SetConfiguration(deviceInterface, 1)
        guard result == kIOReturnSuccess else {
            throw USBError.connectionFailed("SetConfiguration failed: \(result)")
        }
    }
    
    private func claimInterface() throws {
        guard let device = deviceInterface?.pointee?.pointee else {
            throw USBError.deviceNotOpen
        }
        
        // Create interface iterator
        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )
        
        var iterator: io_iterator_t = 0
        let result = device.CreateInterfaceIterator(deviceInterface, &request, &iterator)
        guard result == kIOReturnSuccess else {
            throw USBError.connectionFailed("CreateInterfaceIterator failed: \(result)")
        }
        
        defer { IOObjectRelease(iterator) }
        
        let usbInterface = IOIteratorNext(iterator)
        guard usbInterface != 0 else {
            throw USBError.connectionFailed("No interface found")
        }
        
        defer { IOObjectRelease(usbInterface) }
        
        // Get interface interface
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        
        let kr = IOCreatePlugInInterfaceForService(
            usbInterface,
            kIOUSBInterfaceUserClientTypeUUID,
            kIOCFPlugInInterfaceUUID,
            &plugInInterface,
            &score
        )
        
        guard kr == kIOReturnSuccess, let plugIn = plugInInterface else {
            throw USBError.connectionFailed("Failed to create plugin interface")
        }
        
        defer { _ = plugIn.pointee?.pointee.Release(plugIn) }
        
        var interfaceInterfacePtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>?>?
        let queryResult = withUnsafeMutablePointer(to: &interfaceInterfacePtr) { ptr in
            plugIn.pointee?.pointee.QueryInterface(
                plugIn,
                CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceUUID),
                UnsafeMutablePointer<LPVOID?>(OpaquePointer(ptr))
            )
        }
        
        guard queryResult == S_OK, let intfInterface = interfaceInterfacePtr else {
            throw USBError.connectionFailed("Failed to get interface interface")
        }
        
        self.interfaceInterface = intfInterface
        
        // Open interface
        let openResult = intfInterface.pointee?.pointee.USBInterfaceOpen(intfInterface)
        guard openResult == kIOReturnSuccess else {
            throw USBError.connectionFailed("USBInterfaceOpen failed: \(String(describing: openResult))")
        }
        
        isInterfaceClaimed = true
    }
    
    func close() {
        if isInterfaceClaimed, let intf = interfaceInterface {
            _ = intf.pointee?.pointee.USBInterfaceClose(intf)
            _ = intf.pointee?.pointee.Release(intf)
            interfaceInterface = nil
            isInterfaceClaimed = false
        }
        
        if isOpen, let device = deviceInterface {
            _ = device.pointee?.pointee.USBDeviceClose(device)
            _ = device.pointee?.pointee.Release(device)
            deviceInterface = nil
            isOpen = false
        }
    }
    
    // MARK: - Transfers
    
    func transferOut(endpoint: UInt8, data: Data) throws {
        guard isInterfaceClaimed, let intf = interfaceInterface?.pointee?.pointee else {
            throw USBError.interfaceNotClaimed
        }
        
        // Find the pipe number for the endpoint
        let pipeRef = try findPipeRef(for: endpoint, direction: kUSBOut)
        
        var mutableData = data
        let result = mutableData.withUnsafeMutableBytes { buffer in
            intf.WritePipe(
                interfaceInterface,
                pipeRef,
                buffer.baseAddress,
                UInt32(data.count)
            )
        }
        
        guard result == kIOReturnSuccess else {
            throw USBError.transferFailed("WritePipe failed: \(String(format: "0x%08X", result))")
        }
    }
    
    func transferIn(endpoint: UInt8, length: Int, timeout: UInt32 = 5000) throws -> Data {
        guard isInterfaceClaimed, let intf = interfaceInterface?.pointee?.pointee else {
            throw USBError.interfaceNotClaimed
        }
        
        let pipeRef = try findPipeRef(for: endpoint, direction: kUSBIn)
        
        var buffer = Data(count: length)
        var actualLength = UInt32(length)
        
        let result = buffer.withUnsafeMutableBytes { bufferPtr in
            intf.ReadPipeTO(
                interfaceInterface,
                pipeRef,
                bufferPtr.baseAddress,
                &actualLength,
                timeout,  // noDataTimeout
                timeout   // completionTimeout
            )
        }
        
        // IOKit timeout error code (0xe0004051 as signed Int32)
        let kIOUSBTransactionTimeoutValue: IOReturn = Int32(bitPattern: 0xe0004051)
        if result == kIOUSBTransactionTimeoutValue {
            throw USBError.timeout
        }
        
        guard result == kIOReturnSuccess else {
            throw USBError.transferFailed("ReadPipe failed: \(String(format: "0x%08X", result))")
        }
        
        return buffer.prefix(Int(actualLength))
    }
    
    private func findPipeRef(for endpoint: UInt8, direction: Int) throws -> UInt8 {
        guard let intf = interfaceInterface?.pointee?.pointee else {
            throw USBError.interfaceNotClaimed
        }
        
        var numEndpoints: UInt8 = 0
        let result = intf.GetNumEndpoints(interfaceInterface, &numEndpoints)
        guard result == kIOReturnSuccess else {
            throw USBError.transferFailed("GetNumEndpoints failed")
        }
        
        for pipeRef: UInt8 in 1...numEndpoints {
            var dir: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0
            
            let pipeResult = intf.GetPipeProperties(
                interfaceInterface,
                pipeRef,
                &dir,
                &number,
                &transferType,
                &maxPacketSize,
                &interval
            )
            
            if pipeResult == kIOReturnSuccess {
                let isOut = (direction == kUSBOut)
                let pipeIsOut = (dir == kUSBOut)
                
                if number == endpoint && isOut == pipeIsOut {
                    return pipeRef
                }
            }
        }
        
        // Default mapping: endpoint 1 -> pipe 2, endpoint 2 -> pipe 1
        if endpoint == 1 { return 2 }
        if endpoint == 2 { return 1 }
        
        throw USBError.transferFailed("Pipe not found for endpoint \(endpoint)")
    }
}
