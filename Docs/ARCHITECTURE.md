# Shuo — iOS Architecture & Feature Analysis

**Status:** Design document — implementation in progress. Built: Purpose selection, Input Script (all three modes), the transcription loading step, and the transcript analysis screen with catalog classification, component-mapped key points and on-demand refinement, over SwiftData persistence. **Not built: the entire `FeatureHome` package** — `HomeViewModel`, `HomeViewState`, `ScriptRowView`, `SearchScriptsUseCase` and `FetchScriptSummariesUseCase` are empty stubs and `HomeView` is a placeholder, so saved scripts currently have no list to appear in and reopening one is unreachable. Also unbuilt: several `ShuoDesignSystem` components (`AccordionView`, `GhostTextField`, `HighlightedText`, `SegmentedModeControl`, `EmptyStateView`), `LegacySpeechRecognitionService`, and all three XCUITest paths. Sections describing those still read as design, not as description.
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

**Navigation (implemented — revised from the original design below):** Home is the only screen presented as a regular, persistent part of the app's `NavigationStack`. The create flow is driven by a single `CreateScriptCoordinator`, but rather than one shared `.fullScreenCover`, it's implemented as **chained native `.sheet` presentations**: Purpose is presented as its own sheet (from `RootView` in the `Shuo` app target, via a "+" button on `HomeView`), and selecting a purpose card presents Input Script as a second sheet on top of it. **Only Input Script disables interactive dismiss** (`.interactiveDismissDisabled(true)`, so a half-filled Speak/Write/Attach session can't be swiped away by accident) — **Purpose stays swipe-dismissible**, since nothing is entered yet at that step and canceling the whole flow from the root screen is a reasonable, low-cost action. Both sheets show `.presentationDragIndicator(.visible)`. The coordinator owns a single `selectedPurpose: SpeechPurpose?` (not an array/`NavigationPath` — there's only ever one thing "on top of" Purpose today) plus an `onFinish: () -> Void` callback, the classic Coordinator-pattern way of signaling the presenter to tear the whole flow down without exposing a raw presented/dismissed flag for the presenter to poll:

```swift
@Observable @MainActor final class CreateScriptCoordinator {
    private(set) var selectedPurpose: SpeechPurpose?
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func selectPurpose(_ purpose: SpeechPurpose) { selectedPurpose = purpose }
    func dismissInputScript() { selectedPurpose = nil }
    func close() { onFinish() }
}
```
`RootView` (in the `Shuo` app target) constructs the coordinator with `onFinish: { coordinator = nil }`, so its own `@State private var coordinator: CreateScriptCoordinator?` is the single source of truth for "is the create flow showing" — there's no separate `isPresented` flag on the coordinator to keep in sync with it.

The **`.analysis` step is now built**; the reopen-a-saved-script path is not. Neither needed a `Route`/`path` stack — see the presentation model below — so the §6 sketch still describes a target end-state rather than what exists. Don't reintroduce that complexity before it's actually needed.

**The loading step deliberately did *not* introduce that stack.** `InputScriptViewModel` owns an optional `loadingVM: LoadingRouteViewModel?`, presented by `InputScriptView` as a **`.sheet`** — keeping the forward path one stacked sheet chain (Purpose → Input Script → Loading) rather than breaking out into a full-screen cover.

**Current implementation: one sheet, one step at a time (decision #20).** `CreateScriptCoordinator` owns a `Step` enum — `.purpose` / `.input` / `.loading` / `.analysis(ScriptDraft)` — and the flow is a content swap on that value inside a single sheet. `CreateFlowView` (in `FeatureSpeechCreation`) renders the first three; `CreateFlowSheet` (app target) swaps that whole view for `TranscriptAnalysisView` once there is a draft, since only the app target may know both features (CLAUDE.md §4). The coordinator also owns the live `InputScriptViewModel`, built through an injected factory, so the loading step can read its source and a retryable failure comes straight back to a screen with the user's content still on it.

The consequences of the earlier design still hold: the user is never returned to Input Script after a *successful* transcription, and leaving analysis ends the create flow rather than revealing a purpose picker three steps stale. What changed is that no presentation is ever stacked, so nothing has to be unwound.

> **Superseded — the flicker was real, and the fix was the route stack.** The stacked design fired three presentation changes in one synchronous update: `LoadingRouteView`'s `.onAppear` dismissed the loading sheet, then `beginAnalysis` cleared `selectedPurpose` (dismissing Input Script) and set `analysisDraft` (swapping the root sheet's content) while `PurposeSelectionView` was itself being removed. Observed on device as a visible blink. Replaced by the single-sheet step model in decision #20 — see that row for the current design. Sequencing the dismissals across a runloop tick was considered and rejected: it would have hidden a symptom produced by modelling one linear flow as three independent presentations.
>
> `LoadingRouteView` also guards hand-off with a `didHandOff` flag, because `.onAppear` fires again whenever the view re-enters the hierarchy — returning from the background would otherwise build a second draft and restart an analysis already running.

**Rejection is the one exception — it goes backwards.** `returnToInput(rejecting:)` clears `analysisDraft`, restores `selectedPurpose` from the draft, and stashes the transcript, which `PurposeSelectionView` picks up via `consumeRejectedTranscript()` to rebuild Input Script seeded in Write mode. Everywhere else, replacing the earlier steps is right because the user is done with them; a "this isn't a speech" verdict is precisely the case where the earlier step *is* the fix, and discarding the transcript would make the user re-record a speech the app is already holding. Input Script is rebuilt rather than restored — the original session's recorder and file handles are long gone — which is why the seed is text in Write mode rather than a resumed Speak session.

