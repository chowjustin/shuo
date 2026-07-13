//
//  CreateScriptCoordinator.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// `@Observable @MainActor`. Owns the `Route` enum (.purpose, .inputScript, .loading,
// .analysis) and `NavigationPath` for the single fullscreen-cover create/reopen flow,
// plus the in-flight `ScriptDraft`. See ARCHITECTURE.md §3.1.1.

import Foundation
