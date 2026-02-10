//
//  AppEventService.swift
//  HiDocu
//
//  Lightweight event bus for cross-layer UI updates.
//  Uses Combine PassthroughSubject — no GRDB/SQLite observers.
//

import Foundation
import Combine

/// Events fired by background services to notify the UI layer of data changes.
enum AppEvent {
    /// A document's body or summary was updated (e.g. after judge/summary job).
    case documentUpdated(id: Int64)
    /// Transcripts for a document were created or modified (e.g. after transcription job).
    case transcriptsUpdated(documentId: Int64)
    /// A background LLM job finished (any type).
    case jobCompleted(jobId: Int64, documentId: Int64?)
}

/// Thread-safe event bus for broadcasting data-change notifications.
///
/// Producers call `send(_:)` from any isolation context (actors, MainActor, etc.).
/// Consumers subscribe via `publisher` and filter for relevant events.
final class AppEventService: @unchecked Sendable {

    private let subject = PassthroughSubject<AppEvent, Never>()

    /// Publish an event. Thread-safe — can be called from any actor or thread.
    func send(_ event: AppEvent) {
        subject.send(event)
    }

    /// Subscribe to the event stream.
    var publisher: AnyPublisher<AppEvent, Never> {
        subject.eraseToAnyPublisher()
    }
}
