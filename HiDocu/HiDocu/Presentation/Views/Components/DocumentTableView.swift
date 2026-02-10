//
//  DocumentTableView.swift
//  HiDocu
//
//  Reusable table for document-like rows across library screens.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentTableConfiguration {
    var showIcon: Bool = true
    var showDate: Bool = true
    var showSubtext: Bool = true
    var showDaysLeft: Bool = false
    var allowsReordering: Bool = false
    var dateColumnTitle: String = "Date"
    var metaColumnTitle: String = "Status"
}

extension DocumentTableConfiguration {
    static let documents = DocumentTableConfiguration(
        showIcon: true,
        showDate: true,
        showSubtext: true,
        showDaysLeft: false,
        allowsReordering: false,
        dateColumnTitle: "Created",
        metaColumnTitle: "Status"
    )

    static let trash = DocumentTableConfiguration(
        showIcon: true,
        showDate: true,
        showSubtext: true,
        showDaysLeft: true,
        allowsReordering: false,
        dateColumnTitle: "Deleted",
        metaColumnTitle: "Days Left"
    )
}

private enum DocumentTableConstants {
    static let iconColumnWidth: CGFloat = 30
    static let titleColumnWidth: (min: CGFloat, ideal: CGFloat) = (220, 360)
    static let dateColumnWidth: (min: CGFloat, ideal: CGFloat) = (160, 180)
    static let metaColumnWidth: (min: CGFloat, ideal: CGFloat) = (80, 110)

    static let dateFormat: Date.FormatStyle = .dateTime
        .day(.twoDigits)
        .month(.abbreviated)
        .year()
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
}

struct DocumentTableView<Row: DocumentRowDisplayable, ContextMenuContent: View>: View {
    let rows: [Row]

    @Binding var selection: Set<Int64>
    @Binding var sortOrder: [KeyPathComparator<Row>]

    let config: DocumentTableConfiguration

    private let contextMenu: (Set<Int64>) -> ContextMenuContent
    private let primaryAction: ((Row) -> Void)?
    private let onMove: ((IndexSet, Int) -> Void)?

    @State private var draggedRowID: Int64?

    init(
        rows: [Row],
        selection: Binding<Set<Int64>>,
        sortOrder: Binding<[KeyPathComparator<Row>]>,
        config: DocumentTableConfiguration,
        primaryAction: ((Row) -> Void)? = nil,
        onMove: ((IndexSet, Int) -> Void)? = nil,
        @ViewBuilder contextMenu: @escaping (Set<Int64>) -> ContextMenuContent
    ) {
        self.rows = rows
        _selection = selection
        _sortOrder = sortOrder
        self.config = config
        self.primaryAction = primaryAction
        self.onMove = onMove
        self.contextMenu = contextMenu
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            if config.showIcon {
                TableColumn("") { row in
                    if let iconName = row.statusIcon {
                        Image(systemName: iconName)
                            .foregroundStyle(row.statusColor)
                    }
                }
                .width(DocumentTableConstants.iconColumnWidth)
            }

            TableColumn("Title", value: \.title) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if config.showSubtext,
                       let subtext = row.subtext,
                       !subtext.isEmpty {
                        Text(subtext)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .modifier(ReorderModifier(
                    enabled: config.allowsReordering,
                    rowID: row.id,
                    rowIDs: rows.map(\.id),
                    draggedRowID: $draggedRowID,
                    onMove: onMove
                ))
            }
            .width(min: DocumentTableConstants.titleColumnWidth.min, ideal: DocumentTableConstants.titleColumnWidth.ideal)

            if config.showDate {
                TableColumn(config.dateColumnTitle, sortUsing: KeyPathComparator(\Row.sortableDate, order: .reverse)) { row in
                    Text(row.date.formatted(DocumentTableConstants.dateFormat))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: DocumentTableConstants.dateColumnWidth.min, ideal: DocumentTableConstants.dateColumnWidth.ideal)
            }

            if config.showDaysLeft {
                TableColumn(config.metaColumnTitle, sortUsing: KeyPathComparator(\Row.sortableDaysRemaining)) { row in
                    if let days = row.daysRemaining {
                        Text("\(days)d")
                            .monospacedDigit()
                            .foregroundStyle(days < 7 ? .red : .secondary)
                    } else {
                        Text("--")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: DocumentTableConstants.metaColumnWidth.min, ideal: DocumentTableConstants.metaColumnWidth.ideal)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selectedIds in
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
        .onMoveCommand { direction in
            guard config.allowsReordering,
                  let onMove,
                  let selectedID = selection.first,
                  let selectedIndex = rows.firstIndex(where: { $0.id == selectedID }) else {
                return
            }

            switch direction {
            case .up:
                guard selectedIndex > 0 else { return }
                onMove(IndexSet(integer: selectedIndex), selectedIndex - 1)
            case .down:
                guard selectedIndex < rows.count - 1 else { return }
                onMove(IndexSet(integer: selectedIndex), selectedIndex + 2)
            default:
                break
            }
        }
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

private struct ReorderModifier: ViewModifier {
    let enabled: Bool
    let rowID: Int64
    let rowIDs: [Int64]
    @Binding var draggedRowID: Int64?
    let onMove: ((IndexSet, Int) -> Void)?

    func body(content: Content) -> some View {
        guard enabled, let onMove else {
            return AnyView(content)
        }

        return AnyView(
            content
                .onDrag {
                    draggedRowID = rowID
                    return NSItemProvider(object: NSString(string: String(rowID)))
                }
                .onDrop(of: [UTType.plainText], delegate: DocumentRowDropDelegate(
                    targetRowID: rowID,
                    rowIDs: rowIDs,
                    draggedRowID: $draggedRowID,
                    onMove: onMove
                ))
        )
    }
}

private struct DocumentRowDropDelegate: DropDelegate {
    let targetRowID: Int64
    let rowIDs: [Int64]
    @Binding var draggedRowID: Int64?
    let onMove: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedRowID,
              let sourceIndex = rowIDs.firstIndex(of: draggedRowID),
              let targetIndex = rowIDs.firstIndex(of: targetRowID),
              sourceIndex != targetIndex else {
            self.draggedRowID = nil
            return false
        }

        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        onMove(IndexSet(integer: sourceIndex), destination)
        self.draggedRowID = nil
        return true
    }
}
