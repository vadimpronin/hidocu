//
//  UnifiedRecordingListView.swift
//  HiDocu
//
//  Shared recording-list container that centralizes loading, empty, and refresh behavior.
//

import SwiftUI

struct UnifiedRecordingListView<
    Row: RecordingRowDisplayable,
    SourceIconContent: View,
    StatusContent: View,
    DocumentContent: View,
    ContextMenuContent: View
>: View {
    let rows: [Row]

    @Binding var selection: Set<Row.ID>
    @Binding var sortOrder: [KeyPathComparator<Row>]

    let isLoading: Bool
    let errorMessage: String?
    let config: RecordingTableConfiguration
    let emptyStateTitle: String
    let emptyStateSubtitle: String
    let onRefresh: () async -> Void

    private let sourceName: (Row) -> String?
    private let statusSortComparator: KeyPathComparator<Row>?
    private let rowOpacity: (Row) -> Double
    private let primaryAction: ((Row) -> Void)?
    private let sourceIcon: (Row) -> SourceIconContent
    private let statusCell: (Row) -> StatusContent
    private let documentCell: (Row) -> DocumentContent
    private let contextMenu: (Set<Row.ID>) -> ContextMenuContent

    init(
        rows: [Row],
        selection: Binding<Set<Row.ID>>,
        sortOrder: Binding<[KeyPathComparator<Row>]>,
        isLoading: Bool,
        errorMessage: String?,
        config: RecordingTableConfiguration,
        emptyStateTitle: String,
        emptyStateSubtitle: String,
        onRefresh: @escaping () async -> Void,
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
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.config = config
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateSubtitle = emptyStateSubtitle
        self.onRefresh = onRefresh
        self.sourceName = sourceName
        self.statusSortComparator = statusSortComparator
        self.rowOpacity = rowOpacity
        self.primaryAction = primaryAction
        self.sourceIcon = sourceIcon
        self.statusCell = statusCell
        self.documentCell = documentCell
        self.contextMenu = contextMenu
    }

    var body: some View {
        DataStateView(
            isLoading: isLoading,
            isEmpty: rows.isEmpty,
            content: {
                RecordingTableView(
                    rows: rows,
                    selection: $selection,
                    sortOrder: $sortOrder,
                    config: config,
                    sourceName: sourceName,
                    statusSortComparator: statusSortComparator,
                    rowOpacity: rowOpacity,
                    primaryAction: primaryAction,
                    sourceIcon: sourceIcon,
                    statusCell: statusCell,
                    documentCell: documentCell,
                    contextMenu: contextMenu
                )
            },
            emptyContent: {
                StandardEmptyStateView(
                    symbolName: "waveform.slash",
                    title: emptyStateTitle,
                    subtitle: emptyStateSubtitle,
                    errorMessage: errorMessage,
                    isLoading: isLoading,
                    onRefresh: {
                        Task {
                            await onRefresh()
                        }
                    }
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await onRefresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh list")
                .disabled(isLoading)
            }
        }
    }
}
