//
//  MediaLimits.swift
//  ShuoCore
//

import Foundation

/// The bounds an imported audio or video file has to fit inside to be transcribable.
///
/// These live in the domain rather than in `FileImportService` for two reasons: the
/// limits are testable without touching AVFoundation, and the UI needs to *describe*
/// them ("Maximum file size: …") without importing the data layer.
public enum MediaLimits {
    /// Upper bound on audio length, in seconds.
    ///
    /// This is the limit that actually matters. Transcription runs roughly in real time,
    /// and the resulting transcript still has to fit through the on-device model's
    /// context window, so a two-hour lecture is a poor experience long before it is a
    /// technical failure.
    public static let maxDurationSeconds: TimeInterval = 30 * 60

    /// Lower bound on audio length, in seconds.
    ///
    /// A take this short cannot contain a speech worth structuring — it is a mis-tap, a
    /// stray attachment, or a recording abandoned a moment after it started. Transcribing
    /// it would spend a full round trip only to come back empty and surface as "we
    /// couldn't hear any speech", which reads as a fault rather than as guidance.
    /// Rejecting it here, before transcription, makes the feedback immediate and honest.
    public static let minDurationSeconds: TimeInterval = 3

    /// Upper bound on file size, in bytes.
    ///
    /// A sanity guard against pathological files, not the real constraint — bytes vary
    /// by orders of magnitude across codecs at identical durations, which is why
    /// `maxDurationSeconds` carries the actual policy.
    public static let maxFileSizeBytes: Int = 500 * 1_024 * 1_024

    /// "500 MB" — for UI copy, so the number is never hardcoded in a view.
    public static var formattedMaxFileSize: String {
        let megabytes = maxFileSizeBytes / (1_024 * 1_024)
        return "\(megabytes)MB"
    }

    /// "30 minutes" — for UI copy, so the number is never hardcoded in a view.
    public static var formattedMaxDuration: String {
        let minutes = Int(maxDurationSeconds / 60)
        return "\(minutes) minutes"
    }

    /// "3 seconds" — for UI copy, so the number is never hardcoded in a view.
    public static var formattedMinDuration: String {
        let seconds = Int(minDurationSeconds)
        return "\(seconds) seconds"
    }

    /// Whether `duration` is within the allowed length. A nil duration passes: the
    /// probe genuinely failing is not the user's fault, and transcription will surface a
    /// real error soon enough if the file is unusable.
    public static func isDurationAllowed(_ duration: TimeInterval?) -> Bool {
        guard let duration else { return true }
        return duration <= maxDurationSeconds
    }

    /// Whether `duration` is long enough to be worth transcribing. A nil duration passes,
    /// for the same reason it does in `isDurationAllowed`: an unknown length is a failed
    /// probe, not a short take, and rejecting it would block a perfectly usable file.
    public static func isDurationLongEnough(_ duration: TimeInterval?) -> Bool {
        guard let duration else { return true }
        return duration >= minDurationSeconds
    }

    /// Whether `byteCount` is within the allowed size.
    public static func isFileSizeAllowed(_ byteCount: Int) -> Bool {
        byteCount <= maxFileSizeBytes
    }
}
