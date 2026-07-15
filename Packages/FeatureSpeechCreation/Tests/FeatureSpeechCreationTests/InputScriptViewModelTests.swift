//
//  InputScriptViewModelTests.swift
//  FeatureSpeechCreationTests
//
//  Created by Justin Chow on 13/07/26.
//

import Testing
import ShuoCore
import ShuoTestSupport
@testable import FeatureSpeechCreation

@MainActor
@Suite("InputScriptViewModel")
struct InputScriptViewModelTests {

    private func makeMedia() -> ImportedMedia {
        ImportedMedia(
            fileURL: URL(filePath: "/tmp/speech.m4a"),
            kind: .audio,
            originalFileName: "speech.m4a"
        )
    }

    @Test("defaults to speak mode")
    func defaultsToSpeakMode() {
        let viewModel = InputScriptViewModel(
            purpose: .persuade,
            fileImporter: FakeFileImporting(returning: makeMedia())
        )
        #expect(viewModel.mode == .speak)
    }

    @Test("retains the purpose it was initialized with")
    func retainsInjectedPurpose() {
        let viewModel = InputScriptViewModel(
            purpose: .inspire,
            fileImporter: FakeFileImporting(returning: makeMedia())
        )
        #expect(viewModel.purpose == .inspire)
    }

    @Test("mode switches to every input mode")
    func modeSwitchesToEachCase() {
        let viewModel = InputScriptViewModel(
            purpose: .inform,
            fileImporter: FakeFileImporting(returning: makeMedia())
        )
        for mode in InputMode.allCases {
            viewModel.mode = mode
            #expect(viewModel.mode == mode)
        }
    }

    // MARK: - hasValidContent

    @Test("hasValidContent is false in attachFile mode before a file is imported")
    func hasValidContentFalseWhenIdle() {
        let viewModel = InputScriptViewModel(
            purpose: .persuade,
            fileImporter: FakeFileImporting(returning: makeMedia())
        )
        viewModel.mode = .attachFile
        #expect(!viewModel.hasValidContent)
    }

    @Test("hasValidContent is true in attachFile mode after a successful import")
    func hasValidContentTrueAfterImport() async {
        let media = makeMedia()
        let viewModel = InputScriptViewModel(
            purpose: .persuade,
            fileImporter: FakeFileImporting(returning: media)
        )
        viewModel.mode = .attachFile

        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value

        #expect(viewModel.hasValidContent)
    }

    @Test("hasValidContent is false in attachFile mode after a failed import")
    func hasValidContentFalseAfterFailedImport() async {
        let viewModel = InputScriptViewModel(
            purpose: .persuade,
            fileImporter: FakeFileImporting(throwing: ShuoError.importFailed)
        )
        viewModel.mode = .attachFile

        viewModel.attachVM.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
        await viewModel.attachVM.importTask?.value

        #expect(!viewModel.hasValidContent)
    }
}
