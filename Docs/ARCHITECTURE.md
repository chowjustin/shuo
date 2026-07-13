# Shuo — iOS Architecture & Feature Analysis

**Status:** Pre-implementation design document
**Scope:** User Stories 1–3 (speech creation, transcription & AI analysis, save/search/history)
**Target platform:** iOS 26+, Swift 6.2, SwiftUI

---

## 1. Recommended architecture at a glance

| Concern | Recommendation | Why (short version) |
|---|---|---|
| Architectural style | **Clean Architecture** (Domain / Data / Presentation) + **MVVM-C** | 3 subsystems (persistence, STT, AI) are genuinely swappable and hard to test as-is — see §4 |
| UI | SwiftUI only | No UIKit legacy, no cross-platform requirement |
| State management | `@Observable` (Observation framework) | Replaces `ObservableObject`/`@Published`, less boilerplate, granular re-renders |
| Concurrency | Swift 6.2 strict concurrency; actors for I/O services | Compile-time data-race safety; matches Xcode 26 defaults |
| Persistence | SwiftData behind a `ScriptRepository` protocol | Swift-native, integrates with SwiftUI, but isolated behind a mapper (see §4.3) |
| Speech-to-text | `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26+), `SFSpeechRecognizer` fallback | Built for long-form speech, on-device, no Settings dictation toggle needed |
| AI analysis | Apple **Foundation Models** framework, `@Generable`/`@Guide` structured generation | Structured, type-safe output maps directly onto patterns/key points/refined transcript |
| Navigation | Coordinator pattern over `NavigationStack` | Multi-step modal flow with shared state (title, purpose, draft) |
| Dependency injection | Manual constructor injection from a composition root | No framework needed at this scale; fully testable |
| Testing | **Swift Testing** for unit/domain/ViewModel tests, **XCTest/XCUITest** for UI & performance | Current (2026) Apple-recommended split |
| Modularization | Local Swift Package Manager packages per layer + per feature | Compiler-enforced boundaries, parallel test builds |

The diagram above shows the core rule this all follows: **outer layers depend inward on Domain, never the other way around.** Everything below expands on why, and where the exceptions and trade-offs are.

---

## 2. Confirmed product decisions

These were open assumptions in the first draft and have since been confirmed:

1. **iOS 26+ minimum deployment target, and Apple Intelligence–eligible hardware is *required*, not optional.** Both `SpeechAnalyzer` and `FoundationModels` are iOS 26-only, and for v1 the app will not offer a degraded "no-AI" mode — a device that doesn't meet Apple Intelligence's hardware requirement is treated as unsupported. This simplifies the availability handling considerably: the `AIAvailabilityGate` (§3.2.4) only needs to handle the *transient* "model still downloading" state gracefully, not a permanent feature-degradation path. It does mean the App Store listing, onboarding, and QA device matrix all need to communicate/enforce the hardware requirement — see the open questions in §9 for what's still pending on this.
2. **Local-first, single-user, no backend.** Nothing in the stories mentions accounts, sync, or a server. Everything is designed to run fully on-device. If cross-device sync becomes a requirement later, SwiftData's CloudKit integration is additive, not a rearchitecture — the repository protocol boundary already isolates this decision.
3. **English-only for v1**, with the domain/locale boundary designed so more languages are a config change later, not a rearchitecture (`SpeechTranscriber.supportedLocales` already supports this).
4. Undergraduate students will have "a handful to a few hundred" saved scripts, not thousands — this affects the search implementation recommendation in §3.3.
5. **Grammar & vocabulary analysis is deferred past v1.** It's a real capability of the Foundation Models framework and worth keeping in mind at the protocol level (§3.2.4), but no v1 use case or ViewModel wires it up, and no UI is built for it. Revisit as a fast-follow.

---

## 3. Feature-by-feature analysis

### 3.1 User Story 1 — Purpose selection & script input

#### 3.1.1 Purpose selection
This is static, enum-driven content — no network, no persistence needed for the options themselves.

```swift
enum SpeechPurpose: String, Codable, CaseIterable, Sendable, Identifiable {
    case persuade, inspire, inform
    var id: String { rawValue }
    var title: String { /* localized */ }
    var description: String { /* localized */ }
}
```
Because it's just three `CaseIterable` cases, the Purpose screen is a `ForEach(SpeechPurpose.allCases)` over cards — no ViewModel logic beyond "which one was tapped," which the coordinator handles directly.

**Navigation (confirmed):** Home is the only screen presented as a regular, persistent part of the app's `NavigationStack`. Everything from tapping "+" through seeing the transcript & pattern suggestions is **one continuous `.fullScreenCover`**, internally driven by a single `CreateScriptCoordinator` owning its own `NavigationPath` and `Route` enum:

```swift
@Observable @MainActor final class CreateScriptCoordinator {
    enum Route: Hashable {
        case purpose
        case inputScript(SpeechPurpose)
        case loading(LoadingContext)          // extraction / transcription / first AI pass
        case analysis(ScriptDraft)            // transcript + pattern suggestions
    }
    var path: [Route] = []
    // reopening a saved script skips straight to .analysis — see §3.3
}
```
This keeps title/purpose/draft state alive across every step without re-fetching or duplicating it, and the "X" button dismisses the *entire* cover from any step — with one exception: inside Attach File, "X" only cancels the file picker sub-modal, not the whole creation flow (per the acceptance criteria, these are two different dismiss actions). Reopening a previously saved script from Home also presents the same `.fullScreenCover`, but with `path` initialized directly to `.analysis(existingScript)`, bypassing purpose/input/loading entirely.

**Loading UI (confirmed):** the transition after "Save"/"proceed" in Input Script — which may involve audio extraction (video attachments), speech-to-text, and the first AI analysis pass — is a dedicated, reusable `LoadingView` pushed as its own route (`.loading`), living in `ShuoDesignSystem` so any step can reuse it with a different status message ("Extracting audio…", "Transcribing…", "Analyzing your speech…"). It stays inside the same fullscreen cover — the user never sees a screen transition outside the flow. This is distinct from the *inline* "Updating suggestions…" indicator used for incremental edits in the Transcript view (§3.2.2) — that one is a small in-place indicator, not a navigation to a new route, since navigating away for a small edit would be jarring.

#### 3.1.2 Input Script — shared shell
Because Speak / Write / Attach File have meaningfully different state and behavior, I'd avoid one giant `InputScriptViewModel` with a dozen optional properties (a common anti-pattern) and instead compose three focused child ViewModels owned by a parent:

```swift
@Observable @MainActor final class InputScriptViewModel {
    var title: String = ""
    let purpose: SpeechPurpose
    var mode: InputMode = .speak
    let speakVM: SpeakModeViewModel
    let writeVM: WriteModeViewModel
    let attachVM: AttachFileModeViewModel

