# Task 122 brief — roll ruler and header presentation preserve visible targets and reveal navigation

# Context

Finish existing roll presentation: fallback/signature ruler positions, header rename focus and polyphony reveal-note navigation. The current ApplicationSession already routes polyphony onJump, so the ledger’s absent-owner claim is stale; prove the actual consumer and repair only demonstrated divergence. Consume 117’s event-row producer and 118’s stable application state.

Verified planning selection: **36 open rows (28 GAP + 8 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/rollcheck/static/proof.geometry.txt` — A002, A003, A004, A006, A007, A008, A027, A028, A029, A030, A033, A034, A038, A040, A041, A048, A049, A051, A052, A053, A054.
- `src/checks/rollcheck/proof.presentation.txt` — A007, A008, A009, A010, A012, A014, A017, A018, A019, A020, A021, A022, A023, A024, A026.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `85b97239ce94dc4c4cf5f3f4fb66fc96ff2cf27e`, `02752345fa3a1dbaf11ee6f1cd3ad5da475f0e06`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/ApplicationSession.swift`
- `src/swift/app/roll/PianoGrid.swift`
- `src/swift/app/roll/GridScene+Rebuild.swift`
- `src/swift/app/roll/PianoGrid+SceneSync.swift`
- `src/swift/app/timeline/EditorCamera.swift`
- `src/swift/app/headers/TrackHeaders.swift`
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`
- `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml`
- `src/checks/rollcheck/static/geometry.swift`
- `src/checks/rollcheck/presentation.swift`
- `src/checks/editorqml/GatedVisualsProbe.swift`
- `src/checks/editorqml/PolyphonyShellProbe.swift`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/editorqml/tst_ShellNoteVisuals.qml`
- `src/checks/editorqml/tst_ShellPolyphony.qml`
- `src/checks/rollcheck/static/proof.geometry.txt`
- `src/checks/rollcheck/proof.presentation.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

Accepted Group A checkpoint, especially 117’s polyphony fixture/consumer and 118’s ApplicationSession, precedes this task. Rebase PianoGrid and shell-grid input over 112; EditorSurface/TrackHeaderBand over 114; retain 109’s mounted tooltip and 105’s tick ceiling. Group B 121 does not write ApplicationSession or any file listed here.

# Interface contract

- Geometry A002/A003/A004/A049 retains positive lead pad, tick-zero content offset within 0.5 and the original default pixels-per-beat. A048 preserves ruler height through signature binding. Use the existing EditorCamera/TimeAxis/scene equations; do not add an alternate test-only ruler or hard-code device coordinates.
- At the original fallback 4/4 bar ticks, observe each painted line within the fork tolerance, at least two actual captions/bar groups, the beat-line positions, and exact lines after pan/zoom. Binding 3/4 moves the signature-dependent bar lines to the independently computed ticks while ruler height stays unchanged (A052–A054). Expected tick locations, font-size ratios and palette ink/backdrop come from the fork and fixture, not scene primitives. Include the negative/old-position samples where the original requires moved bars.
- The production editor is installed only after load. Use a real loaded song without an explicit signature for its fallback 4/4 journey; do not resurrect the deleted fresh/MIDI-only partially-ready tab to close the old setup context. A006/A007/A008 are the obsolete embedded QQuickWindow color/alpha/resize representation; retain an opaque real shell/ruler background observation, but do not equate different window ownership. A033/A038/A051 retire only native capture validity, paired with successful exact raster consumers.
- Presentation A007/A008 observes actual header active focus. Open the existing rename field, observe visibility/activeFocus and literal Rolled, commit, reopen/cancel, then reopen for the loop-marker guard; each A009/A010/A012/A014 observes its own field state. Deliver actual keys through ShellWindow, not the editor-only drawer lane. A026 retains canonical Solo authority and the existing mute/solo checked-role/no-reset behavior; retire only the deleted QAction pointer prerequisite.
- Keep the current ApplicationSession.polyphony.onJump producer/consumer route. On a real positioned event-row click, select the losing track and exactly the last note on its key starting at or before the event tick, then reveal it in the viewport. For an unused key, report no note match but retain that track context. Full MIDI bytes and history index/count remain unchanged for both hit and miss. Pair registered runPresentationChecks domain evidence with the actual mounted shell-polyphony row; extend the existing probe only to supply audio snapshots to the real session presenter, never to fake a click or expected selection. A017’s no-notes fixture guard is representation, not a new nonempty assertion.
- Run the ruler pixel helper in normal shell-note-visuals and from its already-registered test_dpr2SmallFontThinning child, asserting physical DPR2. Keep existing small-font thinning predicates intact. No ShellQmlTests.swift edit is needed or allowed here; task 119 owns that file for the separate drawer child.

# Implementation steps

1. Complete registered geometry/presentation predicates for fallback, signature binding, rename lifecycle and reveal hit/miss bytes/history.
2. Extend real shell-grid-input rename/focus and shell-polyphony event-click routing journeys, preserving 117’s fixture exact-content expectations.
3. Add exact ruler raster targets to shell-note-visuals and its existing DPR2 callback; do not create a standalone fake ruler.
4. Repair only selected current owners; the separate ledger writer conditionally deletes geometry/presentation ledgers after all selected and pre-existing native obligations are settled.

# Acceptance predicate

The registered roll domain suite proves exact selection/history/bytes, shell-grid-input observes real rename focus, shell-polyphony proves the click-to-roll consumer, and shell-note-visuals proves exact ruler pixels at normal DPR and physical DPR2. Every original behavioral clause remains distinct from deleted fresh-window/capture representation.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-note-visuals --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-polyphony --verbose
```

# Task-specific constraints

No ShellWindow, ShellQmlTests, codec, core document/history, typography owner or fixture-file edits. Preserve 118’s complete-state transaction and 119’s separate DPR2 registration; do not change the global shortcut dispatcher or add a new reveal gesture.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
