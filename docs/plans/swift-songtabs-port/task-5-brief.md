# Task 5 — Tab scenarios in swiftrollgated

## Context

Ports the prototype's eight `songtabs_smoke` scenarios onto the production
gate. Source: `swift-qml-songtabs-integration`'s
`src/checks/swiftgridprototype/songtabs_smoke.cpp`. The production harness is
`src/checks/swiftrollgated/` driving `RewriteWindow` + the real session.

## Exact write set

- `src/checks/swiftrollgated/tst_swiftrollgated.cpp` (new test slots + fix
  `failedOpenPreservesSceneAndSurfacesError` at ~337-359)
- `src/checks/swiftrollgated/tst_swiftrollgated.h`
- `src/checks/swiftrollgated/tabchecks.cpp` (new — scenario bodies, matching
  the existing gesturechecks/clipboardchecks/chromevisuals/notevisuals split)
- `src/checks/swiftrollgated/clipboardchecks.cpp` (fix ~437-450)
- `src/checks/swiftrollgated/gesturechecks.cpp` (fix ~564-568)
- `src/checks/swiftrollgated/CMakeLists.txt` (register tabchecks.cpp)

## Broken call sites to re-express (string-based invokeMethod — compile clean,
fail at run time)

- `clipboardchecks.cpp:437-445` and `gesturechecks.cpp:564-568`: two-arg
  `openSong(label, bool)` no longer exists; re-opening the selected label is
  an in-place reload, and the QQuickView persists across tab closes. Assert
  the presented grid/revision changed, not that the view was recreated.
- `tst_swiftrollgated.cpp:337-359` (`failedOpenPreservesSceneAndSurfacesError`):
  under the tab model a failed re-open installs no tab — assert zero tabs,
  `songOpen` false, `lastSaveError`/`openFailed` surfaced.

## Prerequisites

- Tasks 1–4 landed: tabbed session, strip QML, window wiring.

## Interface contract

New `SwiftRollGatedTest` slots (names mirror the prototype scenarios):

- `songTabsGeometryAndSelection` — strip height/margins/close extent vs
  production metrics; selection follows `selectedId`.
- `songTabsScrollControlsAndGridInput` — overflow arrows enable/disable at
  bounds; strip doesn't steal grid input.
- `songTabsOpenCreatesIndependentWorkspace` — second `openSong` appends a tab
  with its own grid/document.
- `songTabsSwitchPreservesPageState` — camera/selection/undo survive a
  switch away and back (persistent Repeater pages).
- `songTabsPointerReorderPreservesIdentities` — drag reorder keeps
  `songTab_<id>` ↔ session pairing (genuine moveRows).
- `songTabsBackgroundClosePreservesActive` — closing a non-selected tab
  doesn't touch the active page.
- `songTabsDirtyCancelDiscardSave` — dirty close → dialog; Cancel keeps the
  tab; Discard closes; Save writes then closes.
- `songTabsFinalCloseEmptyAndReopen` — last close leaves blank page + empty
  strip; a later `openSong` works.
- `songTabsReopenExistingFocusesTab` — `openSong` on an open label selects
  its tab instead of duplicating.

## Implementation steps

1. Read `songtabs_smoke.cpp` for scenario steps and the existing
   `swiftrollgated` helpers (window spin-up, `findChild` by objectName,
   pointer helpers) for the production driving pattern.
2. Implement the nine slots using real pointer input where the prototype did;
   object names are the frozen `songTab*` set.
3. Multi-song fixture: the harness already stages `mus_route101`; check the
   fixture catalog for a second playable song in the same project and use it
   (extend `fixtureFiles` in `checkcatalog.cpp` only if the staged project
   lacks one — name the addition in the report).

## Acceptance predicate

`deno task verify --filter swiftrollgated --verbose` — all nine new slots
plus the existing suite PASS. Native-input scenarios need a quiet desktop;
run sequentially.

## Task-specific constraints

- Real pointer input for select/close/reorder (no direct controller calls
  for those paths; controller calls are allowed for fixture setup only, as in
  the prototype).
- No test-only production hooks; drive through `RewriteWindow` + QML object
  names.
- Dirty state must be produced by a real edit through the session, not a
  property poke.
