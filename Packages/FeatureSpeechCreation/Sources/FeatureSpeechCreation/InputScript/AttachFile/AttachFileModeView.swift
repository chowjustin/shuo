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

struct AttachFileModeView: View {
    let viewModel: AttachFileModeViewModel
    @State private var isPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomActions
                .padding(.bottom, 40)
        }
        .fileImporter(
            isPresented: $isPickerPresented,
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
        case .idle:
            Text("Attach a file to get started.")
                .foregroundStyle(.secondary)

        case .processing:
            ProgressView("Importing…")
                .foregroundStyle(.secondary)

        case .ready(let media):
            fileCard(name: media.originalFileName, systemIcon: iconName(for: media.kind))

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
        case .idle, .failed, .ready:
            attachButton

        case .processing:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var attachButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1.5)
                }
                .frame(width: 72, height: 72)

                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 52, height: 52)

                Image(systemName: "paperclip")
                    .font(.title2.bold())
                    .foregroundStyle(Color.primary)
            }
        }
    }

    private func fileCard(name: String, systemIcon: String) -> some View {
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
            .frame(width: 120, height: 120)

            Text(name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
