//
//  RecordingTableView.swift
//  HiDocu
//
//  Reusable table for recording-like rows used across multiple screens.
//

import SwiftUI

struct RecordingTableConfiguration {
    var showSourceIcon: Bool = false
    var showSourceName: Bool = false
    var showStatusColumn: Bool = true
    var showDocumentColumn: Bool = false
    var nameBeforeDate: Bool = false
}

extension RecordingTableConfiguration {
    static let allRecordings = RecordingTableConfiguration(
        showSourceIcon: true,
        showSourceName: true,
        showStatusColumn: true,
        showDocumentColumn: true,
        nameBeforeDate: true
    )

    static let recordingSource = RecordingTableConfiguration(
        showStatusColumn: true,
        showDocumentColumn: true,
        nameBeforeDate: false
    )

    static let deviceDashboard = RecordingTableConfiguration(
        showStatusColumn: true,
        showDocumentColumn: false,
        nameBeforeDate: false
    )
}

struct RecordingTableView<Row: RecordingRowDisplayable, ContextMenuContent: View>: View {
    let rows: [Row]

    @Binding var selection: Set<Row.ID>
    @Binding var sortOrder: [KeyPathComparator<Row>]

    let config: RecordingTableConfiguration

    private let sourceName: (Row) -> String?
    private let statusSortComparator: KeyPathComparator<Row>?
    private let rowOpacity: (Row) -> Double
    private let sourceIcon: (Row) -> AnyView
    private let statusCell: (Row) -> AnyView
    private let documentCell: (Row) -> AnyView
    private let contextMenu: (Set<Row.ID>) -> ContextMenuContent
    private let primaryAction: ((Row) -> Void)?

