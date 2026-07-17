//
//  WaveformSamplerTests.swift
//  ShuoAudioTests
//
//  Created by Justin Chow on 13/07/26.
//

// Swift Testing suite for `WaveformSampler` — pure function, fully unit-tested. See
// ARCHITECTURE.md §12.4.

import Foundation
import Testing
@testable import ShuoAudio

@Suite("WaveformSampler")
struct WaveformSamplerTests {

    // MARK: - Binning

    @Test("produces one amplitude per requested bin")
    func producesOneAmplitudePerBin() {
        let samples = [Float](repeating: 0.5, count: 100)

        #expect(WaveformSampler.amplitudes(from: samples, binCount: 10).count == 10)
        #expect(WaveformSampler.amplitudes(from: samples, binCount: 1).count == 1)
    }

    @Test("produces one amplitude per sample rather than padding when samples are scarce")
    func doesNotPadWhenSamplesAreScarce() {
        // Padding would render as bars of fake silence at the end of the waveform.
        let amplitudes = WaveformSampler.amplitudes(from: [1, 1, 1], binCount: 25)

        #expect(amplitudes.count == 3)
    }

    @Test("returns no amplitudes for empty input")
    func returnsNothingForEmptyInput() {
        #expect(WaveformSampler.amplitudes(from: [], binCount: 10).isEmpty)
    }

    @Test("returns no amplitudes for a non-positive bin count")
    func returnsNothingForNonPositiveBinCount() {
        #expect(WaveformSampler.amplitudes(from: [1, 1], binCount: 0).isEmpty)
        #expect(WaveformSampler.amplitudes(from: [1, 1], binCount: -1).isEmpty)
    }

    @Test("covers every sample when the count is not a multiple of the bin count")
    func coversEverySampleWithUnevenBins() {
        // 10 samples across 3 bins: loud only in the final sample, which must still land
        // in a bin rather than being dropped by integer division.
        var samples = [Float](repeating: 0, count: 9)
        samples.append(1)

        let amplitudes = WaveformSampler.amplitudes(from: samples, binCount: 3)

        #expect(amplitudes.count == 3)
        #expect(amplitudes[0] == 0)
        #expect(amplitudes[2] > 0)
    }

    @Test("keeps loud and quiet halves in their own bins")
    func separatesLoudAndQuietRegions() {
        let samples = [Float](repeating: 0, count: 50) + [Float](repeating: 1, count: 50)

        let amplitudes = WaveformSampler.amplitudes(from: samples, binCount: 2)

        #expect(amplitudes[0] == 0)
        #expect(amplitudes[1] == 1)
    }

    // MARK: - Normalization

    @Test("maps silence to zero")
    func mapsSilenceToZero() {
        #expect(WaveformSampler.normalizedAmplitude(0) == 0)
    }

    @Test("maps full scale to one")
    func mapsFullScaleToOne() {
        #expect(WaveformSampler.normalizedAmplitude(1) == 1)
    }

    @Test("maps anything at or below the noise floor to zero")
    func mapsBelowFloorToZero() {
        // -60dB is 0.001 in linear terms; quieter than that contributes no visible bar.
        #expect(WaveformSampler.normalizedAmplitude(0.001) == 0)
        #expect(WaveformSampler.normalizedAmplitude(0.0001) == 0)
    }

    @Test("clamps amplitudes louder than full scale to one")
    func clampsAboveFullScale() {
        #expect(WaveformSampler.normalizedAmplitude(2) == 1)
    }

    @Test("maps quiet speech to a visible amplitude rather than near zero")
    func mapsQuietSpeechToVisibleAmplitude() {
        // The point of the decibel scale: 0.01 linear is 1% of full scale and would be
        // invisible on a linear mapping, but is -40dB — two thirds up the range.
        let amplitude = WaveformSampler.normalizedAmplitude(0.01)

        #expect(abs(amplitude - 1.0 / 3.0) < 0.001)
    }

    @Test("increases monotonically with loudness")
    func increasesWithLoudness() {
        let quiet = WaveformSampler.normalizedAmplitude(0.01)
        let medium = WaveformSampler.normalizedAmplitude(0.1)
        let loud = WaveformSampler.normalizedAmplitude(1)

        #expect(quiet < medium)
        #expect(medium < loud)
    }

    // MARK: - RMS

    @Test("root mean square of a constant signal is that constant")
    func rootMeanSquareOfConstantSignal() {
        let samples: [Float] = [0.5, 0.5, 0.5, 0.5]

        #expect(abs(WaveformSampler.rootMeanSquare(of: samples[...]) - 0.5) < 0.0001)
    }

    @Test("root mean square ignores sign, so a full-scale wave does not cancel out")
    func rootMeanSquareIgnoresSign() {
        // A symmetric waveform averages to zero; RMS is what makes it read as loud.
        let samples: [Float] = [1, -1, 1, -1]

        #expect(abs(WaveformSampler.rootMeanSquare(of: samples[...]) - 1) < 0.0001)
    }

    @Test("root mean square of no samples is zero")
    func rootMeanSquareOfEmptyIsZero() {
        let samples: [Float] = []

        #expect(WaveformSampler.rootMeanSquare(of: samples[...]) == 0)
    }
}