Because a sheet is swipe-dismissable, dismissal is a real exit path and not just a hide: presentation is driven through a binding whose setter calls `dismissLoading()`, so leaving by *any* means — swipe, ✕, or the flow being torn down — cancels the in-flight transcription (CLAUDE.md §6).

This keeps title/purpose state alive across every step without re-fetching or duplicating it, and the "X" button dismisses the *entire* chain from any step — since `close()` calling `onFinish()` tears down `RootView`'s single `coordinator` reference, which dismisses any sheet stacked on top of Purpose too — with one planned exception: inside Attach File, "X" is meant to only cancel the file picker sub-modal, not the whole creation flow (per the acceptance criteria, these are two different dismiss actions) — not yet implemented, since Attach File mode itself isn't built. Reopening a previously saved script from Home is intended to present the same sheet chain pre-hydrated at the analysis step, bypassing purpose/input/loading entirely — also not yet implemented.

**Loading UI (implemented for extract → transcribe; `.analyzing` still pending):** the transition after "Save"/"proceed" in Input Script — which may involve audio extraction (video attachments), speech-to-text, and the first AI analysis pass — is meant to be a dedicated, reusable `LoadingView` pushed as its own route (`.loading`), living in `ShuoDesignSystem` so any step can reuse it with a different status message ("Extracting audio…", "Transcribing…", "Analyzing your speech…"). It should stay inside the same sheet chain — the user should never see a screen transition outside the flow. This is distinct from the *inline* "Updating suggestions…" indicator used for incremental edits in the Transcript view (§3.2.2) — that one is a small in-place indicator, not a navigation to a new route, since navigating away for a small edit would be jarring.

**Error presentation.** Failures during the loading step surface as `ShuoDesignSystem.ErrorSheet` — a reusable component taking primitives only, so the design system stays free of domain types (CLAUDE.md §4). The `ShuoError → copy` mapping lives in `FeatureSpeechCreation/Loading/TranscriptionErrorCopy.swift` and switches exhaustively over every case, so adding a `ShuoError` fails the build there rather than silently shipping generic wording. It carries **copy only, no action** — see decision #23. An earlier version attached a `primaryAction` per case, which forced the copy to guess what produced the failure and offered "choose another file" to users who had recorded.

