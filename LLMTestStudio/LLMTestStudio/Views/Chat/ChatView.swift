import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: TestStudioViewModel

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.currentMessages) { message in
                        MessageBubble(message: message) {
                            viewModel.deleteMessage(id: message.id)
                        }
                        .id(message.id)
                    }
                    if let streaming = viewModel.currentStreamingMessage {
                        MessageBubble(message: streaming)
                            .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.currentMessages.count) {
                withAnimation {
                    if let last = viewModel.currentMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentStreamingMessage?.text) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: viewModel.currentStreamingMessage?.attachments.count) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Picker("Chat mode", selection: $viewModel.chatMode) {
                ForEach(ChatMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()

            Button {
                viewModel.clearChat()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentMessages.isEmpty && !viewModel.isStreaming)
            .help("Clear chat history")

            Toggle("Thinking", isOn: $viewModel.thinkingEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)

            TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        viewModel.sendMessage()
                    }
                }

            if viewModel.isStreaming {
                Button {
                    viewModel.cancelStream()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }
}
