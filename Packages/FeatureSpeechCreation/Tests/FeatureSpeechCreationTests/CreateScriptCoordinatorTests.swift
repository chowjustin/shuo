//
//  CreateScriptCoordinatorTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

import Foundation
import ShuoCore
import Testing

@testable import FeatureSpeechCreation

@MainActor
@Suite("CreateScriptCoordinator")
struct CreateScriptCoordinatorTests {
    @Test("starts with no purpose selected, so the Purpose screen is the root")
    func startsAtPurpose() {
        let coordinator = CreateScriptCoordinator(onFinish: {})

        #expect(coordinator.selectedPurpose == nil)
    }

    @Test("selecting a purpose stores it")
    func selectPurposeStoresIt() {
        let coordinator = CreateScriptCoordinator(onFinish: {})

        coordinator.selectPurpose(.persuade)

        #expect(coordinator.selectedPurpose == .persuade)
    }

    @Test("selecting another purpose replaces the previous selection, never accumulates")
    func selectingAnotherPurposeReplacesTheFirst() {
        let coordinator = CreateScriptCoordinator(onFinish: {})

        coordinator.selectPurpose(.inform)
        coordinator.selectPurpose(.inspire)

        #expect(coordinator.selectedPurpose == .inspire)
    }

    @Test("close invokes the finish callback")
    func closeInvokesOnFinish() {
        var finished = false
        let coordinator = CreateScriptCoordinator(onFinish: { finished = true })

        coordinator.close()

        #expect(finished)
    }

    @Test("close invokes the finish callback even after selecting a purpose")
    func closeInvokesOnFinishFromAnyStep() {
        var finished = false
        let coordinator = CreateScriptCoordinator(onFinish: { finished = true })

        coordinator.selectPurpose(.persuade)
        coordinator.close()

        #expect(finished)
    }

    @Test("dismissing input script clears the selected purpose")
    func dismissInputScriptClearsSelectedPurpose() {
        let coordinator = CreateScriptCoordinator(onFinish: {})

        coordinator.selectPurpose(.persuade)
        coordinator.dismissInputScript()

        #expect(coordinator.selectedPurpose == nil)
    }

    @Test("dismissing input script when no purpose is selected is a no-op")
    func dismissInputScriptWhenAlreadyAtPurposeIsANoOp() {
        let coordinator = CreateScriptCoordinator(onFinish: {})

        coordinator.dismissInputScript()

        #expect(coordinator.selectedPurpose == nil)
    }
}
