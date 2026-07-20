//
//  LoadingRouteViewModel.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 20/07/26.
//

import Foundation
import Observation
import ShuoCore

/// Drives the extract → transcribe sequence that turns a `SpeechSource` into the original
/// transcript, and owns the failure state the UI turns into an `ErrorSheet`.
///
/// The `.analyzing` step is not wired yet — pattern and key-point generation land with
/// `SpeechAnalyzing`. `.finished` is where that will hand off (ARCHITECTURE.md §3.1.1).
@Observable
@MainActor
public final class LoadingRouteViewModel {
    public enum ViewState: Equatable {
        case loading(LoadingContext)
        case finished(Transcript)
        case failed(ShuoError)
    }

    public private(set) var viewState: ViewState = .loading(.transcribing)

    /// The transcript, once there is one.
    public var transcript: Transcript? {
        if case .finished(let transcript) = viewState { return transcript }
        return nil
    }

    public var failure: ShuoError? {
        if case .failed(let error) = viewState { return error }
        return nil
    }

    /// Filename of the attachment being processed, for the loading screen's detail line.
    public var sourceDescription: String? {
        if case .importedMedia(let media) = source { return media.originalFileName }
        return nil
    }

    private let source: SpeechSource
    private let generateTranscript: GenerateTranscriptUseCase
    /// Held so the work can be cancelled explicitly when the user leaves. An
    /// un-cancelled transcription firing after the screen is gone is exactly the bug
    /// class CLAUDE.md §6 flags for this app.
    private var workTask: Task<Void, Never>?

    public init(source: SpeechSource, generateTranscript: GenerateTranscriptUseCase) {
        self.source = source
        self.generateTranscript = generateTranscript
    }

    /// Starts (or restarts) transcription. Safe to call again for a retry — any in-flight
    /// attempt is cancelled first.
    public func start() {
        workTask?.cancel()
        viewState = .loading(initialContext)

        workTask = Task { [generateTranscript, source] in
            do {
                let transcript = try await generateTranscript(source: source)
                guard !Task.isCancelled else { return }
                viewState = .finished(transcript)
            } catch let error as ShuoError {
                guard !Task.isCancelled else { return }
                viewState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                // A non-domain error escaping the service layer is a boundary bug, but
                // the user still gets an explainable failure rather than a hang.
                viewState = .failed(.transcriptionFailed)
            }
        }
    }

    /// Abandons the in-flight work. Must be called when the screen goes away.
    public func cancel() {
        workTask?.cancel()
        workTask = nil
    }

    // Video is the only source that pays the extraction step first, so it is the only one
    // whose first message mentions it.
    private var initialContext: LoadingContext {
        if case .importedMedia(let media) = source, media.kind.requiresAudioExtraction {
            return .extractingAudio
        }
        return .transcribing
    }
}
