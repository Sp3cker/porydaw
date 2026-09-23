# plan.md — Swift/QML dock lists (Songs + Voicegroup) conversion

Read `spec.md` first: it records current source ownership, frozen pins,
sample behavior, proof inventories, and the exact retirement list. Briefs
carry task-specific write sets and acceptance predicates.

## Summary

Complete the Swift/QML Songs and Voicegroup dock migration against the
existing rewrite. Reuse the existing song service and `SongListPresenter`,
the existing `VoiceListController`, `ProjectService`, `DocumentSession`,
and `NativeAudio`. Add only missing sample/voicegroup bridge behavior,
functional registration/deletion, voicegroup creation, sample workflows,
audition, and synth persistence. Every retired native assertion must have
a named runnable Swift/QML counterpart before its source is retired.

## Task table

| # | Task | Route / seat | Why this route | Checks |
|---|---|---|---|---|
| 1 | Accepted pre-existing `PdSongListEntry` / `pd_service_list_songs` / `ProjectService.songs()` baseline; no implementation dispatch | **Pre-existing** | The service and `SongListPresenter` already exist; task 2 owns residual application wiring | `swiftcore/SongList::serviceFeed` |
| 2 | Wire existing `SongListPresenter` into `ApplicationSession`, keyed by `songId`; migrate the QML drawer diagnostic while retaining legacy chooser/count-cache bridges until task 3 | SDD / `sdd-implementer` | Integrates existing service/presenter and app navigation before the task 3 shell cutover | `swiftcore` + `verify:qml` |
| 3 | Functional register/delete confirmations; replace Open Song with the `songs.find` Find Song action/focus handoff and retire the chooser/count/label/cache bridge; own outer dock width | SDD / `sdd-implementer` | User-visible mutation/cancel/error paths, keyboard navigation, and the Songs shell cutover | `swiftcore` + `swiftrollgated` |
| 4 | Register existing visual-swift lanes and capture the production Songs QML panel for frozen pins | SDD / `qt-cpp-reviewer` | Uses the existing visual comparator and frozen catalog; no comparator implementation | `visual-swift-12`, `visual-swift-16` |
| 5 | Missing voicegroup catalog/sample data/bank-load operations and undoable `DocumentSession` `-G` rebind; reuse `pd_service_voicegroup_args` | SDD / `qt-cpp-reviewer` | C bridge ownership and async rebind/history semantics | `swiftcore` |
| 6 | Integrate existing `VoiceListController` into QML; add one stacked Songs/Voicegroup `SplitView`, own its adjustable divider and `swiftDock/songsRatio`; preserve tone fallback and structural flag | SDD / `sdd-implementer` | Connects existing controller/session/audio owners without a new presenter; minimum heights prevent pane collapse | `swiftcore` + `swiftrollgated` |
| 7 | Full editor decision tree through existing `voiceDraft` / `requestVoiceEdit` / `applyVoiceEdit`; at default 280, CGB/DirectSound selection must not widen the dock; editor scrolls at constrained pane heights | SDD / `sdd-implementer` | Complex editor semantics; 420×680 is the isolated visual capture only | `swiftcore` + scoped visual |
| 8 | Sample/Wave/Keysplit picker audition and synth mint/save; exact samplepicker pin incl. `vgSamplePickerList` | SDD / `sdd-implementer` | Audio audition and save receipt behavior | `swiftcore` + scoped visual |
| 9 | New voicegroup creation and undoable assignment | SDD / `qt-cpp-reviewer` | Project mutation worker plus session history | `swiftcore` + `swiftrollgated` |
| 10 | New/Edit Sample QML workflow on the compiled service bridge, consuming task 11; name-collision controls, Return-to-commit rate behavior, full voicegroup vanilla/dark and sample-editor pins | SDD / `qt-cpp-reviewer` | Project worker/sample commit behavior plus QML controls | `swiftcore`, `swiftrollgated`, both visual lanes |
| 11 | Link sample processing backend (`sampleimport`, `sampledsp`, `sampledoc`, `samplewav`) and add parity: `analysis`, `decoder`, `dsp`, `soundfont` (229 sites / 30 methods) | SDD / `sdd-implementer` | Processing contract and required app target wiring consumed by tasks 10/12 | Named Swift backend predicates |
| 12 | Sample project/editor lifecycle parity: `editor`, `integration`, `project` (264 sites / 32 methods; 18 SwiftCore + 14 SwiftRollGated) consuming tasks 10 and 11 | SDD / `sdd-implementer` | Completes workflow lifecycle after UI and processing contracts exist | SwiftCore + SwiftRollGated predicates |
| 13 | Per-assertion correspondence for seven voicegroupsave ledgers plus historical browser proof | SDD / `sdd-implementer` | Separate proof package for voicegroup behavior and visual oracle | `deno task proof check` (structure only) |
| 14 | Per-assertion correspondence for seven samplecheck ledgers plus sample-specific visual proof | SDD / `sdd-implementer` | Separate proof package for sample backend and editor visuals | `deno task proof check` (structure only) |
| 15 | Swift history/viewcache parity for 70 legacy sites; split document-save and bank-merge sealing in `src/swift/core/SongHistory.swift`, and seal a clean-bank edit boundary in `src/swift/app/DocumentSession.swift` | SDD / `sdd-implementer` | Completes behavior coverage; existing workspace predicates are partial starting points only | `swiftcore` |
| 16 | Per-assertion correspondence for the 70-site viewcache proof inventory | SDD / `sdd-implementer` | Maps every retired viewcache assertion to its named runnable Swift predicate | `deno task proof check` (structure only) |
| 17 | Direct retirement of the exact uncompiled C++ widget/check sources in spec §7 and their fully proved proof ledgers | **Direct** (inline below) | Mechanical allowlisted deletion after parity and proof gates | `deno task proof check` (surviving ledgers only) |

