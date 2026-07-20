//
//  SpeechTranscribingRouter.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// `actor` conforming to `SpeechTranscribing` (ShuoCore); the facade that resolves file
// access, extracts audio from video, and delegates to
// `SpeechAnalyzerTranscriptionService`.

import Foundation
import ShuoCore

/// The package's public entry point for turning a media file into text.
///
/// Everything the domain must not know about lives behind this one call: security-scoped
/// bookmark resolution, audio extraction for video, and translating AVFoundation/Speech
/// failures into `ShuoError` at the package boundary (CLAUDE.md §5).
///
/// Named "Router" because it was designed to choose between the modern `SpeechAnalyzer`
/// and an `SFSpeechRecognizer` fallback. Only the former is built: Apple Intelligence
/// hardware is a hard requirement for v1 (ARCHITECTURE.md §2.1), so `SpeechAnalyzer` is
/// always present and a second implementation would be dead code. When it is genuinely
/// unavailable the user gets `.speechModelUnavailable` rather than a silent downgrade —
/// see `LegacySpeechRecognitionService` for the deferred path.
public actor SpeechTranscribingRouter: SpeechTranscribing {
    private let analyzerService = SpeechAnalyzerTranscriptionService()
    private let videoExtractor = VideoAudioExtractor()

    public init() {}

    public func transcribe(_ input: TranscriptionInput) async throws -> String {
        switch input {
        case .recordedAudio(let recording):
            // The app wrote this file into its own sandbox — no bookmark, no extraction.
            return try await analyzerService.transcribe(fileAt: recording.fileURL)

        case .importedMedia(let media):
            return try await transcribeImported(media)
        }
    }

    // MARK: - Imported media

    private func transcribeImported(_ media: ImportedMedia) async throws -> String {
        // The file lives outside the sandbox, so access has to go through the bookmark —
        // reading `media.fileURL` directly stopped being valid when imports moved from
        // sandbox copies to bookmarks.
        let resolved: (url: URL, stopAccessing: () -> Void)
        do {
            resolved = try media.resolveURL()
        } catch {
            throw ShuoError.importFailed
        }
        defer { resolved.stopAccessing() }

        guard media.kind.requiresAudioExtraction else {
            return try await analyzerService.transcribe(fileAt: resolved.url)
        }

        // Video: pull the audio track out first (CLAUDE.md §12), and delete the
        // temporary file however this call ends.
        let extracted = try await videoExtractor.extractAudio(from: resolved.url)
        defer { extracted.cleanUp() }

        return try await analyzerService.transcribe(fileAt: extracted.url)
    }
}
