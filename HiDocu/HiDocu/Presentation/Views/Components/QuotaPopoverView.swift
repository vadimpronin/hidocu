//
//  QuotaPopoverView.swift
//  HiDocu
//
//  Popover showing detailed quota information per provider.
//

import SwiftUI

/// Popover displaying quota details for all LLM providers.
struct QuotaPopoverView: View {
    let quotaService: QuotaService
    @State private var expandedProvider: LLMProvider?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView.padding()
            Divider()
            providerListView
            Divider()
            footerView.padding()
        }
        .frame(width: 300)
    }

    private var providerListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if quotaService.quotas.isEmpty {
                    Text("No quota data available")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    providerRows
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private var providerRows: some View {
        ForEach(sortedProviders) { provider in
            ProviderRow(
                provider: provider.provider,
                quota: quotaService.quotas[provider.provider]!,
                isExpanded: expandedProvider == provider.provider,
                onTap: {
                    withAnimation {
                        expandedProvider = expandedProvider == provider.provider ? nil : provider.provider
                    }
                }
            )

            if expandedProvider == provider.provider {
                ModelQuotaList(modelQuotas: quotaService.quotas[provider.provider]!.modelQuotas)
                    .transition(.opacity)
            }

            if provider.provider != sortedProviders.last?.provider {
                Divider()
            }
        }
    }

    private var footerView: some View {
        HStack {
            if let lastUpdated = mostRecentUpdate {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                Task {
                    isRefreshing = true
                    defer { isRefreshing = false }
                    await quotaService.refreshAll()
                }
            }
            .controlSize(.small)
            .disabled(isRefreshing)
        }
    }

    private var headerView: some View {
        HStack {
            Text("LLM Quotas")
                .font(.headline)
            Spacer()
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var sortedProviders: [QuotaService.ProviderQuota] {
        quotaService.quotas.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    private var mostRecentUpdate: Date? {
        quotaService.quotas.values.compactMap { $0.lastUpdated }.max()
    }
}

// MARK: - Provider Row

private struct ProviderRow: View {
    let provider: LLMProvider
    let quota: QuotaService.ProviderQuota
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Provider icon/initial
                Circle()
                    .fill(provider.brandColor)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(provider.initial)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.medium))

                    if quota.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        // Battery bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(batteryColor)
                                    .frame(width: geometry.size.width * quota.batteryLevel, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                Spacer()

                if !quota.isLoading {
                    Text("\(Int(quota.batteryLevel * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !quota.modelQuotas.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var batteryColor: Color {
        if quota.batteryLevel > 0.5 { return .green }
        if quota.batteryLevel > 0.2 { return .yellow }
        return .red
    }
}

// MARK: - Model Quota List

private struct ModelQuotaList: View {
    let modelQuotas: [QuotaService.ModelQuota]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(modelQuotas) { modelQuota in
                HStack {
                    Text(modelQuota.modelId)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Mini battery bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(modelBatteryColor(modelQuota.remainingFraction))
                                .frame(width: geometry.size.width * modelQuota.remainingFraction, height: 3)
                        }
                    }
                    .frame(width: 60, height: 3)

                    Text("\(Int(modelQuota.remainingFraction * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 8)
    }

    private func modelBatteryColor(_ fraction: Double) -> Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.2 { return .yellow }
        return .red
    }
}
