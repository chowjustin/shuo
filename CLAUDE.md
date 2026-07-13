# CLAUDE.md — working guide for Shuo

This file tells you (Claude, or any other contributor) how to work in this repository day to day.
**`Docs/ARCHITECTURE.md` is the source of truth for *why* things are structured this way** — feature
analysis, the reasoning behind every architectural decision, and the full file-by-file project
structure. Read it before your first change if you haven't already. This file is the source of
truth for *how to work here*: conventions, rules, workflow, and things that are easy to get wrong.

If anything in this file conflicts with `Docs/ARCHITECTURE.md`, treat `ARCHITECTURE.md` as
authoritative and flag the conflict rather than silently picking one.

---

## 1. What Shuo is

An iOS app that helps undergraduate students structure a speech during preparation: pick a
purpose (persuade / inspire / inform), capture ideas by speaking, writing, or attaching a
file, get an on-device AI transcript analysis with structural pattern suggestions and key
points, then save and search past speeches. Fully on-device — no backend, no network calls,
no accounts. See `Docs/ARCHITECTURE.md` §1–3 for the full feature breakdown.

## 2. Tech stack

- **iOS 26+**, Swift 6.2, Swift 6 language mode, strict concurrency everywhere.
- **SwiftUI** only — no UIKit.
- **`@Observable`** (Observation framework) for all view models — never `ObservableObject`/`@Published`.
- **SwiftData** for persistence, isolated behind a repository protocol (see §5 below).
- **`SpeechAnalyzer`/`SpeechTranscriber`** for speech-to-text, `SFSpeechRecognizer` as fallback.
- **Apple `FoundationModels`** (on-device LLM) for all AI analysis, via `@Generable`/`@Guide`
  structured generation. No cloud AI provider in v1.
- **Swift Testing** for unit/integration/ViewModel tests. **XCTest/XCUITest** only for UI
  automation and performance tests — never write new unit tests in XCTest.
- Plain, Xcode-native `.xcodeproj` with local Swift packages under `Packages/` — **no XcodeGen,
  no Tuist**. Don't introduce one without discussing it first; it's a structural change.
- No CI configured yet, no SwiftLint/SwiftFormat configured yet (deliberate, see
  `Docs/ARCHITECTURE.md` §10). Follow the style rules in this file manually until tooling
  catches up — don't let that gap turn into inconsistent code.

## 3. Repository map

```
Shuo/
├── Shuo.xcodeproj, Shuo/, ShuoTests/, ShuoUITests/     — app target (composition root)
├── Packages/
│   ├── ShuoCore/                — domain: entities, use cases, protocols. Zero Apple-SDK imports.
│   ├── ShuoPersistence/         — SwiftData models, repository, mapper
│   ├── ShuoAudio/               — AVFoundation recording, SpeechAnalyzer/SFSpeechRecognizer
│   ├── ShuoAI/                  — FoundationModels wrapper, @Generable schemas
│   ├── ShuoDesignSystem/        — reusable, domain-agnostic SwiftUI components + tokens
│   ├── ShuoTestSupport/         — shared fakes for every other package's tests
│   ├── FeatureHome/
│   ├── FeatureSpeechCreation/
│   └── FeatureTranscriptAnalysis/
├── Docs/ARCHITECTURE.md
├── CLAUDE.md                    — this file
└── README.md
```
Full per-file breakdown: `Docs/ARCHITECTURE.md` §12.

## 4. The one rule that matters more than any other

**Dependencies point inward, toward `ShuoCore`. Never the other way, and never sideways
between Feature packages.**

```
Presentation (Features, App)  ──depends on──▶  ShuoCore (Domain)
Data & services (Persistence,
  Audio, AI)                  ──depends on──▶  ShuoCore (Domain)
```

Concretely, enforced by each package's `Package.swift` dependency list — if you find yourself
wanting to violate one of these, stop and reconsider the design rather than adding the import:

- `ShuoCore` imports **nothing** but Foundation. No SwiftUI, no SwiftData, no AVFoundation, no
  FoundationModels, ever.
- `FeatureHome`, `FeatureSpeechCreation`, `FeatureTranscriptAnalysis` depend **only** on
  `ShuoCore` and `ShuoDesignSystem`. They must never import `ShuoPersistence`, `ShuoAudio`, or
  `ShuoAI` directly — they talk to those through protocols defined in `ShuoCore` and get
  concrete instances injected from `AppContainer`.
