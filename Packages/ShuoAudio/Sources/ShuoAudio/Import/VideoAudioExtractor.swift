//
//  VideoAudioExtractor.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// Extracts the audio track from a video attachment (`AVAssetReader`/
// `AVAssetExportSession`) before it's fed to the transcriber. Easy to miss when reading
// the acceptance criteria at a glance — flagged explicitly in CLAUDE.md §12.

import Foundation
