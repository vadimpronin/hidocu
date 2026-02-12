import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MessageBubble: View {
    let message: ChatMessage
    var onDelete: (() -> Void)?

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
                if !message.attachments.isEmpty {
                    attachmentsView
                }
            }
            .padding(10)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contextMenu {
                if let onDelete {
                    Button("Delete Message", role: .destructive) {
                        onDelete()
                    }
                }
            }

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

    // MARK: - Attachments

    private var attachmentsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(message.attachments.enumerated()), id: \.element.id) { index, attachment in
                if attachment.isImage {
                    imageAttachmentView(attachment, index: index)
                } else {
                    nonImageAttachmentView(attachment)
                }
            }
        }
    }

    private func imageAttachmentView(_ attachment: ChatAttachment, index: Int) -> some View {
        Group {
            if let nsImage = NSImage(data: attachment.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
                    .accessibilityLabel("Image attachment \(index + 1)")
                    .contextMenu {
                        Button("Copy Image") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([nsImage])
                        }
                        Button("Save Image As...") {
                            saveImage(nsImage, attachment: attachment)
                        }
                    }
                    .help("Right-click for options")
            } else {
                Label("Failed to load image", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func nonImageAttachmentView(_ attachment: ChatAttachment) -> some View {
        Text("[\(attachment.mimeType)]")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Attachment: \(attachment.mimeType)")
    }

    private func saveImage(_ image: NSImage, attachment: ChatAttachment) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "attachment.\(attachment.fileExtension)"

        Task { @MainActor in
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            let response = await panel.beginSheetModal(for: window)
            if response == .OK, let url = panel.url {
                Task.detached {
                    if let tiffData = image.tiffRepresentation,
                       let bitmapImage = NSBitmapImageRep(data: tiffData)
                    {
                        let fileType: NSBitmapImageRep.FileType
                        switch url.pathExtension.lowercased() {
                        case "jpg", "jpeg": fileType = .jpeg
                        case "tiff", "tif": fileType = .tiff
                        default: fileType = .png
                        }
                        if let data = bitmapImage.representation(using: fileType, properties: [:]) {
                            try? data.write(to: url)
                        }
                    }
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
