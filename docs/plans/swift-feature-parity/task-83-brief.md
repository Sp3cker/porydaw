# Task 83 brief — cross-tab drawer commands and durable editor preferences

# Context

Complete the mounted drawer's A/V/P and hide/resize journeys across two songs,
then prove the complete stored chrome-and-lane preferences survive malformed
lane data. This is not a new global ViewState class or a lane-remap project.
Task 84 consumes the resulting durable drawer preferences during real restart.

Freeze: HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`; oracle `fceecd88`.
**Rebase after 81 lands**: it owns `tst_ShellWindow.qml`; preserve its Insert
Time journey and A093–A119 input-ledger ownership.

1. **Verified census: 31 open rows (25 GAP, 6 PARTIAL)**, read with
   `deno task proof sites <ledger> --status GAP|PARTIAL` and `--offset 20`:
   - `mainwindowrouting/proof.tst_mainwindowrouting_state.txt`: PARTIAL
     **6** — A019, A021, A025, A053, A054, A055; GAP **13** — A014, A017,
     A018, A027, A028, A034, A035, A036, A039, A040, A042, A043, A057.
   - `workspace/proof.selftest_workspace.txt`: GAP **12** — A003, A004,
     A005, A006, A007, A013, A020, A021, A023, A032, A034, A036.
   Target **29 behavior rows and 2 representation retirements**. A005/A007
   call only `compactJsonObject(laneBlob(reloaded))`: the fork helper pins JSON
   whitespace/object encoding, already superseded by complete value round-trip
   through the Swift codec. Retire those two inside this preference surface;
   do not add serialization-style tests or an aggregate production test seam.
2. **Fork laws**, read with `git show fceecd88:<path>`:
   - `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp`,
     `drawerFanout`, `eventListGating`, `drawerFocusFollowsFallback`,
     `hideRetains`, `tabSwitchRefocus`: hide-all mirrors to the sibling;
     A/V/P publish visibility and active page on both tabs; hiding Voice leaves
     Velocity, hiding Velocity leaves Automation; hiding does not erase stored
     heights or active page. Leaving Event List re-enables all three commands.
   - `src/checks/workspace/selftest_workspace.cpp`, `codecRows` and
     `livePersistenceAndFinalClose`: full and optional-height state round-trip
     for all three active pages; malformed stored lane bytes default only lane
     members, preserve drawer chrome, and are not rewritten merely by reading.
     `bareState()` changes only the three optional heights and active page from
     `fullState()`: A032 is that live transition, not wholesale lane clearing.
   - The fork's `EditorViewState` here is drawer chrome plus lane preferences;
     its `fullState` does not contain the camera. `SongView::ViewState` camera,
     cursor, grid and track lifecycle is task 84's separate contract. Do not
     follow stale ledger prose into adding camera fields to this codec.
3. **Current owners**, verified by source reads:
   - `src/swift/app/ApplicationSession.swift:630-637,808-811,1100-1124`
     loads chrome/lanes, seeds new workspaces and fans out chrome/ranges.
     Chrome and lanes deliberately have separate codec keys; preserve that
     representation instead of inventing a second aggregate authority.
   - `src/swift/app/drawer/EditorDrawer.swift:135-205` owns `chromeState`,
     `applyChrome`, `toggleSection`, `setSectionVisible`, and
     `setSectionBodyHeight`; the hub projection uses the existing silent
     restoration path. `DocumentWorkspace.swift:138-144,226-228` connects and
     mounts the same three page owners; this task does not edit that file.
   - `src/ui/songview/quick/drawer/EditorDrawer.qml:149-221` mounts each
     `drawerHandle_<section>` and delivers press/move/release through
     `beginResize`, `applyResize`, `endResize`; use that real gesture path.
   - `src/swift/app/timeline/EditorViewStateCodec.swift:28-65,71-108,132-198`
     already has every persisted lane member and both chrome/lane codecs.
     `PreferencesStore.swift:130-147` is the existing persistence boundary.
   - `src/checks/workspace/session_view_state.swift:35-81` proves selected
     chrome cases, but not all origin/sibling active-page and height outcomes.
     `editor_view_state_checks.swift:9-55,75-98` tests decoding directly and
     separate round-trips, not the complete persisted poison/read/change path.
   - `src/checks/editorqml/tst_ShellWindow.qml:178-244` already delivers real
     keys and checks sibling visibility. Origin visibility lacks a message;
     re-enabled menu rows, hide-all and page/height retention are absent.

# Exact write set

- `src/swift/app/ApplicationSession.swift`
- `src/swift/app/drawer/EditorDrawer.swift`
- `src/swift/app/drawer/EditorDrawerLayout.swift`
- `src/swift/app/timeline/EditorViewStateCodec.swift`
- `src/checks/workspace/session_view_state.swift`
- `src/checks/workspace/editor_view_state_checks.swift`
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt` — listed rows and their predicates only.
- `src/checks/workspace/proof.selftest_workspace.txt` — listed rows/predicates and removal of the obsolete compact-encoding anchor only.

