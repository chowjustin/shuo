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

    @Test("Media at exactly the minimum duration is long enough")
    func minimumDurationBoundaryIsInclusive() {
        // The boundary falls on the accepted side: three seconds passes, under it fails.
        #expect(MediaLimits.isDurationLongEnough(MediaLimits.minDurationSeconds))
    }

    @Test("Media just under the minimum duration is too short")
    func belowMinimumIsRejected() {
        #expect(!MediaLimits.isDurationLongEnough(MediaLimits.minDurationSeconds - 0.5))
    }

    @Test("A one-second take is too short to be worth transcribing")
    func oneSecondTakeIsRejected() {
        #expect(!MediaLimits.isDurationLongEnough(1))
    }

    @Test("An unknown duration is long enough rather than blocking transcription")
    func unknownDurationIsLongEnough() {
        // Unknown is not short — only a duration we actually have is judged.
        #expect(MediaLimits.isDurationLongEnough(nil))
    }

    @Test("The minimum sits well below the maximum, so no duration satisfies neither")
    func minimumIsBelowMaximum() {
        #expect(MediaLimits.minDurationSeconds < MediaLimits.maxDurationSeconds)
    }

    @Test("Limits are described for UI copy so no view hardcodes the numbers")
    func formattedCopyMatchesLimits() {
        #expect(MediaLimits.formattedMaxFileSize == "500MB")
        #expect(MediaLimits.formattedMaxDuration == "30 minutes")
        #expect(MediaLimits.formattedMinDuration == "3 seconds")
    }
}
