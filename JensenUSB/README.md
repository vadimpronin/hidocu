# JensenUSB

**JensenUSB** is a native Swift library that acts as the communication driver for HiDock audio hardware. It handles
low-level USB I/O via macOS `IOKit` and provides a high-level, object-oriented API to manage recordings, configuration,
firmware updates, and Bluetooth connectivity on HiDock devices.

## 📋 Features

* **Device Discovery**: Automatic detection of H1, H1E, P1, and P1 Mini devices.
* **File Management**: List recordings, download files (with progress reporting), and delete files.
* **System Control**: Firmware updates, Factory Reset, SD Card formatting, and Mass Storage mode toggling.
* **Configuration**: Manage device settings (Auto-record, Voice prompts, Notifications).
* **Bluetooth Manager**: (P1/P1 Mini only) Scan, pair, and connect to Bluetooth headsets.
* **Protocol Handling**: Abstracts binary packet construction, sequence management, and CRC/Ack logic.

## 🔌 Supported Devices

* **HiDock H1** (Desktop Audio Dock)
* **HiDock H1E** (Essential Dock)
* **HiDock P1** (Portable AI Recorder)
* **HiDock P1 Mini**

## 💻 Requirements

* **macOS** 12.0 (Monterey) or later.
* **Swift** 5.9 or later.
* **App Sandbox**: If used in a sandboxed app, you must add the `com.apple.security.device.usb` entitlement.

## 📦 Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(path: "path/to/JensenUSB") // Or git URL
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["JensenUSB"]
    )
]
```

## 🚀 Quick Start

### 1. Connecting to a Device

The `Jensen` class is the main entry point. It manages the connection lifecycle and provides access to functional
controllers.

```swift
import JensenUSB

// 1. Initialize the driver
let jensen = Jensen(verbose: true)

do {
    // 2. Connect to the first available HiDock device
    try jensen.connect()
    
    print("Connected to: \(jensen.model)")
    print("Firmware Version: \(jensen.versionCode ?? "Unknown")")
    print("Serial Number: \(jensen.serialNumber ?? "Unknown")")

} catch {
    print("Failed to connect: \(error)")
}
```

### 2. Managing Recordings

Use the `file` controller to interact with the SD card.

```swift
// List files
let files = try jensen.file.list()
for file in files {
    print("Found: \(file.name) (\(file.duration) sec)")
}

// Download a file
if let firstFile = files.first {
    let data = try jensen.file.download(
        filename: firstFile.name, 
        expectedSize: firstFile.length
    ) { received, total in
        let progress = Double(received) / Double(total) * 100.0
        print("Download progress: \(Int(progress))%")
    }
    
    // Save data to disk...
}
```

### 3. Changing Settings

Use the `settings` controller to toggle device features.

```swift
// Enable Auto-Recording when a call starts
try jensen.settings.setAutoRecord(true)

// Disable "Start Recording" voice prompt
try jensen.settings.setAutoPlay(false)
```

## 🏗 Architecture

JensenUSB uses a controller-based architecture. The main `Jensen` instance holds references to specific logic modules:

| Controller              | Accessor           | Description                                |
|:------------------------|:-------------------|:-------------------------------------------|
| **FileController**      | `jensen.file`      | Listing, downloading, deleting recordings. |
| **SystemController**    | `jensen.system`    | Firmware, Factory Reset, SD Card Format.   |
| **SettingsController**  | `jensen.settings`  | Device configuration toggles.              |
| **TimeController**      | `jensen.time`      | RTC synchronization.                       |
| **BluetoothController** | `jensen.bluetooth` | Bluetooth scanning/pairing (P1 models).    |

## 📄 License

MIT License. See LICENSE file for details.