    var hasValidContent: Bool {
        switch mode {
        case .speak: speakVM.hasFinishedRecording
        case .write: !writeVM.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .attachFile: attachVM.hasImportedFile
        }
    }
}
```
This keeps each mode independently unit-testable (Interface Segregation) and makes `hasValidContent` — which gates "proceed to Transcript" — trivial to test as a pure function of state.

#### 3.1.3 Speak mode
- **APIs:** `AVAudioEngine` (tap on the input node for live amplitude) or `AVAudioRecorder`, `AVAudioSession` category `.record`/`.playAndRecord`, `NSMicrophoneUsageDescription`.
- **Concurrency:** wrap capture in an `actor AudioRecordingService: AudioCapturing` — the actor isolates the non-`Sendable` `AVAudioEngine`/recorder state and exposes `async` methods (`start()`, `pause()`, `resume()`, `finish() -> AudioRecording`) plus an `AsyncStream<[Float]>` of downsampled amplitude values for the waveform (throttled to ~10–20Hz so SwiftUI isn't redrawing on every audio buffer).
- **Duration** comes from the recorder's `currentTime`, published on the same cadence as the waveform.
- **Testing:** the `AudioCapturing` protocol lets ViewModel tests inject a fake (assert on start/pause/resume/finish call counts and the idle→recording→paused→recording→finished state machine) without ever touching real hardware — which also can't run reliably in CI. The real actor implementation gets a small number of manual/integration checks instead (record to a temp file, assert non-zero duration), not exhaustive unit coverage.

#### 3.1.4 Write mode
Straightforward: `TextEditor` bound to `writeVM.content`, an `.overlay` placeholder for "Start typing your ideas." when empty (native SwiftUI pattern, no extra library needed). Nearly all logic here is pure and trivially testable.

#### 3.1.5 Attach File mode
- Use SwiftUI's `.fileImporter(allowedContentTypes: [.audio, .movie])` rather than hand-wrapping `UIDocumentPickerViewController`, unless you also want Photos-library sourcing (in which case combine `PhotosPicker` + `.fileImporter` behind an action sheet from the paperclip button).
- **Security-scoped resource:** the picked URL is only valid transiently — call `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` and copy the file into the app's sandbox (e.g. Application Support) before any further processing.
- **Naming note:** since everything is on-device, there's no server to "upload" to — the Upload button really means "confirm selection & start ingesting." Worth a quick UX gut-check, not a blocker.
- **Video files need an extra step:** audio must be extracted from the video track (`AVAssetReader`/`AVAssetExportSession`) before it can be fed to the transcriber. This is easy to miss when reading the acceptance criteria at a glance — flagging it now so it's scoped from day one, not discovered late.
- **Testing:** a `FileImporting` protocol (`importFile(from: URL) async throws -> ImportedMedia`) is mockable exactly like the audio service; the ViewModel's idle → selected → processing → ready state machine is unit-testable the same way.

---

### 3.2 User Story 2 — Transcription & AI analysis

#### 3.2.1 Unifying the three input sources
Model the input as a domain enum so the use-case layer doesn't care which mode produced it:

```swift
enum SpeechSource: Sendable {
    case recordedAudio(AudioRecording)
    case importedMedia(ImportedMedia)
    case typedText(String)
}
```
A single `GenerateTranscriptUseCase(source: SpeechSource) async throws -> Transcript` pattern-matches: `.recordedAudio`/`.importedMedia` go through `SpeechTranscribing`; `.typedText` short-circuits straight to the "original transcript." This directly satisfies the acceptance criteria ("typed input is used directly as transcript content") without special-casing it in the UI layer.

`SpeechTranscribing` wraps `SpeechAnalyzer` + `SpeechTranscriber` with the **long-form preset**, since a speech draft is exactly the "lectures, meetings, multi-speaker conversation" case Apple built the new model for — a meaningful accuracy improvement over the old `SFSpeechRecognizer` for this specific use case. `SFSpeechRecognizer` remains as an automatic fallback when `SpeechTranscriber`'s locale/hardware requirements aren't met.

#### 3.2.2 Transcript view
- Segmented control (Original/Refined) and accordion expand/collapse are cheap: a mode enum in the ViewModel and local `@State` per section respectively — expand/collapse doesn't need to survive app relaunch, so it's fine to keep as ephemeral view state rather than persisted.
- **Highlighting:** have the AI return highlight *snippets* (short excerpts), not character offsets — offsets break the moment the user edits the transcript. Compute highlight ranges client-side via substring/fuzzy matching between each key point's snippet and the current transcript text, then render with `AttributedString` (`Text(attributedString)` handles this natively in modern SwiftUI, no third-party rich text library needed).
- **Editable transcript → auto-updated key points:** debounce edits (roughly 800ms–1.5s after typing stops), then re-invoke `GenerateKeyPointsUseCase`. Store the in-flight `Task` on the ViewModel and cancel-and-replace it on every new debounce firing, so rapid edits don't queue up redundant AI calls or race each other. Show a lightweight "Updating suggestions…" indicator while this runs.

#### 3.2.3 Pattern suggestions
- "Max 3 patterns" maps directly onto Foundation Models' guided generation: `@Guide(.count(3))` on an array **forces** exactly 3 items back from the model — no client-side truncation needed.
- `ScrollView(.horizontal) { LazyHStack { ... } }` over `[SpeechPattern]`.
- Selecting a pattern re-runs generation scoped to that pattern: `ApplyPatternUseCase(original: Transcript, pattern: SpeechPattern) async throws -> (keyPoints: [KeyPoint], refinedTranscript: String)` — this is a second, smaller AI call conditioned on the already-generated original transcript, matching "selected pattern updates key points preview + refined transcript."
- "Suggestion under every empty key point textfield" is a near-perfect fit for SwiftUI's native placeholder parameter: `TextField(keyPoint.suggestion ?? "", text: $keyPoint.text)` gives you ghost-text for free.

#### 3.2.4 AI Foundation Model integration (deep dive)

This is the feature with the most architectural weight, so it gets its own protocol seam, independent of everything else:

```swift
protocol SpeechAnalyzing: Sendable {
    func suggestPatterns(for transcript: String) async throws -> [SpeechPattern]
    func generateKeyPoints(transcript: String, pattern: SpeechPattern) async throws -> [KeyPoint]
    func refineTranscript(_ transcript: String, pattern: SpeechPattern) async throws -> String
    func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion]
}
```
Domain use cases depend only on this protocol — never on `import FoundationModels` directly. The concrete `FoundationModelSpeechAnalyzer` lives in its own package and defines **AI response schemas separate from domain entities**:

```swift
import FoundationModels

