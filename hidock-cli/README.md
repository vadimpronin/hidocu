# hidock-cli

A native macOS command-line utility for managing HiDock voice recorders via USB. This tool allows developers and power
users to interact programmatically with their HiDock devices to manage recordings, configure settings, and control
Bluetooth connections.

## Supported Devices

* **HiDock H1** (Desktop Audio Dock)
* **HiDock H1E** (Essential Dock)
* **HiDock P1** (Portable AI Recorder)
* **HiDock P1 Mini** (Ultra-portable Recorder)

## Features

* **File Management**: List, count, and delete recording files.
* **Smart Download**: Batch download recordings with resume capability.
* Includes a `--sync` mode to detect changed files and backup local copies before overwriting.


* **Device Configuration**: View and toggle device settings (Auto-record, Auto-play, Notifications).
* **Bluetooth Manager**: Scan, pair, connect, and disconnect Bluetooth devices (P1/P1 Mini).
* **System Status**: View battery levels, firmware versions, and storage capacity.
* **Time Sync**: Synchronize device clock with your computer.

## Prerequisites

* **macOS** 12.0 (Monterey) or later.
* **Swift** 5.9 or later.
* **Xcode Command Line Tools** (for building).

> **Note:** This tool currently relies on the `IOKit` framework and is exclusively for macOS. Linux support is planned
> but not yet implemented.

## 📦 Installation

### Build from Source

1. Clone the repository:

```bash
git clone https://github.com/yourusername/hidock-cli.git
cd hidock-cli

```

2. Build the project using the Makefile:

```bash
make build

```

3. (Optional) Install to `/usr/local/bin`:

```bash
sudo make install

```

### Run without Installing

You can compile and run directly using Swift:

```bash
cd hidock-cli
swift run hidock-cli info

```

## Usage

The general syntax is:

```bash
hidock-cli <command> [subcommand] [flags]

```

### Device Information

Get core details about the connected device.

```bash
# General device info (Model, Serial, Firmware)
hidock-cli info

# Get battery status (P1/P1 Mini only)
hidock-cli battery

# Check SD card usage
hidock-cli card-info

```

### Device Time

Manage the internal clock of the device (critical for correct file timestamps).

```bash
# Get current device time
hidock-cli time get

# Sync device time to current system time
hidock-cli time set

# Set a specific time
hidock-cli time set "2025-01-27 14:30:00"

```

### File Operations

Manage audio recordings stored on the device.

```bash
# List all files
hidock-cli list

# Get total file count
hidock-cli count

# Delete a specific file
hidock-cli delete 20250127REC001.wav

# Check current recording status
hidock-cli recording

```

### Downloading Files

The `download` command supports single file fetch, batch download, and smart syncing.

```bash
# Download a specific file to current directory
hidock-cli download 20250127REC001.wav

# Download to a specific folder
hidock-cli download 20250127REC001.wav --output ~/Music/HiDock

# Download ALL files (overwrites existing files)
hidock-cli download --all --output ~/Music/HiDock

# Smart Sync (Recommended)
# Downloads files only if they differ from local versions.
# If a local file exists but sizes differ, the local file is renamed to .bak
hidock-cli download --all --sync --output ~/Music/HiDock

```

### Settings Configuration

Read and toggle hardware behaviors.

```bash
# View all current settings
hidock-cli settings get

# Enable/Disable Auto-Recording on calls
hidock-cli settings set-auto-record on

# Enable/Disable "Start Recording" voice prompt
hidock-cli settings set-auto-play off

# Enable/Disable USB connection popup (Windows only feature)
hidock-cli settings set-notification off

# Enable/Disable Bluetooth connection tones
hidock-cli settings set-bt-tone on

```

### Bluetooth Management

*Specific to HiDock P1 and P1 Mini.*

```bash
# View current connection status
hidock-cli bt-status

# List paired devices
hidock-cli bt-paired

# Scan for available devices (runs for 5 seconds)
hidock-cli bt-scan

# Connect to a device by MAC address
hidock-cli bt-connect A1-B2-C3-D4-E5-F6

# Disconnect current device
hidock-cli bt-disconnect

# Clear all paired devices
hidock-cli bt-clear-paired

```

### USB Mass Storage Mode

```bash
# Switch device to USB Mass Storage mode
# (Device will disconnect from CLI and mount as a drive)
hidock-cli mass-storage

```

