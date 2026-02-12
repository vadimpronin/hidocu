import SwiftUI
import LLMService

struct ProviderListView: View {
    @Bindable var viewModel: TestStudioViewModel

    private var providers: [LLMProvider] { TestStudioViewModel.supportedProviders }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Providers")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            List(providers, id: \.rawValue, selection: Binding(
                get: { viewModel.selectedProvider },
                set: { newValue in
                    if let value = newValue {
                        viewModel.selectedProvider = value
                        viewModel.selectedModelId = nil
                        viewModel.models = []
                        Task { await viewModel.loadModels() }
                    }
                }
            )) { provider in
                providerRow(provider)
                    .tag(provider)
            }
            .listStyle(.sidebar)
        }
    }

    private func providerRow(_ provider: LLMProvider) -> some View {
        HStack {
            Image(systemName: iconName(for: provider))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: provider))
                    .font(.body)
                Text(viewModel.isLoggedIn(for: provider) ? "Authenticated" : "Not logged in")
                    .font(.caption)
                    .foregroundStyle(viewModel.isLoggedIn(for: provider) ? .green : .secondary)
            }
            Spacer()
            authButton(provider)
        }
        .padding(.vertical, 2)
    }

    private func authButton(_ provider: LLMProvider) -> some View {
        Group {
            if viewModel.isLoggedIn(for: provider) {
                Button("Logout") {
                    viewModel.logout(provider: provider)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption)
            } else {
                Button("Login") {
                    Task { await viewModel.login(provider: provider) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .font(.caption)
            }
        }
    }

    private func displayName(for provider: LLMProvider) -> String {
        switch provider {
        case .claudeCode: "Claude Code"
        case .geminiCLI: "Gemini CLI"
        case .antigravity: "Antigravity"
        }
    }

    private func iconName(for provider: LLMProvider) -> String {
        switch provider {
        case .claudeCode: "brain.head.profile"
        case .geminiCLI: "sparkles"
        case .antigravity: "globe"
        }
    }
}
