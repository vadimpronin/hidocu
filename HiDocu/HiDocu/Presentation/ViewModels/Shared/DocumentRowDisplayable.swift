//
//  DocumentRowDisplayable.swift
//  HiDocu
//
//  Shared display contract for document-like table rows.
//

import SwiftUI

protocol DocumentRowDisplayable: Identifiable where ID == Int64 {
    var title: String { get }
    var date: Date { get }
    var subtext: String? { get }
    var statusIcon: String? { get }
    var statusColor: Color { get }
    var isTrashed: Bool { get }
    var daysRemaining: Int? { get }
}

extension DocumentRowDisplayable {
    var sortableDate: Double { date.timeIntervalSince1970 }
    var sortableDaysRemaining: Int { daysRemaining ?? Int.max }
}
