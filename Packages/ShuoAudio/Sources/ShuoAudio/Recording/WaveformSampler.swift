//
//  WaveformSampler.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// Pure function: raw audio buffer -> downsampled `[Float]` for waveform rendering. Fully
// unit-tested since it has no I/O. See ARCHITECTURE.md §12.4.

import Foundation

/// Reduces raw PCM samples to a small number of normalized amplitudes.
///
/// Pure and synchronous by design: this is the only part of the capture pipeline with
/// real logic worth testing, so it is deliberately separated from `AudioRecordingService`,
/// which cannot be unit-tested (CLAUDE.md §7).
enum WaveformSampler {
    /// Amplitudes quieter than this are treated as silence. -60dB is roughly a quiet
    /// room; anything below contributes no visible bar.
    static let floorDecibels: Float = -60

    /// Reduces `samples` to at most `binCount` normalized (0...1) amplitudes, one per
    /// equal-width bin, using RMS within each bin.
    ///
    /// Returns fewer than `binCount` values when there are fewer samples than bins —
    /// padding would render as fake silence.
    static func amplitudes(from samples: [Float], binCount: Int) -> [Float] {
        guard binCount > 0, !samples.isEmpty else { return [] }

        let bins = min(binCount, samples.count)
        return (0..<bins).map { index in
            // Multiply before dividing so bins stay evenly sized when `samples.count`
            // is not a multiple of `bins`, and every sample lands in exactly one bin.
            let start = index * samples.count / bins
            let end = (index + 1) * samples.count / bins
            return normalizedAmplitude(rootMeanSquare(of: samples[start..<end]))
        }
    }

    /// Root mean square — loudness of a chunk, as opposed to a peak, which would make
    /// the waveform spiky and hard to read.
    static func rootMeanSquare(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// Maps a linear RMS amplitude to 0...1 on a decibel scale, so quiet speech still
    /// produces a visible bar — a linear mapping leaves normal speech near zero.
    static func normalizedAmplitude(_ rootMeanSquare: Float) -> Float {
        guard rootMeanSquare > 0 else { return 0 }
        let decibels = 20 * log10(rootMeanSquare)
        guard decibels > floorDecibels else { return 0 }
        return min(1, (decibels - floorDecibels) / -floorDecibels)
    }
}
