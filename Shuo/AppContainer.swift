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

    // MARK: - Factories

    func makeHomeView(onTapCreate: @escaping () -> Void) -> HomeView {
        HomeView(onTapCreate: onTapCreate)
    }

    func makeCreateScriptCoordinator(onFinish: @escaping () -> Void) -> CreateScriptCoordinator {
        CreateScriptCoordinator(onFinish: onFinish)
    }

    func makePurposeSelectionView(coordinator: CreateScriptCoordinator) -> PurposeSelectionView {
        PurposeSelectionView(coordinator: coordinator, fileImporter: fileImportService)
    }
}
