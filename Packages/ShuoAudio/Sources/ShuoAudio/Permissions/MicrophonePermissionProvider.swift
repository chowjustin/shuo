//
//  MicrophonePermissionProvider.swift
//  ShuoAudio
//
//  Created by Justin Chow on 13/07/26.
//

// Wraps the microphone permission status and request flow, backing the
// `NSMicrophoneUsageDescription` prompt.

import AVFoundation
import Foundation
import ShuoCore

/// `MicrophonePermissionProviding` backed by `AVAudioApplication`.
///
/// Uses `AVAudioApplication` rather than `AVAudioSession.requestRecordPermission`, which
/// is deprecated as of iOS 17.
public struct MicrophonePermissionProvider: MicrophonePermissionProviding {

    public init() {}

    public func currentStatus() async -> MicrophonePermissionStatus {
        Self.map(AVAudioApplication.shared.recordPermission)
    }

    public func request() async -> MicrophonePermissionStatus {
        // Requesting when already decided returns the existing answer without prompting,
        // but checking first keeps that guarantee ours rather than the framework's.
        let current = Self.map(AVAudioApplication.shared.recordPermission)
        guard current == .notDetermined else { return current }

        let granted = await AVAudioApplication.requestRecordPermissionWithCompletionHandler
        return granted ? .granted : .denied
    }

    // `.denied` collapses denied and any future restricted-style case: both mean the same
    // thing to the UI — we cannot prompt, only Settings can change it.
    private static func map(_ permission: AVAudioApplication.recordPermission) -> MicrophonePermissionStatus {
        switch permission {
        case .undetermined: .notDetermined
        case .granted: .granted
        case .denied: .denied
        @unknown default: .denied
        }
    }
}

private extension AVAudioApplication {
    static var requestRecordPermissionWithCompletionHandler: Bool {
        get async {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
