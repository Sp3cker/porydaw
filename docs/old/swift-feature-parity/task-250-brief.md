# Task 250 brief — Sample Studio loop and pitch tools: adopt-pitch hint, loop populate/cycle/refine, crossfade, seam badge

# Context

Spec.md: pitch detection is a hint/prefill that never silently overwrites deliberate
metadata; preserve candidate loop cycling/refinement, first-enable loop population and seam
amplitude/slope/correlation diagnostics ("not meaningful" correlation without context); the
loop toggle and crossfade stay available. Fork owner: the loop/pitch half of
`SampleEditorDialog` (`ensurePitchDetected` 770, `updatePitchHint` 804, `applyDetectedPitch`
827, `analysisParams` 842, `computeChips` 858, `ensureChips` 901, `autoPopulateLoop` 913,
`tryAnotherLoop` 933, `applyChip` 942, `refineCurrentLoop` 956, loop checkbox/crossfade wiring
279–345, seam badge in `refreshOutputs` 697–720). Consumes 249's presenter API and 245's
analysis; the QML dialog (253) binds this object.

Surface: `SampleLoopTools` (SA03 loop/pitch).
Ledger spec and rows (`proof.editor.txt`; → MATCHED; widget lookups → RETIRED-REPRESENTATION
as in 249; setup rows per the P4 scaffolding rule):
pipelineLoopToggle A022–A024 (A023 retired), editorPitchAdoption A047–A053 (A050 retired;
NATIVE A051–A053 ported), editorLoopPopulate A054–A070 (A057, A069 retired; NATIVE A058–A060,
A062, A065, A066 ported — loop-body visibility is the presenter's `loopBodyVisible`),
editorLoopRefine A071–A077 (A074 retired; NATIVE A075, A077 ported).
Verify lane: `samplecheck`.
Blocked rows left untouched: editorCrossfade A078–A084 (251 proves `setCrossfade` with the
seam overlay) and every row outside the list.

# Exact write set

- `src/swift/app/samplestudio/SampleLoopTools.swift` — NEW `@QtBridgeable` object.
- `src/swift/app/CMakeLists.txt` — add the file (hot).
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline`.
- `src/checks/samplecheck/LoopToolsChecks.swift` — NEW `runLoopToolsChecks` (MainActor).
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledger `proof.editor.txt` rows above.

# Prerequisites

249 (`SampleStudioPresenter.commitParams`, `params`, `processed`, `source`,
`addRenderObserver`), 245 (`detectPitchYin`, `suggestLoop`, `refineLoop`).

# Interface contract

`@QtBridgeable @MainActor public final class SampleLoopTools`:

- `@QtIgnored init(presenter: SampleStudioPresenter)` — subscribes as a render observer.
- Tracked: `loopBodyVisible` (= `params.loopOn`), `pitchApplyVisible`, `pitchApplyText`
  ("Use detected pitch (<name>)"), `pitchApplyToolTip` (fork text), `suggestStatus`
  ("loop k of n" / "sample too short for a loop search — drag the markers." / "no loop
  candidates found — drag the markers."), `canTryAnother`, `seamBadgeVisible`,
  `seamBadgeText` ("seam: clean" | "seam: fair" | "seam: click"), `seamBadgeSeverity`
  (0 clean, 1 fair, 2 click; fork thresholds amp ≤ 2 & slope ≤ 3 / ≤ 4 & ≤ 6), `crossfadeOn`.
- QML-callable: `setLoopEnabled(_ on: Bool)` — first enable while `loopStart == loopEnd`
  seeds the best candidate as ONE entry with crossfade off (fork `autoPopulateLoop`), every
  other toggle is a plain parameter edit (merge key −1); `applyDetectedPitch()` (one entry;
  base key + cents from the detection); `tryAnotherLoop()` (cycles candidates, one entry,
  keeps a valid loop); `refineLoop()` (≤ one entry; NCC never below before − 0.02 per fork);
  `setCrossfade(_ on: Bool)` (one entry).
- Pitch detection runs once per source lazily (fork `ensurePitchDetected`: loop region when
  looped, whole buffer when shorter than 8192 frames) on `analysisParams` (normalize off,
  source rate) — it never changes params by itself; the hint hides when the current key/cents
  already agree.

# Implementation steps

1. Port the listed fork functions onto the presenter API (no direct `SampleDocument` mutation;
   every edit through `commitParams`).
2. `LoopToolsChecks.swift` on the fork fixtures (hi-res tone loop 2000..9999; misaligned loop
   2000..2137; the pitch-mismatch fixture): loop toggle off → one-shot size 64; adopt-pitch
   visible on mismatch, click → key 57 / cents ≈ 3.93 ± 1.5, one entry, hidden after; loop
   body hides/shows with the toggle; reset (three entries) then re-enable seeds one clean
   loop (amp ≤ 2, slope ≤ 3, NCC ≥ 0.95) with the badge; undo/redo; "Try another" keeps a
   valid loop; refine keeps NCC and adds ≤ one entry.
3. `deno task bridge:baseline`; ledger edits.

# Acceptance predicate

Detection only offers a hint, first loop enable seeds a clean analyzer loop in one undo entry,
cycling and refining keep valid loops without worsening the seam, and the badge reports the
fork's clean/fair/click classes.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

# Task-specific constraints

Seam badge colors: the fork's literal chip colors (`#7CCB7C`/`#E0C060`/`#E08080` with black
text) are not reproduced — the text-contrast rule forbids literal colors and no theme role
exists; 253 renders the badge text in `windowText`/`warningText`/`errorText` on the window
surface by `seamBadgeSeverity` (decision recorded in sprint-4 §P4).
