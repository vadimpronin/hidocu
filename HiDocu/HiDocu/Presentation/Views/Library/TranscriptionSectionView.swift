//
//  TranscriptionSectionView.swift
//  HiDocu
//
//  Transcription section with variant tabs, text editor, and export controls.
//

import SwiftUI

/// Transcription section displayed within RecordingDetailView.
///
/// Features:
/// - Variant tabs (pill-shaped, primary shows star)
/// - Text editor with unsaved-changes indicator
/// - Add / delete / set-primary via context menus
/// - Copy to clipboard and export as Markdown
struct TranscriptionSectionView: View {

    @Bindable var viewModel: TranscriptionViewModel

    @State private var showAddSheet = false
    @State private var newVariantTitle = ""
    @State private var variantToDelete: Transcription?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if viewModel.variants.isEmpty {
                    emptyState
                } else {
                    variantTabs
                    textEditor
                    statusBar
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text("Transcription")
        }
        .task {
            await viewModel.loadVariants()
        }
        .sheet(isPresented: $showAddSheet) {
            addVariantSheet
        }
        .confirmationDialog(
            "Delete Variant",
            isPresented: .init(
                get: { variantToDelete != nil },
                set: { if !$0 { variantToDelete = nil } }
            ),
            presenting: variantToDelete
        ) { variant in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteVariant(id: variant.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { variant in
            Text("Delete \"\(variant.title ?? "Untitled")\"? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Variants (\(viewModel.variants.count)/\(TranscriptionViewModel.maxVariants))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Copy button
            Button {
                viewModel.copyToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy selected variant to clipboard")
            .disabled(viewModel.selectedVariant?.fullText?.isEmpty ?? true)

            // Export menu
            Menu {
                Button("Export as Markdown...") {
                    viewModel.exportToFile()
                }
                .disabled(viewModel.exportPrimaryAsMarkdown() == nil)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Export options")

            // Add button
            Button {
                newVariantTitle = ""
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add transcription variant")
            .disabled(!viewModel.canAddVariant)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.page")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No transcriptions yet")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Add Transcription") {
                newVariantTitle = ""
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Variant Tabs

    private var variantTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.variants) { variant in
                    variantTab(for: variant)
                }
            }
        }
    }

    private func variantTab(for variant: Transcription) -> some View {
        let isSelected = variant.id == viewModel.selectedVariantId

        return Button {
            Task {
                await viewModel.selectVariant(id: variant.id)
            }
        } label: {
            HStack(spacing: 4) {
                if variant.isPrimary {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(variant.title ?? "Untitled")
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !variant.isPrimary {
                Button {
                    Task {
                        await viewModel.setPrimary(id: variant.id)
                    }
                } label: {
                    Label("Set as Primary", systemImage: "star")
                }
            }

            Button(role: .destructive) {
                variantToDelete = variant
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Text Editor

    private var textEditor: some View {
        TextEditor(text: $viewModel.editableText)
            .font(.body)
            .frame(minHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onChange(of: viewModel.editableText) { _, _ in
                viewModel.textDidChange()
            }
            .disabled(viewModel.selectedVariantId == nil)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if viewModel.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Save") {
                Task {
                    await viewModel.saveCurrentText()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving)
        }
    }

    // MARK: - Add Variant Sheet

    private var addVariantSheet: some View {
        VStack(spacing: 16) {
            Text("New Variant")
                .font(.headline)

            TextField("Title (optional)", text: $newVariantTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showAddSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    showAddSheet = false
                    Task {
                        await viewModel.addVariant(title: newVariantTitle)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