- `ShuoDesignSystem` never imports `ShuoCore`. Components take primitive values (strings,
  bools, closures, enums local to the design system), never domain types. This is what keeps
  it previewable and reusable in isolation.
- `ShuoPersistence`, `ShuoAudio`, `ShuoAI` each depend on `ShuoCore` only — never on each
  other, and never on any Feature package.
- Only `Shuo` (the app target) is allowed to depend on everything and wire concretes to
  protocols, in `AppContainer.swift`.

If a task seems to require breaking one of these, the right move is to add or adjust a
protocol in `ShuoCore`, not to add the import.

## 5. Coding conventions

- **One type per file, filename matches the type name.** `SaveScriptUseCase.swift` contains
  `SaveScriptUseCase` and nothing else load-bearing.
- **Naming pattern:** `XyzUseCase` (domain), `XyzRepository`/`XyzService` (data-layer
  concretes), `XyzViewModel`, `XyzView`, `FakeXyz` (test doubles in `ShuoTestSupport`). Don't
  invent alternate suffixes for the same role.
- **Access control is deliberate, not default-public.** Everything `internal` unless it's
  part of a package's public API surface (what other packages actually call) — then `public`,
  with a `///` doc comment explaining what it does and any preconditions.
- **No force-unwraps (`!`), no force-`try!`, no force-`as!`** outside of test code. Use
  `guard let`/`if let`, typed `throws`, or `ShuoError` cases. If you're tempted to force-unwrap
  something that "can never be nil," make the type system say so instead (non-optional
  property, `precondition` with a message, or a narrower type).
- **Errors are domain errors.** Data-layer failures (a `SwiftData` fetch throwing, a
  `FoundationModels` `GenerationError`, an `AVFoundation` error) get caught at the package
  boundary and re-thrown as a `ShuoError` case — Feature packages and view models never
  `catch` an Apple-framework error type directly, since they don't import those frameworks
  in the first place.
- **Value types by default.** Domain entities are `struct`s conforming to `Sendable`.
  Reach for `class`/`actor` only where reference semantics or isolation genuinely matter
  (services, coordinators, view models) — see §6.
- **Prefer composition over one large type.** If a view model is accumulating unrelated
  optional properties for different modes/states (see `InputScriptViewModel` in
  `Docs/ARCHITECTURE.md` §3.1.2), split it into child view models instead of adding more
  optionals.
- **View-state as an enum, not scattered booleans.** Any screen with loading/empty/error/
  loaded semantics gets an explicit `enum ViewState` (see `HomeViewState` in
  `Docs/ARCHITECTURE.md` §3.3) so illegal combinations are unrepresentable.

## 6. Concurrency rules

- **Domain layer (`ShuoCore`):** plain `Sendable` structs/enums; use-case protocols are
  `async throws` functions, callable safely from any isolation context. No actors, no
  `@MainActor` in this package.
- **Data/service layer:** wrap any non-`Sendable` Apple SDK state (`AVAudioEngine`,
  `LanguageModelSession`, `ModelContext` outside the main actor, etc.) in an `actor`. Don't
  reach for `@unchecked Sendable` to make the compiler stop complaining — if you think you
  need it, that's a signal the type needs an actor or a redesign, not a suppression.
- **Presentation layer:** view models are `@Observable @MainActor`. Xcode 26's default actor
  isolation (`MainActor` per target) means most presentation code needs no explicit
  annotation — don't sprinkle redundant `@MainActor` everywhere it's already implied.
- **Cancellation matters here more than in a typical app.** Any debounced or AI-triggered
  `Task` (transcript-edit → key-point regeneration, pattern switch → refine) must be stored
  as a handle on the owning view model and explicitly `.cancel()`ed before starting a
  replacement. A leaked, un-cancelled `Task` firing an AI call after the user has moved on
  is a real bug class in this app specifically — watch for it in review.
- **`SwiftData` `@Model` types stay inside `ShuoPersistence`.** They never cross a package
  boundary. This is *why* the mapper pattern exists (`Docs/ARCHITECTURE.md` §4.3) — don't
  "simplify" by passing a `ScriptEntity` up into a use case or view model.

## 7. Testing — mandatory, not optional

