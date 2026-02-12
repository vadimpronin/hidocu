import SwiftUI
import LLMService

struct ModelListView: View {
    @Bindable var viewModel: TestStudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Models")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.loadModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if viewModel.models.isEmpty {
                Text("No models loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                List(viewModel.models, id: \.id, selection: $viewModel.selectedModelId) { model in
                    modelRow(model)
                        .tag(model.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func modelRow(_ model: LLMModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.displayName)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 4) {
                if model.supportsThinking {
                    capabilityBadge("Think")
                }
                if model.supportsImage {
                    capabilityBadge("Image")
                }
                if model.supportsTools {
                    capabilityBadge("Tools")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func capabilityBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
