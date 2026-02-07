//
//  LLMSettingsTab.swift
//  HiDocu
//
//  SwiftUI view for AI/LLM settings configuration.
//

import SwiftUI

/// Settings tab for managing LLM accounts, provider selection, and prompt templates.
struct LLMSettingsTab: View {
    @Environment(\.container) private var container
    @State private var viewModel: LLMSettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                LLMSettingsContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = LLMSettingsViewModel(
                llmService: container.llmService,
                settingsService: container.settingsService
            )
            await viewModel?.loadAccounts()
            await viewModel?.refreshModels()
        }
    }
}

// MARK: - Content View

private struct LLMSettingsContent: View {
    @Bindable var viewModel: LLMSettingsViewModel

    var body: some View {
        Form {
            accountsSection
            modelSection
            promptTemplateSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Accounts Section

    @ViewBuilder
    private var accountsSection: some View {
        Section {
            if viewModel.accounts.isEmpty {
                emptyAccountsView
            } else {
                ForEach(viewModel.accounts) { account in
                    accountRow(account)
                }
            }

            // Add Account buttons footer
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        addAccountButton(provider: provider)
                    }
                }

                if let error = viewModel.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 8)
        } header: {
            Text("Accounts")
        } footer: {
            Text("Add an account to enable AI-powered summaries and context generation.")
        }
    }

    @ViewBuilder
    private var emptyAccountsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("No accounts connected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Add an account to enable AI-powered summaries.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func accountRow(_ account: LLMAccount) -> some View {
        HStack(spacing: 12) {
            // Provider circle badge
            ZStack {
                Circle()
                    .fill(account.provider.brandColor)
                    .frame(width: 16, height: 16)

                Text(account.provider.initial)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }

            // Account email
            Text(account.email)
                .font(.body)

            Spacer()

            // Remove button
            Button {
                Task {
                    await viewModel.removeAccount(account)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func addAccountButton(provider: LLMProvider) -> some View {
        Button {
            Task {
                await viewModel.addAccount(provider: provider)
            }
        } label: {
            if viewModel.oauthState[provider] == .authenticating {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting...")
                        .font(.caption)
                }
            } else {
                Text("Add \(provider.displayName)")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(viewModel.oauthState[provider] == .authenticating)
    }

    // MARK: - Model Section

    @ViewBuilder
    private var modelSection: some View {
        Section("Model") {
            LabeledContent("Default Model") {
                HStack(spacing: 4) {
                    Picker("", selection: $viewModel.selectedModelId) {
                        if viewModel.availableModels.isEmpty {
                            Text("No models available").tag("")
                        }
                        ForEach(viewModel.availableModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .id(viewModel.availableModels.map(\.id))

                    refreshButton
                }
            }

            if case .error(let message) = viewModel.modelRefreshState {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.refreshModels()
            }
        } label: {
            Group {
                switch viewModel.modelRefreshState {
                case .idle:
                    Image(systemName: "arrow.triangle.2.circlepath")
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                case .error:
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(viewModel.modelRefreshState == .loading)
    }

    // MARK: - Prompt Template Section

    @ViewBuilder
    private var promptTemplateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $viewModel.summaryPromptTemplate)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    )
                    .frame(height: 100)

                Button("Reset to Default") {
                    viewModel.summaryPromptTemplate = AppSettings.LLMSettings.defaultPromptTemplate
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } header: {
            Text("Prompt Template")
        } footer: {
            Text("Template used for generating document summaries. Placeholders: {{document_title}}, {{document_body}}, {{current_date}}.")
        }
    }
}

// MARK: - Preview

#Preview {
    LLMSettingsTab()
        .frame(width: 500, height: 400)
}
