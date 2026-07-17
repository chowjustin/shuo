//
//  SpeechSource.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `SpeechSource` enum unifying the three ways a speech can originate
// (recordedAudio / importedMedia / typedText) so the use-case layer doesn't need to
// special-case the input mode. See ARCHITECTURE.md §3.2.1.

import Foundation

public enum SpeechSource: Sendable, Equatable {
    case recordedAudio(AudioRecording)
    case importedMedia(ImportedMedia)
    case typedText(String)
}
