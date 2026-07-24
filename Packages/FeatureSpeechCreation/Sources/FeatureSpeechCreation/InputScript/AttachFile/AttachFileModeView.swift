//
//  AttachFileModeView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Attach File-mode UI: `.fileImporter`/`PhotosPicker` entry point for audio/video
// attachments. See ARCHITECTURE.md §3.1.5.

import SwiftUI
import UniformTypeIdentifiers
import ShuoCore
import ShuoDesignSystem

public struct AttachFileModeView: View {
    @Bindable var viewModel: AttachFileModeViewModel

    public init(viewModel: AttachFileModeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomActions
                .padding(.bottom, 40)
        }
        // Audio and video only. `.movie` covers video-with-audio containers; `.audio`
        // covers m4a/mp3/wav/caf. A video's audio track is extracted before
        // transcription (CLAUDE.md §12).
        .fileImporter(
            isPresented: $viewModel.isPickerPresented,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.fileSelected(url: url)
                }
            case .failure:
                // The picker itself failed rather than the user cancelling — surfaced so
                // the screen does not sit silently on its previous state.
                viewModel.pickerFailed()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.viewState {
        case .idle, .fileTooLarge:
            Text("Upload your audio or video file.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
        case .processing:
            ProgressView("Importing…")
                .foregroundStyle(.secondary)

        case .ready(let media):
            fileCard(
                name: media.originalFileName,
                systemIcon: iconName(for: media.kind),
                durationLabel: media.formattedDuration
            )

        case .failed(let error):
            // Inline rather than a sheet: the import failed before any long-running work
            // started, so the user is still on this screen and the attach button below
            // is already the way to retry.
            let copy = TranscriptionErrorCopy(error: error)
            VStack(spacing: 12) {
                Image(systemName: copy.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(copy.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(copy.message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Bottom actions

    @ViewBuilder
    private var bottomActions: some View {
        switch viewModel.viewState {
        case .idle, .failed, .ready, .fileTooLarge:
            attachButton

        case .processing:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var attachButton: some View {
        CircularIconButton(systemImage: "paperclip", accessibilityTitle: "Attach a file") {
            viewModel.isPickerPresented = true
        }
    }

    private func fileCard(name: String, systemIcon: String, durationLabel: String?) -> some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.1))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                Image(systemName: systemIcon)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, height: 215)

            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let durationLabel {
                Text(durationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iconName(for kind: ImportedMedia.Kind) -> String {
        switch kind {
        case .audio: "waveform"
        case .video: "video"
        }
    }
}

// MARK: - Preview

private struct PreviewFileImporter: FileImporting {
    func importFile(from url: URL) async throws -> ImportedMedia {
        ImportedMedia(fileURL: url, kind: .audio, originalFileName: url.lastPathComponent)
    }
}

private struct FailingPreviewFileImporter: FileImporting {
    func importFile(from url: URL) async throws -> ImportedMedia {
        throw ShuoError.importFailed
    }
}

private struct TooLargePreviewFileImporter: FileImporting {
    func importFile(from url: URL) async throws -> ImportedMedia {
        throw ShuoError.fileTooLarge
    }
}
