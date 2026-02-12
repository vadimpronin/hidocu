import SwiftUI
import UniformTypeIdentifiers

struct DebugControlsView: View {
    @Bindable var viewModel: TestStudioViewModel

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Debug Logging", isOn: Binding(
                get: { viewModel.debugEnabled },
                set: { _ in viewModel.toggleDebug() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Menu {
                Button("Last 5 minutes") {
                    exportHAR(minutes: 5)
                }
                Button("Last 15 minutes") {
                    exportHAR(minutes: 15)
                }
                Button("Last 30 minutes") {
                    exportHAR(minutes: 30)
                }
            } label: {
                Label("Export HAR", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button("Clear Log") {
                viewModel.clearLog()
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func exportHAR(minutes: Int) {
        Task {
            guard let data = await viewModel.exportHAR(lastMinutes: minutes) else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "har", conformingTo: .json) ?? .json]
            panel.nameFieldStringValue = "llm_debug_\(minutes)min"
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
                viewModel.log("No window available for save panel", level: .warning)
                return
            }
            let response = await panel.beginSheetModal(for: window)
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                    viewModel.log("HAR saved to \(url.lastPathComponent)", level: .info)
                } catch {
                    viewModel.log("Failed to save HAR: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
}
