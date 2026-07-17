//
//  MicrophonePermissionStatus.swift
//  ShuoCore
//
//  Created by Justin Chow on 17/07/26.
//

import Foundation

/// Microphone authorization, as the domain sees it.
///
/// Deliberately coarser than the platform's own status: the only distinction that
/// changes what the UI does is "can we ask?" versus "must the user go to Settings?".
public enum MicrophonePermissionStatus: Sendable, Equatable {
    /// Never asked. Requesting will show the system prompt.
    case notDetermined
    case granted
    /// Denied or restricted. Requesting again will not prompt — only Settings can
    /// change this.
    case denied
}
