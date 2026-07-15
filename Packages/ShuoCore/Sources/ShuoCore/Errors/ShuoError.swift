//
//  ShuoError.swift
//  ShuoCore
//

import Foundation

public enum ShuoError: Error, Sendable {
    case transcriptionFailed
    case aiUnavailable
    case contextWindowExceeded
    case importFailed
    case persistenceFailed
}
