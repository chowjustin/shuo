//
//  SpeechSetup.swift
//  ShuoAudio
//

import Foundation
import Speech
import ShuoCore

/// Locale matching, authorization, and asset installation shared by the live and
/// file-based transcription paths.
///
/// Extracted so the two paths cannot drift on which locale counts as supported or when
/// assets get installed. The behavioural difference between them stays at the call site:
/// `LiveTranscriptionSession` treats every failure here as silent and non-fatal, while
/// `SpeechAnalyzerTranscriptionService` surfaces them as `ShuoError` — file transcription
/// has no recording to fall back on.
enum SpeechSetup {
    /// v1 is English-only (ARCHITECTURE.md §2.3). When more locales land, this becomes a
    /// parameter rather than a constant.
    static let locale = Locale(identifier: "en-US")

    /// Compares by language and region only — `SpeechTranscriber` reports locales with
    /// extra components, so exact equality against "en-US" would miss valid matches.
    static func matchesLocale(_ candidate: Locale) -> Bool {
        candidate.language.languageCode == locale.language.languageCode
            && candidate.region == locale.region
    }

    /// Whether speech recognition is authorized. Never prompts.
    static var isAlreadyAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Prompts only when the user has not been asked before.
    /// - Returns: whether speech recognition ended up authorized.
    static func requestAuthorizationIfNeeded() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            // Refused or restricted. Re-asking would not prompt.
            return false
        }
    }

    /// Whether the app's locale can be transcribed on this device at all.
    static func isLocaleSupported() async -> Bool {
        await SpeechTranscriber.supportedLocales.contains(where: matchesLocale)
    }

    /// Installs on-device assets for the app's locale if they are not already present.
    /// - Returns: whether assets are installed and ready afterwards.
    @discardableResult
    static func ensureAssetsInstalled(for transcriber: SpeechTranscriber) async -> Bool {
        if await SpeechTranscriber.installedLocales.contains(where: matchesLocale) {
            return true
        }
        // `assetInstallationRequest` returns nil when nothing needs installing.
        guard let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return await SpeechTranscriber.installedLocales.contains(where: matchesLocale)
        }
        do {
            try await request.downloadAndInstall()
        } catch {
            return false
        }
        return true
    }

    /// A transcriber configured for one-shot, whole-file transcription.
    ///
    /// No `.volatileResults`, unlike the live path: nothing is displayed mid-run, so
    /// revisable partial results would only have to be filtered back out.
    static func makeFileTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
    }
}