@Generable
struct GeneratedPatternSet {
    @Guide(.count(3))
    let patterns: [GeneratedPattern]
}

@Generable
struct GeneratedPattern {
    @Guide(description: "Short structural pattern name, e.g. Problem-Solution")
    let name: String
    @Guide(description: "One sentence on when to use this pattern")
    let summary: String
    @Guide(description: "3 to 5 ordered structural beats")
    let outline: [String]
}
```
The service maps these `@Generable` DTOs to the domain's `SpeechPattern` — keeping the macro-generated schema out of the domain layer entirely.

A few things worth designing in from the start, based on how the framework actually behaves:

- **Availability still needs a gate, even though hardware is required.** `SystemLanguageModel.default.availability` can come back `.unavailable(.deviceNotEligible)`, `.appleIntelligenceNotEnabled`, or `.modelNotReady` (still downloading). Since v1 requires Apple Intelligence–eligible hardware (§2.1), `.deviceNotEligible` is treated as a hard block — realistically enforced earlier, at first-launch/onboarding, so the user isn't let deep into the app before hitting a wall. `AIAvailabilityGate` therefore has a narrower job for v1 than a fully degraded product would: handle `.modelNotReady` gracefully (show the Loading UI with a "Setting up on-device AI…" message and retry/poll), and treat `.appleIntelligenceNotEnabled` as an actionable prompt ("Enable Apple Intelligence in Settings") since that one's user-fixable without a new device.
- **The context window is real and finite — confirmed in scope for v1.** `SystemLanguageModel.default.contextSize` is a token budget shared across prompt *and* response. A full speech draft (easily 1,500+ words) plus instructions can threaten this, so a **chunking or summarize-then-analyze fallback** for long transcripts is part of v1, not a later hardening pass. Test against realistic full-length speeches, not just short demo input.
- **Only include `@Generable` properties you'll actually display.** The model populates every property of a `@Generable` type regardless of whether the UI shows it, so an unused `steps` field adds latency for nothing. Design the schemas tight.
- **Stream where it helps perceived latency.** `session.streamResponse(to:)` lets the refined transcript / key points render progressively instead of the UI sitting on a spinner for the full generation.
- **Grammar/vocab is deferred past v1 (confirmed).** `analyzeGrammar` stays defined on `SpeechAnalyzing` as a documented extension point — the interface is designed to support it — but no v1 use case calls it and no UI surfaces it. Revisit the UI question (inline strikethrough? separate panel?) when it's prioritized.
- **Provider swap is now natively supported, which validates the protocol seam.** Apple's WWDC 2026 update lets `LanguageModelSession` be backed by a swappable provider (on-device today, cloud providers optionally in future). Because `SpeechAnalyzing` already sits behind a protocol, adopting that later is a contained change inside one package, not a refactor of use cases or ViewModels.

---

### 3.3 User Story 3 — Save, history & search

- `Script` is the aggregate root, persisted via SwiftData behind a `ScriptRepository` protocol; a mapper converts between the `@Model` persistence type and the plain domain `Script` struct (reasoning for this split is in §4.3).
- **History list** should fetch a lightweight `ScriptSummary` projection (id, title, date, purpose, duration) rather than full `Script` objects with entire transcripts — keeps the Home list fast regardless of how large individual transcripts get.
- **Search:** given the likely dataset size (§2.4), naive in-memory filtering of an already-fetched `[ScriptSummary]` array is simpler than a `#Predicate`-driven fetch and fully sufficient — I'd avoid the extra complexity unless you have evidence the dataset will be large. `.searchable(text:)` bound to the ViewModel's search string is all the SwiftUI wiring needed for "instant results."
- **Reopening a script** loads the full `Script` aggregate directly from storage — no AI re-invocation needed, since "previously generated data remains available" means the persisted `Script` must capture the *entire* generated state (patterns, key points, refined transcript, grammar suggestions), not just the raw transcript.
- **Empty state:** model it as an explicit view-state enum rather than scattered booleans —

```swift
enum HomeViewState {
    case loading
    case empty
    case loaded([ScriptSummary])
}
```
This makes illegal states (e.g. "empty but also loading") unrepresentable and each state trivially unit-testable in isolation.

---

## 4. Why Clean Architecture + MVVM-C (and not something else)

### 4.1 The core argument
Three subsystems in this app are genuinely independent and likely to change on their own schedule:

1. **Persistence** (SwiftData) — stable, but you might add CloudKit sync later.
2. **Speech-to-text** (`SpeechAnalyzer`) — brand new as of iOS 26, actively evolving.
3. **AI analysis** (`FoundationModels`) — also brand new; Apple already added provider-swapping in a single subsequent OS cycle (WWDC 2026), which tells you this surface is moving fast.

