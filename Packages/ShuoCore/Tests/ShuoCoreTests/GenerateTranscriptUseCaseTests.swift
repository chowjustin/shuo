//
//  GenerateTranscriptUseCaseTests.swift
//  ShuoCoreTests
//
//  Created by Justin Chow on 13/07/26.
//

// Swift Testing suite for `GenerateTranscriptUseCase`, injecting fakes from
// ShuoTestSupport (e.g. asserting `.typedText` never invokes `SpeechTranscribing`). See
// ARCHITECTURE.md §8.

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

    // MARK: - Helpers

    private func makeMedia(kind: ImportedMedia.Kind) -> ImportedMedia {
        ImportedMedia(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID(),
            fileURL: URL(filePath: "/tmp/speech.m4a"),
            kind: kind,
            originalFileName: "speech.m4a",
            duration: 42
        )
    }

    private func makeRecording(liveTranscript: String?) -> AudioRecording {
        AudioRecording(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB") ?? UUID(),
            fileURL: URL(filePath: "/tmp/recording.caf"),
            duration: 12,
            createdAt: Date(timeIntervalSince1970: 0),
            liveTranscript: liveTranscript
        )
    }
}
