//
//  HomeViewState.swift
//  FeatureHome
//
//  Created by Justin Chow on 13/07/26.
//

// `enum HomeViewState { .loading, .empty, .loaded([ScriptSummary]) }` — makes illegal
// combinations like 'empty but also loading' unrepresentable. See ARCHITECTURE.md §3.3.

import Foundation
import ShuoCore

public enum HomeViewState: Equatable {
    case loading
    case empty
    case loaded([ScriptSummary])
}
