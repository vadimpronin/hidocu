//
//  RecordingRowDisplayable.swift
//  HiDocu
//
//  Shared display contract for recording table rows.
//

import Foundation

protocol RecordingRowDisplayable: Identifiable where ID: Hashable {
    var filename: String { get }
    var createdAt: Date? { get }
    var durationSeconds: Int? { get }
    var fileSizeBytes: Int? { get }
    var recordingMode: RecordingMode? { get }
    var syncStatus: RecordingSyncStatus? { get }
    var documentInfo: [DocumentLink] { get }
    var isProcessing: Bool { get }
    var sortableDate: Double { get }
    var durationSortValue: Int { get }
    var fileSizeSortValue: Int { get }
    var modeDisplayName: String { get }
    var syncStatusSortOrder: Int { get }
    var dimmingFactor: Double { get }
}

extension RecordingRowDisplayable {
    var sortableDate: Double { createdAt?.timeIntervalSince1970 ?? 0 }
    var durationSortValue: Int { durationSeconds ?? 0 }
    var fileSizeSortValue: Int { fileSizeBytes ?? 0 }
    var modeDisplayName: String { recordingMode?.displayName ?? "—" }

    var syncStatusSortOrder: Int {
        switch syncStatus {
        case .onDeviceOnly?: return 0
        case .localOnly?: return 1
        case .synced?: return 2
        case nil: return -1
        }
    }

    var dimmingFactor: Double { 1.0 }
}

extension AllRecordingsRow: RecordingRowDisplayable {}

extension UnifiedRecordingRow: RecordingRowDisplayable {
    var fileSizeBytes: Int? { size }
    var recordingMode: RecordingMode? { mode }
}

extension DeviceFileRow: RecordingRowDisplayable {
    var fileSizeBytes: Int? { size }
    var recordingMode: RecordingMode? { mode }
    var syncStatus: RecordingSyncStatus? { isImported ? .synced : .onDeviceOnly }
    var documentInfo: [DocumentLink] { [] }
    var isProcessing: Bool { false }
}
