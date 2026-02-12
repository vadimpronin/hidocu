import SwiftUI
import LLMService

struct NetworkRequestDetailView: View {
    let entry: NetworkRequestEntry
    @Bindable var viewModel: TestStudioViewModel
    @State private var selectedTab: DetailTab = .requestHeaders

    enum DetailTab: String, CaseIterable {
        case requestHeaders = "Req Headers"
        case requestBody = "Req Body"
        case responseHeaders = "Resp Headers"
        case responseBody = "Resp Body"
        case curl = "cURL"
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            tabPicker
            Divider()
            tabContent
        }
        .background(.background)
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: 8) {
            Text(entry.httpMethod)
                .font(.system(size: 11, weight: .bold, design: .monospaced))

            Text(entry.fullURL)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Text(entry.statusText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.statusColor)

            Text(entry.durationText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .requestHeaders:
            headersView(entry.requestHeaders)
        case .requestBody:
            bodyView(entry.formattedRequestBody)
        case .responseHeaders:
            headersView(entry.responseHeaders)
        case .responseBody:
            responseBodyView
        case .curl:
            curlView
        }
    }

    // MARK: - Content Views

    private func headersView(_ headers: [(key: String, value: String)]) -> some View {
        ScrollView {
            if headers.isEmpty {
                Text("(no headers)")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(header.key):")
                                .foregroundStyle(.blue)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Text(header.value)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func bodyView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }

    private var responseBodyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let error = entry.trace.error {
                    Text("Error: \(error)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Divider()
                }
                Text(entry.formattedResponseBody)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
        }
    }

    private var curlView: some View {
        let curl = CURLExporter.generateCURL(from: entry.trace)
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(curl, forType: .string)
                }
                .font(.caption)
                .padding(6)
            }
            ScrollView {
                Text(curl)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }
}
