# Brief 06 — Delete unreachable QML files + repoint the track-headers pane

## Context

Finding D (audit §2), membership re-verified: five `src/ui` QML files
(≈1,238L) are neither module-registered (`CMakeLists.txt:211-268`), nor
contentUrl-loaded, nor referenced by anything live; `quick/TrackHeaderBand.qml`
(772L) is a stale duplicate of the registered production file
(`swiftroll/TrackHeaderBand.qml`, `CMakeLists.txt:238`). The only live
reference to the duplicate is a **metadata string** in the editorqml lane —
`EditorQmlTests.swift:90` compares `component:` for pane identity and never
loads the path; the pane's captures already render the production copy via
`EditorSurface.qml:150`. This task deletes the dead files and points the
metadata at production so the lane names what it actually captures.

## Exact write set

- delete `/src/ui/songview/quick/TimelineCanvas.qml` (643L)
- delete `/src/ui/songview/quick/DrawerChromeLayer.qml` (267L)
- delete `/src/ui/songview/quick/RulerControls.qml` (207L)
- delete `/src/ui/songview/quick/QuickPopupLayer.qml` (61L)
- delete `/src/ui/songview/quick/OtherStripToolTip.qml` (60L)
- delete `/src/ui/songview/quick/TrackHeaderBand.qml` (772L)
- edit `/src/checks/editorqml/EditorQmlTests.swift:90` — `component:`
  becomes `"src/ui/songview/quick/swiftroll/TrackHeaderBand.qml"`
- edit `/src/ui/songview/quick/EventListPage.qml:26` — delete the stale
  comment referencing `TimelineCanvas` (AGENTS: stale comments go when their
  file is touched by this change's blast radius; this is the one live-file
  comment naming a deleted file)
- same-commit anchor repairs in `/src/checks/**/proof.*.txt` (see steps)

## Prerequisites

02 (guard B0 names the six files), 04. Parallel with 05/07/08 (disjoint).

## Interface contract

Production behavior is unchanged: none of the six files is compiled into any
target (verified: absent from `CMakeLists.txt`; `run_checks.ts` stages no
QML; `macdeployqt`'s `qmldir` scan at `release.yml:87,162` merely loses dead
files). The editorqml `track-headers` pane identity string changes to the
production path; `drawnRoot` stays `"timelineQuickTrackHeaders"`.

## Implementation steps

1. Delete the six files.
2. Repoint `EditorQmlTests.swift:90`; change nothing else in the file.
3. Delete the `EventListPage.qml:26` comment line only.
4. **Ledger anchors (same commit):** search `src/checks/**/proof.*.txt` for
   `Anchor:` lines whose path resolves into the six deleted files
   (candidates from the sweep: `proof.trackheadermenu.txt`,
   `proof.trackheadermutations.txt`, `proof.trackheaderraster.txt`,
   `proof.drag.txt` mention `TrackHeaderBand`; `proof.drag.txt` A025-A040
   contrast `EditorSurface.qml` vs the mounted band). For each such anchor,
   re-point to the `swiftroll/` production path when the anchored symbol
   exists there; if the anchored symbol exists only in a deleted file, mark
   that row `RETIRED-REPRESENTATION` with a one-line reason naming the
   deleted file. Prose `Mapping/reason` mentions stay untouched (workflow
   forbids cosmetic ledger edits).
5. Local inspection: grep the six basenames across `src/`, `CMakeLists.txt`,
   `deno.json`, `tools/` — remaining hits must be prose-only (ledger text,
   historical comments in `src/checks/rollqml/tst_SwiftRoll*.qml`).

Edge cases: if an `Anchor:` line points at
`src/ui/songview/quick/TrackHeaderBand.qml` with a line number that has no
corresponding symbol in the swiftroll copy, prefer `RETIRED-REPRESENTATION`
over guessing a mapping.

## Acceptance predicate

NAMED CHECKS (controller): `deno task build:checks` green (CMake never
listed these files); `deno task verify:bridge` reports zero
`UNREACHABLE_QML` findings under `src/ui`; `deno task verify:qml --verbose`
green — the `track-headers` reference pane captures and validates against
the repointed identity; `deno task proof check` resolves every anchor (no
unresolved-anchor output for the touched ledgers).

## Task-specific constraints

- This brief touches `src/checks/editorqml/EditorQmlTests.swift` (check
  source, not a ledger) and performs same-commit anchor repairs in
  `src/checks/**/proof.*.txt` per `proof-ledger-workflow.md`'s allowed
  case. No other ledger rows change; note: `.omp/rules/ledger-delegation.md`
  does not exist; the workflow rule governs (plan.md Global constraints).
- Ruling on ledger prose: `evidence/deletion-safety.md` recommends rewording
  four GAP rows whose reason text names `TimelineCanvas.qml`/
  `RulerControls.qml` as the unmounted host
  (`themelayout/proof.tst_themelayout_settings.txt:161`,
  `automation/proof.automationpointmenus.txt:784`,
  `automation/proof.ccdeleteconfirmation.txt:856`,
  `visual/proof.quick.txt:50`). Overruled at plan time:
  `proof-ledger-workflow.md` forbids cosmetic rewording outside the surface
  being proved, and the rows stay historically accurate (the files were
  unmounted; now they are deleted). Reviewer may revisit only if a row's
  reason becomes actively misleading about current behavior.
