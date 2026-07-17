//
//  WriteModeViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

// `@MainActor` Swift Testing suite for `WriteModeViewModel`'s content validity checks.

import Testing
@testable import FeatureSpeechCreation

@MainActor
@Suite("WriteModeViewModel")
struct WriteModeViewModelTests {

    @Test("starts with empty content and is invalid")
    func startsEmpty() {
        let vm = WriteModeViewModel()

        #expect(vm.content.isEmpty)
        #expect(!vm.hasValidContent)
    }

    @Test("whitespace-only content is invalid")
    func whitespaceOnlyIsInvalid() {
        let vm = WriteModeViewModel()

        vm.content = "   \n\t  "

        #expect(!vm.hasValidContent)
    }

    @Test("non-whitespace content is valid")
    func nonWhitespaceIsValid() {
        let vm = WriteModeViewModel()

        vm.content = "My speech starts here."

        #expect(vm.hasValidContent)
    }

    @Test("clearing content back to empty becomes invalid again")
    func clearingContentBecomesInvalid() {
        let vm = WriteModeViewModel()

        vm.content = "Some ideas."
        #expect(vm.hasValidContent)

        vm.content = ""
        #expect(!vm.hasValidContent)
    }
}
