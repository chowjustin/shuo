# Shuo

**Structure your speech, on-device.**

Shuo is an iOS app that helps undergraduate students prepare a speech: pick a purpose,
capture ideas by speaking, writing, or attaching a file, get an on-device AI analysis with
structural pattern suggestions and key points, then save and search past speeches — fully
on-device, with no backend, no accounts, and no network calls.

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.2-orange)
![Architecture](https://img.shields.io/badge/architecture-Clean%20Architecture%20%2B%20MVVM--C-informational)
![UI](https://img.shields.io/badge/UI-SwiftUI-blue)

---

## Overview

A student opens Shuo, picks what their speech needs to do — **persuade**, **inspire**, or
**inform** — and captures their ideas however is fastest for them in the moment: talking
through it out loud, typing it out, or attaching an existing recording or video. Shuo
transcribes the input on-device, then uses Apple's on-device Foundation Models to suggest
up to three structural patterns (e.g. Problem–Solution), surface key points, and produce a
refined transcript. Every generated speech is saved locally and searchable later, with the
full generated state (transcript, patterns, key points) restored instantly on reopen — no
re-analysis needed.

Everything runs on-device. There is no server, no account system, and no cross-device sync
in v1.

## Features

- **Purpose-driven speech prep** — persuade, inspire, or inform, each framing the AI
  analysis that follows.
- **Three ways to capture ideas** — speak it (live waveform + transcription), write it
  directly, or attach an existing audio/video file (with automatic audio extraction from
  video).
- **On-device transcription** — Apple's `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26+),
  tuned for long-form speech, with an `SFSpeechRecognizer` fallback.
- **On-device AI analysis** — up to 3 suggested structural patterns, auto-generated key
  points with ghost-text suggestions, and a refined transcript, all via Apple's
  `FoundationModels` framework. Nothing leaves the device.
- **Editable, self-updating analysis** — edit the transcript and key points regenerate
  automatically (debounced, cancellation-safe); switch patterns and the key
  points/refined transcript re-scope to match.
- **Save, search, and reopen** — every generated speech persists locally via SwiftData;
  reopening a saved speech restores the full analysis instantly, with no AI re-invocation.

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (no UIKit) |
| State management | `@Observable` (Observation framework) |
| Concurrency | Swift 6.2, strict concurrency, actors for I/O services |
| Persistence | SwiftData, behind a repository protocol |
| Speech-to-text | `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26+), `SFSpeechRecognizer` fallback |
| AI analysis | Apple `FoundationModels`, `@Generable`/`@Guide` structured generation |
| Navigation | Coordinator pattern over `NavigationStack` |
| Testing | Swift Testing (unit/integration/ViewModel), XCTest/XCUITest (UI automation) |
| Modularization | Local Swift Package Manager packages, one per architectural layer/feature |

**Requirements:** iOS 26+, Xcode 26+, Swift 6.2. Apple Intelligence–eligible hardware is
required to run the AI analysis features — this is a deliberate v1 constraint, not a bug;
there is no degraded "no-AI" mode.

## Architecture

Shuo follows **Clean Architecture** (Domain / Data / Presentation) with an **MVVM-C**
presentation layer, enforced not just by convention but by the module graph itself —
Feature packages physically cannot `import SwiftData` or `import FoundationModels`,
because those packages aren't in their dependency graph.

```
Presentation (Features, App)   ──depends on──▶  ShuoCore (Domain)
Data & services (Persistence,
  Audio, AI)                   ──depends on──▶  ShuoCore (Domain)
```

`ShuoCore` sits at the center: pure Foundation, zero Apple-SDK imports, owning every
entity, use case, and protocol. Persistence (SwiftData), Audio (`AVFoundation`/speech),
and AI (`FoundationModels`) each implement `ShuoCore` protocols but never see each other.
Feature packages talk only to `ShuoCore` protocols and `ShuoDesignSystem` components —
concrete implementations are wired together in exactly one place, `AppContainer`, the
app's composition root.

Why this split: three subsystems here (persistence, speech-to-text, AI) are new,
independently evolving, and impossible to run meaningfully in unit tests as-is. Putting a
domain-owned protocol between business logic and each Apple SDK is what makes the domain
layer fast and fully testable with fakes, while letting any one subsystem be swapped or
upgraded without touching a use case or a view.

The full reasoning — feature-by-feature analysis, alternatives considered, decisions log —
lives in [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md). Day-to-day conventions and rules
for working in this codebase live in [`CLAUDE.md`](CLAUDE.md).

## Project Structure

```
Shuo/
├── Shuo.xcodeproj                    Xcode-native project (no XcodeGen/Tuist)
├── Shuo/                             App target — composition root only
│   ├── ShuoApp.swift                 @main entry point
│   └── AppContainer.swift            Wires concrete implementations to ShuoCore protocols
├── ShuoTests/                        Composition-root smoke tests
├── ShuoUITests/                      XCUITest: the 2–3 critical end-to-end paths
│
├── Packages/
│   ├── ShuoCore/                     Domain: entities, use cases, protocols (zero Apple-SDK imports)
│   ├── ShuoPersistence/              SwiftData models, repository, mapper
│   ├── ShuoAudio/                    AVFoundation recording, speech transcription
│   ├── ShuoAI/                       FoundationModels wrapper, @Generable schemas
│   ├── ShuoDesignSystem/             Reusable, domain-agnostic SwiftUI components + tokens
│   ├── ShuoTestSupport/              Shared test fakes for every other package
│   ├── FeatureHome/                  Home screen — list, search, empty state
│   ├── FeatureSpeechCreation/        Purpose → input → loading flow
│   └── FeatureTranscriptAnalysis/    Transcript, patterns, key points screen
│
├── Docs/ARCHITECTURE.md              Architecture & feature-analysis source of truth
├── CLAUDE.md                         Day-to-day working conventions
└── README.md                         This file
```

Every package boundary above is compiler-enforced, not just a convention — see
`Docs/ARCHITECTURE.md` §5 and §12 for the full per-file breakdown and the reasoning
behind each dependency direction.

## Getting Started

**Prerequisites**
- Xcode 26 or later
- An iOS 26 Simulator (Apple Intelligence–eligible hardware for AI features on a physical device)

**Clone and open**

```bash
git clone <repo-url>
cd Shuo
open Shuo.xcodeproj
```

Xcode resolves the local Swift packages under `Packages/` automatically on first open.
Select the **Shuo** scheme and Run (`⌘R`).

**Build from the command line**

```bash
# Run a single package's tests in isolation (fast inner loop)
cd Packages/ShuoCore && swift test

# Run everything, including the app target and UI tests
xcodebuild test -project Shuo.xcodeproj -scheme Shuo -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Testing

| Layer | Framework | Approach |
|---|---|---|
| Domain use cases | Swift Testing | Pure logic, no I/O — fakes from `ShuoTestSupport`, fully parallel |
| Persistence | Swift Testing | Real SwiftData engine against an in-memory `ModelContainer` |
| Audio/Speech/AI adapters | Minimal, mostly manual | Kept as thin "humble objects" — can't meaningfully unit-test live hardware/on-device LLM calls in CI |
| ViewModels | Swift Testing, `@MainActor` | Fake use cases injected via the initializer; assert on view-state enums |
| Critical flows end-to-end | XCUITest | Create-speech happy path, search, reopen a saved script |

Every new use case, repository method, and ViewModel state transition ships with a Swift
Testing test in the same change — see `CLAUDE.md` §7 for the full testing policy.

## Project Status

The project is currently at the **architecture-scaffolding stage**: the full module
layout above is in place and wired into a buildable Xcode project — every package has a
correct `Package.swift`, every planned source/test file exists, and the app target
(`ShuoApp` → `AppContainer` → `FeatureHome.HomeView`) builds and runs end-to-end as a
proof of the composition-root wiring. Feature implementation — recording, transcription,
AI analysis, persistence, search — has not started yet.

The suggested build order (domain first, then persistence, then each feature) is in
`Docs/ARCHITECTURE.md` §11.

## Documentation

- [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) — architecture decisions, feature-by-feature
  analysis, domain model, module structure, and the full project layout.
- [`CLAUDE.md`](CLAUDE.md) — conventions, workflow, and the rules for working in this
  codebase day to day.
