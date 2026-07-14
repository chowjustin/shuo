//
//  AttachFileModeViewModelTests.swift
//  FeatureSpeechCreationTests
//

import Testing
import Foundation
import ShuoCore
import ShuoTestSupport
@testable import FeatureSpeechCreation

@MainActor
@Suite("AttachFileModeViewModel")
struct AttachFileModeViewModelTests {

    private func makeMedia(kind: ImportedMedia.Kind = .audio) -> ImportedMedia {
        ImportedMedia(
            fileURL: URL(filePath: "/tmp/speech.m4a"),
            kind: kind,
            originalFileName: "speech.m4a"
        )
    }

    private let testURL = URL(filePath: "/tmp/speech.m4a")

    // MARK: - Idle

    @Test("starts in idle state")
    func startsIdle() {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        if case .idle = vm.viewState { } else { Issue.record("Expected idle") }
        #expect(!vm.hasImportedFile)
        #expect(vm.importedMedia == nil)
    }

    // MARK: - fileSelected

    @Test("fileSelected transitions to selected state with correct URL")
    func fileSelectedTransitionsToSelected() {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        vm.fileSelected(url: testURL)

        if case .selected(let url) = vm.viewState {
            #expect(url == testURL)
        } else {
            Issue.record("Expected selected")
        }
        #expect(!vm.hasImportedFile)
    }

    // MARK: - confirmUpload

    @Test("confirmUpload transitions to ready on success")
    func confirmUploadSuccess() async {
        let media = makeMedia()
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: media))

        vm.fileSelected(url: testURL)
        vm.confirmUpload()
        await Task.yield()

        #expect(vm.hasImportedFile)
        #expect(vm.importedMedia?.id == media.id)
        #expect(vm.importedMedia?.originalFileName == media.originalFileName)
    }

    @Test("confirmUpload transitions to failed on error")
    func confirmUploadFailure() async {
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.importFailed)
        )

        vm.fileSelected(url: testURL)
        vm.confirmUpload()
        await Task.yield()

        if case .failed = vm.viewState { } else { Issue.record("Expected failed") }
        #expect(!vm.hasImportedFile)
        #expect(vm.importedMedia == nil)
    }

    @Test("confirmUpload is a no-op when called from idle")
    func confirmUploadNoOpFromIdle() {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        vm.confirmUpload()

        if case .idle = vm.viewState { } else { Issue.record("Expected idle unchanged") }
    }

    // MARK: - cancel

    @Test("cancel from selected resets to idle")
    func cancelFromSelected() {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        vm.fileSelected(url: testURL)
        vm.cancel()

        if case .idle = vm.viewState { } else { Issue.record("Expected idle") }
        #expect(!vm.hasImportedFile)
    }

    @Test("cancel from ready resets to idle")
    func cancelFromReady() async {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        vm.fileSelected(url: testURL)
        vm.confirmUpload()
        await Task.yield()
        vm.cancel()

        if case .idle = vm.viewState { } else { Issue.record("Expected idle after cancel") }
        #expect(!vm.hasImportedFile)
        #expect(vm.importedMedia == nil)
    }

    @Test("cancel from failed resets to idle")
    func cancelFromFailed() async {
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.importFailed)
        )

        vm.fileSelected(url: testURL)
        vm.confirmUpload()
        await Task.yield()
        vm.cancel()

        if case .idle = vm.viewState { } else { Issue.record("Expected idle after cancel from failed") }
    }
}
