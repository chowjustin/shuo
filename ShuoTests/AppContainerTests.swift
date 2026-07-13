//
//  AppContainerTests.swift
//  ShuoTests
//
//  Created by Justin Chow on 13/07/26.
//

// Composition-root smoke test: asserts AppContainer constructs without crashing and
// that its factory methods (makeHomeViewModel(), makeCreateScriptCoordinator(), etc.)
// return non-nil ViewModels. This is the only test at the app-target level — every
// other behavior is tested inside its own package. See CLAUDE.md §13, ARCHITECTURE.md
// §12.1.

import Foundation
