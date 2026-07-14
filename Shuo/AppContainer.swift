//
//  AppContainer.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

// Composition root. Will own the app's ModelContainer and every concrete service
// (ShuoPersistence, ShuoAudio, ShuoAI) as those land; for now it exposes a single
// factory method proving the FeatureHome -> AppContainer -> ShuoApp wiring end to
// end. This is the only file in the app allowed to import concrete implementations
// alongside the protocols they satisfy — see CLAUDE.md §4, §9 and ARCHITECTURE.md
// §5, §12.1.

import FeatureHome
import FeatureSpeechCreation

final class AppContainer {
    func makeHomeView(onTapCreate: @escaping () -> Void) -> HomeView {
        HomeView(onTapCreate: onTapCreate)
    }

    func makeCreateScriptCoordinator(onFinish: @escaping () -> Void) -> CreateScriptCoordinator {
        CreateScriptCoordinator(onFinish: onFinish)
    }
}
