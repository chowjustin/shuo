//
//  AppContainer.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

// Composition root. The only file in the app allowed to import concrete implementations
// alongside the protocols they satisfy — see CLAUDE.md §4, §9 and ARCHITECTURE.md §5,
// §12.1. As each concrete service lands (ShuoPersistence, ShuoAudio, ShuoAI) it is
// owned here and handed to Feature packages through factory methods, never imported
// directly by a Feature package.

import FeatureHome
import FeatureSpeechCreation
import ShuoAudio
import ShuoCore

final class AppContainer {
    // MARK: - Services

    private let fileImportService: any FileImporting = FileImportService()
    private let microphonePermissions: any MicrophonePermissionProviding = MicrophonePermissionProvider()

    // MARK: - Factories

    func makeHomeView(onTapCreate: @escaping () -> Void) -> HomeView {
        HomeView(onTapCreate: onTapCreate)
    }

    func makeCreateScriptCoordinator(onFinish: @escaping () -> Void) -> CreateScriptCoordinator {
        CreateScriptCoordinator(onFinish: onFinish)
    }

    func makePurposeSelectionView(coordinator: CreateScriptCoordinator) -> PurposeSelectionView {
        PurposeSelectionView(
            coordinator: coordinator,
            makeInputScriptViewModel: makeInputScriptViewModel
        )
    }

    @MainActor
    private func makeInputScriptViewModel(purpose: SpeechPurpose) -> InputScriptViewModel {
        InputScriptViewModel(
            purpose: purpose,
            fileImporter: fileImportService,
            // A fresh capturer per session rather than one shared instance:
            // `AudioRecordingService` is single-use by contract — its event stream
            // completes when the session ends — so reusing one would hand the next
            // recording a dead stream.
            audioCapturer: AudioRecordingService(),
            microphonePermissions: microphonePermissions
        )
    }
}
