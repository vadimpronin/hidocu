import SwiftUI

struct NetworkConsoleToolbar: View {
    @Bindable var viewModel: TestStudioViewModel

    var body: some View {
        DebugToggle(viewModel: viewModel)

        TextField("Filter", text: $viewModel.networkFilterText)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(maxWidth: 180)

        Text("\(viewModel.filteredNetworkEntries.count) requests")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

        Spacer()

        Button {
            viewModel.copySelectedAsHAR()
        } label: {
            Label(
                viewModel.selectedTraceIds.isEmpty
                    ? "Copy HAR"
                    : "Copy \(viewModel.selectedTraceIds.count) as HAR",
                systemImage: "doc.on.doc"
            )
            .font(.caption)
        }
        .disabled(viewModel.networkEntries.isEmpty)

        Button {
            viewModel.exportSelectedAsHAR()
        } label: {
            Label(
                viewModel.selectedTraceIds.isEmpty
                    ? "Export HAR"
                    : "Export \(viewModel.selectedTraceIds.count) as HAR",
                systemImage: "square.and.arrow.up"
            )
            .font(.caption)
        }
        .disabled(viewModel.networkEntries.isEmpty)

        Button("Clear") {
            viewModel.clearNetworkEntries()
        }
        .font(.caption)
    }
}
