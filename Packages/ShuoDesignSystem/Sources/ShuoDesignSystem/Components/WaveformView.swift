//
//  WaveformView.swift
//  ShuoDesignSystem
//
//  Created by Justin Chow on 13/07/26.
//

// Renders live/recorded amplitude samples as a waveform. Takes a `[Float]` of samples,
// not an `AudioRecording` — domain-agnostic per CLAUDE.md §4.

import SwiftUI

/// Renders normalized (0...1) amplitudes as a row of mirrored, centre-aligned bars.
///
/// Every sample gets a bar, including silent ones, which render at `minBarHeight` — a row
/// of all-silent samples therefore reads as a dashed line, which is what a session that
/// has started but captured no sound should look like.
public struct WaveformView: View {
    private let samples: [Float]
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let maxBarHeight: CGFloat
    private let minBarHeight: CGFloat
    private let color: Color

    /// - Parameter samples: normalized 0...1 amplitudes, oldest first. Values outside
    ///   that range are clamped.
    public init(
        samples: [Float],
        barWidth: CGFloat = 6,
        spacing: CGFloat = 5,
        maxBarHeight: CGFloat = 90,
        minBarHeight: CGFloat = 3,
        color: Color = ShuoColor.pink
    ) {
        self.samples = samples
        self.barWidth = barWidth
        self.spacing = spacing
        self.maxBarHeight = maxBarHeight
        self.minBarHeight = minBarHeight
        self.color = color
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: height(for: sample))
            }
        }
        .frame(height: maxBarHeight)
        // Short and linear: long or springy easing would still be catching up to the
        // previous sample when the next one arrives ~12 times a second.
        .animation(.linear(duration: 0.08), value: samples)
        // The duration label beside this carries the information a screen reader needs;
        // announcing every amplitude would be noise.
        .accessibilityHidden(true)
    }

    private func height(for sample: Float) -> CGFloat {
        let normalized = CGFloat(min(max(sample, 0), 1))
        return max(minBarHeight, normalized * maxBarHeight)
    }
}

// MARK: - Previews
