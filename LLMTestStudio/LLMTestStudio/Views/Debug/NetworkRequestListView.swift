import SwiftUI
import LLMService

struct NetworkRequestListView: View {
    @Bindable var viewModel: TestStudioViewModel

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        Table(viewModel.filteredNetworkEntries, selection: $viewModel.selectedTraceIds) {
            TableColumn("Time") { entry in
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 75, ideal: 85, max: 100)

            TableColumn("Status") { entry in
                statusBadge(entry)
            }
            .width(min: 35, ideal: 45, max: 55)

            TableColumn("Method") { entry in
                Text(entry.httpMethod)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .width(min: 40, ideal: 50, max: 60)

            TableColumn("URL") { entry in
                Text(entry.shortURL)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.fullURL)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Provider") { entry in
                Text(entry.provider)
                    .font(.system(size: 11))
            }
            .width(min: 70, ideal: 90, max: 120)

            TableColumn("Type") { entry in
                Text(entry.typeText)
                    .font(.system(size: 11))
            }
            .width(min: 60, ideal: 90, max: 120)

            TableColumn("Duration") { entry in
                Text(entry.durationText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 65, max: 80)
        }
        .contextMenu(forSelectionType: String.self) { selectedIds in
            contextMenuItems(selectedIds: selectedIds)
        }
        .onChange(of: viewModel.selectedTraceIds) { _, newValue in
            if newValue.count == 1, let id = newValue.first {
                viewModel.selectedDetailTraceId = id
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func contextMenuItems(selectedIds: Set<String>) -> some View {
        if selectedIds.count == 1, let id = selectedIds.first,
           let entry = viewModel.networkEntry(byId: id) {
            Button("Copy as cURL") {
                viewModel.copyAsCURL(entry)
            }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.fullURL, forType: .string)
            }
            Button("Copy as HAR") {
                viewModel.selectedTraceIds = selectedIds
                viewModel.copySelectedAsHAR()
            }
            Divider()
            Button("Export as HAR") {
                viewModel.selectedTraceIds = selectedIds
                viewModel.exportSelectedAsHAR()
            }
        } else if selectedIds.count > 1 {
            Button("Copy \(selectedIds.count) Selected as HAR") {
                viewModel.selectedTraceIds = selectedIds
                viewModel.copySelectedAsHAR()
            }
            Button("Export \(selectedIds.count) Selected as HAR") {
                viewModel.selectedTraceIds = selectedIds
                viewModel.exportSelectedAsHAR()
            }
        }
    }

    private func statusBadge(_ entry: NetworkRequestEntry) -> some View {
        Text(entry.statusText)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(entry.statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
