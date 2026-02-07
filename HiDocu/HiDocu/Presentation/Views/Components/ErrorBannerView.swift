//
//  ErrorBannerView.swift
//  HiDocu
//
//  Non-intrusive error banner that auto-dismisses after a timeout.
//

import SwiftUI

/// A transient error banner shown at the bottom of a view.
/// Visibility is controlled by the parent (via ErrorBannerModifier).
struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

/// ViewModifier that overlays an error banner when the binding is non-nil.
/// Handles auto-dismiss with proper cancellation to avoid stale timer issues.
struct ErrorBannerModifier: ViewModifier {
    @Binding var errorMessage: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = errorMessage {
                    ErrorBannerView(message: message) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            errorMessage = nil
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: errorMessage)
            .onChange(of: errorMessage) { _, newValue in
                // Cancel any pending dismiss timer
                dismissTask?.cancel()

                if newValue != nil {
                    // Schedule new auto-dismiss
                    dismissTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            errorMessage = nil
                        }
                    }
                }
            }
    }
}

extension View {
    /// Show a transient error banner at the bottom when errorMessage is non-nil.
    func errorBanner(_ errorMessage: Binding<String?>) -> some View {
        modifier(ErrorBannerModifier(errorMessage: errorMessage))
    }
}