## Order and shared-file boundaries

Task 1 is a pre-existing baseline gate (M0), not a second service
implementation. Execute the shared application/service train serially in
this dependency order:
`1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 11 → 10 → 12`.
Task 5 is not disjoint from tasks 2–4: it reuses
`swift_project_service.*`, `ProjectService.swift`, and application/session
wiring. Task 11 must link processing sources before task 10 consumes them;
task 12 depends on both tasks 10 and 11. Tasks 6–10 successively extend
the same controller/QML surface. Task 7 and task 8 capture only scoped
visual scenarios; the full voicegroup vanilla/dark pin waits for task 10.

Tasks 13 and 14 complete only after task 12's runtime gates. Task 15 may
start earlier once task 5's bank-service boundary and its shared
`DocumentSession.swift` / `SessionChecks.swift` ownership have settled; it
does not consume sample-editor or QML behavior. Task 11's headless processing
work may likewise move earlier when its shared app/check build files are
available, while still preceding task 10. Serialize every shared-file edit.
Task 16 depends on task 15. Task 17 starts only after tasks 13, 14, and 16,
with all behavior and visual gates green.

Already-green headless predicates may have their individual proof sites
reconciled early: preserve source IDs/hashes, name the executed assertion,
and leave every uncovered site as `GAP`. This is progress within the
inventory, not completion of tasks 13, 14, or 16. Their final acceptance
and task 17 retirement still require all named SwiftCore, SwiftRollGated,
and visual counterparts; a matching `cppID` alone never proves a site.

Tasks 13 and 14 deliberately exceed the three-file WBS package size as
bounded mechanical exceptions: each is one source-oracle reconciliation
behavior with a proof-only write set (task 13's seven voicegroupsave
ledgers plus `proof.browsers.txt`; task 14's seven samplecheck ledgers plus
only visual proof sites A010–A015). Keep each inventory family atomic so
site identity and evidence are not split across writers. Task 15 likewise
keeps a cohesive six-file history seam together: the `SongHistory` and
`DocumentSession` production boundary, three existing runtime predicate
files, and their shared suite dispatcher.

## Direct task 17 — legacy source retirement

- **Target:** only the source files listed in spec §7 and proof ledgers whose
  every original assertion site is `MATCHED` to an executed Swift/QML
  predicate. The closed source list includes uncompiled samplecheck suites
  and C++-only headers; it excludes frozen fixtures, visual baselines, and
  production sample processing/registration modules.
- **Change:** remove exactly the allowlisted legacy C++ widget/check sources
  and the fully proved `proof.*.txt` ledgers. Keep ledgers with `GAP`,
  `PARTIAL`, `NATIVE`, or another non-MATCHED site; never reclassify a site
  merely to make its ledger deletable. Do not edit build targets: the
  retired sources are already excluded from application/check builds.
  Keep frozen fixtures and visual baselines.
- **Acceptance:** tasks 1–15 behavior and visual gates are green; tasks 13,
  14, and 16 have reconciled every source site against a runnable predicate.
  Confirm each ledger selected for deletion was wholly `MATCHED` and its
  Swift/QML execution succeeded before deletion. `deno task proof check`
  succeeds on the remaining ledgers (structure only). Review the source
  deletion diff against spec §7 and the exact selected ledger list; a
  structural proof-check pass is not runtime parity evidence.

## Global constraints

- **Accepted baseline:** task 1 already has `PdSongListEntry`,
  `pd_service_list_songs`, `ProjectService.songs()`, and
  `SongListPresenter.swift`. Task 2 owns remaining `ApplicationSession`
  song-list wiring/navigation. Do not create a second song service or
  presenter.
