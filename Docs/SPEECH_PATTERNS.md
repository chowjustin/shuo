# Speech Structure Pattern Catalog

**Status:** reference spec — source of truth for the pattern catalog that will be encoded as
`SpeechPatternCatalog` in `ShuoCore`. This document is the human-readable original; the Swift
catalog must stay in sync with it. If they diverge, this file wins and the code is the bug.

**Scope note:** the catalog is a *fixed, closed set*. The AI does **not** invent pattern names or
summaries — it only **classifies** a transcript against these entries and then **maps** transcript
content onto a chosen entry's components. This is a deliberate change from the earlier
`Docs/ARCHITECTURE.md` §3.2.4 sketch, which had the model free-generating `GeneratedPattern`
values. See §4 below.

---

## 1. Structure of an entry

Every pattern has:

| Field | Meaning |
|---|---|
| **ID** | Stable slug, e.g. `inform.topical`. Never change once shipped — it is persisted and it is what the model returns. |
| **Name** | Display name. |
| **Summary** | One sentence on what the pattern organizes / when to use it. |
| **Purpose(s)** | Which `SpeechPurpose` values offer this pattern. |
| **Components** | Ordered, named slots. **These are the key-point slots** — one key point per component, in order. |
| **Contains** | What belongs in that component. Feeds the prompt as AI guidance; is *not* itself a separate output slot. |
| **AI Guideline** | Extra instruction for extracting that component, where the source material specified one. |
| **Source** | Provenance for the pattern. |

**Absent content rule:** if the transcript has no content for a component, its key point text is
the literal string `"-"`. The model is never asked to invent content for an empty slot.

---

## 2. Purpose: To Inform

### 2.1 `inform.topical` — Topical (Categorical)

Organizes information into categories or major aspects of the topic.

| # | Component | Contains | AI Guideline |
|---|---|---|---|
| 1 | Topic Overview | Main subject; brief introduction; scope of discussion | Extract the overall topic and explain what will be discussed. |
| 2 | Category 1 | First major aspect; supporting explanation; facts/examples | Identify the first independent category that explains the topic. |
| 3 | Category 2 | Second major aspect; supporting explanation; facts/examples | — |
| 4 | Category 3 | Third major aspect; supporting explanation | — |
| 5 | Closing Summary | Recap of categories; final takeaway | — |

**Source:** Lucas, *The Art of Public Speaking* (13th ed.) —
https://www.mheducation.com/highered/product/art-public-speaking-lucas/M9781264305085.html

### 2.2 `inform.chronological` — Chronological

Presents information according to time order.

| # | Component | Contains | AI Guideline |
|---|---|---|---|
| 1 | Beginning | Starting event; initial situation | Find the earliest event. |
| 2 | Middle | Sequence of developments; progression | — |
| 3 | End | Final event; result | — |
| 4 | Takeaway | Overall timeline summary | — |

**Source:** Lucas (2023).

### 2.3 `inform.causeEffect` — Cause-Effect

Explains why something happened and what followed from it.

| # | Component | Contains | AI Guideline |
|---|---|---|---|
| 1 | Cause | Root causes; contributing factors | Identify WHY something happened. |
| 2 | Effects | Immediate impacts; long-term impacts | Identify WHAT happened because of the causes. |
| 3 | Conclusion | Overall implication | — |

**Source:** Oklahoma State University — https://open.library.okstate.edu/speech2713/

> See also `persuade.causeEffect` (§3.5) — same components, persuasive framing in the conclusion.

### 2.4 `inform.sequential` — Sequential (Process)

Walks through a process step by step toward an outcome.

| # | Component | Contains |
|---|---|---|
| 1 | Goal | Desired outcome |
| 2 | Step 1 | First action |
| 3 | Step 2 | Second action |
| 4 | Step 3 | Remaining actions |
| 5 | Expected Result | Final outcome |

**Source:** Lucas.

### 2.5 `inform.spatial` — Spatial

Organizes information by physical location or arrangement.

| # | Component | Contains |
|---|---|---|
| 1 | Overall Subject | Object/place overview |
| 2 | Area 1 | Description; importance |
| 3 | Area 2 | Description; importance |
| 4 | Area 3 | Description; importance |
| 5 | Overall Understanding | Relationship between locations |

**Source:** Lucas.

### 2.6 `inform.definition` — Definition

Explains what something *is* and why it matters.

| # | Component | Contains |
|---|---|---|
| 1 | Definition | Formal definition |
| 2 | Characteristics | Key attributes |
| 3 | Examples | Illustrations |
| 4 | Importance | Why the audience should understand it |

**Source:** *not specified in source material.*

### 2.7 `inform.classification` — Classification

Sorts a subject into categories by criteria.

| # | Component | Contains |
|---|---|---|
| 1 | Main Topic | Object being classified |
| 2 | Category A | Criteria; explanation |
| 3 | Category B | Criteria; explanation |
| 4 | Comparison Summary | Differences among categories |

