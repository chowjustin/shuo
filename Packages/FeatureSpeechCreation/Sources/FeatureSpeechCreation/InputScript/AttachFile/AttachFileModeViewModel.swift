//
//  AttachFileModeViewModel.swift
//  FeatureSpeechCreation
//

import Foundation
import ShuoCore

@Observable @MainActor
public final class AttachFileModeViewModel {
    public enum ViewState {
        case idle
        case processing
        case ready(ImportedMedia)
        case fileTooLarge
        case failed(String)
    }

    public private(set) var viewState: ViewState = .idle
    public var isPickerPresented: Bool = false

    public var hasImportedFile: Bool {
        if case .ready = viewState { return true }
        return false
    }

    public var isFileTooLarge: Bool {
        if case .fileTooLarge = viewState { return true }
        return false
    }

    public var importedMedia: ImportedMedia? {
        if case .ready(let media) = viewState { return media }
        return nil
    }

    /// The imported file as a domain `SpeechSource`, once there is one.
    public var speechSource: SpeechSource? {
        importedMedia.map(SpeechSource.importedMedia)
    }

    private let fileImporter: any FileImporting
    public private(set) var importTask: Task<Void, Never>?

    public init(fileImporter: any FileImporting) {
        self.fileImporter = fileImporter
    }

    public func fileSelected(url: URL) {
        importTask?.cancel()
        importTask = nil
        let previousState = viewState
        viewState = .processing
        importTask = Task {
            do {
                let media = try await fileImporter.importFile(from: url)
                guard !Task.isCancelled else { return }
                viewState = .ready(media)
            } catch ShuoError.fileTooLarge {
                guard !Task.isCancelled else { return }
                viewState = previousState
                viewState = .fileTooLarge
            } catch {
                guard !Task.isCancelled else { return }
                viewState = .failed(error.localizedDescription)
            }
        }
    }

    public func cancel() {
        importTask?.cancel()
        importTask = nil
        viewState = .idle
    }
}