**Every new use case, repository method, and view-model state transition needs a Swift
Testing test in the same change.** This isn't a "nice to have" for this project — the person
building this explicitly wants industry-grade test coverage, and the whole point of the
Clean Architecture split is that most of this code is *cheap* to test well. Don't skip it
because a feature "seems simple."

- **Framework:** `import Testing`, `@Test` functions, `@Suite` for grouping, `#expect`/
  `#require` for assertions. Only use `XCTest` for files under `ShuoUITests/`.
- **Domain (`ShuoCoreTests`):** inject fakes from `ShuoTestSupport`. No I/O, no real
  SwiftData, no real Apple frameworks. These should be the fastest, most numerous tests in
  the suite.
- **Persistence (`ShuoPersistenceTests`):** use a real `ModelContainer` configured with
  `isStoredInMemoryOnly: true` via `ModelContainerFactory` — don't hand-roll a separate
  schema for tests; use the same factory the app uses so tests can't drift from production
  schema.
- **View models:** `@MainActor @Suite` (or `@Test` functions marked `@MainActor`), fakes
  injected through the initializer, assert on the view-state enum and derived computed
  properties, not on private implementation details.
- **Audio/Speech/AI service adapters:** keep these thin ("humble object") specifically so
  they don't need heavy test coverage — push logic into `ShuoCore` where it's cheap to test,
  and treat the adapter itself as a small, mostly-untested translation layer plus a couple
  of manual integration checks. Don't try to unit-test `AVAudioEngine` capture or a live
  `LanguageModelSession` call — that's not a productive use of effort and these can't run
  reliably in CI anyway.
- **Test doubles live in `ShuoTestSupport`, not duplicated per package.** If you need a new
  fake, add it there once.
- **Naming:** `<TypeUnderTest>Tests.swift`, `@Test("plain-English description of the
  behavior")` — test names should read as a sentence describing behavior, not
  `testSaveScript1`.

## 8. AI (`ShuoAI`) specific guidance

- Every `@Generable` type lives in `Schemas/` and is **never** exposed outside `ShuoAI` —
  `GeneratedContentMapper` converts to `ShuoCore` domain entities before anything else sees
  it. Feature packages and view models only ever see `SpeechPattern`, `KeyPoint`, etc.
- Only include `@Generable` properties the UI will actually display — the model populates
  every declared property regardless of use, so unused fields cost real latency for nothing.
- Check `AIAvailabilityGate` before any generation call. Since Apple Intelligence–eligible
  hardware is required for v1 (`Docs/ARCHITECTURE.md` §2.1), the only states this needs to
  handle gracefully at runtime are `.modelNotReady` (show the Loading UI, poll/retry) and
  `.appleIntelligenceNotEnabled` (actionable prompt to enable it in Settings). Don't build a
  degraded no-AI mode — that's explicitly out of scope for v1 (see §11).
- Long transcripts can exceed `SystemLanguageModel.default.contextSize`. Route anything long
  through `ContextWindowChunker` rather than sending a raw multi-thousand-word transcript
  straight into a prompt — this is in scope for v1, not a later hardening pass.
- Centralize prompt/instruction text in `PromptBuilder`, not inline in
  `FoundationModelSpeechAnalyzer`'s methods — keeps prompt wording reviewable and testable
  as data rather than buried in control flow.
- Grammar/vocab analysis (`analyzeGrammar` on `SpeechAnalyzing`) stays defined but **unused**
  in v1 — don't wire it into any use case or view model unless explicitly asked to pick that
  work back up.

## 9. Working with the plain Xcode project

There's no `project.yml`/`Project.swift` generating the `.xcodeproj` — it's the real,
Xcode-native project file, and local packages under `Packages/` are added via **File → Add
Package Dependencies → Add Local…**. Practical implications:

- When you add a new source file to a package, add it inside that package's `Sources/<Name>/`
  folder — Swift Package Manager picks up new files automatically, no project-file editing
  needed for package-internal files.
