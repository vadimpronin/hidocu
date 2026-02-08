//
//  ModelPickerMenu.swift
//  HiDocu
//
//  Reusable model picker menu with provider sections.
//

import SwiftUI

/// A shared dropdown menu for selecting an LLM model, grouped by provider.
struct ModelPickerMenu: View {
    var models: [AvailableModel]
    @Binding var selectedModelId: String
    var disabled: Bool = false

    var body: some View {
        Menu {
            ForEach(modelsGroupedByProvider, id: \.provider) { group in
                Section(group.provider.displayName) {
                    ForEach(group.models) { model in
                        Button {
                            selectedModelId = model.id
                        } label: {
                            if model.id == selectedModelId {
                                Label(model.modelId, systemImage: "checkmark")
                            } else {
                                Text(model.modelId)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedDisplayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(disabled)
    }

    // MARK: - Private Helpers

    private var modelsGroupedByProvider: [(provider: LLMProvider, models: [AvailableModel])] {
        let grouped = Dictionary(grouping: models, by: \.provider)
        return LLMProvider.allCases.compactMap { provider in
            guard let models = grouped[provider], !models.isEmpty else { return nil }
            return (provider: provider, models: sortedModels(models))
        }
    }

    /// Sorts models by numerical subnames first (left-to-right), then non-numerical subnames (left-to-right).
    /// Subnames are extracted by splitting on any non-alphanumeric character.
    /// E.g. "gpt-5.1-codex-max" → numerical: [5, 1], textual: ["gpt", "codex", "max"]
    private func sortedModels(_ models: [AvailableModel]) -> [AvailableModel] {
        models.sorted { lhs, rhs in
            let lKey = modelSortKey(lhs.modelId)
            let rKey = modelSortKey(rhs.modelId)

            for (l, r) in zip(lKey.numerical, rKey.numerical) {
                if l != r { return l > r }
            }
            if lKey.numerical.count != rKey.numerical.count {
                return lKey.numerical.count > rKey.numerical.count
            }

            for (l, r) in zip(lKey.textual, rKey.textual) {
                if l != r { return l < r }
            }
            return lKey.textual.count < rKey.textual.count
        }
    }

    private func modelSortKey(_ modelId: String) -> (numerical: [Int], textual: [String]) {
        let subnames = modelId
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let numerical = subnames.compactMap { Int($0) }
        let textual = subnames.filter { Int($0) == nil }
        return (numerical, textual)
    }

    private var selectedDisplayName: String {
        if let model = models.first(where: { $0.id == selectedModelId }) {
            return model.displayName
        }
        if !selectedModelId.isEmpty {
            return selectedModelId
        }
        return "Select Model"
    }
}
