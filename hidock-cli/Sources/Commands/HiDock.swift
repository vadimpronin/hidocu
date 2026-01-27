import ArgumentParser
import Foundation

@main
struct HiDock: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "hidock-cli",
        abstract: "A utility for managing HiDock voice recorders.",
        version: "0.2.0",
        subcommands: [
            Info.self,
            List.self,
            TimeCmd.self,
            CardInfo.self,
            Battery.self,
            Delete.self,
            Recording.self,
            Count.self,
            Settings.self,
            BTStatus.self,
            BTPaired.self,
            BTScan.self,
            BTConnect.self,
            BTDisconnect.self,
            BTReconnect.self,
            BTClearPaired.self,
            MassStorage.self,
            Format.self,
            FactoryReset.self,
            RestoreFactory.self,
            USBTimeout.self,
            BNCStart.self,
            BNCStop.self,
            SendKey.self,
            RecordTest.self,
            Download.self,
            FirmwareCheck.self,
            FirmwareDownload.self,
            FirmwareUpdate.self,
            ToneUpdate.self,
            UACUpdate.self,
        ]
    )
}