- When you add a **new package**, it needs to be added to the Xcode project through Xcode
  (or by editing the app target's package dependencies) — this one step doesn't happen
  automatically the way adding a file to an existing package does.
- Don't introduce XcodeGen or Tuist to "fix" merge-conflict pain on the `.xcodeproj` without
  raising it first — it's a deliberate choice (`Docs/ARCHITECTURE.md` §10), not an oversight.

## 10. Adding a new feature — the expected workflow

1. **Start in `ShuoCore`.** Add/extend the entity, the protocol (if a new capability is
   needed from Data/Services), and the use case. Write its Swift Testing tests against a
   fake from `ShuoTestSupport`. This should be fully done, tested, and reviewable before any
   UI exists.
2. **If it touches persistence,** extend `ScriptEntity`/`ScriptMapper` in `ShuoPersistence`
   and add/update the round-trip test.
3. **If it touches audio/speech/AI,** extend the relevant adapter in `ShuoAudio`/`ShuoAI`
   behind its existing protocol — don't add a new ad hoc access path.
4. **Build the view model** in the owning Feature package, injected with the use case
   protocol(s) it needs (never a concrete service). Test the view model against fakes.
5. **Build the view** using `ShuoDesignSystem` components where one already fits; add a new
   design-system component only if the need is genuinely reusable, not feature-specific.
6. **Wire it up** in `AppContainer.swift` — this is the only file that should need to import
   the concrete implementation alongside the protocol.
7. **Update `Docs/ARCHITECTURE.md`** if this changes the module structure, the domain model,
   or a documented decision — keep the design doc and the code from drifting apart.

## 11. Explicitly out of scope for v1 — don't build these unprompted

- Grammar/vocabulary suggestions UI (interface defined, not wired up — §8 above).
- Any degraded "no Apple Intelligence" mode — hardware is required, not optional.
- Any language other than English.
- Any backend, network call, account/auth, or cross-device sync. `ShuoPersistence`'s
  repository boundary is designed so CloudKit sync could be added later without a
  rearchitecture — but don't start building toward it now.
- CI configuration, SwiftLint/SwiftFormat config — deliberately deferred.
- A `DeleteScriptUseCase` or any script-deletion UI — not in the acceptance criteria; if this
  comes up, ask before adding it rather than assuming it's implied.

If a task seems to require any of the above, stop and ask rather than quietly expanding scope.

## 12. Common pitfalls in this codebase specifically

- **Naming collision risk:** the domain *entity* is `AudioRecording` (a struct); the
  *protocol* for the recording service is `AudioCapturing`. Don't rename one to match the
  other — they're deliberately distinct.
- **Video attachments need audio extraction before transcription** (`VideoAudioExtractor`)
  — easy to forget since it's not obvious from the acceptance criteria at a glance.
  Extraction and transcription both route through the same `.loading` route/`LoadingContext`
  in the create flow.
- **`@Model` SwiftData classes have real Swift 6 actor-isolation sharp edges.** If you hit an
  isolation error inside `ShuoPersistence`, the fix belongs there (`nonisolated` on the
  model, or restructuring the `ModelActor` usage) — it should never leak out as a reason to
  loosen concurrency checking elsewhere in the app.
- **Reopening a saved script and creating a new one share the same `.analysis` route and the
  same `ScriptDraft` type** — the only difference is whether `ScriptDraft.existingScriptID`
  is set (`Docs/ARCHITECTURE.md` §6). Don't build a separate "view saved script" screen.
- **The bundle identifier is a placeholder** (`com.shuo.app`,
  `Docs/ARCHITECTURE.md` §10.4) — flag it rather than treating it as final if it comes up in
  a signing/App Store context.

## 13. Definition of done (PR / change checklist)

- [ ] New/changed logic in `ShuoCore` has Swift Testing coverage using `ShuoTestSupport` fakes
- [ ] No new dependency crosses a boundary described in §4
- [ ] No force-unwraps/force-try introduced
- [ ] New async work that can overlap (edits, regenerations) has explicit cancellation
- [ ] SwiftData changes include an updated round-trip test via the in-memory `ModelContainerFactory`
- [ ] `Docs/ARCHITECTURE.md` updated if this change affects structure, domain model, or a
      logged decision
- [ ] `swift test` passes in every touched package

## 14. Build & test commands

```bash
# Run a single package's tests in isolation (fast inner loop)
cd Packages/ShuoCore && swift test

# Run everything, including the app target and UI tests, via Xcode's test plan
xcodebuild test -project Shuo.xcodeproj -scheme Shuo -destination 'platform=iOS Simulator,name=iPhone 17'
```

## 15. When unsure

This document and `Docs/ARCHITECTURE.md` cover the decisions made so far. For anything not
covered here — new scope, a tooling change, a structural decision — ask rather than assuming.
That's been the working style for this project from the start; keep it that way.
