//
//  InputScriptViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

import Testing
import ShuoCore
@testable import FeatureSpeechCreation

@MainActor
@Suite("InputScriptViewModel")
struct InputScriptViewModelTests {
    @Test("defaults to speak mode")
    func defaultsToSpeakMode() {
        let viewModel = InputScriptViewModel(purpose: .persuade)
        #expect(viewModel.mode == .speak)
    }

    @Test("retains the purpose it was initialized with")
    func retainsInjectedPurpose() {
        let viewModel = InputScriptViewModel(purpose: .inspire)
        #expect(viewModel.purpose == .inspire)
    }

    @Test("mode switches to every input mode")
    func modeSwitchesToEachCase() {
        let viewModel = InputScriptViewModel(purpose: .inform)
        for mode in InputMode.allCases {
            viewModel.mode = mode
            #expect(viewModel.mode == mode)
        }
    }
}
