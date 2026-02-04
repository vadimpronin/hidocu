import Foundation
import IOKit
import IOKit.usb

import os

// IOKit Notification Constants (sometimes missing in Swift)
let kIOPublishNotification = "IOServicePublish"
let kIOTerminateNotification = "IOServiceTerminate"

public final class USBMonitor: NSObject {
    
    private let logger = Logger(subsystem: "com.hidocu.jensenusb", category: "USBMonitor")
    
    // Callbacks
    public var deviceDidConnect: ((UInt64) -> Void)?
    public var deviceDidDisconnect: ((UInt64) -> Void)?
    
    private var notificationPort: IONotificationPortRef?
    private var notificationRunLoopSource: CFRunLoopSource?
    private var iterators: [io_iterator_t] = []
    
    public override init() {
        super.init()
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        guard notificationPort == nil else {
            logger.warning("start called but already running")
            return
        }
        
        logger.info("Starting...")
        
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort = notificationPort else {
            logger.error("Failed to create IONotificationPort")
            return
        }
        
        // CFRunLoopSource handling
        let source = IONotificationPortGetRunLoopSource(notificationPort)
        if let unmanagedSource = source {
             notificationRunLoopSource = unmanagedSource.takeUnretainedValue()
        }
        
        if let source = notificationRunLoopSource {
            logger.info("Adding source to Main RunLoop")
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            logger.error("Failed to get RunLoop source")
        }
        
        // Monitor all USB devices (filter in callback)
        observe()
    }
    
    public func stop() {
        logger.info("Stopping...")
        if let source = notificationRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            notificationRunLoopSource = nil
        }
        
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        
        for iterator in iterators {
            IOObjectRelease(iterator)
        }
        iterators.removeAll()
    }
    
    private func observe() {
        guard let notificationPort = notificationPort else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        // 1. Device Added
        let matchDictAdded = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        
        var addedIterator: io_iterator_t = 0
        let resultAdded = IOServiceAddMatchingNotification(
            notificationPort,
            kIOPublishNotification,
            matchDictAdded,
            handleDeviceAdded,
            context,
            &addedIterator
        )
        
        if resultAdded == kIOReturnSuccess {
            iterators.append(addedIterator)
            logger.info("Registered ADDED notification for all USB devices")
            handleDeviceAdded(refCon: context, iterator: addedIterator)
        } else {
            logger.error("Failed to register ADDED notification: \(resultAdded)")
        }
        
        // 2. Device Removed
        let matchDictRemoved = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        
        var removedIterator: io_iterator_t = 0
        let resultRemoved = IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminateNotification,
            matchDictRemoved,
            handleDeviceRemoved,
            context,
            &removedIterator
        )
        
        if resultRemoved == kIOReturnSuccess {
            iterators.append(removedIterator)
            logger.info("Registered REMOVED notification for all USB devices")
            handleDeviceRemoved(refCon: context, iterator: removedIterator)
        } else {
            logger.error("Failed to register REMOVED notification: \(resultRemoved)")
        }
    }
    
    fileprivate func processDevices(iterator: io_iterator_t, isArrival: Bool) {
        while case let device = IOIteratorNext(iterator), device != 0 {
            // Filter by Vendor ID
            var vendorID: UInt16 = 0
            if let vendorRef = IORegistryEntryCreateCFProperty(device, "idVendor" as CFString, kCFAllocatorDefault, 0) {
                 vendorID = (vendorRef.takeRetainedValue() as? NSNumber)?.uint16Value ?? 0
            }
            
            // Only proceed if it matches our vendors
            if USBDevice.vendorIDs.contains(vendorID) {
                var entryID: UInt64 = 0
                let result = IORegistryEntryGetRegistryEntryID(device, &entryID)
                
                if result == kIOReturnSuccess {
                    logger.info("HiDock Device event: \(isArrival ? "CONNECTED" : "DISCONNECTED") (Vendor: \(vendorID), EntryID: \(entryID))")
                    if isArrival {
                        deviceDidConnect?(entryID)
                    } else {
                        deviceDidDisconnect?(entryID)
                    }
                } else {
                     logger.error("Failed to get RegistryEntryID")
                }
            }
            
            IOObjectRelease(device)
        }
    }
}

// Global C-handlers
private func handleDeviceAdded(refCon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refCon = refCon else { return }
    let monitor = Unmanaged<USBMonitor>.fromOpaque(refCon).takeUnretainedValue()
    monitor.processDevices(iterator: iterator, isArrival: true)
}

private func handleDeviceRemoved(refCon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refCon = refCon else { return }
    let monitor = Unmanaged<USBMonitor>.fromOpaque(refCon).takeUnretainedValue()
    monitor.processDevices(iterator: iterator, isArrival: false)
}
