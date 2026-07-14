//
//  AttachFileModeViewModel.swift
//  FeatureSpeechCreation
//

import Foundation
import ShuoCore

@Observable @MainActor
final class AttachFileModeViewModel {
    enum ViewState {
        case idle
        case selected(URL)
        case processing
        case ready(ImportedMedia)
        case failed(String)
    }

    private(set) var viewState: ViewState = .idle

    var hasImportedFile: Bool {
        if case .ready = viewState { return true }
        return false
    }

    var importedMedia: ImportedMedia? {
        if case .ready(let media) = viewState { return media }
        return nil
    }

    private let fileImporter: any FileImporting
    private var importTask: Task<Void, Never>?

    init(fileImporter: any FileImporting) {
        self.fileImporter = fileImporter
    }

    func fileSelected(url: URL) {
        importTask?.cancel()
        importTask = nil
        viewState = .selected(url)
    }

    func confirmUpload() {
        guard case .selected(let url) = viewState else { return }
        viewState = .processing
        importTask = Task {
            do {
                let media = try await fileImporter.importFile(from: url)
                guard !Task.isCancelled else { return }
                viewState = .ready(media)
            } catch {
                guard !Task.isCancelled else { return }
                viewState = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        importTask?.cancel()
        importTask = nil
        viewState = .idle
    }
}
