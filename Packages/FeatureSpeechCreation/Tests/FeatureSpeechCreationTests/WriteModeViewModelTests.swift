//
//  WriteModeViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

// `@MainActor` Swift Testing suite for `WriteModeViewModel`'s content validity checks.

import Foundation
import Testing
import ShuoCore
@testable import FeatureSpeechCreation

@MainActor
@Suite("WriteModeViewModel")
struct WriteModeViewModelTests {

    @Test("starts with no content")
    func startsEmpty() {
        let viewModel = WriteModeViewModel()

        #expect(viewModel.content.isEmpty)
        #expect(!viewModel.hasContent)
        #expect(viewModel.speechSource == nil)
    }

    @Test("has content once something is typed")
    func hasContentOnceTyped() {
        let viewModel = WriteModeViewModel()

        viewModel.content = "Why we must join campus organizations."

        #expect(viewModel.hasContent)
    }

    @Test(
        "treats whitespace alone as no content",
        arguments: [" ", "   ", "\n", "\t", " \n\t "]
    )
    func treatsWhitespaceAsEmpty(content: String) {
        // Otherwise a stray newline would enable the confirm button.
        let viewModel = WriteModeViewModel()

        viewModel.content = content

        #expect(!viewModel.hasContent)
        #expect(viewModel.speechSource == nil)
    }

    @Test("typed text becomes a speech source directly, with no transcription")
    func typedTextBecomesSpeechSource() {
        let viewModel = WriteModeViewModel()

        viewModel.content = "Why we must join campus organizations."

        #expect(viewModel.speechSource == .typedText("Why we must join campus organizations."))
    }

    @Test("trims surrounding whitespace from the speech source")
    func trimsSurroundingWhitespace() {
        let viewModel = WriteModeViewModel()

        viewModel.content = "\n  Why we must join campus organizations.  \n"

        #expect(viewModel.speechSource == .typedText("Why we must join campus organizations."))
    }

    @Test("keeps whitespace inside the content intact")
    func keepsInnerWhitespace() {
        // Only the edges are noise; paragraph breaks the user typed are content.
        let viewModel = WriteModeViewModel()

        viewModel.content = "First point.\n\nSecond point."

        #expect(viewModel.speechSource == .typedText("First point.\n\nSecond point."))
    }

    @Test("loses content again when cleared")
    func losesContentWhenCleared() {
        let viewModel = WriteModeViewModel()
        viewModel.content = "Something"

        viewModel.content = ""

        #expect(!viewModel.hasContent)
        #expect(viewModel.speechSource == nil)
    }
}
