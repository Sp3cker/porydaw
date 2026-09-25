# Swift migration history: editor drawer, roll checks, edit checks

Historical record condensing four retired planning sources. Everything below
describes decisions, tallies, and verification results AS RECORDED in those
sources — not claims about the current tree, and not standing instructions.
Unfinished work described here MUST NOT be read as implemented. Before acting
on anything resembling a rule below, consult the current proof workflow,
current sources, and active planning in `docs/plans/swift-feature-parity/`;
live proof state is in `src/checks/**/proof.*.txt`.
Recovery revision for every deleted file: `1096534c7d3e97c17a785625a93a215459c39d6e`
 (2026-09-24, "Restore missing menu items and roll display modes"). All files
 were Git-tracked and clean at deletion; nothing below is reconstructed.
- Deleted: `docs/plans/swift-editor-consumers/` (plan, spec, briefs 1–7 incl. 6a/6b),
 `docs/plans/rollcheck-swift-migration/` (plan, spec, briefs 1–12),
 `docs/plans/editcheck-proof-retirement/` (plan, spec, `engine-reachability.md`,
 briefs 1–13, 15), `docs/plans/editor-drawer-swift-refactor-handoff.md`.

## 1. Editor drawer Swift refactor handoff (2026-09-21)

Structural refactor of the production Swift drawer into small cohesive files,
explicitly ordered BEFORE parity-gap closure so failures stay attributable.
Integration base: worktree `swift-qml-grid`, commit `682095474e862b`.
Recorded baseline: `verify --filter swiftcore` passed; `verify:qml` had two
known failures — `test_numericFieldWindowShortcutPriority(velocity|automation)`
(expected Space count 1, actual 0), protecting the rule that window shortcuts
outrank focused drawer chrome. Full 24/24 suite had passed pre-hardening; one
later run showed transient `swiftrollgated`/`selectionkey` native-window
failures, one retry green.

Durable boundaries (still load-bearing for drawer work):

- `EditorDrawerPresenter` owns the bridge, delegates policy to pure
  `EditorDrawerLayout`; `EditorDrawerPage` is the Swift page seam;
  `DocumentWorkspace` owns one Velocity/Voice/Automation page per document.
- All QML-visible members stay in the `@QtBridgeable` class body; pages attach
  before first publication and cancel synchronously before owners retire;
  hide/replace/cancel ends the interaction before publishing new layout.
- Gesture/picker/prompt/menu targets keep captured document revision+identity;
  `EditorDrawerLayout` alone owns stacking/clamping/resize/focus/preference;
  playhead stays composition-owned; persistent chrome never claims bare Space.
- Legacy C++ seam map preserved as architecture guide: `EditorDrawer` (thin
  owner), `DrawerSections` (layout state machine), `DrawerChrome`, per-area
  gesture/axis/menu/transaction modules; `Scene`/`Projection` values for
  painting math, never transactions or lifetimes.
- Proof discipline from this era (historical — the path/hash/`S###` ledger
 scheme has since been superseded by compact ledgers; do not restore it):
 proofs then ledgered Swift *check* files, not production files, so production
 moves needed no proof churn; check splits refreshed anchors in the same
 change; C++ was never retired while `GAP`/`PARTIAL` remained.

## 2. Swift editor consumers plan (restore drawer pages in Swift/QML)

Accepted base: camera integration `5f0924e8`, drawer container `becfeb40`;
one `DocumentSession`-owned `EditorCamera`, one `ApplicationSession`-owned
grid/audio/drawer; whole-scene detachment before owners release; lanes
`swiftcore`, `editorqml-drawer`, `swiftrollgated`. Sibling `swift-qml-songtab`
worktree was read-only parity authority (C++ checks = inventories to translate).

Behavioral contracts worth keeping:

- One document/history, one sample authority, one `PlaybackTimeline`, one
  camera, one shared playhead owner. Playback maps `NativeAudio.playheadSamples`
  through `PlaybackTimeline.tick(for:)` only — never wall clock, interpolation,
  or QML timers. Playhead-only updates rebuild nothing, dirty nothing.
- Follow rule (then-frozen scope, now obsolete): at the time, follow defaulted
 on with no public toggle (Swift-only setter for checks allowed) and the plan
 froze that scope — do NOT treat this as the current contract. The current app
 has a follow control; current behavior lives in source, not here.
 The historical formula was: while playing, enabled, unsuspended, and no
 aggregate interaction, if `x = camera.contentX(tick:)` leaves `[0, 0.85w]`,
 scroll to `tick * pixelsPerTick - w/10` via the camera path.
- Page transaction contract: freeze targets+before-values at gesture begin,
  preview on motion, exactly one document transaction + one history entry on
  release; every hide/switch/ungrab/Escape/deactivate path uses the same
  synchronous cancel; Undo/Redo rebuilds pages from the document.
- Focus: bare Space stays window transport; Enter/Return/pointer/accessibility
  press activate local controls. Drawer heights feed `PianoGrid.configureViewport`.
- Lanes: `swiftcore` = projection/transaction/history invariants;
  `editorqml-drawer` = production composition/input/focus/rendering;
  `swiftrollgated` = real-window/shortcut/DPR/lifetime evidence.

Recorded capability blockers (historical — re-verify before acting):

- Velocity per-note keysplit/drumkit subvoice resolution unavailable through
  `BankSlotView` (top-level `BankVoice` only); no native expansion authorized.
- Voice picker audition: native `AudioEngine::previewVoice` exists but Swift
  `NativeAudio` exposes only `previewNote` — not equivalent; left blocked.
- Four native MIME clipboard gaps and ten stale absent-UI exclusions tracked
  separately; voicegroup-save rows out of drawer milestone scope.

