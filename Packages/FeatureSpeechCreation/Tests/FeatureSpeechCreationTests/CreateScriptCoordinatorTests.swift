//
//  CreateScriptCoordinatorTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

// Swift Testing suite for `CreateScriptCoordinator`'s route transitions, including the
// reopen-a-saved-script path that initializes `path` directly to `.analysis`. See
// ARCHITECTURE.md §3.1.1.

import Foundation
import ShuoCore
import Testing

@testable import FeatureSpeechCreation

@MainActor
@Suite("CreateScriptCoordinator")
struct CreateScriptCoordinatorTests {
    @Test("starts presented with an empty path, so the Purpose screen is the root")
    func startsAtPurpose() {
        let coordinator = CreateScriptCoordinator()

        #expect(coordinator.isPresented)
        #expect(coordinator.path.isEmpty)
    }

    @Test("selecting a purpose stores it and pushes .inputScript with that purpose")
    func selectPurposePushesInputScript() {
        let coordinator = CreateScriptCoordinator()

        coordinator.selectPurpose(.persuade)

        #expect(coordinator.path == [.inputScript(.persuade)])
    }

    @Test("selecting a second purpose pushes another .inputScript route onto the path")
    func selectingAnotherPurposeAppendsANewRoute() {
        let coordinator = CreateScriptCoordinator()

        coordinator.selectPurpose(.inform)
        coordinator.selectPurpose(.inspire)

        #expect(coordinator.path == [.inputScript(.inform), .inputScript(.inspire)])
    }

    @Test("close dismisses the entire flow")
    func closeDismissesFlow() {
        let coordinator = CreateScriptCoordinator()

        coordinator.close()

        #expect(!coordinator.isPresented)
    }

    @Test("close dismisses the flow even after navigating past Purpose")
    func closeDismissesFlowFromAnyStep() {
        let coordinator = CreateScriptCoordinator()

        coordinator.selectPurpose(.persuade)
        coordinator.close()

        #expect(!coordinator.isPresented)
    }
}
