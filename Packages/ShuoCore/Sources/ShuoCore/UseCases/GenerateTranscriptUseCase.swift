//
//  GenerateTranscriptUseCase.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Use case: routes a `SpeechSource` to a `Transcript` — recordedAudio/importedMedia go
// through `SpeechTranscribing`, typedText short-circuits straight to the transcript with
// no transcription call. See ARCHITECTURE.md §3.2.1.

import Foundation

/// Produces the original transcript for a speech, whichever way the user supplied it.
///
/// This is the single place that knows transcription can be skipped. Two of the three
/// input modes already hold their text by the time they get here — Write mode by
/// definition, and Speak mode whenever live transcription succeeded — so only
/// attachments, and recordings whose live transcription fell through, pay the cost of
/// transcribing a file.
public struct GenerateTranscriptUseCase: Sendable {
    private let transcriber: any SpeechTranscribing

    public init(transcriber: any SpeechTranscribing) {
        self.transcriber = transcriber
    }

    /// Returns the transcript for `source`.
    ///
    /// - Throws: `ShuoError.mediaTooShort` when the source is a recording or attachment
    ///   below `MediaLimits.minDurationSeconds`, `ShuoError.noSpeechDetected` when the
    ///   source yields no usable text, plus anything `SpeechTranscribing` throws.
    public func callAsFunction(source: SpeechSource) async throws -> Transcript {
        switch source {
        case .typedText(let text):
            // Nothing to transcribe. Still validated, so an all-whitespace draft fails
            // here rather than reaching the model as an empty prompt. Typed text has no
            // duration, so the length check below deliberately does not reach it.
            return try makeTranscript(from: text)

        case .recordedAudio(let recording):
            // Ordering matters: this runs *before* the live-transcript short-circuit.
            // A one-second tap can still produce a live transcript, and letting that
            // path return first would admit exactly the take this check exists to reject.
            try validateDuration(recording.duration)

            // A live transcript is an optimization, never a guarantee (see
            // `AudioRecording.liveTranscript`) — fall through to the file when it is
            // absent or turns out to be blank.
            if let live = recording.liveTranscript,
               let transcript = try? makeTranscript(from: live) {
                return transcript
            }
            let text = try await transcriber.transcribe(.recordedAudio(recording))
            return try makeTranscript(from: text)

        case .importedMedia(let media):
            try validateDuration(media.duration)
            let text = try await transcriber.transcribe(.importedMedia(media))
            return try makeTranscript(from: text)
        }
    }

    // Rejects a take too short to hold a speech, before any transcription work happens.
    // A nil duration is an unknown one, not a short one, so it passes through — see
    // `MediaLimits.isDurationLongEnough`.
    private func validateDuration(_ duration: TimeInterval?) throws {
        guard MediaLimits.isDurationLongEnough(duration) else {
            throw ShuoError.mediaTooShort
        }
    }

    // Trims and rejects empty text, so `Transcript.original` is never blank and callers
    // get one consistent error instead of each transcription path inventing its own.
    private func makeTranscript(from text: String) throws -> Transcript {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShuoError.noSpeechDetected }
        return Transcript(original: trimmed)
    }
}
