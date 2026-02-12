import SwiftUI

struct LogView: View {
    @Bindable var viewModel: TestStudioViewModel

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.logEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .font(.system(size: 11, design: .monospaced))
            .onChange(of: viewModel.logEntries.count) {
                if let last = viewModel.logEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .background(.black.opacity(0.03))
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundStyle(.secondary)
            levelBadge(entry.level)
            Text(entry.message)
                .textSelection(.enabled)
        }
    }

    private func levelBadge(_ level: LogEntry.Level) -> some View {
        Text(level.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(badgeColor(level))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func badgeColor(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        case .debug: .gray
        }
    }
}
