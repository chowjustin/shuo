//
//  AnalysisField.swift
//  FeatureTranscriptAnalysis
//

import Foundation

/// A focusable field on the analysis screen.
enum AnalysisField: Hashable {
    case title
    case refined
    case keyPoint(String)
}
