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

    @Test("Every error has non-empty copy, so no case can ship blank")
    func everyErrorHasCopy() {
        let allErrors: [ShuoError] = [
            .fileTooLarge, .mediaTooLong, .unsupportedMediaType, .importFailed,
            .audioExtractionFailed, .speechPermissionDenied, .speechModelUnavailable,
            .noSpeechDetected, .transcriptionFailed, .aiUnavailable,
            .contextWindowExceeded, .persistenceFailed, .microphonePermissionDenied,
            .recordingFailed,
        ]

        for error in allErrors {
            let copy = TranscriptionErrorCopy(error: error)
            #expect(!copy.title.isEmpty, "\(error) has no title")
            #expect(!copy.message.isEmpty, "\(error) has no message")
            #expect(!copy.primaryActionTitle.isEmpty, "\(error) has no action title")
            #expect(!copy.systemImage.isEmpty, "\(error) has no glyph")
        }
    }

    @Test("Failures caused by the file itself offer to pick a different one")
    func fileFailuresOfferAnotherFile() {
        let fileErrors: [ShuoError] = [
            .fileTooLarge, .mediaTooLong, .unsupportedMediaType, .importFailed,
            .audioExtractionFailed, .noSpeechDetected,
        ]

        for error in fileErrors {
            #expect(
                TranscriptionErrorCopy(error: error).primaryAction == .pickAnotherFile,
                "\(error) should offer another file"
            )
        }
    }

    @Test("A denied permission never offers a retry that cannot work")
    func permissionDenialDoesNotOfferRetry() {
        // Re-requesting will not prompt again — only Settings can change this, so a
        // "Try again" button would be a dead end.
        #expect(TranscriptionErrorCopy(error: .speechPermissionDenied).primaryAction == .close)
        #expect(TranscriptionErrorCopy(error: .microphonePermissionDenied).primaryAction == .close)
    }

    @Test("Transient failures offer a retry rather than blaming the file")
    func transientFailuresOfferRetry() {
        #expect(TranscriptionErrorCopy(error: .transcriptionFailed).primaryAction == .retry)
        #expect(TranscriptionErrorCopy(error: .speechModelUnavailable).primaryAction == .retry)
    }

    @Test("The size limit in the copy is read from the domain, not hardcoded")
    func sizeCopyTracksTheDomainLimit() {
        let copy = TranscriptionErrorCopy(error: .fileTooLarge)
        #expect(copy.message.contains(MediaLimits.formattedMaxFileSize))
    }

    @Test("The duration limit in the copy is read from the domain, not hardcoded")
    func durationCopyTracksTheDomainLimit() {
        let copy = TranscriptionErrorCopy(error: .mediaTooLong)
        #expect(copy.message.contains(MediaLimits.formattedMaxDuration))
    }
}