**Source:** *not specified in source material.*

### 2.8 `inform.comparisonContrast` — Comparison / Contrast

Sets two subjects side by side.

| # | Component | Contains |
|---|---|---|
| 1 | Subject A | Key features |
| 2 | Subject B | Key features |
| 3 | Similarities | Shared characteristics |
| 4 | Differences | Contrasting characteristics |
| 5 | Conclusion | Main insight |

**Source:** *not specified in source material.*

---

## 3. Purpose: To Persuade

### 3.1 `persuade.prep` — PREP

Claim, justification, evidence, restated claim.

| # | Component | Contains | AI Guideline |
|---|---|---|---|
| 1 | Point | One clear claim or recommendation; the speaker's stance; the central persuasive message | Extract the main opinion or recommendation as one concise sentence. |
| 2 | Reason | Logical justification; benefits/rationale; why the audience should believe the claim | Identify the strongest supporting reason directly connected to the point. |
| 3 | Example | Personal experience; real-world example; statistics; research findings; case study | Extract the most convincing evidence that supports the reason. |
| 4 | Reinforced Point | Restated claim; strong call-to-action or memorable closing | Rewrite the original point as a stronger concluding statement that reinforces the desired action. |

**Sources:** PREP Method (Japanese business communication); Dale Carnegie Training;
Barbara Minto, *The Pyramid Principle*.

### 3.2 `persuade.monroe` — Monroe's Motivated Sequence

| # | Component | Contains |
|---|---|---|
| 1 | Attention | Hook; problem introduction; surprising fact; question |
| 2 | Need | Problem explanation; why the audience should care |
| 3 | Satisfaction | Proposed solution |
| 4 | Visualization | The future if the solution is adopted (or ignored) |
| 5 | Action | Clear call to action |

**Source:** Alan Monroe (1935).

### 3.3 `persuade.problemCauseSolution` — Problem-Cause-Solution

| # | Component | Contains |
|---|---|---|
| 1 | Problem | Current issue |
| 2 | Cause | Root causes |
| 3 | Solution | Proposed solution |
| 4 | Benefits | Expected outcomes |

**Source:** *not specified in source material.*

### 3.4 `persuade.comparativeAdvantages` — Comparative Advantages

| # | Component | Contains |
|---|---|---|
| 1 | Option | Recommended choice |
| 2 | Alternative | Other choices |
| 3 | Comparison | Strengths and weaknesses |
| 4 | Recommendation | Why the recommended option is best |

**Source:** *not specified in source material.*

### 3.5 `persuade.causeEffect` — Cause-Effect (persuasive)

Same components as `inform.causeEffect` (§2.3); the **Conclusion** emphasizes persuasive
implications or a recommended action rather than a neutral implication.

| # | Component | Contains | AI Guideline |
|---|---|---|---|
| 1 | Cause | Root causes; contributing factors | Identify WHY something happened. |
| 2 | Effects | Immediate impacts; long-term impacts | Identify WHAT happened because of the causes. |
| 3 | Conclusion | Persuasive implication; recommended action | State what the audience should conclude or do. |

**Source:** Oklahoma State University — https://open.library.okstate.edu/speech2713/

### 3.6 `persuade.refutation` — Refutation

| # | Component | Contains |
|---|---|---|
| 1 | Claim | Opposing viewpoint |
| 2 | Counterargument | Weaknesses; missing evidence |
| 3 | Evidence | Supporting evidence for the rebuttal |
| 4 | Conclusion | Stronger position |

**Source:** *not specified in source material.*

### 3.7 `persuade.cer` — Claim-Evidence-Reasoning (CER)

| # | Component | Contains |
|---|---|---|
| 1 | Claim | Main argument |
| 2 | Evidence | Facts; statistics; examples |
| 3 | Reasoning | Explanation of how the evidence supports the claim |

**Sources:** McNeill & Krajcik (2012), *Supporting Grade 5–8 Students in Constructing Explanations
in Science*; NGSS Evidence-Based Reasoning Framework.

---

## 4. Purpose: To Inspire

> These come largely from storytelling literature rather than formal public-speaking texts, but
> are defined here on the same footing as the rest.

### 4.1 `inspire.challengeChoiceOutcome` — Challenge–Choice–Outcome

| # | Component | Contains |
|---|---|---|
| 1 | Challenge | The obstacle, setback, or defining moment that created tension or required action |
| 2 | Choice | The decision, mindset, or action taken to address the challenge |
| 3 | Outcome | The result, lesson learned, or positive transformation that inspires the audience |

**Source:** Leadership storytelling frameworks (leadership development, behavioral interviews).

### 4.2 `inspire.narrativeArc` — Narrative / Storytelling Arc

