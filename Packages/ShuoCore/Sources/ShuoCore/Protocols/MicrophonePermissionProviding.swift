//
//  MicrophonePermissionProviding.swift
//  ShuoCore
//
//  Created by Justin Chow on 17/07/26.
//

import Foundation

/// Microphone authorization, behind a seam so view models can be tested without the
/// system permission prompt. Implemented by `MicrophonePermissionProvider` in ShuoAudio.
///
/// Speech-recognition authorization deliberately has no equivalent here: it is requested
/// inside ShuoAudio and, when refused, only costs the live-transcript optimization —
/// recording itself is unaffected, so it never reaches the UI. See ARCHITECTURE.md §3.1.3.
public protocol MicrophonePermissionProviding: Sendable {
    /// The current status. Never prompts.
    func currentStatus() async -> MicrophonePermissionStatus

    /// Requests access, prompting only when the status is `.notDetermined`.
    /// - Returns: the status after the user responds.
    func request() async -> MicrophonePermissionStatus
}
