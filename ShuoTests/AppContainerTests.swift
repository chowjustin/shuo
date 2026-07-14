//
//  AppContainerTests.swift
//  ShuoTests
//
//  Created by Justin Chow on 13/07/26.
//

// Composition-root smoke test: asserts AppContainer constructs without crashing and
// that its factory methods wire dependencies through correctly. This is the only test
// at the app-target level — every other behavior is tested inside its own package.
// See CLAUDE.md §13, ARCHITECTURE.md §12.1.

import Testing
import FeatureSpeechCreation
@testable import Shuo

@MainActor
@Suite("AppContainer")
struct AppContainerTests {
    @Test("makes a coordinator that starts with no purpose selected")
    func makesCreateScriptCoordinator() {
        let container = AppContainer()

        let coordinator = container.makeCreateScriptCoordinator(onFinish: {})

        #expect(coordinator.selectedPurpose == nil)
    }

    @Test("makes a coordinator whose close() invokes the onFinish closure passed in")
    func makeCreateScriptCoordinatorWiresOnFinishThrough() {
        let container = AppContainer()
        var finished = false

        let coordinator = container.makeCreateScriptCoordinator(onFinish: { finished = true })
        coordinator.close()

        #expect(finished)
    }

    @Test("makes a HomeView without crashing")
    func makesHomeView() {
        let container = AppContainer()

        _ = container.makeHomeView(onTapCreate: {})
    }
}
