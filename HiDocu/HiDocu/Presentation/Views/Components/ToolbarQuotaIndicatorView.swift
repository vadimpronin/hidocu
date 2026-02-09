//
//  ToolbarQuotaIndicatorView.swift
//  HiDocu
//
//  Compact toolbar indicator showing quota status for active LLM providers.
//

import SwiftUI

/// Toolbar indicator showing colored dots for each provider with quota data.
struct ToolbarQuotaIndicatorView: View {
    let quotaService: QuotaService
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                if activeProviders.isEmpty {
                    Text("AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeProviders, id: \.self) { provider in
                        Circle()
                            .fill(providerColor(provider))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .popover(isPresented: $showPopover) {
            QuotaPopoverView(quotaService: quotaService)
        }
        .help("LLM Provider Quotas")
    }

    private var activeProviders: [LLMProvider] {
        quotaService.quotas.values
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
            .map { $0.provider }
    }

    private func providerColor(_ provider: LLMProvider) -> Color {
        guard let quota = quotaService.quotas[provider] else {
            return provider.brandColor.opacity(0.3)
        }

        let opacity = 0.3 + (quota.batteryLevel * 0.7)
        return provider.brandColor.opacity(opacity)
    }
}
