//
//  SpeechAnalyzerTranscriptionService.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// `actor` wrapping `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26+) with the long-form
// preset, tuned for lecture/speech-length audio. See ARCHITECTURE.md §3.2.1.

import AVFoundation
import Foundation
import Speech
import ShuoCore

/// Transcribes a finished audio file in one pass.
///
/// The counterpart to `LiveTranscriptionSession`, and deliberately its opposite in one
/// respect: every failure here is **loud**. Live transcription can fail silently because
/// the recorded file is still there to fall back on — but this *is* that fallback, so
/// when it fails the user has no transcript at all, and each failure mode maps to a
/// distinct `ShuoError` the UI can actually explain.
actor SpeechAnalyzerTranscriptionService {

    /// Transcribes the audio file at `url`.
    ///
    /// - Returns: the transcript, trimmed. May be empty — the caller decides whether an
    ///   empty result means `noSpeechDetected`.
    /// - Throws: `ShuoError.speechPermissionDenied`, `.speechModelUnavailable`, or
    ///   `.transcriptionFailed`.
    func transcribe(fileAt url: URL) async throws -> String {
        guard await SpeechSetup.requestAuthorizationIfNeeded() else {
            throw ShuoError.speechPermissionDenied
        }
        guard await SpeechSetup.isLocaleSupported() else {
            throw ShuoError.speechModelUnavailable
        }

        let transcriber = SpeechSetup.makeFileTranscriber()
        guard await SpeechSetup.ensureAssetsInstalled(for: transcriber) else {
            throw ShuoError.speechModelUnavailable
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            // The file exists but its audio is unreadable — corrupt, or a codec
            // CoreAudio cannot decode.
            throw ShuoError.transcriptionFailed
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Results have to be consumed concurrently with the analysis: the sequence yields
        // as audio is processed, so collecting only after `analyzeSequence` returned
        // would stall against a full buffer on a long file.
        let collector = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }

        do {
            let lastSample = try await analyzer.analyzeSequence(from: audioFile)
            if let lastSample {
                // Flushes audio already queued but not yet transcribed — without this the
                // tail of the file is lost, exactly as in the live path.
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw ShuoError.transcriptionFailed
        }

        do {
            return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw ShuoError.transcriptionFailed
        }
    }
}
