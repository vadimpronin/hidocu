import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: .leading, spacing: 6) {
                if !message.thinkingText.isEmpty {
                    thinkingBlock
                }
                if !message.text.isEmpty || message.isStreaming {
                    textContent
                }
            }
            .padding(10)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var thinkingBlock: some View {
        DisclosureGroup {
            ScrollView {
                Text(message.thinkingText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption2)
                Text("Thinking")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var textContent: some View {
        Group {
            if message.text.isEmpty && message.isStreaming {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(height: 16)
            } else {
                Text(message.text)
                    .textSelection(.enabled)
                if message.isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Streaming...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 12)
                }
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .blue.opacity(0.15)
        case .assistant: .secondary.opacity(0.1)
        }
    }
}
