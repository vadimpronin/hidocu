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
            tabContent
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
                Text("Summary: \(viewModel.summaryBytes.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            TextEditor(text: $viewModel.bodyText)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .onChange(of: viewModel.bodyText) { _, _ in
                    viewModel.bodyDidChange()
                }

        case .summary:
            TextEditor(text: $viewModel.summaryText)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .onChange(of: viewModel.summaryText) { _, _ in
                    viewModel.summaryDidChange()
                }

        case .sources:
            if let doc = viewModel.document, let sourcesVM = sourcesViewModel {
                SourcesSectionView(viewModel: sourcesVM, documentId: doc.id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .info:
            if let doc = viewModel.document {
                Form {
                    LabeledContent("Type", value: doc.documentType)
                    LabeledContent("Created", value: doc.createdAt, format: .dateTime)
                    LabeledContent("Modified", value: doc.modifiedAt, format: .dateTime)
                    LabeledContent("Body Size", value: viewModel.bodyBytes.formattedFileSize)
                    LabeledContent("Summary Size", value: viewModel.summaryBytes.formattedFileSize)
                    LabeledContent("Disk Path", value: doc.diskPath)
                }
                .formStyle(.grouped)
                .padding()
            }
        }
    }
}