    init<SourceIconContent: View, StatusContent: View, DocumentContent: View>(
        rows: [Row],
        selection: Binding<Set<Row.ID>>,
        sortOrder: Binding<[KeyPathComparator<Row>]>,
        config: RecordingTableConfiguration,
        sourceName: @escaping (Row) -> String? = { _ in nil },
        statusSortComparator: KeyPathComparator<Row>? = nil,
        rowOpacity: @escaping (Row) -> Double = { _ in 1.0 },
        primaryAction: ((Row) -> Void)? = nil,
        @ViewBuilder sourceIcon: @escaping (Row) -> SourceIconContent,
        @ViewBuilder statusCell: @escaping (Row) -> StatusContent,
        @ViewBuilder documentCell: @escaping (Row) -> DocumentContent,
        @ViewBuilder contextMenu: @escaping (Set<Row.ID>) -> ContextMenuContent
    ) {
        self.rows = rows
        _selection = selection
        _sortOrder = sortOrder
        self.config = config
        self.sourceName = sourceName
        self.statusSortComparator = statusSortComparator
        self.rowOpacity = rowOpacity
        self.primaryAction = primaryAction
        self.contextMenu = contextMenu
        self.sourceIcon = { row in AnyView(sourceIcon(row)) }
        self.statusCell = { row in AnyView(statusCell(row)) }
        self.documentCell = { row in AnyView(documentCell(row)) }
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            if config.showSourceIcon {
                TableColumn("") { row in
                    sourceIcon(row)
                        .opacity(effectiveOpacity(for: row))
                }
                .width(RecordingTableConstants.sourceIconColumnWidth)
            }

            if config.showSourceName {
                TableColumn("Source") { row in
                    Text(sourceName(row) ?? "Unknown")
                        .foregroundStyle(sourceName(row) != nil ? .secondary : .tertiary)
                        .opacity(effectiveOpacity(for: row))
                }
                .width(min: RecordingTableConstants.sourceColumnWidth.min, ideal: RecordingTableConstants.sourceColumnWidth.ideal)
            }

            if config.nameBeforeDate {
                TableColumn("Name", value: \.filename) { row in
                    Text(row.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                        .opacity(effectiveOpacity(for: row))
                }
                .width(min: RecordingTableConstants.nameColumnWidth.min, ideal: RecordingTableConstants.nameColumnWidth.ideal)

                TableColumn("Date", sortUsing: KeyPathComparator(\Row.sortableDate, order: .reverse)) { row in
                    if let date = row.createdAt {
                        Text(date.formatted(RecordingTableConstants.dateFormat))
                            .monospacedDigit()
                            .opacity(effectiveOpacity(for: row))
                    } else {
                        Text("--")
                            .foregroundStyle(.tertiary)
                            .opacity(effectiveOpacity(for: row))
                    }
                }
                .width(min: RecordingTableConstants.dateColumnWidth.min, ideal: RecordingTableConstants.dateColumnWidth.ideal)
            } else {
                TableColumn("Date", sortUsing: KeyPathComparator(\Row.sortableDate, order: .reverse)) { row in
                    if let date = row.createdAt {
                        Text(date.formatted(RecordingTableConstants.dateFormat))
                            .monospacedDigit()
                            .opacity(effectiveOpacity(for: row))
                    } else {
                        Text("--")
                            .foregroundStyle(.tertiary)
                            .opacity(effectiveOpacity(for: row))
                    }
                }
                .width(min: RecordingTableConstants.dateColumnWidth.min, ideal: RecordingTableConstants.dateColumnWidth.ideal)

                TableColumn("Name", value: \.filename) { row in
                    Text(row.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .monospacedDigit()
                        .opacity(effectiveOpacity(for: row))
                }
                .width(min: RecordingTableConstants.nameColumnWidth.min, ideal: RecordingTableConstants.nameColumnWidth.ideal)
            }

            TableColumn("Duration", sortUsing: KeyPathComparator(\Row.durationSortValue, order: .reverse)) { row in
                if let duration = row.durationSeconds {
                    Text(duration.formattedDurationFull)
                        .monospacedDigit()
                        .opacity(effectiveOpacity(for: row))
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                        .opacity(effectiveOpacity(for: row))
                }
            }
            .width(min: RecordingTableConstants.durationColumnWidth.min, ideal: RecordingTableConstants.durationColumnWidth.ideal)

            TableColumn("Mode", sortUsing: KeyPathComparator(\Row.modeDisplayName)) { row in
                Text(row.modeDisplayName)
                    .opacity(effectiveOpacity(for: row))
            }
            .width(min: RecordingTableConstants.modeColumnWidth.min, ideal: RecordingTableConstants.modeColumnWidth.ideal)

            TableColumn("Size", sortUsing: KeyPathComparator(\Row.fileSizeSortValue, order: .reverse)) { row in
                if let size = row.fileSizeBytes {
                    Text(size.formattedFileSize)
                        .monospacedDigit()
                        .opacity(effectiveOpacity(for: row))
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                        .opacity(effectiveOpacity(for: row))
                }
            }
            .width(min: RecordingTableConstants.sizeColumnWidth.min, ideal: RecordingTableConstants.sizeColumnWidth.ideal)

            if config.showStatusColumn {
                TableColumn("", sortUsing: statusSortComparator ?? KeyPathComparator(\Row.syncStatusSortOrder)) { row in
                    statusCell(row)
                        .opacity(effectiveOpacity(for: row))
                }
                .width(RecordingTableConstants.statusIconColumnWidth)
            }

            if config.showDocumentColumn {
                TableColumn("") { row in
                    documentCell(row)
                        .opacity(effectiveOpacity(for: row))
                }
                .width(min: RecordingTableConstants.documentColumnWidth.min, ideal: RecordingTableConstants.documentColumnWidth.ideal)
            }
        }
        .contextMenu(forSelectionType: Row.ID.self) { selectedIds in
            if !selectedIds.isEmpty {
                contextMenu(selectedIds)
            }
        }
        .onTapGesture(count: 2) {
            _ = runPrimaryAction()
        }
        .onKeyPress(.space) {
            runPrimaryAction() ? .handled : .ignored
        }
    }

    private func effectiveOpacity(for row: Row) -> Double {
        max(0, min(1, row.dimmingFactor * rowOpacity(row)))
    }

    private func runPrimaryAction() -> Bool {
        guard let primaryAction,
              let selectedID = selection.first,
              let selectedRow = rows.first(where: { $0.id == selectedID }) else {
            return false
        }

        primaryAction(selectedRow)
        return true
    }
}