- **Ownership:** reuse `VoiceListController`, `ProjectService`,
  `DocumentSession`, `NativeAudio`, and the existing project worker/service
  pattern. Do not create `VoicegroupPresenter` or a duplicate `groupArgs`
  bridge. Keep the structural flag and `PdBankSlotView.tone` fallback.
- **Functional scope:** register/delete, voicegroup creation, sample
  creation/edit, and Sample/Wave/Keysplit audition are required behavior.
  The unrelated new-song wizard is excluded. Follow spec §3.2 exactly:
  preserve the native invalid/nested/square/noise refusals; valid direct
  Sample/Wave leaves must audibly preview.

- **Dock layout:** task 3 owns the single outer left-column width,
  persisted at `swiftDock/columnWidth` (280 logical pixels by default,
  clamped to 200–480). Task 6 owns the internal Songs-over-Voicegroup
  vertical `SplitView`, its horizontal drag handle, and the 0.5-default
  `swiftDock/songsRatio`. Clamp the split so each pane retains its controls
  and one full list row. Task 7
  adapts within the saved dock width without forcing it wider; a native QML
  check confirms CGB/DirectSound selection leaves the default 280-pixel
  column unchanged. The live editor scrolls and remains reachable at
  constrained pane heights. Allow editor fields to shrink/clip as in the
  native `QSizePolicy::Ignored` behavior (`voicegroupbrowser.cpp:304-310`).
  The 420×680 editor geometry applies only to its isolated visual capture.
  Do not create an additional dock column or divider.
- **Sample ownership:** keep `src/project/samplereg.*`; task 11 links the
  currently unlinked processing modules
  `src/audio/{sampleimport,sampledsp,sampledoc,samplewav}.*`. Task 17 keeps
  these production sources. The uncompiled `src/checks/samplecheck` sources
  are historical check oracles only until task 17; never enable their C++
  target as a substitute for Swift predicates.
- **Verification:** implementers run the exact commands in their briefs.
  Swift/QML behavior uses the native `swiftrollgated` surface; visual lanes
  `visual-swift-12` and `visual-swift-16` require a native desktop and a
  connected 2x display. The controller owns shared builds and
  project-wide gates. `deno task proof check` is structural only.
- **Geometry and color:** derive QML geometry from
  `Application.font` and frozen JSON rects. Use the shared `GridPalette`
  roles; the only sanctioned literal is warning foreground `#C08030`.
- **Keyboard:** task 3 installs Find Song on the existing `songs.find`
  keymap ID and calls `SongListPresenter.focusSearch()`; QML consumes
  `searchFocusRequest`. The keymap ID alone does not already invoke the
  presenter. Songs search bare Space propagates to transport;
  Up/Down/PageUp/PageDown forward to the list. The modal sample editor's
  focused audition control is the sole local bare-Space exception; it
  consumes Space to audition as the native dialog does.
- **Brief discipline:** task briefs follow the required headings
  `Context`, `Exact write set`, `Prerequisites`, `Interface contract`,
  `Implementation steps`, `Acceptance predicate`, and
  `Task-specific constraints`. Keep global policy/checkpoint rules here,
  not repeated in every brief.

- **Proof retirement:** `proof.*.txt` files are temporary correspondence
  workpapers, not permanent checks. Retire a ledger once every site is
  `MATCHED` to executed Swift/QML behavior and its historical oracle is
  recoverable from the pinned Git revision/hash. Keep any mixed, blocked,
  unproved, or still-active native-implementation inventory. The underlying
  Swift checks, fixtures, and visual baselines remain. Before deleting a
  proof file, inspect its exact tally and relevant runtime result; the
  structural `deno task proof check` cannot establish semantic parity.

## Checkpoints

- **M0 — existing song baseline** (before task 2): `swiftcore/SongList::serviceFeed`
  confirms the already-present service/presenter evidence.
- **M1 — song surface** (after task 4): app wiring, functional register/
  delete flows, and Songs visual pins are accepted before task 5 reuses
  application/service files.
- **M2 — voice and sample behavior** (after task 12): voicegroup/sample UI,
  sample processing and lifecycle predicates, full sample workflows, and
  both 2x visual lanes are green. Task 10 alone is not the complete sample
  behavior gate.
- **M3 — proof and retirement** (after task 17): task 15 viewcache
  predicates and task 13, 14, and 16 correspondence packages are green;
  source deletion matches the closed list, eligible wholly proved ledgers
  have been retired, and `deno task proof check` succeeds on survivors without
  deleting any fixture or visual baseline.