| # | Component | Contains |
|---|---|---|
| 1 | Beginning | Setting, context, and characters |
| 2 | Conflict | The central challenge or tension |
| 3 | Climax | The turning point or decisive moment |
| 4 | Resolution | How the situation was resolved |
| 5 | Takeaway | The lesson or message for the audience |

**Sources:** Freytag's Pyramid; Nancy Duarte, *Resonate*.

### 4.3 `inspire.publicNarrative` — Public Narrative (Marshall Ganz)

| # | Component | Contains |
|---|---|---|
| 1 | Story of Self | Why this issue matters personally to the speaker |
| 2 | Story of Us | Connection from the personal story to shared values or experiences |
| 3 | Story of Now | The urgency; inspiring immediate collective action |

**Source:** Marshall Ganz, Harvard Kennedy School.

### 4.4 `inspire.herosJourney` — Hero's Journey

| # | Component | Contains |
|---|---|---|
| 1 | Ordinary World | Initial situation before change |
| 2 | Challenge / Call to Adventure | The event that initiates change |
| 3 | Trials | Obstacles and growth throughout the journey |
| 4 | Transformation | The key insight or personal change achieved |
| 5 | Return / Message | The lesson shared; how it inspires the audience |

**Source:** Joseph Campbell, *The Hero with a Thousand Faces*.

### 4.5 `inspire.personalStory` — Personal Story

| # | Component | Contains |
|---|---|---|
| 1 | Situation | The context |
| 2 | Experience | What happened |
| 3 | Reflection | What was learned |
| 4 | Application | How the lesson connects to the audience |

**Source:** Annette Simmons, *Whoever Tells the Best Story Wins*.

### 4.6 `inspire.problemSolution` — Problem–Solution

| # | Component | Contains |
|---|---|---|
| 1 | Problem | An issue that resonates emotionally with the audience |
| 2 | Solution | The action or idea that addressed the problem |
| 3 | Impact | The positive change created |
| 4 | Inspiration | Encouragement to take a similar perspective or action |

**Source:** *not specified in source material.*

### 4.7 `inspire.beforeAfterBridge` — Before–After–Bridge (BAB)

| # | Component | Contains |
|---|---|---|
| 1 | Before | The current reality or pain point |
| 2 | After | A vivid picture of the desired future state |
| 3 | Bridge | How to move from the current state to the desired future |

**Source:** Popularized in copywriting by Buffer and other marketing practitioners.

### 4.8 `inspire.chronological` — Chronological (inspirational)

| # | Component | Contains |
|---|---|---|
| 1 | Beginning | The starting point of the journey |
| 2 | Milestones | Significant events, in order |
| 3 | Turning Point | The moment of meaningful change |
| 4 | Present / Future | The current outcome and key lesson |

**Source:** *not specified in source material.*

> Distinct from `inform.chronological` (§2.2): that one summarizes a timeline neutrally, this one
> builds to a turning point and a lesson.

---

## 5. Summary counts

| Purpose | Pattern count | Component count (min–max) |
|---|---|---|
| To Inform | 8 | 3–5 |
| To Persuade | 7 | 3–5 |
| To Inspire | 8 | 3–5 |
| **Total** | **23 entries** (21 distinct structures; Cause-Effect and Chronological each appear under two purposes with different framing) | |

---

## 6. Open items

1. **Missing sources.** Seven entries have no cited source (marked above). Fine for v1 — the app
   does not currently surface provenance in the UI — but worth filling in before any
   "learn more about this pattern" feature.
2. **Cross-purpose duplication.** `inform.causeEffect` / `persuade.causeEffect` and
   `inform.chronological` / `inspire.chronological` are modeled as **separate catalog entries with
   distinct IDs**, not one shared entry tagged with two purposes. This is deliberate: their
   guidance text differs, and separate IDs keep classification prompts scoped to a single purpose
   with no conditional wording.
3. **Missing summaries — this document is currently underspecified.** §1 declares `Summary` a
   required field, but summary text is only actually given for the eight `inform.*` entries and
   `persuade.prep`. The remaining **14 entries have no summary sentence here**, yet
   `SpeechPatternCatalog` authors one for each, and those strings ship into the classification
   prompt. Since this file is declared authoritative, the fix is to write the 14 missing summaries
   here and reconcile the code to them — not to backfill this document from the Swift. Until then
   `SpeechPatternCatalogTests` can only pin the fields the spec actually states.
4. **Inconsistent source citation format.** §2.1 gives a full citation plus URL, §2.2 gives
   `Lucas (2023).`, §2.4 gives `Lucas.` — three forms for one source. Pick one before any
   "learn more about this pattern" feature reads these strings.
5. **Component counts are fixed per pattern.** A transcript with four categories still maps into
   Topical's three `Category` slots. If that proves too rigid in testing, the fix is to allow a
   pattern to mark trailing components as repeatable — not to let the model invent extra slots.