None of these can run meaningfully in unit tests as-is (no microphone in CI, no guaranteed on-device model in every test environment). If use cases and ViewModels talk to these frameworks directly, your test suite either doesn't exist or is full of `#if canImport` hacks. Putting a domain-owned protocol between "business logic" and "Apple SDK" is what lets you: (a) unit-test the actual logic — pattern selection rules, validity checks, debounce/cancellation behavior — with fast, deterministic fakes, and (b) swap or upgrade any one of the three subsystems without touching use cases or views.

### 4.2 Alternatives considered

| Alternative | Why not chosen here |
|---|---|
| **Plain MVVM, no domain layer** | Simpler to start, but AI/persistence/STT leak directly into ViewModels — they become hard to test and hard to swap out later. Reasonable for a CRUD-only app; this one has real business logic (recording state machine, debounced re-analysis, pattern-conditioned regeneration). |
| **"MV" pattern** (SwiftUI models directly, skip ViewModels) | Good fit for very simple, mostly-static-data apps. Underpowered for the amount of async orchestration and state machines here. |
| **VIPER** | More ceremony/boilerplate than this app's complexity justifies, and a steeper ramp-up if this isn't a large team. |
| **TCA / unidirectional-reducer style** | Excellent testability and time-travel debugging, but a real learning-curve and either a third-party dependency or significant hand-rolled boilerplate. Worth reconsidering if the team already knows it well, or if the app's state complexity grows a lot — not clearly justified for the current scope. |

### 4.3 One deliberate trade-off worth naming: mapping vs. sharing the SwiftData model

You could let the `@Model` class *be* the domain entity directly — less boilerplate, and plenty of apps do this successfully. I'm recommending the extra mapping layer here specifically because:

- SwiftData's `@Model` classes have real Swift 6 concurrency sharp edges (actor-isolation conflicts with custom `ModelActor`s, `nonisolated` workarounds needed in some cases) — keeping domain entities as plain `Sendable` structs sidesteps this entirely and confines the complexity to the Persistence package.
- AI-generated data (patterns, key points) needs to flow through async, potentially background-executed use cases; plain structs are trivially safe to pass across those boundaries.
- Given you explicitly want thorough unit testing, plain structs with no framework lifecycle (no `ModelContext`, no faulting) are dramatically simpler to construct in test fixtures.

If build velocity matters more than this later, this is an easy one to relax — it's a localized decision, not load-bearing for the rest of the architecture.

---

## 5. Module structure

Local Swift Package Manager packages, one per layer plus one per feature, wired together only at the app target (composition root):

```
Shuo (app target — composition root)
├── depends on: every Feature package, Persistence, Audio, AI, DesignSystem
│
├── ShuoCore              (Domain — pure Foundation, zero Apple-SDK imports)
│     entities, use cases, repository & service protocols
│
├── ShuoPersistence       (depends on Core)
│     SwiftData models, SwiftDataScriptRepository, mappers
│
├── ShuoAudio             (depends on Core)
│     AVFoundation recording, SpeechAnalyzer/SFSpeechRecognizer transcription
│
├── ShuoAI                (depends on Core)
│     FoundationModels wrapper, @Generable schemas, FoundationModelSpeechAnalyzer
│
├── ShuoDesignSystem      (no business-logic dependency)
│     PurposeCard, PatternCard, WaveformView, AccordionView, EmptyStateView, LoadingView…
│
├── FeatureHome                  (depends on Core + DesignSystem only)
├── FeatureSpeechCreation        (depends on Core + DesignSystem only)
└── FeatureTranscriptAnalysis    (depends on Core + DesignSystem only)
```

**Why this specific split matters, not just "modularize for its own sake":** Feature packages depend on `Core` (protocols) and `DesignSystem` only — they physically cannot `import SwiftData` or `import FoundationModels`, because those packages aren't in their dependency graph. That's the Dependency Inversion Principle enforced by the compiler, not just code review. It also means Feature modules build and preview in Xcode without pulling in SwiftData or the AI stack, and each package gets its own fast, parallelizable test target.

**Dependency injection** stays deliberately simple at this scale — no DI framework. A single `AppContainer`, assembled once in `ShuoApp`, exposes factory methods (`makeHomeViewModel()`, `makeSpeechCreationCoordinator()`) that wire concrete implementations to protocols. The container itself is handed down via SwiftUI's `Environment` so deep child views can request what they need without prop-drilling every intermediate view, while every ViewModel still receives its dependencies through its initializer — which is what actually keeps things testable.

---

## 6. Domain model (sketch)

```swift
enum InputMode: String, Codable, Sendable { case speak, write, attachFile }

struct SpeechPattern: Sendable, Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let summary: String
    let outline: [String]
}

struct KeyPoint: Sendable, Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var orderIndex: Int
    var suggestion: String?     // ghost-text placeholder when text is empty
}

// Defined now so the persisted schema and SpeechAnalyzing protocol don't need
// a breaking change later — but no v1 use case populates or displays this yet.
struct GrammarSuggestion: Sendable, Identifiable, Codable {
    let id: UUID
    let originalPhrase: String
    let suggestedPhrase: String
    let explanation: String
}

struct Transcript: Sendable, Equatable {
    var original: String
    var refined: String
}

struct Script: Sendable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var purpose: SpeechPurpose
    var transcript: Transcript
    var suggestedPatterns: [SpeechPattern]      // up to 3
    var selectedPatternID: SpeechPattern.ID?
    var keyPoints: [KeyPoint]
    var grammarSuggestions: [GrammarSuggestion]   // always [] in v1 — see §2.5
    var recordingDuration: TimeInterval?
    var createdAt: Date
    var updatedAt: Date
}

struct ScriptSummary: Sendable, Identifiable {   // lightweight Home-list projection
    let id: UUID
    let title: String
    let purpose: SpeechPurpose
    let createdAt: Date
    let recordingDuration: TimeInterval?
}

// The mutable working state for the entire create/reopen flow (§3.1.1's
// CreateScriptCoordinator). New creation starts with an empty draft;
// reopening a saved script hydrates one from the persisted `Script`.
// `existingScriptID` is nil for a brand-new draft and set when reopening —
// it's what tells SaveScriptUseCase whether to insert or update.
struct ScriptDraft: Sendable, Identifiable {
    let id: UUID
    var existingScriptID: UUID?
    var title: String
    var purpose: SpeechPurpose
    var source: SpeechSource?
    var transcript: Transcript
    var suggestedPatterns: [SpeechPattern]
    var selectedPatternID: SpeechPattern.ID?
    var keyPoints: [KeyPoint]
    var recordingDuration: TimeInterval?
}

// Drives the copy and progress shown by the shared LoadingView (§3.1.1).
enum LoadingContext: Sendable, Equatable {
    case extractingAudio
    case transcribing
    case analyzing
    case waitingForModel   // SystemLanguageModel still downloading
}
```

