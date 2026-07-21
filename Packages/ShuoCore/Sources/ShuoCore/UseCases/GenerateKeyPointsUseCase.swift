//
//  GenerateKeyPointsUseCase.swift
//  ShuoCore
//

// Step two of the analysis flow: map a transcript's content onto the components of one
// pattern. Always returns a complete, ordered set — one key point per component, with
// `KeyPoint.absentText` for anything the transcript doesn't cover.

import Foundation

/// Extracts a transcript's content into the components of `pattern`.
///
/// The model's raw output is never returned directly: it goes through
/// `KeyPointNormalizer`, which is what guarantees one key point per component in order,
/// with `"-"` for uncovered slots. Callers can therefore render positionally and trust
/// the shape.
///
/// Notably this use case does **not** throw when the transcript covers nothing — an
/// all-absent set is a valid, informative result that tells the speaker their draft is
/// missing the entire structure. Only an outright generation failure propagates.
public struct GenerateKeyPointsUseCase: Sendable {

    private let analyzer: any SpeechAnalyzing
    private let normalizer: KeyPointNormalizer

    public init(
        analyzer: any SpeechAnalyzing,
        normalizer: KeyPointNormalizer = KeyPointNormalizer()
    ) {
        self.analyzer = analyzer
        self.normalizer = normalizer
    }

    /// - Returns: Exactly `pattern.components.count` key points, in component order.
    /// - Throws: Whatever the analyzer throws — typically `ShuoError.aiUnavailable` or
    ///   `ShuoError.contextWindowExceeded`.
    public func callAsFunction(
        transcript: Transcript,
        pattern: SpeechPattern
    ) async throws -> [KeyPoint] {
        let raw = try await analyzer.generateKeyPoints(
            transcript: transcript.original,
            pattern: pattern
        )
        return normalizer.normalize(raw, for: pattern)
    }
}
