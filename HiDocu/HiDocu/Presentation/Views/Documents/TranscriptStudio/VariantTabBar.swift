//
//  VariantTabBar.swift
//  HiDocu
//
//  Horizontal scrolling pill tabs for transcript variant switching.
//

import SwiftUI

struct VariantTabBar: View {
    let transcripts: [Transcript]
    @Binding var selectedId: Int64?
    var onAdd: () -> Void
    var onDelete: ((Int64) -> Void)?
    var onPromote: ((Int64) -> Void)?
    var onGenerate: (() -> Void)?
    var onJudge: (() -> Void)?
    var isGenerating: Bool = false
    var isJudging: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(transcripts) { transcript in
                        variantPill(transcript)
                    }

                    addMenu
                    judgeButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(.bar)
    }

    // MARK: - Variant Pill

    private func variantPill(_ transcript: Transcript) -> some View {
        let isSelected = selectedId == transcript.id

        return Button {
            selectedId = transcript.id
        } label: {
            HStack(spacing: 4) {
                // Status-specific rendering
                switch transcript.status {
                case .transcribing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(transcript.title ?? "Variant \(transcript.id)")
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)

                case .ready:
                    if transcript.isPrimary {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Text(transcript.title ?? "Variant \(transcript.id)")
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))
                } else {
                    Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if transcript.status == .failed {
                Button("Retry") {
                    // TODO: Implement retry logic
                }
                Divider()
            }

            Button("Use as Document Body") {
                onPromote?(transcript.id)
            }
            .disabled(transcript.isPrimary || transcript.status != .ready)

            Divider()

            Button("Delete Variant", role: .destructive) {
                onDelete?(transcript.id)
            }
            .disabled(isGenerating)
        }
    }

    private var readyCount: Int {
        transcripts.filter { $0.status == .ready }.count
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Menu {
            Button {
                onAdd()
            } label: {
                Label("Add Manually", systemImage: "square.and.pencil")
            }

            Divider()

            Button {
                onGenerate?()
            } label: {
                Label("Generate with AI...", systemImage: "sparkles")
            }
            .disabled(isGenerating)
        } label: {
            Group {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
            }
        }
        .menuStyle(.borderlessButton)
        .help(isGenerating ? "Generating transcript..." : "Add Variant")
    }

    // MARK: - Judge Button

    private var judgeButton: some View {
        Button {
            onJudge?()
        } label: {
            Group {
                if isJudging {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
        .disabled(readyCount < 3 || isJudging || isGenerating)
        .help(isJudging ? "Evaluating transcripts..." : "AI Judge: pick best transcript")
    }
}
