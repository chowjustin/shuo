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
    private let progress: Double?
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let maxBarHeight: CGFloat
    private let minBarHeight: CGFloat
    private let color: Color

    /// Bars the playhead has not reached yet, so a played bar still reads as the same bar.
    private static let unplayedOpacity: Double = 0.3

    /// - Parameters:
    ///   - samples: normalized 0...1 amplitudes, oldest first. Values outside that range
    ///     are clamped.
    ///   - progress: how far playback has advanced through `samples`, 0...1. `nil` — the
    ///     default — means nothing is playing and every bar is drawn at full strength.
    ///     Dimming the tail rather than overlaying a separate playhead keeps the waveform
    ///     one object: the same bars mean the same thing whether or not audio is playing.
    public init(
        samples: [Float],
        progress: Double? = nil,
        barWidth: CGFloat = 6,
        spacing: CGFloat = 5,
        maxBarHeight: CGFloat = 90,
        minBarHeight: CGFloat = 3,
        color: Color = ShuoColor.pink
    ) {
        self.samples = samples
        self.progress = progress
        self.barWidth = barWidth
        self.spacing = spacing
        self.maxBarHeight = maxBarHeight
        self.minBarHeight = minBarHeight
        self.color = color
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                Capsule()
                    .fill(color.opacity(hasPlayed(index) ? 1 : Self.unplayedOpacity))
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

    /// Whether the playhead has reached the bar at `index`. Always true when nothing is
    /// playing, which is what keeps the recording waveform undimmed.
    private func hasPlayed(_ index: Int) -> Bool {
        guard let progress else { return true }
        let clamped = min(max(progress, 0), 1)
        return Double(index) < clamped * Double(samples.count)
    }
}

// MARK: - Previews

#Preview("Silence") {
    WaveformView(samples: Array(repeating: 0, count: 25))
}

#Preview("Speech") {
    WaveformView(samples: (0 ..< 25).map { _ in Float.random(in: 0.15 ... 1) })
}

#Preview("Filling up") {
    WaveformView(samples: (0 ..< 25).map { index in index < 12 ? Float.random(in: 0.2 ... 1) : 0 })
}

#Preview("Playing back") {
    WaveformView(samples: (0 ..< 25).map { _ in Float.random(in: 0.15 ... 1) }, progress: 0.4)
}
