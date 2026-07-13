//
//  LoadingRouteView.swift
//  FeatureSpeechCreation
//
//  Created by Justin Chow on 13/07/26.
//

// Wires `LoadingContext` (ShuoCore) to `ShuoDesignSystem.LoadingView`, and drives the
// extract → transcribe → analyze use-case sequence before pushing `.analysis` onto the
// coordinator's route. See ARCHITECTURE.md §3.1.1; video attachments need audio
// extraction first (CLAUDE.md §12).

import Foundation
