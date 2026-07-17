//
//  ShuoError.swift
//  ShuoCore
//

import Foundation

public enum ShuoError: Error, Sendable, Equatable {
    case transcriptionFailed
    case aiUnavailable
    case contextWindowExceeded
    case importFailed
    case persistenceFailed
    /// The user declined microphone access, or it is restricted. Only Settings can
    /// change this — re-requesting will not prompt again.
    case microphonePermissionDenied
    /// Audio capture could not start, or produced nothing usable.
    case recordingFailed
}
