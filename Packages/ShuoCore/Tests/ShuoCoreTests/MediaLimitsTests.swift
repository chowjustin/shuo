//
//  MediaLimitsTests.swift
//  ShuoCoreTests
//

import Foundation
import Testing
import ShuoCore

@Suite("MediaLimits")
struct MediaLimitsTests {

    @Test("A file at exactly the size limit is allowed")
    func sizeBoundaryIsInclusive() {
        #expect(MediaLimits.isFileSizeAllowed(MediaLimits.maxFileSizeBytes))
    }

    @Test("A file one byte over the size limit is rejected")
    func oversizeIsRejected() {
        #expect(!MediaLimits.isFileSizeAllowed(MediaLimits.maxFileSizeBytes + 1))
    }

    @Test("Media at exactly the duration limit is allowed")
    func durationBoundaryIsInclusive() {
        #expect(MediaLimits.isDurationAllowed(MediaLimits.maxDurationSeconds))
    }

    @Test("Media one second over the duration limit is rejected")
    func overlongMediaIsRejected() {
        #expect(!MediaLimits.isDurationAllowed(MediaLimits.maxDurationSeconds + 1))
    }

    @Test("An unknown duration is allowed rather than blocking the import")
    func unknownDurationPasses() {
        // A failed AVAsset probe is not the user's fault; transcription surfaces a real
        // error later if the file is genuinely unusable.
        #expect(MediaLimits.isDurationAllowed(nil))
    }

    @Test("Limits are described for UI copy so no view hardcodes the numbers")
    func formattedCopyMatchesLimits() {
        #expect(MediaLimits.formattedMaxFileSize == "500MB")
        #expect(MediaLimits.formattedMaxDuration == "30 minutes")
    }
}
