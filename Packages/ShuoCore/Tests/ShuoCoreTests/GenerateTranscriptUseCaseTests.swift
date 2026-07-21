//
//  GenerateTranscriptUseCaseTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import Testing
import ShuoCore
import ShuoTestSupport

@Suite("GenerateTranscriptUseCase")
struct GenerateTranscriptUseCaseTests {

    // MARK: - Short-circuiting

    @Test("Typed text becomes the transcript without ever calling the transcriber")
    func typedTextSkipsTranscription() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "should never be used")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        let transcript = try await sut(source: .typedText("Why we must join campus organizations."))

        #expect(transcript.original == "Why we must join campus organizations.")
        #expect(transcript.refined == nil)
        await #expect(transcriber.callCount == 0)
    }

    @Test("A recording that already has a live transcript is not transcribed again")
    func liveTranscriptSkipsTranscription() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "should never be used")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        let recording = makeRecording(liveTranscript: "Live captured text.")

        let transcript = try await sut(source: .recordedAudio(recording))

        #expect(transcript.original == "Live captured text.")
        await #expect(transcriber.callCount == 0)
    }

    // MARK: - Transcription paths

    @Test("An attachment is transcribed, and the media is passed through unchanged")
    func importedMediaIsTranscribed() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "Transcribed from the attachment.")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        let media = makeMedia(kind: .audio)

        let transcript = try await sut(source: .importedMedia(media))

        #expect(transcript.original == "Transcribed from the attachment.")
        await #expect(transcriber.receivedInputs == [.importedMedia(media)])
    }

    @Test("A recording without a live transcript falls back to transcribing the file")
    func recordingWithoutLiveTranscriptIsTranscribed() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "Transcribed from the recording.")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        let recording = makeRecording(liveTranscript: nil)

        let transcript = try await sut(source: .recordedAudio(recording))

        #expect(transcript.original == "Transcribed from the recording.")
        await #expect(transcriber.receivedInputs == [.recordedAudio(recording)])
    }

    @Test("A blank live transcript falls back to transcribing the file rather than failing")
    func blankLiveTranscriptFallsBackToFile() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "Recovered from the file.")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        let recording = makeRecording(liveTranscript: "   \n  ")

        let transcript = try await sut(source: .recordedAudio(recording))

        #expect(transcript.original == "Recovered from the file.")
        await #expect(transcriber.callCount == 1)
    }

    // MARK: - Empty and failing results

    @Test("Whitespace-only typed text is rejected as no speech detected")
    func blankTypedTextThrows() async {
        let transcriber = FakeSpeechTranscribing(returning: "unused")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        await #expect(throws: ShuoError.noSpeechDetected) {
            _ = try await sut(source: .typedText("   \n\t "))
        }
    }

    @Test("An empty transcription result is reported as no speech detected")
    func emptyTranscriptionThrows() async {
        let transcriber = FakeSpeechTranscribing(returning: "  ")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        await #expect(throws: ShuoError.noSpeechDetected) {
            _ = try await sut(source: .importedMedia(makeMedia(kind: .audio)))
        }
    }

    @Test("A transcriber failure propagates unchanged")
    func transcriberErrorPropagates() async {
        let transcriber = FakeSpeechTranscribing(throwing: .audioExtractionFailed)
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        await #expect(throws: ShuoError.audioExtractionFailed) {
            _ = try await sut(source: .importedMedia(makeMedia(kind: .video)))
        }
    }

    @Test("Surrounding whitespace is trimmed off the transcript")
    func transcriptIsTrimmed() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "\n  Padded text.  \n")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        let transcript = try await sut(source: .importedMedia(makeMedia(kind: .audio)))

        #expect(transcript.original == "Padded text.")
    }

    // MARK: - Minimum duration

    @Test("A recording shorter than the minimum is rejected without any transcription")
    func shortRecordingIsRejectedBeforeTranscribing() async {
        let transcriber = FakeSpeechTranscribing(returning: "should never be used")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        let recording = makeRecording(liveTranscript: nil, duration: 1)

        await #expect(throws: ShuoError.mediaTooShort) {
            _ = try await sut(source: .recordedAudio(recording))
        }
        // The whole point of checking duration in the domain layer: no round trip is
        // spent only to come back empty.
        await #expect(transcriber.callCount == 0)
    }

    @Test("A short recording is rejected even when live transcription already produced text")
    func shortRecordingWithLiveTranscriptIsStillRejected() async {
        let transcriber = FakeSpeechTranscribing(returning: "should never be used")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        // The ordering trap: the live-transcript route returns without transcribing, so a
        // duration check placed after it would let this take through and this test fail.
        let recording = makeRecording(liveTranscript: "A stray second of speech.", duration: 1)

        await #expect(throws: ShuoError.mediaTooShort) {
            _ = try await sut(source: .recordedAudio(recording))
        }
        await #expect(transcriber.callCount == 0)
    }

    @Test("A recording at exactly the minimum duration is accepted")
    func recordingAtMinimumDurationIsAccepted() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "Just long enough.")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        // The boundary is inclusive — exactly the minimum passes, only below it fails.
        let recording = makeRecording(
            liveTranscript: nil,
            duration: MediaLimits.minDurationSeconds
        )

        let transcript = try await sut(source: .recordedAudio(recording))

        #expect(transcript.original == "Just long enough.")
        await #expect(transcriber.callCount == 1)
    }

    @Test("An attachment shorter than the minimum is rejected without any transcription")
    func shortImportedMediaIsRejected() async {
        let transcriber = FakeSpeechTranscribing(returning: "should never be used")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        await #expect(throws: ShuoError.mediaTooShort) {
            _ = try await sut(source: .importedMedia(makeMedia(kind: .audio, duration: 2)))
        }
        await #expect(transcriber.callCount == 0)
    }

    @Test("An attachment whose duration could not be read is transcribed rather than rejected")
    func importedMediaWithUnknownDurationIsAccepted() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "Transcribed anyway.")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)
        // A failed probe is not a short file; only a duration we actually have is judged.
        let media = makeMedia(kind: .audio, duration: nil)

        let transcript = try await sut(source: .importedMedia(media))

        #expect(transcript.original == "Transcribed anyway.")
        await #expect(transcriber.callCount == 1)
    }

    @Test("Typed text is never rejected for length, however short it is")
    func shortTypedTextIsNotRejected() async throws {
        let transcriber = FakeSpeechTranscribing(returning: "should never be used")
        let sut = GenerateTranscriptUseCase(transcriber: transcriber)

        let transcript = try await sut(source: .typedText("Hi."))

        #expect(transcript.original == "Hi.")
        await #expect(transcriber.callCount == 0)
    }

    // MARK: - Helpers

    private func makeMedia(
        kind: ImportedMedia.Kind,
        duration: TimeInterval? = 42
    ) -> ImportedMedia {
        ImportedMedia(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID(),
            fileURL: URL(filePath: "/tmp/speech.m4a"),
            kind: kind,
            originalFileName: "speech.m4a",
            duration: duration
        )
    }

    private func makeRecording(
        liveTranscript: String?,
        duration: TimeInterval = 12
    ) -> AudioRecording {
        AudioRecording(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB") ?? UUID(),
            fileURL: URL(filePath: "/tmp/recording.caf"),
            duration: duration,
            createdAt: Date(timeIntervalSince1970: 0),
            liveTranscript: liveTranscript
        )
    }
}
