import SwiftUI

struct NetworkConsoleView: View {
    @Bindable var viewModel: TestStudioViewModel
    @State private var selectedTab: ConsoleTab = .network

    enum ConsoleTab: String, CaseIterable {
        case network = "Network"
        case log = "Log"
    }

    var body: some View {
        VStack(spacing: 0) {
            consoleHeader
            Divider()

            switch selectedTab {
            case .network:
                networkPanel
            case .log:
                logPanel
            }
        }
    }

    private var consoleHeader: some View {
        HStack(spacing: 12) {
            Picker("", selection: $selectedTab) {
                ForEach(ConsoleTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            if selectedTab == .network {
                NetworkConsoleToolbar(viewModel: viewModel)
            } else {
                DebugToggle(viewModel: viewModel)
                Spacer()
                Button("Clear Log") {
                    viewModel.clearLog()
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var networkPanel: some View {
        VSplitView {
            NetworkRequestListView(viewModel: viewModel)
                .frame(minHeight: 80)

            if let entry = viewModel.selectedDetailEntry {
                NetworkRequestDetailView(entry: entry, viewModel: viewModel)
                    .frame(minHeight: 120, idealHeight: 200)
            } else {
                Text("Select a request to view details")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private var logPanel: some View {
        LogView(viewModel: viewModel)
    }
}

// MARK: - Shared Components

/// Reusable debug toggle used in both Network and Log tabs
struct DebugToggle: View {
    @Bindable var viewModel: TestStudioViewModel

    var body: some View {
        Toggle("Debug", isOn: Binding(
            get: { viewModel.debugEnabled },
            set: { _ in viewModel.toggleDebug() }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