**Actions live in the toolbar, not in the content.** `LoadingRouteView` wraps every state in a `NavigationStack` with fixed chrome — but only **one** control: **‹ leading**, meaning "back to Input Script" in every state (decision #23). While transcribing it cancels the work; on a failure it simply returns. There is no ✓ and no ✕. **Success needs no confirmation**: `.finished` hands the transcript to analysis on appearance, guarded by a `didHandOff` flag so a re-appearing view cannot hand off twice. Consequently `ErrorSheet` and `LoadingView` are **content-only** — a button pinned inside either would compete with the toolbar for the same action.

Two failure surfaces coexist by design: import failures (which happen before any long-running work, while the user is still on the input screen) render *inline* in `AttachFileModeView`, and the pre-existing full-screen file-too-large overlay in `InputScriptView` is retained as-is. Only failures during the loading step get an `ErrorSheet`.

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
**Implemented.** Revised from the original design in three places — the event stream shape, live transcription, and interruption handling — all noted below.

- **APIs:** `AVAudioEngine` (tap on the input node), `AVAudioSession` category `.record` mode `.spokenAudio`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.
- **One tap, three consumers.** Audio is captured once and fans out to an `AVAudioFile` on disk, the waveform/duration event stream, and a `LiveTranscriptionSession`. The tap runs on a realtime audio thread and cannot touch actor state, so it extracts plain `[Float]` (Sendable) and hands them over through an `AsyncStream`, which preserves ordering — spawning a `Task` per buffer would not.
- **Concurrency:** capture lives in an `actor AudioRecordingService: AudioCapturing`, isolating the non-`Sendable` `AVAudioEngine` state behind `async` `prepare()`/`start()`/`pause()`/`resume()`/`finish() -> AudioRecording`/`discard()`.
- **One event stream, not an amplitude stream** *(revised)*. The original design specified `AsyncStream<[Float]>` for amplitudes with duration published separately. It is instead a single `AsyncStream<AudioCaptureEvent>` carrying `.tick(amplitudes:duration:)`, `.interrupted`, and `.failed`. One stream means every state transition flows through one consumer loop in the view model, so an interruption cannot race a waveform update, and amplitude and duration cannot drift apart. Ticks arrive at ~12Hz (one 4096-frame tap buffer at 48kHz ≈ 85ms), which lands inside the intended 10–20Hz without a separate throttle.
- **Duration comes from frames written** (`framesWritten / sampleRate`), not the recorder's `currentTime` *(revised)*. It cannot drift from the audio actually on disk and needs no special handling across pause/resume.
- **Interruptions auto-pause** *(added)*. `AVAudioSession.interruptionNotification` (`.began`) and `routeChangeNotification` (`.oldDeviceUnavailable`) both emit `.interrupted`, which moves the UI to `.paused`. Without this the UI would sit in `.recording` capturing silence through an incoming call.
- **Live transcription is an optimization, never a dependency** *(added)*. See §3.2.1.
- **Waveform:** a rolling window of the most recent 25 amplitudes, pre-filled with silence so it spans its full width from the first frame — a started-but-silent session reads as a dashed line rather than growing in from the left. The full downsampled history is kept in `AudioRecording.waveformSamples`.
- **Permissions are deliberately asymmetric.** Microphone is a hard gate (denied → explicit UI plus an Open Settings affordance). Speech recognition is soft: refusing it costs only the live-transcript optimization, so it never surfaces. Neither is requested when the screen merely appears — asking before the user has expressed intent to record is startling and likely to be refused — so `prepare()` warms assets only when already authorized, and the request happens behind the record tap, before `engine.start()` so no audio is captured while a modal is up.
- **Testing:** `AudioCapturing` lets ViewModel tests inject `FakeAudioCapturing` and assert the idle→recording→paused→recording→finished machine without hardware. Critically, all the logic worth testing lives in a **synchronous** `SpeakModeViewModel.handle(_:)`, with the stream task doing nothing but call it — tests drive `handle` directly and stay deterministic instead of racing an `AsyncStream`. `WaveformSampler` is pure and fully covered. `AudioRecordingService` and `LiveTranscriptionSession` get manual/device checks only, per §8.

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

**Speak mode transcribes while recording, so `.recordedAudio` can short-circuit too.** `AudioRecording` carries an optional `liveTranscript`, populated by the `SpeechAnalyzer` pass that runs alongside capture (§3.1.3). `GenerateTranscriptUseCase` therefore gets a third route: `.recordedAudio` *with* a `liveTranscript` skips `SpeechTranscribing` entirely, exactly as `.typedText` does, and the create flow has no transcription wait at all.

The reason this is worth the extra field is that it keeps live transcription a **pure optimization rather than a dependency**. `SpeechSource` stays at three cases; the audio file is always written even when the live pass succeeds; and if the model assets are still downloading, the locale is unsupported, speech authorization is refused, or the analyzer throws mid-session, `liveTranscript` is simply nil and the existing `SpeechTranscribing` path transcribes the file. Recording never fails because transcription did, which is why none of it needs to surface in the UI.

`SpeechTranscribing` wraps `SpeechAnalyzer` + `SpeechTranscriber` with the **long-form preset**, since a speech draft is exactly the "lectures, meetings, multi-speaker conversation" case Apple built the new model for — a meaningful accuracy improvement over the old `SFSpeechRecognizer` for this specific use case.

> **Decision (v1, superseding the `SFSpeechRecognizer` fallback above):** the fallback is *defined but not built*. `SpeechTranscribingRouter` uses `SpeechAnalyzer` only, and raises `ShuoError.speechModelUnavailable` when it is unavailable rather than silently downgrading. Apple Intelligence–eligible hardware is already a hard requirement (§2.1), so `SpeechAnalyzer` is effectively always present and a second implementation would be untestable dead code. `LegacySpeechRecognitionService` remains a stub marking the deferred path.

**`SpeechTranscribing` takes `TranscriptionInput`, not `SpeechSource`.** `.typedText` can never legitimately reach a transcriber, so admitting it would force every conformer to handle an impossible case; `GenerateTranscriptUseCase` owns that filtering. The two remaining cases stay distinct because their file access genuinely differs — an `ImportedMedia` lives outside the sandbox and must be reached through `resolveURL()`, while an `AudioRecording` is a file the app wrote itself.

**Import limits are duration-first.** `MediaLimits` (domain, so it is testable without AVFoundation and quotable by the UI) caps audio at **30 minutes** with a **500 MB** byte guard. Duration carries the real policy: bytes vary by orders of magnitude across codecs at identical lengths, and it is transcription time and model context — not file size — that actually bound the experience. The two limits raise distinct errors (`mediaTooLong` vs `fileTooLarge`) so the user is told which one they hit.

**Attachments are audio and video only.** `ImportedMedia.Kind` is `.audio`/`.video`; the `.pdf` case was removed rather than left unused, since nothing downstream extracted PDF text and an unreachable case invites half-built handling. Video routes through `VideoAudioExtractor` (`AVAssetExportSession` → temporary m4a, deleted after transcription) before reaching the analyzer.

#### 3.2.2 Transcript view
- Segmented control (Original/Refined) and accordion expand/collapse are cheap: a mode enum in the ViewModel and local `@State` per section respectively — expand/collapse doesn't need to survive app relaunch, so it's fine to keep as ephemeral view state rather than persisted.
- **Highlighting:** have the AI return highlight *snippets* (short excerpts), not character offsets — offsets break the moment the user edits the transcript. Compute highlight ranges client-side via substring/fuzzy matching between each key point's snippet and the current transcript text, then render with `AttributedString` (`Text(attributedString)` handles this natively in modern SwiftUI, no third-party rich text library needed).
- **Editable transcript → auto-updated key points:** debounce edits (roughly 800ms–1.5s after typing stops), then re-invoke `GenerateKeyPointsUseCase`. Store the in-flight `Task` on the ViewModel and cancel-and-replace it on every new debounce firing, so rapid edits don't queue up redundant AI calls or race each other. Show a lightweight "Updating suggestions…" indicator while this runs.

#### 3.2.3 Pattern suggestions

> **Revised during implementation.** The original design below had the model *inventing*
> patterns freely. It now **classifies against a fixed catalog** — see
> `Docs/SPEECH_PATTERNS.md` for the catalog itself and the reasoning. The rest of this
> subsection reflects what is built.

- **Patterns are a closed set of 23 catalog entries** (8 inform / 7 persuade / 8 inspire),
  encoded as `SpeechPatternCatalog` in `ShuoCore`. The model never authors a pattern name
  or summary; it only ranks the catalog subset for the user's chosen purpose. A closed set
  is far more reliable on a small on-device model, and — decisively — a *fixed component
  list per pattern* is what makes component-mapped key points possible at all.
- **Each pattern owns ordered, named components** (`SpeechPatternComponent`): Topical has
  Topic Overview / Category 1–3 / Closing Summary; PREP has Point / Reason / Example /
  Reinforced Point. These components *are* the key-point slots.
- **Key points are one-per-component, always.** Where the transcript covers nothing for a
  component, its key point text is the literal `"-"`. `KeyPointNormalizer` (domain layer,
  pure, heavily tested) enforces this against whatever the model actually returned —
  dropping invented components, collapsing duplicates, reordering, and filling gaps. The
  UI can therefore render positionally and trust the shape.
- **Validity is judged in the same call as ranking.** A cheap non-AI
  `TranscriptUsabilityPrecheck` rejects empty/garbage input for free first; anything past it
  goes into one model call returning both a usability verdict and the ranked ids.
  `ClassifyTranscriptUseCase` validates every returned id against the *candidate* set, so a
  hallucinated id — or a real id from another purpose — never reaches the UI.
- **Scheduling: eager first, background prefetch after.** Key points for the top-ranked
  pattern are awaited and shown; the other two generate sequentially in the background so
  switching is a cache hit. Sequential, not concurrent — the analyzer is an actor and the
  neural engine serializes generations anyway.
- **The refined transcript is user-triggered**, via a "Regenerate Transcript" button, not
  produced on every pattern switch. It is the most expensive call in the flow, and it is
  cached per pattern.
- `ScrollView(.horizontal) { LazyHStack { ... } }` over `[SpeechPattern]`.
- "Suggestion under every empty key point textfield" is a near-perfect fit for SwiftUI's
  native placeholder parameter — the ghost text comes from the component's own `contains`
  hints, not from the model.

#### 3.2.4 AI Foundation Model integration (deep dive)

This is the feature with the most architectural weight, so it gets its own protocol seam, independent of everything else:

```swift
protocol SpeechAnalyzing: Sendable {
    func classify(transcript: String, purpose: SpeechPurpose,
                  candidates: [SpeechPattern]) async throws -> PatternClassification
    func generateKeyPoints(transcript: String, pattern: SpeechPattern) async throws -> [KeyPoint]
    func refineTranscript(_ transcript: String, pattern: SpeechPattern,
                          keyPoints: [KeyPoint]) async throws -> String
    func analyzeGrammar(_ transcript: String) async throws -> [GrammarSuggestion]
}
```
Domain use cases depend only on this protocol — never on `import FoundationModels` directly.

**Schemas are dynamic, not `@Generable` structs.** The original sketch here used
`@Generable`/`@Guide(.count(3))` DTOs. That does not work for a catalog-backed design:
`@Guide(.anyOf(...))` needs its values at compile time, but the legal pattern ids depend on
the user's chosen purpose, and the legal component names depend on which pattern is being
applied. So `ClassificationSchema` and `KeyPointsSchema` build a `DynamicGenerationSchema`
per request, baking the *exact* candidate ids / component names into the grammar:

```swift
DynamicGenerationSchema.Property(
    name: "rankedPatternIDs",
    schema: DynamicGenerationSchema(
        arrayOf: DynamicGenerationSchema(name: "PatternIdentifier",
                                         anyOf: candidates.map(\.id)),
        maximumElements: 3
    )
)
```
This makes it structurally impossible for the model to return an id from another purpose or
a component the pattern doesn't have. `GeneratedContentMapper` decodes the resulting
`GeneratedContent` into domain entities, sharing property-name constants with the schema
builders so the two halves cannot drift. Refinement uses no schema at all — it produces free
prose, and constraining that would only get in the way.

Constrained decoding is treated as a strong guarantee, not an absolute one: the domain layer
still validates ids and normalizes key points, so the app never depends on a framework
detail holding perfectly.

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

struct AudioRecording: Sendable, Identifiable, Equatable {
    let id: UUID
    let fileURL: URL              // always written — the fallback transcription source
    let duration: TimeInterval    // derived from frames written, not a wall clock
    let waveformSamples: [Float]  // normalized 0...1, whole session
    let createdAt: Date
    // Captured during recording (§3.1.3). Nil when the live pass was unavailable or
    // failed; callers then transcribe `fileURL`. An optimization, not a guarantee.
    let liveTranscript: String?
}

// Everything an active capture session reports, on one stream so waveform updates and
// system interruptions cannot race each other (§3.1.3).
enum AudioCaptureEvent: Sendable, Equatable {
    case tick(amplitudes: [Float], duration: TimeInterval)
    case interrupted          // incoming call, or headphones unplugged
    case failed(ShuoError)
}

enum MicrophonePermissionStatus: Sendable, Equatable { case notDetermined, granted, denied }

// Superseded by decision #10: the id is a stable catalog slug ("inform.topical"), not a
// UUID, and `outline: [String]` became ordered `SpeechPatternComponent`s — the fixed
// per-pattern component list is what makes component-mapped key points possible at all.
// `SpeechPatternCatalog` owns all 23; Docs/SPEECH_PATTERNS.md is their source of truth.
struct SpeechPattern: Sendable, Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let summary: String
    let purpose: SpeechPurpose
    let components: [SpeechPatternComponent]
}

