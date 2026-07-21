//
//  TranscriptionErrorCopyTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 20/07/26.
//

import Testing
import Foundation
import ShuoCore
@testable import FeatureSpeechCreation

@Suite("TranscriptionErrorCopy")
struct TranscriptionErrorCopyTests {

    /// The errors a user can actually reach on the transcription screen. Each one earns
    /// its own wording, because each one has a different thing the user should do next.
    ///
    /// Hand-listed rather than derived, because `ShuoError` is not `CaseIterable` — the
    /// exhaustive `switch` in the initializer is what actually forces a new case to be
    /// handled, and this list is the reminder to cover it here too.
    private static let reachableErrors: [ShuoError] = [
        .fileTooLarge, .mediaTooLong, .mediaTooShort, .unsupportedMediaType, .importFailed,
        .audioExtractionFailed, .speechPermissionDenied, .speechModelUnavailable,
        .noSpeechDetected, .transcriptionFailed, .microphonePermissionDenied,
        .recordingFailed,
    ]

    /// Errors belonging to the analysis and saving steps, which own their own copy. They
    /// deliberately share one generic message here rather than duplicating wording for a
    /// screen that never shows them.
    private static let unreachableErrors: [ShuoError] = [
        .aiUnavailable, .contextWindowExceeded, .persistenceFailed,
        .transcriptNotUsable(.notASpeech), .aiGenerationFailed,
    ]

    private static var allErrors: [ShuoError] { reachableErrors + unreachableErrors }

    @Test("Every error has non-empty copy, so no case can ship blank")
    func everyErrorHasCopy() {
        for error in Self.allErrors {
            let copy = TranscriptionErrorCopy(error: error)
            #expect(!copy.title.isEmpty, "\(error) has no title")
            #expect(!copy.message.isEmpty, "\(error) has no message")
            #expect(!copy.systemImage.isEmpty, "\(error) has no glyph")
        }
    }

    @Test("Every reachable error reads differently, so the copy tells the user what happened")
    func everyReachableErrorReadsDifferently() {
        // Non-emptiness alone would pass against an implementation returning the same
        // placeholder for every case. Distinctness is what makes the copy worth having.
        let messages = Self.reachableErrors.map { TranscriptionErrorCopy(error: $0).message }
        #expect(
            Set(messages).count == Self.reachableErrors.count,
            "two reachable errors share a message"
        )
    }

    @Test("Errors owned by later steps share one generic message rather than inventing copy")
    func unreachableErrorsShareGenericCopy() {
        // The counterpart to the test above: this sharing is deliberate, so it is asserted
        // rather than merely tolerated. If one of these ever becomes reachable here it
        // needs real wording, and moving it into `reachableErrors` is what forces that.
        let messages = Set(Self.unreachableErrors.map { TranscriptionErrorCopy(error: $0).message })
        #expect(messages.count == 1, "the generic group has drifted into multiple messages")

        let reachable = Set(Self.reachableErrors.map { TranscriptionErrorCopy(error: $0).message })
        #expect(reachable.isDisjoint(with: messages), "a real error fell through to generic copy")
    }

    @Test("No copy tells the user to pick another file, since a recording cannot")
    func noCopyAssumesTheSourceWasAFile() {
        // The removed `primaryAction` mapping sent `noSpeechDetected` to a file picker,
        // which is what a user saw after recording something silent. Wording is now the
        // only channel, so it must not re-introduce the same assumption.
        let fileOnlyPhrases = ["another file", "choose a file", "pick a file", "select a file"]

        for error in Self.allErrors {
            let copy = TranscriptionErrorCopy(error: error)
            let text = "\(copy.title) \(copy.message)".lowercased()

            // The genuinely file-only failures may say so: they are unreachable from a
            // recording, because there is no file to be too large or of a wrong type.
            let isFileOnly: Bool
            switch error {
            case .fileTooLarge, .unsupportedMediaType, .importFailed, .audioExtractionFailed:
                isFileOnly = true
            default:
                isFileOnly = false
            }
            guard !isFileOnly else { continue }

            for phrase in fileOnlyPhrases {
                #expect(!text.contains(phrase), "\(error) assumes the source was a file")
            }
        }
    }

    @Test("The size limit in the copy is read from the domain, not hardcoded")
    func sizeCopyTracksTheDomainLimit() {
        let copy = TranscriptionErrorCopy(error: .fileTooLarge)
        #expect(copy.message.contains(MediaLimits.formattedMaxFileSize))
    }

    @Test("The maximum duration in the copy is read from the domain, not hardcoded")
    func durationCopyTracksTheDomainLimit() {
        let copy = TranscriptionErrorCopy(error: .mediaTooLong)
        #expect(copy.message.contains(MediaLimits.formattedMaxDuration))
    }

    @Test("The minimum duration in the copy is read from the domain, not hardcoded")
    func minimumDurationCopyTracksTheDomainLimit() {
        let copy = TranscriptionErrorCopy(error: .mediaTooShort)
        #expect(copy.message.contains(MediaLimits.formattedMinDuration))
    }
}
