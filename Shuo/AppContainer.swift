//
//  AppContainer.swift
//  Shuo
//
//  Created by Justin Chow on 13/07/26.
//

// Composition root. Will own the app's ModelContainer and every concrete service
// (ShuoPersistence, ShuoAudio, ShuoAI) as those land; for now it exposes a single
// factory method proving the FeatureHome -> AppContainer -> ShuoApp wiring end to
// end. This is the only file in the app allowed to import concrete implementations
// alongside the protocols they satisfy — see CLAUDE.md §4, §9 and ARCHITECTURE.md
// §5, §12.1.

import Foundation
import AVFoundation
import ShuoCore
import FeatureSpeechCreation

// Temporary importer for manual testing — replace with FileImportService from ShuoAudio
// once that is implemented.
private struct TemporaryFileImporter: FileImporting {
    func importFile(from url: URL) async throws -> ImportedMedia {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let kind: ImportedMedia.Kind
        if ["mp3", "m4a", "wav", "aiff", "flac"].contains(ext) {
            kind = .audio
        } else if ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext) {
            kind = .video
        } else {
            kind = .pdf
        }

        var duration: TimeInterval? = nil
        if kind != .pdf {
            let asset = AVURLAsset(url: url)
            if let cmDuration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(cmDuration)
                if seconds.isFinite && seconds > 0 {
                    duration = seconds
                }
            }
        }

        return ImportedMedia(
            fileURL: url,
            kind: kind,
            originalFileName: url.lastPathComponent,
            duration: duration
        )
    }
}

final class AppContainer {
    func makeAttachFileModeView() -> AttachFileModeView {
        let vm = AttachFileModeViewModel(fileImporter: TemporaryFileImporter())
        return AttachFileModeView(viewModel: vm)
    }
}
