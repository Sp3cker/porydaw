# Task 73 brief — editor drawer chrome/resize close-out (focus-fallback journey + representation residue)

# Context

Task 73 closes the editor-drawer chrome/resize ledger
`src/checks/drawerpresentation/proof.drawer.txt` (86 open rows, re-censused by
awk this freeze: 17 GAP + 69 PARTIAL) against the mounted editor drawer, then
deletes the ledger when every row is MATCHED or RETIRED-*. The drawer surface
is landed and extensively proven; the open rows are one real behavior family
(drawer focus fallback) plus representation residue from the retired C++
harness. Proof completion + one mounted journey; production behavior changes
only if a RED predicate exposes a real divergence.

1. **Census (awk over `Disposition:` lines, verified this freeze)**:
   - Focus-routing journey — **A143–A152 (3 PARTIAL + 7 GAP), this task's
     behavior core**: the fork's `DrawerPresentationTest::drawerFocusFallback`
     (`git show f3069ef6:src/checks/drawerpresentation/drawer.cpp:523-549`)
     walks section toggles and asserts where keyboard focus lands: hiding the
     last visible section requests and lands Roll; showing a section from
     blank chrome lands focus in the bar; showing a section while the drawer
     owns focus lands that section; hiding a section lands the first
     remaining visible section (VoiceChanges→Velocity→Automations→Roll).
     Request halves are proven — S057/S063/S064 (`drawer_state.swift`) — and
     two QML landings — S100 "hiding the only visible section returns focus
     to the roll input", S104 blank-chrome bar focus (`tst_EditorDrawer.qml`).
     The per-section QML landings (velocity page, voice-changes page,
     fallback to the next visible section) have no executing predicate.
   - Track-header rows — A170/A173 (GAP): A173 maps to the landed trackheader
     lane predicate `trackheaderinput.swift:28` "title selects primary
     track"; A170 (`input->bounds().contains(point)`) is the hit-containment
     fixture guard of that same journey.
   - Native-delivery GAPs — A010/A178 (`quickWindowIsUnmasked`), A046/A047
     (grip `cursor().shape()` delivery; production declares
     `cursorShape Qt.SizeVerCursor` on the grip), A072/A076/A171/A172
     (`mouseGrabberItem` press/release): task-71 precedent retires this
     cluster as representation.
   - Representation PARTIALs — 66 rows whose behavior halves are proven by
     S001–S114 and whose unproved halves pin retired C++ internals: object
     identity (EditorDrawer/TimelineInputItem/VelocityPage/
     VoiceChangesPage/AutomationPage/DrawerChrome/QQuickItem/
     TrackHeaderModel — A003–A007, A011–A014, A032, A067, A081–A082,
     A093–A095, A106, A135–A138, A154, A166–A167), optional `bodyRect`
     presence (A040–A042, A068, A073, A083–A084, A087, A089–A090, A103,
    A107, A110, A113, A115, A117–A118, A121), `QRectF`/geometry containment
    (A059–A062, A065–A066, A075, A153, A174–A177), native visibility flags
    (A038, A175), `QPalette::Highlight` identity (A016, A037 — behavior is
    the shared palette selection ring, S093), `layout::singlePixel` chrome
    border (A015 — S001 asserts the resolved hairline 1), drawer scrollbar
    strip absence (A063), `EditorViewState` struct equality (A128/A129 — the
    Swift owner records preference change-sets; stored-height restore is
    S046 and persistence is session-owned since task 65), roll-band geometry
    internals (A156/A157), and the exact 16-row header count
    (A169 — a trackheader-lane fact).
2. **Swift current state — production landing exists, predicates do not**:
   the drawer is mounted through `EditorSurface.qml:1153` (presenter) and
   `:1203-1207` (section state); `EditorDrawer.qml:115-128
   executeFocusRequest()` resolves the presenter's `focusTarget` to the
   loaded page item (`loader.item.forceActiveFocus`) or the roll input.
   `tst_EditorDrawer.qml` `test_focusReturnAndPageCancellation` (S100) and
   `test_productionDrawerBlankBarFocus` (S104) are the two landed cases.
3. **Family boundary**: `proof.velocity.txt` (57 open) and
   `proof.valueprompt.txt` (5 open) belong to their landed velocity/valueprompt
   surfaces — untouched here.
