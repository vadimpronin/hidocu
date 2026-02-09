//
//  DocumentDetailView.swift
//  HiDocu
//
//  Document detail with tab-based layout: Body, Summary, Sources, Info.
//

import SwiftUI

struct DocumentDetailView: View {
    @Bindable var viewModel: DocumentDetailViewModel
    let container: AppDependencyContainer

    @State private var sourcesViewModel: SourcesViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Title
            if viewModel.document != nil {
                TextField("Title", text: $viewModel.titleText)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: viewModel.titleText) { _, _ in
                        viewModel.titleDidChange()
                    }
            }

            // Tab Picker
            Picker("Tab", selection: $viewModel.selectedTab) {
                ForEach(DocumentDetailViewModel.DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Content Area
            Group {
                if viewModel.selectedTab == .sources {
                    tabContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(viewModel.selectedTab)
                } else {
                    ScrollView {
                        tabContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(viewModel.selectedTab)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Status Bar
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.titleModified || viewModel.bodyModified || viewModel.summaryModified {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Body: \(viewModel.bodyBytes.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Text("Summary: \(viewModel.summaryBytes.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let doc = viewModel.document, doc.summaryEdited, doc.summaryGeneratedAt != nil {
                        Text("(edited)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .task(id: viewModel.document?.id) {
            if viewModel.document != nil {
                sourcesViewModel = SourcesViewModel(
                    documentService: container.documentService,
                    sourceRepository: container.sourceRepository,
                    transcriptRepository: container.transcriptRepository,
                    apiLogRepository: container.apiLogRepository,
                    recordingRepositoryV2: container.recordingRepositoryV2
                )
            } else {
                sourcesViewModel = nil
            }
        }
        .errorBanner($viewModel.errorMessage)
        .navigationTitle(viewModel.titleText)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .body:
            VStack(spacing: 0) {
                if viewModel.bodyGenerationState == .generating &&
                   viewModel.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating content...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    if case .error(let message) = viewModel.bodyGenerationState {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(message)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                viewModel.bodyGenerationState = .idle
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    MarkdownEditableView(
                        text: $viewModel.bodyText,
                        isEditing: $viewModel.isBodyEditing
                    )
                    .onChange(of: viewModel.bodyText) { _, _ in
                        viewModel.bodyDidChange()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.bodyGenerationState != .generating {
                        Button(viewModel.isBodyEditing ? "Done" : "Edit") {
                            viewModel.isBodyEditing.toggle()
                        }
                    }
                }
            }

        case .summary:
            VStack(spacing: 0) {
                if case .error(let message) = viewModel.summaryGenerationState {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(message)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            viewModel.summaryGenerationState = .idle
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Content
                if case .generating = viewModel.summaryGenerationState {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating summary...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else if !viewModel.hasSummary && viewModel.bodyGenerationState == .generating {
                    // Body is still being generated; summary will be auto-enqueued after
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for content generation...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    MarkdownEditableView(
                        text: $viewModel.summaryText,
                        isEditing: $viewModel.isSummaryEditing,
                        placeholder: "No summary"
                    )
                    .onChange(of: viewModel.summaryText) { _, _ in
                        viewModel.summaryDidChange()
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if viewModel.hasLLMService && viewModel.bodyGenerationState != .generating {
                        ModelPickerMenu(
                            models: viewModel.availableModels,
                            selectedModelId: $viewModel.selectedModelId,
                            disabled: viewModel.summaryGenerationState == .generating
                        )
                    }

                    if case .generating = viewModel.summaryGenerationState {
                        Button("Cancel", systemImage: "xmark") {
                            viewModel.cancelGeneration()
                        }
                    } else if viewModel.hasSummary {
                        Button("Regenerate", systemImage: "arrow.triangle.2.circlepath") {
                            viewModel.generateSummary()
                        }

                        Button(viewModel.isSummaryEditing ? "Done" : "Edit") {
                            viewModel.isSummaryEditing.toggle()
                        }
                    } else if viewModel.bodyGenerationState != .generating {
                        Button("Generate Summary", systemImage: "sparkles") {
                            viewModel.generateSummary()
                        }
                    }
                }
            }

        case .sources:
            if let doc = viewModel.document, let sourcesVM = sourcesViewModel {
                TranscriptStudioView(viewModel: sourcesVM, documentId: doc.id, onBodyUpdated: {
                    viewModel.reloadBody()
                })
                .id(doc.id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            }

        case .info:
            if let doc = viewModel.document {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Document") {
                        LabeledContent("Type", value: doc.documentType)
                        LabeledContent("Created", value: doc.createdAt, format: .dateTime)
                        LabeledContent("Modified", value: doc.modifiedAt, format: .dateTime)
                    }
                    GroupBox("Sizes") {
                        LabeledContent("Body", value: viewModel.bodyBytes.formattedFileSize)
                        LabeledContent("Summary", value: viewModel.summaryBytes.formattedFileSize)
                    }
                    if let summaryGeneratedAt = doc.summaryGeneratedAt {
                        GroupBox("Summary Generation") {
                            LabeledContent("Generated", value: summaryGeneratedAt, format: .dateTime)
                            if let summaryModel = doc.summaryModel {
                                LabeledContent("Model", value: summaryModel)
                            }
                            LabeledContent("Manually Edited", value: doc.summaryEdited ? "Yes" : "No")
                        }
                    }
                    GroupBox("Storage") {
                        LabeledContent("Disk Path", value: doc.diskPath)
                    }
                }
                .padding()
            }
        }
    }
}
