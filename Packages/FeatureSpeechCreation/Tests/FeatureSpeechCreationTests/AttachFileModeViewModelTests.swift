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

    @Test("fileSelected transitions to ready on success")
    func fileSelectedTransitionsToReady() async {
        let media = makeMedia()
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: media))

        vm.fileSelected(url: testURL)
        await vm.importTask?.value

        #expect(vm.hasImportedFile)
        #expect(vm.importedMedia?.id == media.id)
        #expect(vm.importedMedia?.originalFileName == media.originalFileName)
    }

    @Test("fileSelected transitions to failed on error")
    func fileSelectedTransitionsToFailed() async {
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.importFailed)
        )

        vm.fileSelected(url: testURL)
        await vm.importTask?.value

        if case .failed = vm.viewState { } else { Issue.record("Expected failed") }
        #expect(!vm.hasImportedFile)
        #expect(vm.importedMedia == nil)
    }

    @Test("fileSelected transitions to fileTooLarge when file exceeds size limit")
    func fileSelectedTransitionsToFileTooLarge() async {
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.fileTooLarge)
        )

        vm.fileSelected(url: testURL)
        await vm.importTask?.value

        if case .fileTooLarge = vm.viewState { } else { Issue.record("Expected fileTooLarge") }
        #expect(!vm.hasImportedFile)
        #expect(vm.importedMedia == nil)
    }

    @Test("An over-long file is distinguished from an over-large one")
    func overlongMediaKeepsItsOwnError() async {
        // Size and duration are separate limits: a short 4K video can be huge, and a long
        // podcast can be tiny. Collapsing them would show the wrong explanation.
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.mediaTooLong)
        )

        vm.fileSelected(url: testURL)
        await vm.importTask?.value

        #expect(vm.viewState == .failed(.mediaTooLong))
        #expect(!vm.isFileTooLarge)
        #expect(vm.failure == .mediaTooLong)
    }

    @Test("A non-media file is reported as an unsupported type")
    func unsupportedTypeIsReported() async {
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.unsupportedMediaType)
        )

        vm.fileSelected(url: testURL)
        await vm.importTask?.value

        #expect(vm.failure == .unsupportedMediaType)
    }

    @Test("The domain error is preserved rather than flattened to a message string")
    func domainErrorIsPreserved() async {
        let vm = AttachFileModeViewModel(
            fileImporter: FakeFileImporting(throwing: ShuoError.importFailed)
        )

        vm.fileSelected(url: testURL)
        await vm.importTask?.value

        // Keeping the error, not its `localizedDescription`, is what lets the view pick
        // per-case copy instead of showing a framework string.
        #expect(vm.failure == .importFailed)
    }

    @Test("A failing file picker surfaces a failure instead of silently doing nothing")
    func pickerFailureIsSurfaced() {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        vm.pickerFailed()

        #expect(vm.failure == .importFailed)
    }

    // MARK: - cancel

    @Test("cancel from ready resets to idle")
    func cancelFromReady() async {
        let vm = AttachFileModeViewModel(fileImporter: FakeFileImporting(returning: makeMedia()))

        vm.fileSelected(url: testURL)
        await vm.importTask?.value
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
        await vm.importTask?.value
        vm.cancel()

        if case .idle = vm.viewState { } else { Issue.record("Expected idle after cancel from failed") }
    }

    // MARK: - Overwrite

    @Test("fileSelected from ready overwrites with new file")
    func fileSelectedFromReadyOverwrites() async {
        let firstMedia = makeMedia()
        let secondMedia = ImportedMedia(
            fileURL: URL(filePath: "/tmp/new.mp3"),
            kind: .audio,
            originalFileName: "new.mp3"
        )
        let importer = FakeSequentialFileImporting(results: [
            .success(firstMedia),
            .success(secondMedia)
        ])
        let vm = AttachFileModeViewModel(fileImporter: importer)

        vm.fileSelected(url: testURL)
        await vm.importTask?.value
        #expect(vm.importedMedia?.id == firstMedia.id)

        vm.fileSelected(url: URL(filePath: "/tmp/new.mp3"))
        await vm.importTask?.value
        #expect(vm.importedMedia?.id == secondMedia.id)
        #expect(vm.importedMedia?.originalFileName == "new.mp3")
    }
}
