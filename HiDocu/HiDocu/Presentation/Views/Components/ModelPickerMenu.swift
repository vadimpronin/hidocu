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
                            HStack {
                                if model.id == selectedModelId {
                                    Image(systemName: "checkmark")
                                }
                                Text(model.displayName)
                                Spacer()
                                availabilityIndicator(for: model)
                            }
                        }
                    }
                }
            }
        } label: {
            selectedDisplayLabel
        }
        .menuStyle(.borderlessButton)
        .disabled(disabled)
    }

    // MARK: - Availability Indicators

    @ViewBuilder
    private func availabilityIndicator(for model: AvailableModel) -> some View {
        if model.isUnavailable {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption2)
                .help("Not available on any account")
        } else if model.isPartiallyAvailable {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption2)
                .help("Available on \(model.availableAccountCount) of \(model.totalAccountCount) accounts")
        }
    }

    // MARK: - Private Helpers

    @ViewBuilder
    private var selectedDisplayLabel: some View {
        HStack(spacing: 4) {
            if let model = models.first(where: { $0.id == selectedModelId }) {
                Text(model.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                availabilityIndicator(for: model)
            } else if !selectedModelId.isEmpty {
                Text(selectedModelId)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Select Model")
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
    }

    private var modelsGroupedByProvider: [(provider: LLMProvider, models: [AvailableModel])] {
        let grouped = Dictionary(grouping: models, by: \.provider)
        return LLMProvider.allCases.compactMap { provider in
            guard let models = grouped[provider], !models.isEmpty else { return nil }
            return (provider: provider, models: sortedModels(models))
        }
    }

    /// Sorts models by numerical subnames (descending), then textual subnames (ascending).
    /// Uses `displayName` for sort keys so date suffixes in model IDs don't pollute the order.
    /// Shorter numerical arrays are right-padded with 0 so "4" compares as "4.0" against "4.6".
    private func sortedModels(_ models: [AvailableModel]) -> [AvailableModel] {
        models.sorted { lhs, rhs in
            let lKey = modelSortKey(lhs.displayName)
            let rKey = modelSortKey(rhs.displayName)

            let maxLen = max(lKey.numerical.count, rKey.numerical.count)
            for i in 0..<maxLen {
                let l = i < lKey.numerical.count ? lKey.numerical[i] : 0
                let r = i < rKey.numerical.count ? rKey.numerical[i] : 0
                if l != r { return l > r }
            }

            for (l, r) in zip(lKey.textual, rKey.textual) {
                if l != r { return l < r }
            }
            return lKey.textual.count < rKey.textual.count
        }
    }

    private func modelSortKey(_ name: String) -> (numerical: [Int], textual: [String]) {
        let subnames = name
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let numerical = subnames.compactMap { Int($0) }
        let textual = subnames.filter { Int($0) == nil }
        return (numerical, textual)
    }
}
