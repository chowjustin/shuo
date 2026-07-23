//
//  AppContainer.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

// Composition root. The only file in the app allowed to import concrete implementations
// alongside the protocols they satisfy — see CLAUDE.md §4, §9 and ARCHITECTURE.md §5,
// §12.1. Each concrete service is owned here and handed to Feature packages through
// factory methods, never imported directly by a Feature package.

import FeatureHome
import FeatureSpeechCreation
import FeatureTranscriptAnalysis
import ShuoAI
import ShuoAudio
import ShuoCore
import ShuoPersistence
import SwiftData
import Foundation

final class AppContainer {
    // MARK: - Services

    private let fileImportService: any FileImporting = FileImportService()
    private let microphonePermissions: any MicrophonePermissionProviding = MicrophonePermissionProvider()
    // Stateless and safe to share, unlike `AudioRecordingService` below: each call
    // builds its own analyzer session and tears it down again.
    private let speechTranscriber: any SpeechTranscribing = SpeechTranscribingRouter()

    // Shared deliberately: one actor serializes requests against the neural engine and
    // carries the prewarmed session into the first call. It holds no per-request state.
    private let speechAnalyzer = FoundationModelSpeechAnalyzer()
    private let availabilityChecker: any AIAvailabilityChecking = AIAvailabilityGate()

    private let scriptRepository: any ScriptRepository

    init() {
        scriptRepository = SwiftDataScriptRepository(
            modelContainer: Self.makeModelContainer()
        )
    }

    // MARK: - Factories

    @MainActor
    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            fetchScriptSummaries: FetchScriptSummariesUseCase(repository: scriptRepository),
            searchScripts: SearchScriptsUseCase(repository: scriptRepository),
            // 👇 Inject DeleteScriptUseCase di sini
            deleteScript: DeleteScriptUseCase(repository: scriptRepository)
        )
    }

    @MainActor
    func fetchScriptDraft(id: UUID) async throws -> ScriptDraft? {
        try await FetchScriptUseCase(repository: scriptRepository)(id: id)
    }

    @MainActor
    func makeCreateScriptCoordinator(onFinish: @escaping () -> Void) -> CreateScriptCoordinator {
        // Warm the model while the user is still choosing a purpose and speaking, so the
        // first real request lands on an already-loaded model rather than paying the
        // load cost inside the loading screen.
        Task { [speechAnalyzer] in
            await speechAnalyzer.prewarm()
        }
        return CreateScriptCoordinator(
            onFinish: onFinish,
            makeInputScriptViewModel: makeInputScriptViewModel
        )
    }

    @MainActor
    func makeTranscriptAnalysisView(
        draft: ScriptDraft,
        onClose: @escaping () -> Void,
        onBack: @escaping (ScriptDraft) -> Void
    ) -> TranscriptAnalysisView {
        TranscriptAnalysisView(
            viewModel: TranscriptAnalysisViewModel(
                draft: draft,
                availability: availabilityChecker,
                classifyTranscript: ClassifyTranscriptUseCase(analyzer: speechAnalyzer),
                generateKeyPoints: GenerateKeyPointsUseCase(analyzer: speechAnalyzer),
                regenerateTranscript: RegenerateTranscriptUseCase(analyzer: speechAnalyzer),
                saveScript: SaveScriptUseCase(repository: scriptRepository)
            ),
            onClose: onClose,
            onBack: onBack
        )
    }

    @MainActor
    private func makeInputScriptViewModel(
        purpose: SpeechPurpose,
        initialText: String?
    ) -> InputScriptViewModel {
        InputScriptViewModel(
            purpose: purpose,
            fileImporter: fileImportService,
            // A fresh capturer per session rather than one shared instance:
            // `AudioRecordingService` is single-use by contract — its event stream
            // completes when the session ends — so reusing one would hand the next
            // recording a dead stream.
            audioCapturer: AudioRecordingService(),
            microphonePermissions: microphonePermissions,
            generateTranscript: GenerateTranscriptUseCase(transcriber: speechTranscriber),
            initialText: initialText
        )
    }

    // MARK: - Persistence

    /// Builds the SwiftData container, falling back to an in-memory store if the on-disk
    /// one cannot be opened.
    ///
    /// The fallback is a deliberate stopgap, not a finished answer: it keeps the app usable
    /// when the store is corrupt or unreadable, but the user's scripts then silently fail
    /// to survive a relaunch. Surfacing that properly — a migration path, or an explicit
    /// "your library couldn't be opened" screen — is follow-up work worth doing before
    /// shipping.
    private static func makeModelContainer() -> ModelContainer {
        if let container = try? ModelContainerFactory.make() {
            return container
        }
        if let inMemory = try? ModelContainerFactory.make(isStoredInMemoryOnly: true) {
            return inMemory
        }
        // Neither an on-disk nor an in-memory store could be created, which means the
        // schema itself is invalid — a build-time mistake, not a runtime condition.
        preconditionFailure("Could not create a ModelContainer for the Shuo schema")
    }
}
