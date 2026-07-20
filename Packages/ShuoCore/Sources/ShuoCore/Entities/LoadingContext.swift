//
//  LoadingContext.swift
//  ShuoCore
//
//  Created by Justin Chow on 13/07/26.
//

// Domain entity: `LoadingContext` enum (extractingAudio / transcribing / analyzing /
// waitingForModel) driving the copy and progress shown by the shared `LoadingView` in
// ShuoDesignSystem. See ARCHITECTURE.md §3.1.1.

import Foundation

/// Which long-running step the create flow is currently on.
///
/// The steps are sequential but not all mandatory: a typed-text speech skips straight to
/// `.analyzing`, and only video attachments pass through `.extractingAudio`.
public enum LoadingContext: Sendable, Equatable, CaseIterable {
    /// Pulling the audio track out of a video attachment. Video only.
    case extractingAudio
    /// Converting audio to text.
    case transcribing
    /// On-device model producing patterns and key points.
    case analyzing
    /// Apple Intelligence assets are still downloading; nothing can start yet.
    case waitingForModel
}
