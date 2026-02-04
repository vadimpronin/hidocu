//
//  WaveformView.swift
//  HiDocu
//
//  Interactive waveform visualization for audio playback.
//  Displays amplitude bars with two-tone coloring (played/remaining).
//

import SwiftUI

/// Interactive waveform visualization component.
///
/// Displays audio waveform as vertical bars with:
/// - Two-tone coloring based on playback progress
/// - Tap/drag to seek
/// - Smooth animations
struct WaveformView: View {

    // MARK: - Properties

    /// Normalized amplitude samples (0.0-1.0)
    let samples: [Float]

    /// Current playback progress (0.0-1.0)
    let progress: Double

    /// Callback when user seeks to a position
    let onSeek: (Double) -> Void

    // MARK: - Constants

    private let minBarHeight: CGFloat = 2
    private let barSpacing: CGFloat = 1
    private let barCornerRadius: CGFloat = 1

    // MARK: - State

    @State private var isDragging = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, amplitude in
                    barView(
                        for: amplitude,
                        at: index,
                        totalCount: samples.count,
                        height: geometry.size.height
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        seek(at: value.location, width: geometry.size.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .accessibilityLabel("Audio waveform")
        .accessibilityHint("Tap or drag to seek playback position")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    // MARK: - Private Views

    private func barView(for amplitude: Float, at index: Int, totalCount: Int, height: CGFloat) -> some View {
        let barProgress = Double(index) / Double(max(totalCount - 1, 1))
        let isPlayed = barProgress <= progress

        let barHeight = max(CGFloat(amplitude) * height, minBarHeight)

        return RoundedRectangle(cornerRadius: barCornerRadius)
            .fill(isPlayed ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(height: barHeight)
            .frame(maxHeight: height, alignment: .center)
            .animation(.easeInOut(duration: 0.1), value: isPlayed)
    }

    // MARK: - Gestures

    private func seek(at location: CGPoint, width: CGFloat) {
        let progress = max(0, min(1, location.x / width))
        onSeek(progress)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Example 1: Sine wave pattern
        WaveformView(
            samples: (0..<100).map { Float(sin(Double($0) * 0.1)) * 0.5 + 0.5 },
            progress: 0.3,
            onSeek: { print("Seek to \($0)") }
        )
        .frame(height: 80)
        .padding()

        // Example 2: Random amplitudes
        WaveformView(
            samples: (0..<150).map { _ in Float.random(in: 0.2...1.0) },
            progress: 0.6,
            onSeek: { print("Seek to \($0)") }
        )
        .frame(height: 100)
        .padding()

        // Example 3: Quiet audio
        WaveformView(
            samples: (0..<80).map { _ in Float.random(in: 0.0...0.3) },
            progress: 0.9,
            onSeek: { print("Seek to \($0)") }
        )
        .frame(height: 60)
        .padding()
    }
}