---

## 7. Concurrency strategy

- **Domain layer:** plain `Sendable` structs/enums; use-case protocols expose `async throws` functions callable safely from any isolation context.
- **Data/service layer:** actors (`AudioRecordingService`, `SpeechTranscribingRouter`, `FoundationModelSpeechAnalyzer`) encapsulate the non-`Sendable` Apple SDK types and serialize access to hardware/session state.
- **Presentation layer:** `@Observable @MainActor` ViewModels. Xcode 26's default actor isolation (`SE-0466`, set to `MainActor` per target) means most presentation-layer code doesn't need explicit annotations — reserve explicit `nonisolated`/actor usage for the service layer where real background work happens.
- **Cancellation:** every debounced or long-running AI/transcription call is stored as a `Task` handle on the ViewModel and explicitly cancelled before starting a replacement — this matters more here than in a typical app, given how easy it is to fire overlapping AI calls from rapid transcript edits.

---

## 8. Testing strategy

| Layer | Framework | Approach |
|---|---|---|
| Domain use cases | **Swift Testing** | Pure logic, no I/O — inject protocol test doubles, fully parallel, fast |
| Repository (Persistence) | **Swift Testing** | Real SwiftData engine against an in-memory `ModelContainer(configurations: .init(isStoredInMemoryOnly: true))` — standard pattern for SwiftData tests |
| Service adapters (Audio/Speech/AI) | Minimal, mostly manual/integration | Can't meaningfully unit-test `AVAudioEngine` capture or a real on-device LLM call in CI. Keep these adapters as thin as possible ("humble object") so nearly all logic lives in the well-covered domain layer instead |
| ViewModels | **Swift Testing**, `@MainActor` | Inject fake use cases, assert state transitions (`loading`/`empty`/`error`/`loaded`) and derived properties (`hasValidContent`, filtered search results) |
| Critical flows end-to-end | **XCUITest** | Small number of high-value paths: create-speech happy path, search, reopen a saved script |
| Tricky custom UI (optional) | Snapshot testing (e.g. swift-snapshot-testing) | Waveform, highlighted transcript, pattern carousel — cheap protection against visual regressions |

This split follows current (2026) Apple guidance directly: Swift Testing is the default for unit/integration tests, XCTest/XCUITest stays for UI automation and performance tests since Swift Testing doesn't cover either, and the two coexist in the same test target without conflict.

**Representative test list** (illustrative, not exhaustive):
- `hasValidContent` returns `false` for empty write-mode text, `true` after a finished recording
- `GenerateTranscriptUseCase` routes `.typedText` directly to the transcript without invoking `SpeechTranscribing`
- Editing the transcript cancels an in-flight key-point regeneration `Task` and starts a new one
- `ApplyPatternUseCase` returns key points and a refined transcript scoped to the newly selected pattern, not the previous one
- `SwiftDataScriptRepository.save` then `.fetch(id:)` round-trips a `Script` with all fields intact, including patterns and grammar suggestions
- `HomeViewModel` search filters by title case-insensitively and updates synchronously as the query changes
- `AIAvailabilityGate` surfaces a non-blocking fallback state when `SystemLanguageModel.default.availability` is `.unavailable`

---

## 9. Decisions log

| # | Question | Decision |
|---|---|---|
| 1 | Purpose → Input Script: one container or chained sheets? | **One fullscreen sheet** for the entire create-through-analysis flow; Home is the only regular screen. See §3.1.1. |
| 2 | Grammar/vocab UI surface? | **Deferred past v1.** Interface stays defined, nothing wired up or displayed. See §2.5, §3.2.4. |
| 3 | Loading/progress UX for longer processing (video extraction, transcription, first AI pass)? | **Dedicated, reusable `LoadingView`**, pushed as its own route inside the same fullscreen sheet. See §3.1.1. |
| 4 | Chunking strategy for long transcripts vs. the Foundation Models context window? | **In scope for v1**, not deferred. See §3.2.4. |
| 5 | Require Apple Intelligence–eligible hardware, or degrade gracefully? | **Required for v1.** No degraded "no-AI" mode. See §2.1. |
| 6 | Multi-language beyond English for v1? | **English only** for v1. See §2.3. |

## 10. Tooling decisions (scaffolding phase)

