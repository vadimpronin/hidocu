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

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(transcripts) { transcript in
                        variantPill(transcript)
                    }

                    addButton
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
                if transcript.isPrimary {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Text(transcript.title ?? "Variant \(transcript.id)")
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
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
            Button("Use as Document Body") {
                onPromote?(transcript.id)
            }
            .disabled(transcript.isPrimary)

            Divider()

            Button("Delete Variant", role: .destructive) {
                onDelete?(transcript.id)
            }
            .disabled(transcripts.count <= 1)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            onAdd()
        } label: {
            Image(systemName: "plus")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
        .help("Add Variant")
    }
}