Production changes are limited to a demonstrated selected-surface mismatch.
No new files, bridge probes, CMake or C++; preserve every other disposition.
`ShellWindow.qml`, `ShellPresenter.swift`,
`DocumentWorkspace.swift`, `DocumentSession.swift`, `EditorCommandRouter.swift`,
`EditorSurface.qml`, `PianoGrid.swift` and `tst_EditorDrawer.qml` are unchanged.

# Prerequisites

Tasks 79–82 have landed; rebase after 81 lands for the shared shell check. No
interface from 79, 80 or 82 is consumed. Task 84 runs after this task because it
reuses ApplicationSession, the codec and session view-state check. Parallel
placement and hot-file ownership are in sprint-3 §9.

# Interface contract

- Keep the signatures and ownership of `configurePersistence()`,
  `updateEditorChrome(_:)`, `updateEditorLaneRange(parameter:range:)`,
  `EditorDrawerPresenter.applyChrome(_:)`, `toggleSection(kind:drawerOwnsFocus:)`,
  `setSectionVisible(kind:visible:drawerOwnsFocus:)` and
  `setSectionBodyHeight(kind:height:)`. No second state authority or dispatcher.
- Preserve the distinction at `EditorDrawerLayout.swift:149-185`: toggling
  selects the toggled kind as active, even when hiding it; `setSectionVisible`
  changes visibility without changing active page. A053–A055 use the latter
  after seeding Velocity active. Do not reinterpret a menu toggle as that setter.
- A real chrome change persists chrome while retaining the lane preference
  values through the existing codec/store boundary. Reading malformed stored
  data does not normalize or rewrite it, modify song data, or add a delayed
  save. Preserve equality semantics; add no idempotence guards.
- Every stored field is checked independently: three visibility values, three
  optional heights, active page, laneHeight, laneHeights, laneRanges, emptyLanes,
  ordered hiddenLanes. Exercise each active page and the optional-height case.
  Do not assert JSON whitespace or object layout; value restoration is the law.
- Poison the actual staged settings file, synchronize and reload with a fresh
  PreferencesStore; do not settle for `decodeLanes` alone. Use the existing
  staged plist and Foundation property-list APIs in the check, not a public
  test-only data setter. Prove invalid/empty/non-object/wrong-typed lane input,
  grammar/clamps, unchanged chrome and exact unchanged poisoned data on read.
- Mounted commands must show/hide the exact section on both tabs and report the
  correct active page. Hidden section heights/page survive tab switching.
  Leaving Event List re-enables all three actual menu rows. Native QAction and
  focusWidget identity are not part of these selected predicates.
- `chromeState` is Swift-only (`EditorDrawer.swift:135-145`), not a QML
  property. Assert per-tab active page and optional stored heights in the real
  ApplicationSession Swift fixture; QML observes drawn section geometry,
  command delivery and the existing persisted active-page value. Do not add
  bridge properties solely to read internal state in a check.
