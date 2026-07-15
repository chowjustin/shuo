# Copilot Instructions — Shuo

> **Trust these instructions first.** Search the codebase only if something here is incomplete or appears incorrect.

---

## 1. Repository Summary

**Shuo** is a fully on-device iOS app (iOS 26+, Swift 6.2) that helps undergraduate students structure a speech. Users pick a purpose (persuade / inspire / inform), capture ideas by speaking, typing, or attaching an audio/video file, receive on-device AI analysis (structural patterns, key points, refined transcript) via Apple's `FoundationModels` framework, then save and search past speeches via SwiftData. There is no backend, no network calls, and no account system.

- **Language:** Swift 6.2, Swift 6 strict concurrency mode everywhere
- **UI:** SwiftUI only — no UIKit
- **Platform:** iOS 26+ (Apple Intelligence–eligible hardware required for AI features)
- **Architecture:** Clean Architecture (Domain / Data / Presentation) + MVVM-C
- **Modularization:** Local Swift Package Manager packages under `Packages/`
- **Tooling:** Plain Xcode-native `.xcodeproj` (no XcodeGen, no Tuist); no CI yet; no SwiftLint/SwiftFormat yet
- **Xcode version:** Xcode 26 (26.6 / Build 17F113); **Swift version:** Apple Swift 6.3.3

---

## 2. Project Layout

```
Shuo/
├── Shuo.xcodeproj               Xcode project (native, no generator)
├── Shuo/                        App target — composition root only
│   ├── ShuoApp.swift            @main entry point
│   ├── RootView.swift           Root view: HomeView + sheet coordinator
│   └── AppContainer.swift      Wires concrete implementations to protocols
├── ShuoTests/                   AppContainer smoke tests (XCTest)
├── ShuoUITests/                 XCUITest: critical end-to-end paths
├── Packages/
│   ├── ShuoCore/                Domain: entities, use cases, protocols (zero Apple-SDK imports)
│   ├── ShuoPersistence/         SwiftData models, repository, mapper
│   ├── ShuoAudio/               AVFoundation recording, SpeechAnalyzer/SFSpeechRecognizer
│   ├── ShuoAI/                  FoundationModels wrapper, @Generable schemas
│   ├── ShuoDesignSystem/        Reusable SwiftUI components + design tokens (no ShuoCore dependency)
│   ├── ShuoTestSupport/         Shared fakes for all packages' test targets
│   ├── FeatureHome/             Home screen — list, search, empty state
│   ├── FeatureSpeechCreation/   Purpose → input → loading flow
│   └── FeatureTranscriptAnalysis/ Transcript, patterns, key points screen
├── Docs/ARCHITECTURE.md         Architecture decisions source of truth (§12 has per-file breakdown)
├── CLAUDE.md                    Day-to-day coding conventions and rules
└── README.md
```

Every package has its own `Package.swift` at `Packages/<Name>/Package.swift` and tests at `Packages/<Name>/Tests/<Name>Tests/`.

---

## 3. Dependency Rules (Compiler-Enforced — Never Violate)

```
Presentation (Features, App)  ──depends on──▶  ShuoCore (Domain)
Data & services (Persistence,
  Audio, AI)                  ──depends on──▶  ShuoCore (Domain)
```

| Package | Allowed imports |
|---|---|
| `ShuoCore` | Foundation only — never SwiftUI, SwiftData, AVFoundation, FoundationModels |
| `ShuoDesignSystem` | SwiftUI only — never `ShuoCore` or any data package |
| `FeatureHome`, `FeatureSpeechCreation`, `FeatureTranscriptAnalysis` | `ShuoCore` + `ShuoDesignSystem` only |
| `ShuoPersistence`, `ShuoAudio`, `ShuoAI` | `ShuoCore` only — never each other, never Feature packages |
| `Shuo` (app target) | All packages — the **only** place that wires concretes to protocols |

If a change seems to require crossing a boundary, add or extend a protocol in `ShuoCore` instead — never add the forbidden import.

---

## 4. Coding Conventions

- **One type per file**, filename matches type name exactly.
- **Naming:** `XyzUseCase` (domain), `XyzRepository`/`XyzService` (data concretes), `XyzViewModel`, `XyzView`, `FakeXyz` (test doubles in `ShuoTestSupport`).
- **No force-unwraps (`!`), force-`try!`, or force-`as!`** outside test code. Use `guard let`, typed `throws`, or `ShuoError`.
- **Errors:** data-layer failures are caught at the package boundary and re-thrown as `ShuoError` cases — Feature packages never `catch` Apple SDK errors.
- **State management:** `@Observable @MainActor` for all view models — never `ObservableObject`/`@Published`.
- **View state:** use an explicit `enum ViewState` (e.g., `.loading`, `.empty`, `.loaded`) — never scattered booleans.
- **Concurrency:** domain layer = plain `Sendable` structs; service layer = `actor`; presentation layer = `@MainActor`. Never use `@unchecked Sendable` to silence concurrency errors.
- **Task cancellation is critical:** every debounced or AI-triggered `Task` must be stored as a handle and explicitly `.cancel()`ed before starting a replacement. Leaked tasks triggering AI calls after navigation is a known bug class in this app.
- **`SwiftData @Model` types stay inside `ShuoPersistence`** — the mapper converts to/from plain domain structs; never pass `ScriptEntity` to use cases or view models.
- **Access control:** `internal` by default; `public` only for the package's API surface, with a `///` doc comment.

