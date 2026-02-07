//
//  Recording.swift
//  HiDocu
//
//  Shared recording enums used across the app.
//

import Foundation

/// Recording mode as determined by the HiDock device.
enum RecordingMode: String, Sendable, CaseIterable, Hashable {
    case call
    case recording
    case whisper

    var displayName: String {
        switch self {
        case .call:    return "Call"
        case .recording:    return "Recording"
        case .whisper: return "Whisper"
        }
    }
}