| # | Question | Decision |
|---|---|---|
| 1 | Xcode project generation | **Plain, Xcode-native `.xcodeproj`** with local Swift packages added as local package references — no XcodeGen or Tuist. See §12–13 for the resulting layout. |
| 2 | CI | **Skipped for now.** No GitHub Actions workflow scaffolded in this pass. `swift test` per package and the app's test plan remain the way to run tests locally; add CI later without any structural change. |
| 3 | Design tokens / brand assets | **Placeholders for now.** `ShuoDesignSystem`'s token files ship with a sensible, clearly-marked placeholder palette/type scale — swap in real brand values whenever they're ready, nothing else in the app touches raw colors/fonts directly (see §12). |
| 4 | Bundle identifier | **Not yet provided — placeholder `com.shuo.app` used.** This lives in exactly one place (the app target's build settings); change it there before archiving/shipping. |

---

## 11. Suggested implementation order

1. `ShuoCore` package: entities, protocols, use cases + their tests (no UI, no Apple frameworks — fastest to get right and everything else depends on it).
2. `ShuoPersistence`: SwiftData models, repository, mapper + in-memory tests.
3. `FeatureHome` against a fake repository: empty state → list → search, fully testable before any AI/audio code exists.
4. `ShuoAudio`: recording actor + Speak mode UI.
5. `ShuoAI`: Foundation Models wrapper, availability gate, pattern/key-point/refine generation.
6. `FeatureSpeechCreation` and `FeatureTranscriptAnalysis` wired to the real services.
7. XCUITest coverage for the 2–3 critical end-to-end paths.

This ordering front-loads the parts that are cheapest to get thoroughly tested (domain, persistence) and pushes the hardest-to-test parts (audio hardware, on-device AI) to where they're wrapped by an already-solid, already-tested core.

---

## 12. Detailed project structure

Repository root:
```
Shuo/
├── Shuo.xcodeproj
├── Shuo/                          — app target (composition root only, no business logic)
├── ShuoTests/                     — app-target-level tests (composition root smoke tests)
├── ShuoUITests/                   — XCUITest target
├── Packages/                      — every local Swift package lives here
├── Docs/
│   └── ARCHITECTURE.md            — this document
├── CLAUDE.md                      — development guide (companion document)
├── README.md
└── .gitignore
```

### 12.1 App target — `Shuo/`
```
Shuo/
├── ShuoApp.swift          @main App struct. Builds AppContainer, injects it via
│                          .environment, shows HomeView inside a NavigationStack.
├── AppContainer.swift     Composition root. Owns the ModelContainer and every
│                          concrete service; exposes factory methods
│                          (makeHomeViewModel(), makeCreateScriptCoordinator(),
│                          makeAnalysisViewModel(draft:)) that wire concretes to
│                          the protocols each package's inits expect.
├── Info.plist             NSMicrophoneUsageDescription, minimum OS version.
└── Assets.xcassets        AppIcon, accent color (placeholder for now — §10.3).
```
`ShuoTests/AppContainerTests.swift` is the only test here: asserts the container constructs without crashing and that factory methods return non-nil ViewModels. Everything else is tested inside its own package.

`ShuoUITests/` — `CreateScriptHappyPathUITests.swift`, `SearchScriptsUITests.swift`, `ReopenScriptUITests.swift` (the 2–3 critical end-to-end paths from §8).

### 12.2 `Packages/ShuoCore` — Domain layer
No dependencies beyond Foundation. Nothing here imports SwiftUI, SwiftData, AVFoundation, or FoundationModels.

```
Packages/ShuoCore/
├── Package.swift
├── Sources/ShuoCore/
│   ├── Entities/
│   │   ├── SpeechPurpose.swift        enum: persuade/inspire/inform + title/description
│   │   ├── InputMode.swift            enum: speak/write/attachFile
│   │   ├── SpeechSource.swift         enum: recordedAudio/importedMedia/typedText
│   │   ├── AudioRecording.swift       struct: id, fileURL, duration, waveformSamples, createdAt
│   │   ├── ImportedMedia.swift        struct: id, fileURL, kind (audio/video), originalFileName
│   │   ├── Transcript.swift           struct: original, refined
│   │   ├── SpeechPattern.swift        struct: id, name, summary, outline
│   │   ├── KeyPoint.swift             struct: id, text, orderIndex, suggestion
│   │   ├── GrammarSuggestion.swift    struct — defined, unused in v1 (§2.5)
│   │   ├── Script.swift               aggregate root — the persisted, finished record
│   │   ├── ScriptSummary.swift        lightweight Home-list projection
│   │   ├── ScriptDraft.swift          mutable in-flight state for the create/reopen flow
│   │   └── LoadingContext.swift       enum driving the shared LoadingView's copy
│   │
│   ├── Protocols/                     the seams — domain owns these, Data/Presentation implement/consume them
│   │   ├── ScriptRepository.swift         save/fetch(id:)/fetchSummaries()/search(query:)/delete(id:)
│   │   ├── AudioCapturing.swift           start()/pause()/resume()/finish() -> AudioRecording, waveform stream
│   │   ├── SpeechTranscribing.swift       transcribe(_ source: SpeechSource) async throws -> String
│   │   ├── FileImporting.swift            importFile(from: URL) async throws -> ImportedMedia
│   │   ├── SpeechAnalyzing.swift          suggestPatterns / generateKeyPoints / refineTranscript / analyzeGrammar
│   │   └── AIAvailabilityChecking.swift   availability() async -> AIAvailabilityStatus
│   │
│   ├── UseCases/
│   │   ├── GenerateTranscriptUseCase.swift    routes SpeechSource -> Transcript (§3.2.1)
│   │   ├── SuggestPatternsUseCase.swift        transcript -> up to 3 SpeechPattern
│   │   ├── ApplyPatternUseCase.swift           pattern -> (keyPoints, refinedTranscript)
│   │   ├── RegenerateKeyPointsUseCase.swift    edited transcript -> updated keyPoints (debounced caller-side)
│   │   ├── SaveScriptUseCase.swift             ScriptDraft -> persisted Script (insert or update)
│   │   ├── FetchScriptSummariesUseCase.swift   Home list source
│   │   ├── FetchScriptUseCase.swift            full Script by id, for reopen -> hydrates a ScriptDraft
│   │   └── SearchScriptsUseCase.swift          title search over summaries
│   │
│   └── Errors/
│       └── ShuoError.swift             domain error enum: transcriptionFailed, aiUnavailable,
│                                        contextWindowExceeded, importFailed, persistenceFailed…
│
└── Tests/ShuoCoreTests/
    ├── GenerateTranscriptUseCaseTests.swift
    ├── SuggestPatternsUseCaseTests.swift
    ├── ApplyPatternUseCaseTests.swift
    ├── SaveScriptUseCaseTests.swift
    ├── FetchScriptUseCaseTests.swift
    └── SearchScriptsUseCaseTests.swift
```
(Test doubles for these live in `ShuoTestSupport`, §12.7, not duplicated here.)

**`Package.swift` (representative — no dependencies):**
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShuoCore",
    platforms: [.iOS(.v26)],
    products: [.library(name: "ShuoCore", targets: ["ShuoCore"])],
    targets: [
        .target(name: "ShuoCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShuoCoreTests", dependencies: ["ShuoCore", "ShuoTestSupport"]),
    ]
)
```

### 12.3 `Packages/ShuoPersistence` — depends on ShuoCore
```
Packages/ShuoPersistence/
├── Package.swift
├── Sources/ShuoPersistence/
│   ├── Models/
│   │   └── ScriptEntity.swift          @Model class. Scalar fields as attributes; patterns/
│   │                                   keyPoints/grammarSuggestions stored as Codable value
│   │                                   arrays (SwiftData supports this natively — no separate
│   │                                   relationship entities needed for v1's data shape).
│   ├── Mapping/
│   │   └── ScriptMapper.swift          ScriptEntity <-> Script, both directions
│   ├── Repositories/
│   │   └── SwiftDataScriptRepository.swift   implements ScriptRepository from Core
│   └── ModelContainerFactory.swift     builds the schema + ModelContainer; the same factory
│                                       (with `isStoredInMemoryOnly: true`) is what repository
│                                       tests use — one source of truth for the schema.
└── Tests/ShuoPersistenceTests/
    ├── ScriptMapperTests.swift
    └── SwiftDataScriptRepositoryTests.swift    round-trip save/fetch/search/delete, in-memory container
```

**`Package.swift` (representative — depends on another local package):**
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShuoPersistence",
    platforms: [.iOS(.v26)],
    products: [.library(name: "ShuoPersistence", targets: ["ShuoPersistence"])],
    dependencies: [.package(path: "../ShuoCore")],
    targets: [
        .target(name: "ShuoPersistence", dependencies: ["ShuoCore"],
                 swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShuoPersistenceTests", dependencies: ["ShuoPersistence"]),
    ]
)
```
Every other local package's `Package.swift` follows this same shape — a `.library` product, a `dependencies: [.package(path: "../X")]` entry per local package it needs, and matching target dependencies. Not repeated per-package below to avoid restating identical boilerplate.

### 12.4 `Packages/ShuoAudio` — depends on ShuoCore
```
Packages/ShuoAudio/
├── Sources/ShuoAudio/
│   ├── Recording/
│   │   ├── AudioRecordingService.swift     actor; conforms to AudioCapturing; wraps AVAudioEngine
│   │   └── WaveformSampler.swift            pure function: audio buffer -> downsampled [Float]
│   ├── Transcription/
│   │   ├── SpeechAnalyzerTranscriptionService.swift   actor; SpeechAnalyzer/SpeechTranscriber (iOS 26+)
│   │   ├── LegacySpeechRecognitionService.swift        actor; SFSpeechRecognizer fallback
│   │   └── SpeechTranscribingRouter.swift              picks analyzer vs legacy; conforms to
│   │                                                    SpeechTranscribing itself (facade)
│   ├── Import/
│   │   ├── FileImportService.swift          conforms to FileImporting; security-scoped copy into sandbox
│   │   └── VideoAudioExtractor.swift        AVAssetReader/AVAssetExportSession-based audio extraction
│   └── Permissions/
│       └── MicrophonePermissionProvider.swift
└── Tests/ShuoAudioTests/
    ├── WaveformSamplerTests.swift               pure function — fully unit-tested
    └── SpeechTranscribingRouterTests.swift       routing logic against fakes, not real hardware
```

### 12.5 `Packages/ShuoAI` — depends on ShuoCore, imports FoundationModels
```
Packages/ShuoAI/
├── Sources/ShuoAI/
│   ├── Schemas/                         the @Generable DTOs — never exposed outside this package
│   │   ├── GeneratedPatternSet.swift
│   │   ├── GeneratedPattern.swift
│   │   ├── GeneratedKeyPointSet.swift
│   │   ├── GeneratedKeyPoint.swift
│   │   ├── GeneratedRefinedTranscript.swift
│   │   └── GeneratedGrammarSuggestion.swift    defined, unused in v1 (§2.5)
│   ├── Mapping/
│   │   └── GeneratedContentMapper.swift  DTO -> ShuoCore domain entity
│   ├── FoundationModelSpeechAnalyzer.swift     conforms to SpeechAnalyzing; owns LanguageModelSession(s),
│   │                                           prewarm(), streamResponse() usage
│   ├── AIAvailabilityGate.swift                conforms to AIAvailabilityChecking; wraps
│   │                                           SystemLanguageModel.default.availability
│   ├── ContextWindowChunker.swift              chunk/summarize-then-analyze strategy for long transcripts
│   └── PromptBuilder.swift                     centralizes instruction/prompt text per use case
└── Tests/ShuoAITests/
    ├── ContextWindowChunkerTests.swift         pure logic — fully unit-tested
    ├── GeneratedContentMapperTests.swift
    └── AIAvailabilityGateTests.swift           against a fake availability provider
```
(`FoundationModelSpeechAnalyzer` itself gets minimal, manual/integration coverage only — see §8.)

### 12.6 `Packages/ShuoDesignSystem` — no business-logic dependency, domain-agnostic
Components take primitive display values (strings, bools, closures), never `ShuoCore` types directly — that's what keeps this package previewable and reusable in isolation.
```
Packages/ShuoDesignSystem/
├── Sources/ShuoDesignSystem/
│   ├── Tokens/
│   │   ├── ShuoColor.swift          placeholder palette (§10.3) — swap values here only
│   │   ├── ShuoTypography.swift     font styles: title/headline/body/caption
│   │   └── ShuoSpacing.swift        spacing scale constants
│   ├── Components/
│   │   ├── PurposeCard.swift
│   │   ├── PatternCard.swift
│   │   ├── WaveformView.swift
│   │   ├── AccordionView.swift
│   │   ├── SegmentedModeControl.swift   reusable for Speak/Write/Attach and Original/Refined
│   │   ├── EmptyStateView.swift
│   │   ├── LoadingView.swift            reads a display model (icon/message), not LoadingContext directly
│   │   ├── GhostTextField.swift         key-point field with a suggestion placeholder
│   │   └── HighlightedText.swift        renders AttributedString highlight ranges
│   └── Modifiers/
│       └── CardStyle.swift
```
No dedicated test target for v1 — these are presentational; add snapshot tests later if visual regressions become a real problem (§8).

### 12.7 `Packages/ShuoTestSupport` — test-only, shared fakes
Depends on `ShuoCore`; depended on by every other package's test target. Keeps fakes written once instead of duplicated per package.
```
Packages/ShuoTestSupport/
└── Sources/ShuoTestSupport/
    ├── FakeScriptRepository.swift
    ├── FakeAudioCapturing.swift
    ├── FakeSpeechTranscribing.swift
    ├── FakeFileImporting.swift
    ├── FakeSpeechAnalyzing.swift
    └── FakeAIAvailabilityChecking.swift
```
This is a regular `.library` product (not a test target) so other packages' *test targets* can depend on it without pulling it into their runtime targets.

### 12.8 `Packages/FeatureHome` — depends on ShuoCore + ShuoDesignSystem
```
Packages/FeatureHome/
├── Sources/FeatureHome/
│   ├── HomeView.swift
│   ├── HomeViewModel.swift        @Observable @MainActor; HomeViewState, search text,
│   │                              FetchScriptSummariesUseCase + SearchScriptsUseCase
│   ├── HomeViewState.swift        .loading / .empty / .loaded([ScriptSummary])
│   └── ScriptRowView.swift
└── Tests/FeatureHomeTests/
    └── HomeViewModelTests.swift   state transitions, search filtering
```

### 12.9 `Packages/FeatureSpeechCreation` — depends on ShuoCore + ShuoDesignSystem
```
Packages/FeatureSpeechCreation/
├── Sources/FeatureSpeechCreation/
│   ├── Coordinator/
│   │   └── CreateScriptCoordinator.swift    Route enum + path, owns the ScriptDraft (§3.1.1, §6)
│   ├── Purpose/
│   │   └── PurposeSelectionView.swift
│   ├── InputScript/
│   │   ├── InputScriptView.swift
│   │   ├── InputScriptViewModel.swift
│   │   ├── Speak/
│   │   │   ├── SpeakModeView.swift
│   │   │   └── SpeakModeViewModel.swift
│   │   ├── Write/
│   │   │   ├── WriteModeView.swift
│   │   │   └── WriteModeViewModel.swift
│   │   └── AttachFile/
│   │       ├── AttachFileModeView.swift
│   │       └── AttachFileModeViewModel.swift
│   └── Loading/
│       └── LoadingRouteView.swift    wires LoadingContext -> ShuoDesignSystem.LoadingView, drives
│                                     the use cases (extract -> transcribe -> analyze) before pushing .analysis
└── Tests/FeatureSpeechCreationTests/
    ├── CreateScriptCoordinatorTests.swift
    ├── InputScriptViewModelTests.swift
    ├── SpeakModeViewModelTests.swift
    ├── WriteModeViewModelTests.swift
    └── AttachFileModeViewModelTests.swift
```

### 12.10 `Packages/FeatureTranscriptAnalysis` — depends on ShuoCore + ShuoDesignSystem
```
Packages/FeatureTranscriptAnalysis/
├── Sources/FeatureTranscriptAnalysis/
│   ├── TranscriptAnalysisView.swift
│   ├── TranscriptAnalysisViewModel.swift   Original/Refined toggle, debounced edit -> regenerate,
│   │                                       pattern selection, save
│   ├── TranscriptSectionView.swift         accordion + highlighting
│   ├── PatternCarouselView.swift
│   ├── KeyPointsListView.swift
│   └── KeyPointRow.swift
└── Tests/FeatureTranscriptAnalysisTests/
    └── TranscriptAnalysisViewModelTests.swift   debounce/cancel, pattern switch, save wiring
```

---

## 13. Repository layout, tooling & conventions

```
Shuo/                                (repo root — see §12.1–12.10 for what's inside each)
├── Shuo.xcodeproj
├── Shuo/
├── ShuoTests/
├── ShuoUITests/
├── Packages/
│   ├── ShuoCore/
│   ├── ShuoPersistence/
│   ├── ShuoAudio/
│   ├── ShuoAI/
│   ├── ShuoDesignSystem/
│   ├── ShuoTestSupport/
│   ├── FeatureHome/
│   ├── FeatureSpeechCreation/
│   └── FeatureTranscriptAnalysis/
├── Docs/
│   └── ARCHITECTURE.md
├── CLAUDE.md
├── README.md
└── .gitignore
```

- **Adding each package to the project:** File → Add Package Dependencies → Add Local… → point at each `Packages/<Name>` folder, then add it as a dependency of the `Shuo` app target (and of whichever other local packages need it, via that package's own `Package.swift`).
- **Bundle identifier:** placeholder `com.shuo.app` (§10.4) — one place to change, in the `Shuo` app target's Signing & Capabilities.
- **`.gitignore`:** standard Swift/Xcode — `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcuserstate`, `xcuserdata/`.
- **Running tests locally without CI (§10.2):** `swift test` inside any `Packages/<Name>` folder runs that package's tests in isolation; `⌘U` in Xcode with the `Shuo` scheme runs everything, including `ShuoUITests`.
- **SwiftLint/SwiftFormat:** not configured in this pass (kept lean per §10.2) — worth adding once the shape of the code settles; `CLAUDE.md` states the style rules to follow manually until then.

This structure and this document are the design reference. `CLAUDE.md` (repo root) is the companion doc that turns this into day-to-day working rules for anyone — human or Claude — writing code in this repo.
