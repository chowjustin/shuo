//
//  FakeMicrophonePermissionProviding.swift
//  ShuoTestSupport
//
//  Created by Justin Chow on 17/07/26.
//

import Foundation
import ShuoCore

/// `MicrophonePermissionProviding` returning scripted statuses, so view-model tests can
/// cover the grant and denial paths without the system permission prompt.
public actor FakeMicrophonePermissionProviding: MicrophonePermissionProviding {
    private var status: MicrophonePermissionStatus
    /// What `request()` resolves to. Defaults to whatever `status` already is, which
    /// models an already-decided permission.
    private let statusAfterRequest: MicrophonePermissionStatus

    public private(set) var requestCount = 0

    public init(
        status: MicrophonePermissionStatus = .granted,
        statusAfterRequest: MicrophonePermissionStatus? = nil
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest ?? status
    }

    public func currentStatus() async -> MicrophonePermissionStatus {
        status
    }

    public func request() async -> MicrophonePermissionStatus {
        requestCount += 1
        status = statusAfterRequest
        return status
    }
}