// One per component, always, in component order — `"-"` where the transcript covered
// nothing. `KeyPointNormalizer` enforces that shape against whatever the model returned.
struct KeyPoint: Sendable, Identifiable, Equatable, Codable {
    let componentID: String
    let componentName: String
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
    var suggestedPatternIDs: [SpeechPattern.ID]   // catalog slugs, not copies (#10)
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
- `KeyPointNormalizer` returns exactly one key point per component, with `"-"` for anything the transcript did not cover
- `ClassifyTranscriptUseCase` discards a returned pattern id belonging to a different purpose
- `TranscriptAnalysisViewModel.cancelAll()` stops the background prefetch so no AI call fires after the sheet is dismissed
- `SwiftDataScriptRepository.save` then `.fetch(id:)` round-trips a `Script` with all fields intact, including patterns and grammar suggestions
- `HomeViewModel` search filters by title case-insensitively and updates synchronously as the query changes
- `AIAvailabilityGate` surfaces a non-blocking fallback state when `SystemLanguageModel.default.availability` is `.unavailable`

---

## 9. Decisions log

| # | Question | Decision |
|---|---|---|
| 1 | Purpose → Input Script: one container or chained sheets? | **Originally speced as one fullscreen sheet** for the entire create-through-analysis flow. **Revised during implementation to chained `.sheet` presentations** instead (Purpose sheet → Input Script sheet stacked on top; only Input Script is `interactiveDismissDisabled`, Purpose stays swipe-dismissible) — Home remains the only regular screen. See §3.1.1 for the current implementation and what's still unbuilt. |
| 2 | Grammar/vocab UI surface? | **Deferred past v1.** Interface stays defined, nothing wired up or displayed. See §2.5, §3.2.4. |
| 3 | Loading/progress UX for longer processing (video extraction, transcription, first AI pass)? | **Dedicated, reusable `LoadingView`**, pushed as its own route inside the same sheet chain. **Not yet implemented** — no `.loading` route exists yet. See §3.1.1. |
| 4 | Chunking strategy for long transcripts vs. the Foundation Models context window? | **In scope for v1**, not deferred. See §3.2.4. |
| 5 | Require Apple Intelligence–eligible hardware, or degrade gracefully? | **Required for v1.** No degraded "no-AI" mode. See §2.1. |
| 6 | Multi-language beyond English for v1? | **English only** for v1. See §2.3. |
| 7 | Does Speak mode transcribe live, or only record and let the next step transcribe? | **Transcribes live, hidden.** One `AVAudioEngine` tap feeds the file, the waveform, and a `SpeechAnalyzer` pass at the same time, so the transcript is ready the moment the user confirms and the create flow has no transcription wait. Carried forward on `AudioRecording.liveTranscript`, which keeps `SpeechSource` at three cases and makes the live pass a pure optimization over the always-written audio file. No transcript is shown while recording — the UI is waveform and timer only. See §3.1.3, §3.2.1. |
| 8 | Amplitude stream plus separate duration, or one event stream? | **One `AsyncStream<AudioCaptureEvent>`**, superseding §3.1.3's original `AsyncStream<[Float]>`. Added when interruption handling came into scope: with two channels, an interruption could race a waveform tick. See §3.1.3. |
| 9 | Handle microphone denial and audio interruptions now, or defer to a hardening pass? | **Now.** Retrofitting interruption handling into a finished state machine is more churn than building it once, and it is the difference between a demo and a shippable recorder. See §3.1.3. |
| 10 | Does the model invent structure patterns, or classify against a fixed set? | **Classifies against a fixed catalog of 23 entries** (`SpeechPatternCatalog`, documented in `Docs/SPEECH_PATTERNS.md`), reversing the original §3.2.4 design. Two reasons: closed-set classification is far more reliable than free generation on a ~3B on-device model, and a fixed *component list per pattern* is what makes component-mapped key points possible at all. Patterns are persisted as stable slug ids, not copies, so improving a pattern's wording updates every saved script. See §3.2.3. |
| 11 | Where does the "transcript isn't a speech" check live? | **A free non-AI precheck, then merged into the classification call.** `TranscriptUsabilityPrecheck` rejects empty/gibberish/silent input for zero cost; everything past it gets one model call returning both a usability verdict and the ranked patterns. A separate validity call would add a full round trip to every happy path, and the two judgements come from the same reading of the text anyway. Rejection reasons are a closed enum, not model free-text, so the UI can map each to specific actionable copy. See §3.2.3. |
| 12 | Generate all three patterns' key points up front, in parallel, or lazily? | **Eager first, sequential background prefetch after.** The user waits only for the top-ranked pattern; the other two generate in the background so switching is instant. Not parallel: the analyzer is an actor and the neural engine serializes generations regardless, so three concurrent sessions would add memory pressure without finishing sooner. Prefetch failures are swallowed — it is speculative work, and selecting that pattern retries and reports in context. See §3.2.3. |
| 13 | `@Generable` structs or dynamic schemas for AI output? | **`DynamicGenerationSchema`, built per request.** `@Guide(.anyOf(...))` needs compile-time values, but the legal pattern ids depend on the chosen purpose and the legal component names on the chosen pattern. Building the schema at runtime bakes the exact candidates into the grammar, making an out-of-purpose or invented identifier structurally impossible. The domain layer still validates, on the principle that constrained decoding is a strong guarantee rather than an absolute one. See §3.2.4. |
| 14 | Does the user confirm the finished transcript before analysis runs? | **No.** The transcription step hands off automatically on success, and analysis *replaces* the Purpose → Input Script → Loading sheet chain rather than stacking on it. A confirmation screen showing the raw transcript added a tap without adding a decision — the user had already chosen to transcribe, and the analysis screen shows the transcript anyway. Failure states still stop and ask, because those do carry a decision (retry, pick another file, leave). See §3.1.1. |
| 15 | Does the analysis screen get its own loading and failure UI, or reuse the transcription step's? | **Reuses `LoadingView` and `ErrorSheet`.** The two screens are consecutive states of one continuous wait — transcribe, then analyze — and the user crosses from one sheet into the other with no interaction in between, so a different spinner or a bare `VStack` of error text reads as having landed somewhere unrelated. The `ShuoError → copy` mapping is duplicated as `AnalysisErrorCopy` rather than shared, because Feature packages must not depend on each other (CLAUDE.md §4) and the same error warrants different advice here — this screen has no file picker to send the user back to. Both mappings switch exhaustively, so a new `ShuoError` case fails the build in each place rather than silently shipping generic wording. See §3.2. |
| 16 | When is a script persisted — only on an explicit save, or earlier? | **Automatically as soon as classification succeeds, then again on ✓.** Reaching `.loaded` means the transcript passed both the precheck and the model's usability verdict, which is the point at which it is worth keeping. From there the user can leave by ✕, by swipe, or by the app being killed, and none of those can be intercepted reliably — so waiting for an explicit save made every one of them silent data loss. The final ✓ *updates* that record rather than inserting a second, because `save` writes the returned id back onto `ScriptDraft.existingScriptID`, which is exactly what that field is for (§6). Consequence to watch: this creates saved scripts the user never explicitly asked to keep, and v1 has no deletion path (CLAUDE.md §11) — revisit together with `FeatureHome`. See §3.2. |
| 17 | What happens when the user leaves the loaded analysis screen without saving? | **A confirmation dialog, phrased around what is actually at risk.** Because of #16 the speech itself is already persisted, so the honest wording is "leave without saving your *changes*" — Save and Close / Leave / Cancel — not "discard", which would imply the whole speech is lost and would also promise a deletion the app cannot perform. `.interactiveDismissDisabled` is bound to `hasUnsavedChanges` rather than set unconditionally, so the swipe guard appears only when it has something to protect instead of as blanket friction. See §3.2. |
| 18 | Where does a rejected transcript go? | **Back to Input Script, seeded in Write mode.** Re-running the same transcript reaches the same verdict, so ✓ on a rejection is not a retry — it is "edit your draft". Without it the only exit was ✕, which meant re-recording a speech the app already had. This is the single place the flow moves backwards, and it is justified because it is the single place where the earlier step is the actual fix. See §3.1.1. |
| 19 | Does `cancelAll()` cancel an in-flight save? | **No — generations only.** Prefetch and refinement are speculative and safe to abandon when the screen goes away. A save is the one operation whose entire purpose is to outlive the screen, so cancelling it from `.onDisappear` would have re-created the loss that #16 exists to prevent. It is short, bounded, and holds only a detached draft value. See §3.2, CLAUDE.md §6. |
| 20 | Stacked sheets or one sheet with a step enum? | **One sheet, content switched on `CreateScriptCoordinator.Step`** — reversing #1 and the §3.1.1 warning against reintroducing a route stack. The chained version was not merely inelegant, it was **visibly broken**: handing off to analysis dismissed two stacked sheets and replaced the presenter's content in a single update, which rendered as a flicker (confirmed on device, and predicted by the verification note in §3.1.1). The route stack has now earned its keep — the flow branches, since a rejected transcript goes back to input, and the stacked alternative could not be made to transition cleanly. `CreateFlowView` owns purpose/input/loading inside `FeatureSpeechCreation`; the app target swaps that whole view for `TranscriptAnalysisView`, so the cross-feature join stays in the one place allowed to know both (CLAUDE.md §4). `dismissAnalysis()` was deleted along with this: no step in the flow wants "leave analysis but stay in the flow". |
| 21 | The user can fill in all three input modes — which one counts? | **The one they are on when they confirm; the other two are released then and there.** Confirming is the commitment point: `InputScriptViewModel.prepareToProceed()` captures the active mode's source and then calls `discardUnconfirmedModes()`. This matters beyond tidiness — Speak writes a real audio file, and `cancel()` discards it; leaving it would leak storage v1 gives the user no way to reclaim. Attach File needs no file cleanup, because import is **bookmark-based and never copies into the sandbox**. **Release happens at `beginAnalysis`, not at confirm** — corrected after an initial implementation put it at confirm time. Confirming *looks* like commitment but isn't: transcription can still fail, and #23 sends the user straight back to this screen expecting their work intact. Discarding at confirm would have deleted a recording the app was about to hand back. `beginAnalysis` is the first moment nothing can reach the other modes, since the one route back from there (a rejected transcript) rebuilds the step from text rather than resuming it. `recordingDuration` is likewise read from the confirmed mode only — it previously read Speak unconditionally, stamping typed text with an abandoned recording's duration and dropping imported media's duration entirely. |
| 22 | Is AI availability checked before generation? | **Yes, and it wasn't before.** `AIAvailabilityGate` was constructed in `AppContainer` and injected into nothing, so CLAUDE.md §8's "check before any generation call" was violated everywhere and the two runtime states §3.2.4 designs were unreachable — a user whose model was still downloading got a generic retryable failure that retrying could not fix. `TranscriptAnalysisViewModel` now takes an `AIAvailabilityChecking` and gates `runInitialAnalysis()`. `.modelNotReady` → `.waitingForModel`, polled on an interval until it clears, then analysis continues on its own; the wait is a suspended `Task.sleep` inside `analysisTask`, so existing `cancelAll()` teardown covers it with no new path. `.appleIntelligenceNotEnabled` and `.deviceNotEligible` → `.unavailable(status)`, carrying the status because `ShuoError.aiUnavailable` has no payload and the two need different copy — one points at Settings, the other states a hard block without implying a fix. |
| 23 | What actions does the transcription/error screen offer? | **One button: ‹ back to Input Script, in every state, same position.** Replaces the ✕/✓ pair, and the removal of ✓ fixes a real bug rather than simplifying for its own sake. `TranscriptionErrorCopy` carried a per-error `primaryAction`, and it had to guess what produced the failure: `noSpeechDetected` mapped to `.pickAnotherFile`, so a user who **recorded** something silent was shown a file browser. Errors here describe what went wrong; every one of them is resolved on the input screen, which is one ‹ away, so going back and confirming again *is* the retry. `Action`, `primaryAction` and `primaryActionTitle` are gone from that type, along with `retryWithAnotherFile`. During `.loading` the same ‹ cancels the in-flight transcription, so a long file is never unabortable. Copy is now the only channel, so a test asserts no reachable error's wording assumes the source was a file. |
| 24 | Is there a minimum media duration? | **Yes — 3 seconds, enforced in the domain.** A 1-second take was transcribed, came back empty, and surfaced as "we couldn't hear any speech": a wasted round trip reported as a fault rather than as guidance. `MediaLimits.minDurationSeconds` and `ShuoError.mediaTooShort` sit alongside the existing maximum, and `GenerateTranscriptUseCase` checks **before** the live-transcript short-circuit — placing it after would let a short recording through whenever the live pass happened to succeed (§3.2.1). Both boundaries are inclusive, so exactly 3.0s passes. An unknown duration is never rejected, matching the existing stance that a failed probe is not a user error. `FileImportService` checks it too, so all three import limits report at pick time while the picker is still what the user is looking at; the use-case check remains the real guarantee, since a recording never passes through the importer. |
| 25 | Where does the script title live on the analysis screen? | **An editable field at the top of the content, with the purpose beneath it** — not a renameable navigation title, which was the first attempt. The nav bar keeps a static "Speech Analysis" label: ✕ and ✓ sit there with nothing else, and an empty bar between them reads as an unnamed modal, while a second bound copy of the title could disagree with the field mid-edit. An empty title is allowed *during* editing — a user clearing the field to retype passes through empty on every keystroke, and snapping a placeholder back under their cursor fights them — then normalized to "Untitled Script" on commit, and again inside `save()`, because ✓ can be tapped straight from the keyboard and the view cannot be trusted to have committed first. |

## 10. Tooling decisions (scaffolding phase)

| # | Question | Decision |
|---|---|---|
| 1 | Xcode project generation | **Plain, Xcode-native `.xcodeproj`** with local Swift packages added as local package references — no XcodeGen or Tuist. See §12–13 for the resulting layout. |
| 2 | CI | **Skipped for now.** No GitHub Actions workflow scaffolded in this pass. `swift test` per package and the app's test plan remain the way to run tests locally; add CI later without any structural change. |
| 3 | Design tokens / brand assets | **Placeholders for now.** `ShuoDesignSystem`'s token files ship with a sensible, clearly-marked placeholder palette/type scale — swap in real brand values whenever they're ready, nothing else in the app touches raw colors/fonts directly (see §12). |
| 4 | Bundle identifier | **`com.seven.shuo`**, in the app target's build settings. Earlier revisions of this doc recorded a `com.shuo.app` placeholder, but the project does not use that value — corrected here rather than left to mislead. Still worth confirming before archiving/shipping. |

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
│   │   ├── AudioRecording.swift       struct: id, fileURL, duration, waveformSamples,
│   │   │                              createdAt, liveTranscript (§3.2.1)
│   │   ├── AudioCaptureEvent.swift    enum: tick/interrupted/failed — one stream (§3.1.3)
│   │   ├── MicrophonePermissionStatus.swift  enum: notDetermined/granted/denied
│   │   ├── ImportedMedia.swift        struct: id, fileURL, kind (audio/video), originalFileName
│   │   ├── Transcript.swift           struct: original, refined
│   │   ├── SpeechPattern.swift        struct: id (stable slug), name, summary, purpose, components
│   │   ├── SpeechPatternComponent.swift  struct: id, name, contains, aiGuideline, order — one key-point slot
│   │   ├── SpeechPatternCatalog.swift    the fixed 23-entry catalog (see Docs/SPEECH_PATTERNS.md)
│   │   ├── PatternClassification.swift   struct: isUsable, rejectionReason, rankedPatternIDs
│   │   ├── TranscriptRejectionReason.swift  enum: tooShort/mostlySilence/unintelligible/notASpeech
│   │   ├── AIAvailabilityStatus.swift    enum mirroring SystemLanguageModel.Availability
│   │   ├── KeyPoint.swift             struct: componentID, componentName, text, orderIndex, suggestion
│   │   ├── GrammarSuggestion.swift    struct — defined, unused in v1 (§2.5)
│   │   ├── Script.swift               aggregate root — the persisted, finished record
│   │   ├── ScriptSummary.swift        lightweight Home-list projection
│   │   ├── ScriptDraft.swift          mutable in-flight state for the create/reopen flow
│   │   └── LoadingContext.swift       enum driving the shared LoadingView's copy
│   │
│   ├── Protocols/                     the seams — domain owns these, Data/Presentation implement/consume them
│   │   ├── ScriptRepository.swift         save/fetch(id:)/fetchSummaries()/search(query:)
│   │   │                                  (no delete — out of scope for v1, CLAUDE.md §11)
│   │   ├── AudioCapturing.swift           prepare()/start()/pause()/resume()/finish() ->
│   │   │                                  AudioRecording/discard(), plus `events` stream
│   │   ├── MicrophonePermissionProviding.swift  currentStatus()/request()
│   │   ├── SpeechTranscribing.swift       transcribe(_ source: SpeechSource) async throws -> String
│   │   ├── FileImporting.swift            importFile(from: URL) async throws -> ImportedMedia
│   │   ├── SpeechAnalyzing.swift          classify / generateKeyPoints / refineTranscript / analyzeGrammar
│   │   └── AIAvailabilityChecking.swift   availability() async -> AIAvailabilityStatus
│   │
│   ├── UseCases/
│   │   ├── GenerateTranscriptUseCase.swift    routes SpeechSource -> Transcript (§3.2.1)
│   │   ├── ClassifyTranscriptUseCase.swift     precheck + classify -> up to 3 SpeechPattern (validated)
│   │   ├── GenerateKeyPointsUseCase.swift      pattern -> normalized [KeyPoint], one per component
│   │   ├── RegenerateTranscriptUseCase.swift   pattern + keyPoints -> refined transcript (user-triggered)
│   │   ├── SaveScriptUseCase.swift             ScriptDraft -> persisted Script (insert or update)
│   │   ├── FetchScriptSummariesUseCase.swift   Home list source
│   │   ├── FetchScriptUseCase.swift            full Script by id, for reopen -> hydrates a ScriptDraft
│   │   └── SearchScriptsUseCase.swift          title search over summaries
│   │
│   └── Errors/
│       └── ShuoError.swift             domain error enum, grouped by stage: import
│                                        (fileTooLarge, mediaTooLong, unsupportedMediaType,
│                                        importFailed), extraction (audioExtractionFailed),
│                                        transcription (speechPermissionDenied,
│                                        speechModelUnavailable, noSpeechDetected,
│                                        transcriptionFailed), AI, persistence, recording.
│                                        Each case maps to its own user-facing copy in
│                                        FeatureSpeechCreation's TranscriptionErrorCopy.
│
└── Tests/ShuoCoreTests/
    ├── GenerateTranscriptUseCaseTests.swift
    ├── ClassifyTranscriptUseCaseTests.swift
    ├── GenerateKeyPointsUseCaseTests.swift
    ├── RegenerateTranscriptUseCaseTests.swift
    ├── KeyPointNormalizerTests.swift
    ├── TranscriptUsabilityPrecheckTests.swift
    ├── SpeechPatternCatalogTests.swift
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
│   │   ├── AudioRecordingService.swift     actor; conforms to AudioCapturing; wraps AVAudioEngine;
│   │   │                                   one tap -> file + waveform + live transcription
│   │   ├── LiveTranscriptionSession.swift  actor; SpeechAnalyzer/SpeechTranscriber alongside
│   │   │                                   capture. Every failure is silent — see §3.2.1
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
│   ├── Schemas/                         DynamicGenerationSchema builders — never exposed outside this package
│   │   ├── ClassificationSchema.swift    constrains output to the purpose's candidate ids
│   │   ├── KeyPointsSchema.swift         constrains output to the pattern's component names
│   │   └── GeneratedGrammarSuggestion.swift    defined, unused in v1 (§2.5)
│   ├── Mapping/
│   │   └── GeneratedContentMapper.swift  GeneratedContent -> ShuoCore domain entity
│   ├── FoundationModelSpeechAnalyzer.swift     actor conforming to SpeechAnalyzing; owns one
│   │                                           LanguageModelSession per task, plus prewarm()
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
│   │   ├── CircularIconButton.swift    primary action for every Input Script mode —
│   │   │                                  one shape so switching modes never implies
│   │   │                                  a different kind of action
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
    ├── FakeAudioCapturing.swift              actor; scripted events via emit(_:) + call counts
    ├── FakeMicrophonePermissionProviding.swift
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
│   │   │   ├── SpeakModeViewModel.swift
│   │   │   └── SpeakModeViewState.swift   idle/requestingPermission/permissionDenied/
│   │   │                                  recording/paused/finished/failed
│   │   ├── Write/
│   │   │   ├── WriteModeView.swift
│   │   │   └── WriteModeViewModel.swift
│   │   └── AttachFile/
│   │       ├── AttachFileModeView.swift
│   │       └── AttachFileModeViewModel.swift
│   ├── Coordinator/
│   │   └── CreateFlowView.swift      switches purpose -> input -> loading on
│   │                                 CreateScriptCoordinator.Step, in ONE sheet (#20)
│   ├── Loading/
│   │   └── LoadingRouteView.swift    wires LoadingContext -> ShuoDesignSystem.LoadingView, drives
│   │                                 the use cases (extract -> transcribe -> analyze) before pushing .analysis
│   └── Previews/
│       └── PreviewDoubles.swift      #if DEBUG stand-ins so #Preview can build a view model
│                                     without the composition root. Not test doubles — the
│                                     runtime target must not depend on ShuoTestSupport.
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
│   ├── TranscriptAnalysisViewModel.swift   classify -> key points -> prefetch -> refine,
│   │                                       per-pattern caches, save-on-load, cancellation
│   ├── TranscriptAnalysisViewState.swift   .analyzing / .rejected / .loaded / .failed
│   ├── TranscriptSectionView.swift         accordion + highlighting
│   ├── PatternCarouselView.swift
│   ├── PatternCarouselViewModel.swift      child VM: the up-to-3 cards and the selection
│   ├── KeyPointsListView.swift
│   ├── KeyPointRow.swift
│   └── AnalysisErrorCopy.swift             ShuoError/TranscriptRejectionReason -> glyph +
│                                           two strings, with an explicit retry-or-not
└── Tests/FeatureTranscriptAnalysisTests/
    ├── TranscriptAnalysisViewModelTests.swift   debounce/cancel, pattern switch, save wiring
    └── AnalysisErrorCopyTests.swift             every reason distinct, nothing renders blank
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
- **Bundle identifier:** `com.seven.shuo` (§10.4) — one place to change, in the `Shuo` app target's Signing & Capabilities.
- **`.gitignore`:** standard Swift/Xcode — `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcuserstate`, `xcuserdata/`.
- **Running tests locally without CI (§10.2):** `swift test` inside `Packages/ShuoCore` runs the domain tests on the host toolchain — that package and `ShuoTestSupport` declare `.macOS(.v26)` alongside `.iOS(.v26)` purely to keep this fast loop working; iOS remains the only shipping platform. Every other package imports something iOS-only and must be tested against a simulator instead: `cd Packages/<Name> && xcodebuild test -scheme <Name> -destination 'platform=iOS Simulator,name=iPhone 17'`. Note that the `Shuo` scheme's test action covers only `ShuoTests`/`ShuoUITests` — it does **not** run the package test targets, so `⌘U` alone does not validate a change.
- **SwiftLint/SwiftFormat:** not configured in this pass (kept lean per §10.2) — worth adding once the shape of the code settles; `CLAUDE.md` states the style rules to follow manually until then.

This structure and this document are the design reference. `CLAUDE.md` (repo root) is the companion doc that turns this into day-to-day working rules for anyone — human or Claude — writing code in this repo.
