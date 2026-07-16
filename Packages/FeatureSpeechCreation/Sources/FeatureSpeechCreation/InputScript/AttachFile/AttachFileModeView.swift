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
        .fileImporter(
            isPresented: $viewModel.isPickerPresented,
            allowedContentTypes: [.audio, .movie, .pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.fileSelected(url: url)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.viewState {
        case .idle, .fileTooLarge:
            Text("Upload your audio or video file.")
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

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
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
        Button {
            viewModel.isPickerPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 83, height: 83)

                Image(systemName: "paperclip")
                    .font(.system(size: 40).bold())
                    .foregroundStyle(Color.primary)
                    .scaledToFit()
            }
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
                    .font(.system(size: 40))
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
        case .pdf: "doc.text"
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

#Preview("Idle") {
    AttachFileModeView(viewModel: AttachFileModeViewModel(fileImporter: PreviewFileImporter()))
}

#Preview("Ready") {
    let vm = AttachFileModeViewModel(fileImporter: PreviewFileImporter())
    return AttachFileModeView(viewModel: vm)
        .task {
            vm.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
            await vm.importTask?.value
        }
}

#Preview("Failed") {
    let vm = AttachFileModeViewModel(fileImporter: FailingPreviewFileImporter())
    return AttachFileModeView(viewModel: vm)
        .task {
            vm.fileSelected(url: URL(filePath: "/tmp/speech.m4a"))
            await vm.importTask?.value
        }
}

#Preview("File Too Large") {
    let vm = AttachFileModeViewModel(fileImporter: TooLargePreviewFileImporter())
    return AttachFileModeView(viewModel: vm)
        .task {
            vm.fileSelected(url: URL(filePath: "/tmp/huge.mp4"))
            await vm.importTask?.value
        }
}
