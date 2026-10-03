# Task 143 brief — drawer track commands and tempo-range selection reach the editor model

# Context

Complete the hostadapter drawer-to-model surface: the `S`-key solo toggle,
`moveTrack` with empty-lane remap, the tempo-range drag selection and the
automation/voice band geometry that frames them. Each clause already has a
Swift owner (`soloedTracks`, `moveTrack` with `trackRemap`,
`AutomationTimeSelection`, canvas rows); none has an executed predicate. The
centring policy, the unported loop-marker raster and the same-pass
publication residues are explicitly out of scope below.

Selected **14 open rows (14 GAP + 0 PARTIAL)** across two ledgers. Citations
are assertion-start lines at `fceecd88`, grouped by fork test.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A147 | `src/checks/host/tst_hostadapter.cpp:538` — `automationTempoRangeDelegatesTheSelectionScope` |
| A148, A149, A150, A151 | `src/checks/host/tst_hostadapter.cpp:549,550,551,552` — same test |
| A172, A173, A174, A175 | `src/checks/host/tst_hostadapter.cpp:635,642,643,644` — `drawerSoloAndTrackRemapReachTheHost` |
| A177, A178 | `src/checks/host/tst_hostadapter.cpp:660,661` — `voiceChangesRefreshWithoutInvalidatingAutomationRaster` |
| A182 | `src/checks/host/tst_hostadapter.cpp:674` — same test, model conjunct only |
| A006, A010 | `src/checks/host/tst_hostseams.cpp:58,62` — `automationPlotFillsHostViewport` |

# Exact write set

- `src/checks/automation/automationselection.swift` — tempo-range selection
  predicates (runs inside `runAutomationPageChecks`, projectSession suite).
- `src/checks/trackheaders/TrackHeadersChecks.swift` — solo, moveTrack and
  empty-lane predicates.
- `src/swift/app/drawer/automation/AutomationPage.swift` — conditional, only
  if the tempo-range application fails at its boundary.
- `src/swift/app/drawer/automation/AutomationProjectionCache.swift` —
  conditional, only if the canvas-rows clauses fail at its
  `rows(session:track:selection:)` boundary.
- `src/swift/app/roll/NoteCommands.swift` — conditional, only if the `S`-key
  solo toggle fails at its `toggleSolo` boundary.
- `src/swift/app/DocumentSession+Internals.swift` — conditional, only if the
  empty-lane remap application fails at its adoption boundary.
- `src/checks/host/proof.tst_hostadapter.txt`, `src/checks/host/proof.tst_hostseams.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 124 (automation lane ownership) before reusing
`automationselection.swift`; preserve its lane/MIME rows and messages.
Accepted 137 (band geometry) before reading published section geometry;
preserve its geometry predicates and never reintroduce host root-property
aliases. No interface depends on the unselected centring policy (A079).

# Interface contract

Preserve `AutomationTimeSelection` (`isActive`, `Scope.lanes`, `tempo`,
`lanes`), `DocumentSession.soloedTracks` with `.mixState` publication,
`SongDocument.moveTrack(_:to:)` with `trackRemap`, and the published section
geometry 137 proves. New predicates observe, through production input and
model APIs:

- Tempo-range drag: with the tempo parameter activated, a right-button drag
  from the lane body's vertical center spanning the fork's 12 px lands inside
  the tempo lane and publishes a time selection that is active, scoped
  `.lanes`, tempo-flagged and with an empty lane list; the activated lane
  body rect is nonempty. No tick literal is asserted — none appears in the
  selected clauses (A147–A151).
- Solo key: delivering the fork's `S` key through the production key path
  solos the primary track (`soloedTracks` contains it with `.mixState`
  publication); the audio solo mask follows from the existing workspace
  reaction, which this task does not modify. The mounted shell-tabs-close
  `S`-key journey stays corroboration only, not row evidence (A172).
- Move remap: with lane `{track 0, controller 74}` flagged empty,
  `moveTrack(0, 1)` succeeds and the published view state flags
  `{track 1, controller 74}` while no longer flagging `{track 0,
  controller 74}` (A173–A175).
- Band stability: with Automations and VoiceChanges visible, both band
  geometries are present; a voice change with the played sample at the fork
  tick 24 leaves the automation canvas rows exactly equal to the stated
  seeded expectation below (A177, A178, A182).
- Lane geometry: the automation band geometry is present, and the tempo lane
  body occupies the published automation plot rect at the origin with the
  independently derived base-font/180-height size (fork section height 180),
  observed through the canvas rows and 137's body-follows-geometry probes
  (A006, A010).

# Implementation steps

1. Fix the camera inputs (seed base-font size, default zoom/offset) and
   compute the tempo lane rect from base-font layout plus the fork's 180
   section height; drive the right-button drag through `AutomationPage`
   production pointer input from the lane-body center with the fork's 12 px
   span; assert the four selection conjuncts with fork literals.
2. Deliver `S` through the existing key authority to the primary track and
   assert `soloedTracks`/publication; exercise `moveTrack(0, 1)` with the
   fork's `{track 0, controller 74}` empty-lane seed and assert the remapped flags.
3. Seed automation nodes with fixed (parameter, tick, value) literals and
   state the complete expected canvas rows explicitly from those seeds;
   apply the voice change with the tick-24 played sample and assert the rows
   equal the stated expectation and equal the pre-change rows; assert band
   geometry presence and the lane-body rect equality from step 1's derived
   geometry.
4. Repair only the named owners at their boundaries; no new key dispatcher,
   synthetic forwarding, or test-only observation API.

# Acceptance predicate

Drawer track commands and the tempo-range drag publish exact editor-model
state through production input paths.

Under sprint-3 §16 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
```

# Task-specific constraints

A182 selects only the `automationRowsEqual` model conjunct; the
`captureQuickBand` pixel conjuncts in that test are image obligations and
stay open. Lane/flag literals (`{track 0, controller 74}` → `{track 1,
controller 74}`, `.lanes`, tempo) come from the fork, never from fixture read-back. Leave open: A079
centring policy, A140 loop-marker raster (unported feature), all
same-GUI-pass PARTIAL residues, removed root-property rows and native
tooltip/cursor conjuncts. Read sprint-3 §16 for shared constraints,
excluded rows and conditional native retirement.
