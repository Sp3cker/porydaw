# Plan 04 — Small concept owners (lever: cause a; fixes Q7, trims Q4)

Two independent ownership fixes found by the traces, one file each. Prerequisite: none.

## Task 1 — Event-list cell-edit policy (Route: SDD-track)

**Context.** Q7 (accept decimal BPM in a tempo cell) must be answered in two places that gate one
contract: `EventListModel.validatesEdit` (edit mask + integer range, :215-254) and
`EventListEditing.commitCellEdit` (trim at :37, `Int(input)` parse at :71-82). A fix touching one
gate still fails at the other. One policy type makes the acceptance rule single-sourced.

**Exact write set**
- Create `src/swift/app/eventlist/EventListCellPolicy.swift`.
- Edit `src/swift/app/eventlist/EventListModel.swift`, `src/swift/app/eventlist/EventListEditing.swift`.

**Interface contract**
- `EventListCellPolicy` (**public**, pure, `@MainActor`-free): owns per-column text acceptance and
  parsing for cell edits, incl. the tempo special cases — integer BPM bounds (20...255 per
  EventListModel today), tick parse, event-kind parse, and the retyping-to-tempo allowance
  (EventListEditing.swift:26-35). `public` is required, not stylistic: the two consumers live in
  different modules (`EventListEditing.swift` is compiled into PorydawApp, app/CMakeLists.txt:43;
  `EventListModel.swift` into PorydawAppEventList, :278), and PorydawAppEventList is the lowest
  common importer (Core is lower but this is not a core concept) — exactly the AGENTS.md
  `## Files and modules` "public only for what another module calls" case.
- `EventListModel.validatesEdit(row:column:text:)` delegates acceptance to the policy; keeps
  row/column editability facts (tempo-column mask etc.).
- `EventListEditing.commitCellEdit(row:column:text:)` delegates parse to the policy; keeps the
  commit dispatch (editTempo / editRawAndTempo / note edits) and emission order.
- Behavior-identical for every column and every rejected input; no QML change; presenter
  (`EventListPresenter.finishEditing` :319-340) untouched.

**Preservation contract**: both gates keep their current accept/reject results for all inputs
(the check corpus is the oracle); the tempo-retyping branch stays a commit-path allowance, not a
model allowance, exactly as today (:26-35 gate `convertingToTempo`).

**Steps**
1. Extract the acceptance/parse decisions into the policy (typed results, e.g. accepted value or
   nil per column; shape is the implementer's, the two call sites must not retain parsing logic).
2. Delegate both call sites; delete duplicated literals.
3. Register the new file in the `PorydawAppEventList` source list
   (`src/swift/app/CMakeLists.txt`, target sources ~:277-295).

**Acceptance predicate (implementer-run)**
- `deno task build:checks`.
- `deno task checks --filter swiftcore` — event-list edit slots (eventviews/editcheck dirs)
  compile into `swift_core_check`; the specific suite name for event-list editing was not
  individually verified (named gap) → full swiftcore filter.
- `deno task format --check`; `deno task lsp:swift` after the CMake edit.

**Read-set effect [INFERENCE]**: Q7 6→5 files; the "where is cell input validated" question
becomes policy + commit endpoint (2 files) instead of model + editing + presenter.

## Task 2 — Tempo BPM display rounding (Route: Direct)

**Context.** The same rounding expression appears at both BPM projections:
`AutomationLaneProjection.swift:118-121` and `EventListProjection.swift:49-60`
(`Int(TimeDefaults.tempoBPM(forMicrosecondsPerQuarterNote: x).rounded())`). Q4 counted this as
parallel-consumer duplication of tempo semantics.

**Exact write set**: `src/swift/core/MusicTypes.swift` (TimeDefaults),
`src/swift/app/drawer/automation/AutomationLaneProjection.swift`,
`src/swift/app/eventlist/EventListProjection.swift`.

**Change**: add to `TimeDefaults` (MusicTypes.swift:49-)
`static func tempoBPMDisplay(forMicrosecondsPerQuarterNote: UInt32) -> Int` returning the same
`Int(tempoBPM(...).rounded())`; both call sites delegate. No other behavior; no QML; no bridge.

Alternative considered: leave the two sites duplicated and have the maps point at both — rejected
because a third BPM projection (e.g. a transport readout) would drift silently; sharing pins the
rounding once.

**Acceptance predicate (implementer-run)**: `deno task build:checks`;
`deno task checks --filter swiftcore` (playback/documenthistory suites exercise tempo paths;
automation/event-list display slots ride the lane); `deno task format --check`.

## Shared constraints (both tasks)

- Build gate: one new small file in `PorydawAppEventList` (cold: EventListPresenter 598 but
  policy extraction touches model/editing only), one method in core `TimeDefaults` —
  build-neutral; no new modules/targets/edges.
- Comments ≤2 lines; policy types stay pure value-semantic (test seam, no state).
- Do not reformat untouched ranges; `deno task format --check` scopes to changed lines.

## Task 3 (user chose option A) — song-settings resolver (Q3's (a)-slice)

Trace correction: composition was already single (`NativeAudio.songSettings`; `WavExportPresenter`
only calls it). The split was placement and application:
- `AudioSettings.applyingSong` lived in `export/WavExportJob.swift` though live playback uses it;
  moved beside its only production consumer, `NativeAudio.songSettings` (same module).
- Bind, preview reset and WAV export each repeated voicegroup + settings + mix rate; now one
  `AudioRenderEngine.configure(_:voicegroup:settings:)`. `bindEngineVoicegroup` deleted;
  `applySettings` private. `updateSettings` keeps its changed-rate guard (the rate rebuilds reverb).
