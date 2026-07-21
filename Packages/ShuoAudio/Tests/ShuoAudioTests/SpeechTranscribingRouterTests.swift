//
//  SpeechTranscribingRouterTests.swift
//  ShuoAudioTests
//
//  Created by Justin Chow on 13/07/26.
//

// PLACEHOLDER — this file contains no tests.
//
// Unlike the other empty test files, the subject here **does** exist:
// `SpeechTranscribingRouter` is ~69 real lines with a genuine branch (video routes through
// `VideoAudioExtractor`, audio goes direct) plus a bookmark-resolution failure path, none
// of it covered. CLAUDE.md §7's "humble object" exemption covers the `AVAudioEngine` /
// `SpeechAnalyzer` adapters it delegates to, but the routing decision is logic, not
// translation, and is testable against fakes. This is a real gap, not a blocked one.

import Foundation
