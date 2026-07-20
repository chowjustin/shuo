//
//  AttachFileModeViewModel.swift
//  FeatureSpeechCreation
//

import Foundation
import ShuoCore

@Observable @MainActor
public final class AttachFileModeViewModel {
    public enum ViewState: Equatable {
        case idle
        case processing
        case ready(ImportedMedia)
        /// Kept as its own case rather than folded into `.failed`: it is the one import
        /// failure with a bespoke full-screen alert in `InputScriptView`.
        case fileTooLarge
        case failed(ShuoError)
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

    /// The error behind `.failed`, for the caller that turns it into an error sheet.
    public var failure: ShuoError? {
        if case .failed(let error) = viewState { return error }
        return nil
    }

    public func fileSelected(url: URL) {
        importTask?.cancel()
        importTask = nil
        viewState = .processing
        importTask = Task {
            do {
                let media = try await fileImporter.importFile(from: url)
                guard !Task.isCancelled else { return }
                viewState = .ready(media)
            } catch ShuoError.fileTooLarge {
                guard !Task.isCancelled else { return }
                viewState = .fileTooLarge
            } catch let error as ShuoError {
                guard !Task.isCancelled else { return }
                viewState = .failed(error)
            } catch {
                // A non-domain error escaping the import service is a boundary bug
                // (CLAUDE.md §5), but the user still gets an explainable failure.
                guard !Task.isCancelled else { return }
                viewState = .failed(.importFailed)
            }
        }
    }

    /// The system file picker failed to present or returned an error, as opposed to the
    /// user cancelling — which reports success with no URLs and is correctly a no-op.
    public func pickerFailed() {
        viewState = .failed(.importFailed)
    }

    public func cancel() {
        importTask?.cancel()
        importTask = nil
        viewState = .idle
    }
}
