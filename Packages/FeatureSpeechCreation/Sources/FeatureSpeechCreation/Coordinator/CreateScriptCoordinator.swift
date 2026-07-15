//
//  CreateScriptCoordinator.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Owns the in-flight `selectedPurpose` for the Purpose ->
// Input Script sheet chain, plus the `onFinish` callback that signals the presenter
// (RootView) to tear the whole flow down. See ARCHITECTURE.md §3.1.1.

import Foundation
import ShuoCore

@Observable
@MainActor
public final class CreateScriptCoordinator {
    public private(set) var selectedPurpose: SpeechPurpose?
    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public func selectPurpose(_ purpose: SpeechPurpose) {
        selectedPurpose = purpose
    }

    public func dismissInputScript() {
        selectedPurpose = nil
    }

    public func close() {
        onFinish()
    }
}