---

## 5. Testing Policy (Mandatory)

- **Always** write a Swift Testing test for every new use case, repository method, and view-model state transition **in the same change**.
- Use `import Testing`, `@Test`, `@Suite`, `#expect`/`#require`. Only use `XCTest` for `ShuoUITests/`.
- **Domain tests** (`ShuoCoreTests`): inject fakes from `ShuoTestSupport`. No real Apple frameworks, no I/O.
- **Persistence tests** (`ShuoPersistenceTests`): use real `ModelContainer` with `isStoredInMemoryOnly: true` via `ModelContainerFactory`.
- **ViewModel tests**: `@MainActor @Suite`, fake use cases injected through the initializer, assert on `ViewState` enum values.
- **Audio/Speech/AI adapters**: keep thin ("humble object") — minimal tests; do not unit-test live hardware or on-device LLM calls.
- **All fakes live in `ShuoTestSupport`** — never duplicate them per package. Add a new fake there once.
- **Naming:** `<TypeUnderTest>Tests.swift`, `@Test("plain English description")` — names should read as sentences.

---

## 6. PR / Change Checklist

- [ ] New/changed logic in `ShuoCore` has Swift Testing coverage with `ShuoTestSupport` fakes
- [ ] No new import crosses a boundary described in §4
- [ ] No force-unwraps or force-try introduced
- [ ] New async work that can overlap has explicit `Task` cancellation
- [ ] SwiftData changes include an updated round-trip test via in-memory `ModelContainerFactory`
- [ ] `Docs/ARCHITECTURE.md` updated if this changes module structure, domain model, or a logged decision
- [ ] `swift test` passes in every touched package

---

## 7. Key Files Quick Reference

| File | Purpose |
|---|---|
| `Shuo/ShuoApp.swift` | `@main` — builds `AppContainer`, shows `RootView` |
| `Shuo/AppContainer.swift` | Composition root — only file that imports concretes + protocols together |
| `Packages/ShuoCore/Sources/ShuoCore/Entities/` | All domain entities (`Script`, `ScriptDraft`, `SpeechPattern`, `KeyPoint`, etc.) |
| `Packages/ShuoCore/Sources/ShuoCore/Protocols/` | `ScriptRepository`, `AudioCapturing`, `SpeechTranscribing`, `SpeechAnalyzing`, `AIAvailabilityChecking`, `FileImporting` |
| `Packages/ShuoCore/Sources/ShuoCore/UseCases/` | All use cases — pure domain logic, no Apple SDK |
| `Packages/ShuoCore/Sources/ShuoCore/Errors/ShuoError.swift` | Domain error enum; all cross-package errors go through here |
| `Packages/ShuoPersistence/…/ModelContainerFactory.swift` | Used by both app and tests — single source of SwiftData schema truth |
| `Packages/ShuoAI/…/PromptBuilder.swift` | All AI prompt text centralized here |
| `Packages/ShuoTestSupport/Sources/ShuoTestSupport/` | All `FakeXyz` doubles — add new fakes here |
| `Docs/ARCHITECTURE.md` §12 | Full per-file breakdown of every package |

---

## 8. Explicitly Out of Scope for v1

Do **not** build these without being explicitly asked:

- Grammar/vocabulary suggestions UI (protocol defined, nothing wired)
- Any degraded "no Apple Intelligence" mode — hardware is required
- Any language other than English
- Any backend, network calls, accounts, or cross-device sync
- CI configuration, SwiftLint/SwiftFormat config
- A `DeleteScriptUseCase` or script-deletion UI

---

## 9. Common Pitfalls

- `AudioRecording` (domain struct) ≠ `AudioCapturing` (protocol) — distinct by design; do not rename either.
- Video attachments require audio extraction via `VideoAudioExtractor` **before** transcription — easy to miss.
- SwiftData `@Model` actor-isolation errors belong inside `ShuoPersistence`; never solve them by loosening concurrency elsewhere.
- Reopening a saved script and creating a new one share the same route and `ScriptDraft` type — `existingScriptID` is nil for new, set for reopen. Do not build a separate "view saved script" screen.
- Bundle identifier is a placeholder (`com.shuo.app`) — flag rather than treat as final in signing/App Store contexts.