4. **Overlap ruling**: tasks 68/69/72 (in flight) own `ShellWindow.qml`,
   `ShellPresenter.swift`, `ApplicationSession.swift`, `tst_ShellWindow.qml`,
   `tst_ShellMenus.qml`, `tst_ShellClipboard.qml`, `PianoGrid.swift`,
   `SongTabs.qml` — none in this write set. Task 71 (landed) was the last
   writer of `tst_EditorDrawer.qml`; re-snapshot the file at freeze.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawer.qml` — append-only mounted
  focus-fallback journey function(s) covering the fork's full toggle walk.
- `src/checks/drawerpresentation/drawer_state.swift` — only if the journey
  exposes a request-half without an executing predicate (expected: none;
  S057/S063/S064 already cover the requests).
- Contingent production: `src/ui/songview/quick/drawer/EditorDrawer.qml`
  (and `src/swift/app/drawer/EditorDrawer.swift`/`EditorDrawerLayout.swift`
  only if the policy itself diverges) — only for a RED journey predicate.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips in `src/checks/drawerpresentation/proof.drawer.txt` and its
  deletion once every row is MATCHED or RETIRED-* (its C++ original is
  already gone from disk).

No `proof.velocity.txt`/`proof.valueprompt.txt` rows, no in-flight-owned
files, no `src/checks/trackheaders/` edits (cross-cite only).

# Prerequisites

None. Free-parallel with tasks 74/75/76 (disjoint write sets; this task owns
the only `tst_EditorDrawer.qml` edits in the wave).

# Interface contract

- New mounted anchors (message-anchored, one per fork landing clause; the
  `message:` strings are the ledger anchors and stay verbatim once written):
  - "showing a section from blank chrome lands focus in the bar" (A145;
    A146's no-focused-band half joins it).
  - "showing a section while the bar holds focus lands focus in that
    section's page" (A147, the velocity case).
  - "an explicit section focus request lands in that section's page"
    (A149, the voice-changes case).
  - "hiding a section lands focus in the first remaining visible section"
    (A150/A151; the walk VoiceChanges→Velocity→Automations exercises it
    twice).
  - Roll landings (A144 after the explicit request, A152 after hiding the
    last section) stay S100; blank-bar focus stays S104 (A146's other half).
- Journey semantics (fork `drawerFocusFallback`): real toggle activations on
  the mounted drawer; focus asserted through QML `activeFocus` on the bar,
  the loaded page's focus item, and the roll input; the request halves
  (first-remaining-visible target, shown-section target, roll request)
  re-asserted beside each landing only where the existing S057/S063/S064
  predicates do not already execute in the same journey.
- Row dispositions (ledger agent; each fork-verified at `f3069ef6`):
  - MATCHED: A143–A152 → the four new anchors + S100/S104; A173 →
    `src/checks/trackheaders/trackheaderinput.swift:28` "title selects
    primary track" (executed; cross-file cite).
  - RETIRED-REPRESENTATION (one-line reason citing the proven behavior half):
    A170 (hit-containment fixture guard of the trackheader journey) and the
    74-row residue — 66 PARTIALs (identity/bodyRect/containment/flag/
    palette/border/view-state/roll-band/count clusters above) + 8 native
    GAPs (A010/A178 unmasked-window property of the retired native harness;
    A046/A047 engine-native cursor delivery with the declared grip
    `cursorShape` as the registered deviation; A072/A076/A171/A172 native
    `mouseGrabberItem` delivery).
- Preservation contract: every existing check message in touched files stays
  verbatim; `drawer_basics.swift`/`drawer_resize.swift`/
  `EditorDrawerChecks.swift`/`other_events_band.swift` are untouched;
  production drawer geometry/layout/resize policy unchanged unless a RED
  predicate proves divergence (record RED→GREEN for that fix only).

# Implementation steps

1. Re-verify mounts and the request/landing split at freeze:
   `EditorSurface.qml` drawer mount, `EditorDrawer.qml:115-128`, S057/S063/
   S064 anchors in `drawer_state.swift`, S100/S104 functions in
   `tst_EditorDrawer.qml`.
2. Write the mounted journey (append-only function): hide all three sections
   → roll focus; show Automations → bar; show Velocity → velocity page; show
   VoiceChanges + explicit request → voice page; hide VoiceChanges →
   velocity page; hide Velocity → automation page; hide Automations → roll
   input. Real pointer activations on the mounted drawer; font-derived probe
   points only.
3. Classify any RED: harness artifact → fix the predicate; behavior gap →
   stop, report, minimal production repair inside the contingent write set.
4. Produce the rowMap (row id → disposition → anchor file:line or retirement
   reason) for the controller's ledger agent; fork-verify each retirement
   cluster against `git show f3069ef6:src/checks/drawerpresentation/drawer.cpp`.
5. Run the lanes below.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml --verbose` — the new focus-fallback journey plus all
  existing drawer-lane regressions.
- `deno task verify --filter swiftcore --verbose` — drawer_state regressions.
- `deno task proof check --executed` — every new anchor executes.
- Runtime prerequisite: macOS for the QML lane.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions.
- One message-anchored predicate per fork landing clause; real pointer input
  through the mounted scene; no synthetic forwarding, no focus memory — the
  journey reads live `activeFocus` only.
- No hard-coded pixel constants — probe points derive from published drawer
  geometry; WCAG AA beats parity where they conflict; visual parity with the
  fork at `f3069ef6`.
- `tst_EditorDrawer.qml` additions are append-only functions; no existing
  test or message changes.
- Implementers never edit ledgers; the controller's ledger agent flips
  A143–A152 → MATCHED (new anchors + S100/S104), A173 → MATCHED
  (trackheaderinput cross-cite), and the 75 residue rows →
  RETIRED-REPRESENTATION, then deletes `proof.drawer.txt` in the same commit
  only when every row is closed. `proof.velocity.txt`/`proof.valueprompt.txt`
  rows are untouched.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`; `deno task proof sites --area
   drawerpresentation --status GAP` / `--status PARTIAL` shows only
   `proof.velocity.txt`/`proof.valueprompt.txt` rows remaining (drawer ledger
   deleted with this task's commit).
2. Confirm `deno task verify:qml` and `deno task verify --filter swiftcore`
   are green at the settled tree; the focus journey appears in the drawer
   lane output.
3. If the contingent production path fired: also run
   `deno task verify:shell --filter shell-drawer-parity --verbose`
   (the lane mounts the production drawer) and confirm the RED→GREEN record.