## 3. Rollcheck Swift migration plan (C++ roll assertions → Swift)

Goal: re-point 979 addressable sites (799 GAP + 180 PARTIAL) across 22 ledgers
at executing Swift predicates citing `S###`; 274 `NATIVE` sites stay NATIVE.
Success tallies, waves (A: camera/grid → F: rendering/gate), and 18 fixed new
Swift stems (`pencil`, `resize`, `note_commands`, `keyboard`, `selection`,
`identity`, `interlock`, `remap`, `presentation`, `time_signature_prompt`,
`timemenu`, `ruler_loop_menu`, `scale_fold`, `scale_editing`,
`note_rendering`, `static/geometry`, `static/gate`) were the plan's routing —
kept here only so future readers can interpret the resulting filenames.
Durable rules (historical — the plan's own working rules, not current policy):

- Swift follows the C++ piano roll: port fixture values/sequences/transaction
 boundaries verbatim; never retune expectations (charter S-1). Failures fix
 Swift or the driver, never the expectation.
- No new C++ (all stems register into existing `projectSession` suite 10; no
  new `PDC_SUITE_*`), no new QML files, no C++ source edits; production Swift
  changes only to fix behavior an assertion exposes.
- `PARTIAL → MATCHED` only by discharging the site's named unproved condition;
  every flip rewrites Mapping/Mapping-reason with its `S###`.
- Never-flip blockers: `header_reconciliation` A002/A006 (retired native
  viewport, source deleted `91cab247`), `static/proof.gate.txt` A076–A082
  (ruler-tooltip hover geometry, no QML mount), all framebuffer-pixel NATIVE sites.

## 4. Editcheck C++ check retirement plan (seven originals retired, scale kept)

Retired seven `src/checks/editcheck/tst_songdocument_*.cpp` originals by
covering each site's observable contract with Swift, rewriting each proof as a
deletion certificate, deleting the C++ file. `tst_scale.cpp` (24 GAP) was
KEEP-NATIVE by default: registered passing native lane guarding unlinked
`porydaw_scale` tables; retirement needs an explicit user feature decision.

- Historical disposition discipline (a snapshot of how that plan classified
 sites — consult the current proof workflow before reusing any of it):
 STALE → MATCHED (cite `S###`); REPRESENTATION → MATCHED via public-API
 predicate; RETIRED-REPRESENTATION only with the then-required no-ingress
 proof ("C++ file uncompiled in every target and unregistered in checkcatalog,
 Swift stages via Deno fixtures + `coreEditCorpusSongs`"); else BEHAVIOR-GAP
 needing a new assertion. Ties favored the weaker label; GAP could stand.
 The plan's hard rules at the time: no argument-echo predicates;
 non-throwing construction (`SongDocument(file:)`, `PlaybackTimeline.build`)
 has no failure branch — null/staging asserts were RETIRED-REPRESENTATION,
 never MATCHED; `revision` advances on commit AND undo/redo, so it never
 substituted for history depth (the plan used `coreEditHistoryCountAtTip`
 at-tip traversal, never while undone).
- Corpus dimension (historical approach): corpus-driven families needed
 per-row Swift equivalents over the 14 staged decomp songs
 (`NoteMoveCorpusChecks.swift:13-52` pattern) with per-family
 capability-eligibility — synthetic fixtures alone didn't MATCH.
- Certificate format (historical scheme, explicitly not an instruction to
 restore it): the plan used a songraw-canonical deletion certificate
 (correspondence, post-deletion verify line, pinned `Reference revision` +
 verified `Original SHA-256`, Swift counterpart SHAs, covered native
 implementation, engine status, retirement counts, fixtures, history caveat,
 registered run path). Compact ledgers have since superseded this
 hash/tally scheme; do not reintroduce it. Four earlier certificates
 (songmoves/songnotes/songranges/songraw) were recoverable at `4c52acd8`
 at the time of writing.
- Native-engine deletion gate (§8) was BLOCKED at retirement time — a
 historical verdict, not a standing order: `songdocument*.cpp/.h`,
 `songhistory.*` had zero CMake references but live on-disk includers via
 dormant `src/project/projectworkspace.h:13-14` and old widget UI
 (`rangeedit.cpp`, `tempoadapter.cpp`, `voicechangearea.cpp`,
 `trackvoiceops.cpp`, `workspaceui_voicegroup.cpp`). Re-check current source
 before treating any of this as still true. The deleted
 `engine-reachability.md` recorded the per-file CMake/proof/includer table —
 consult the recovery revision above if that gate is ever revisited.
 Explicitly never candidates at the time: `smf`, `miditimeline`, `xcmd`,
 `timelineplayer`, `midiimport`, `m4asemantics`, `mid2agbtables`,
 `velocitymodel`, `lanemoveplan`, `noteid.h`.

## Deleted file manifest (exact paths, all recoverable at `1096534c`)

- `docs/plans/editor-drawer-swift-refactor-handoff.md`
- `docs/plans/swift-editor-consumers/plan.md`, `spec.md`,
  `task-1-brief.md`, `task-2-brief.md`, `task-3-brief.md`,
  `task-4-brief.md`, `task-5-brief.md`, `task-6a-brief.md`,
  `task-6b-brief.md`, `task-7-brief.md`
- `docs/plans/rollcheck-swift-migration/plan.md`, `spec.md`,
  `task-1-brief.md` through `task-12-brief.md` (no 13/15 ever existed here)
- `docs/plans/editcheck-proof-retirement/plan.md`, `spec.md`,
  `engine-reachability.md`, `task-1-brief.md` through `task-13-brief.md`,
  `task-15-brief.md` (no task-14 brief; task 14 was inline in `plan.md`)
