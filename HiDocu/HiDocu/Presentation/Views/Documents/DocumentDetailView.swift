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
            ScrollView {
                tabContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Strict View Identity: Force a fresh view hierarchy when switching tabs.
                    .id(viewModel.selectedTab)
            }
            .coordinateSpace(name: "detailScroll") // Provide a stable coordinate system for Textual layout
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .onChange(of: viewModel.document?.id) { _, _ in
            if viewModel.document != nil {
                sourcesViewModel = SourcesViewModel(
                    documentService: container.documentService,
                    sourceRepository: container.sourceRepository,
                    transcriptRepository: container.transcriptRepository,
                    recordingRepositoryV2: container.recordingRepositoryV2
                )
            }
        }
        .onAppear {
            if viewModel.document != nil {
                sourcesViewModel = SourcesViewModel(
                    documentService: container.documentService,
                    sourceRepository: container.sourceRepository,
                    transcriptRepository: container.transcriptRepository,
                    recordingRepositoryV2: container.recordingRepositoryV2
                )
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
                HStack {
                    Spacer()
                    Button(viewModel.isBodyEditing ? "Done" : "Edit") {
                        viewModel.isBodyEditing.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                MarkdownEditableView(
                    text: $viewModel.bodyText,
                    isEditing: $viewModel.isBodyEditing
                )
                .onChange(of: viewModel.bodyText) { _, _ in
                    viewModel.bodyDidChange()
                }
            }

        case .summary:
            VStack(spacing: 0) {
                // Action Bar
                HStack {
                    if case .generating = viewModel.summaryGenerationState {
                        Button("Cancel", systemImage: "xmark") {
                            viewModel.cancelGeneration()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if viewModel.hasSummary {
                        Button("Regenerate", systemImage: "arrow.triangle.2.circlepath") {
                            viewModel.generateSummary()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Generate Summary", systemImage: "sparkles") {
                            viewModel.generateSummary()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if viewModel.hasLLMService {
                        ModelPickerMenu(
                            models: viewModel.availableModels,
                            selectedModelId: $viewModel.selectedModelId,
                            disabled: viewModel.summaryGenerationState == .generating
                        )
                        .frame(maxWidth: 200)
                        .controlSize(.small)
                    }

                    Spacer()

                    if case .error(let message) = viewModel.summaryGenerationState {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(message)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if viewModel.hasSummary {
                        Button(viewModel.isSummaryEditing ? "Done" : "Edit") {
                            viewModel.isSummaryEditing.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                // Content
                if case .generating = viewModel.summaryGenerationState {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Generating summary...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400) // Ensure enough height for loader
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

        case .sources:
            if let doc = viewModel.document, let sourcesVM = sourcesViewModel {
                SourcesSectionView(viewModel: sourcesVM, documentId: doc.id)
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
