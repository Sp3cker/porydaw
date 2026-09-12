# R8 — Refresh regimes and clarified staleness handling (E-M6)

## Context
Signed-off finding E-M6 (AMEND, QtSignoffFindings). editactions.cpp:162-177 has three regimes: Copy live+focused, Paste cached, others live. observeTarget (:179-238) fans ~15 connections. Canvas snapshot (:223-237) and refreshCheckedStates's live re-walk (:313-318) are two paths for the same state. The amending verdicts: (1) the clipboard cache is the correct Qt idiom, not a regime wart — `editCommandAvailable(Paste)` reads the system clipboard, so all-live refresh would re-read the clipboard on every one of ~15 signals; `QClipboard::dataChanged` + document/rebind invalidation is canonical — **keep it, do not delete it.** (2) The staleness-remedy machinery for "re-observe on replacement" is rejected: `m_editorDrawer` (songview.cpp:284) and `AutomationCanvas` (automationpage.cpp:61) are construction-fixed per SongView and never replaced, so the machinery is dead weight; the real (minor) issue is that snapshot and live refresh are two paths computing the same 21 availabilities / checked states — either verify that none of them depends on the canvas parameter signals and delete those connections (relying on editorViewStateChanged), or keep them and delete the parallel live walk. (3) Fold Copy's third regime into the shared focus-precedence resolver (E-m7 fold, Task R6).

## Exact write set
- `src/ui/songview/editactions.cpp`

## Prerequisites
- Task R6 (editactions.cpp serialization; Copy regime fold lands with R6's resolveCopyTarget)

## Interface contract
Two refresh regimes remain after this task: (1) clipboard-cached Paste, invalidated on `QClipboard::dataChanged`, document, or rebind; (2) everything else live from model state, with Copy's focus-dependent part folded into the shared R6 resolver. An explicit comment should point at the invalidation seams so implementers of R12/R13 review 3 do not re-derive the regime. No refresh machinery keyed on drawer/canvas replacement may exist, since neither is ever replaced after bind.

## Implementation steps
1. Vertically navigate R5's canonical table and R6's policy rows so `refresh()` loops once over both regimes in one table-driven pass, rather than three if-based branches.
2. Delete the snapshot-vs-live duplication: either the canvas parameter-signal connections (after verifying none of the 21 availabilities/checked states depends on them) or the parallel live re-walk — the signoff verdict allows either, and the implementer records which they picked in the task report.
3. Add a comment block naming the clipboard-cache invalidation seams and stating that drawer/canvas are construction-fixed so no replacement re-observation exists or is wanted.

## Acceptance predicate
Paste disables/enables without any availability function reading the system clipboard during the sibling transition signals, and invalidates correctly on clipboard/document/rebind events; the other availabilities and checked states update in the single refresh pass; no dead re-observation machinery remains. Named checks: `deno task verify --filter selectionkey --filter rollcheck --verbose`.

## Task-specific constraints
[Global Constraints](plan.md#global-constraints) apply. **Spec amendment this brief lands:** spec.md#implementation-contracts bullet "Refresh from selection/context, document, committed cursor, readiness, active-tab, drawer/page, and mute/solo transitions, never playback frames." gains "Paste's clipboard payload cache is canonical Qt idiom; invalidate on QClipboard::dataChanged, document, and rebind — no live clipboard re-read on sibling signal transitions" and the dragged-in wording "no drawer/canvas re-observation machinery exists because neither is ever replaced after bind; snapshot and live refresh converge." Signed-off Qt verdicts preserved verbatim: (1) clipboard cache kept; (2) never-replaced-canvas machinery rejected; (3) Copy third regime folded through Task R6.