- Preserve all existing behavioral check messages verbatim. The sole deliberate
  removal is “the saved lane blob is compact JSON without line breaks” at
  `editor_view_state_checks.swift:49-50`; remove, never reword, that obsolete
  encoding-style assertion and any affected anchor. Add one literal message
  per behavior clause, with origin and sibling outcomes separately. No bare
  setup-object, positive-count or copied-value assertions.

# Implementation steps

1. Add complete stored-state, optional-height and persisted-poison journeys to
   the existing codec/session checks before production edits. Record already-green
   clauses honestly; fix only a demonstrated selected-surface divergence.
2. Seed the full preferences before opening the real session. Change all three
   body heights to unset through `setSectionBodyHeight`, and select VoiceChanges
   through the existing toggle path while restoring its original visibility.
   A032 must retain every lane member and persist the exact bare chrome. No new
   aggregate setter, fake bridge observation or normalization on read.
3. Extend the real ShellWindow journey: all-hidden → A twice → V → P; observe
   both tabs after each transition, hide sections through real command rows,
   switch tabs, and exercise Event List disable/re-enable. Set heights through
   the existing resize surface using font-derived geometry, not pixel literals.
4. Prove full/optional stored states and malformed-read silence without MIDI,
   history or revision changes. Remove the obsolete compact-encoding assertion;
   do not claim mounted hidden-lane fanout from codec persistence predicates.
5. Execute the named lanes after the group settles; map only these clauses and
   retire A005/A007 with their exact fork reason in the same surface change.

# Acceptance predicate

Controller-run on the settled built tree; each invocation is capped at 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — real staged
  preferences, full member matrix, persisted poison/read, live optional-height
  reset and unchanged document/history; `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shellwindow --verbose` — actual A/V/P/menu
  delivery, both tab surfaces, hide/resize/tab switching and re-enabled commands;
  `build/proof-evidence/shellwindow.json`.

Registration: `src/checks/workspace/SessionChecks.swift:24,43`,
`src/checks/checkcatalog.cpp:107-125`, `ShellQmlTests.swift:60-61` under
`src/checks/editorqml/`. Evidence: `tools/run_checks.ts:426-434`. The controller
may run all shell lanes together via `deno task verify:shell --verbose` (about
40 s for the existing set); individual selection uses the exact filter above.

# Task-specific constraints

Incorporate sprint-3 §8 Wave constraints and §9 verification policy: **no new
C++**, Swift 6.4 idioms on touched Swift, no avoidable hot-path allocation/copy;
comments at most two lines; base-font sizing, no hard-coded pixels; WCAG AA
beats pixel parity. Window shortcuts retain priority: no second dispatcher,
synthetic forwarding, focus memory, or bare Space capture by chrome.
`Qt.callLater` coalescing and idempotence guards are banned; workarounds require
user approval. One message-anchored predicate per fork clause, existing messages
verbatim, real fixtures and no test-only seams.

Leave full live lane fanout/remap state A103–A183 and native signal-count rows
unmodified; no hidden-lane UI is invented here. Parked areas, deferred menus,
voicegroupsave savecore A016–A026 and switching A030–A046 remain untouched.
Cursor commits never seek. No new user decision is required by this surface.

# Controller verification

After fresh evidence, `deno task proof check --executed`, then separately:

- `deno task proof sites mainwindowrouting/proof.tst_mainwindowrouting_state.txt --status PARTIAL`
- `deno task proof sites mainwindowrouting/proof.tst_mainwindowrouting_state.txt --status GAP`
- `deno task proof sites workspace/proof.selftest_workspace.txt --status GAP`

Expected: 29 selected behavior rows MATCHED, A005/A007 RETIRED-REPRESENTATION;
missing behavior clauses remain open. No ledger deletion. A037's coupled
chrome-change/blob-rewrite row stays unselected; this task neither introduces
that storage coupling nor claims its compact-format conjunct.
