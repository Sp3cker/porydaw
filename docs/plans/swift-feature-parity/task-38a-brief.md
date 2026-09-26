# Context

Task-38 is split at the ownership interface: **38a (this brief) makes the
session own time-selection state with fork `EditorSelectionModel` semantics
and lands the ruler gesture laws task-35 deferred; 38b (task-38b-brief.md)
builds time/ruler menu semantics on the state 38a publishes.** Both briefs
share the hot files `RulerMenuPresenter.swift`/`EditorSurface.qml`/
`ApplicationSession.swift` and serialize 38a → 38b. Fork-main = `fceecd88`.

1. **Fork model** (`git show fceecd88:src/ui/songview/editorselectionmodel.h:23-76`
   and the full `.cpp`): one owner holds primary track, track scope
   (uint32 mask, 16 tracks), note selection, and
   `TimeSelection{startTick, endTick, scope Tracks|Lanes, lanes, tempo}`;
   `active() == endTick > startTick`. Laws:
   - `setTimeSelection` sanitizes, then an active time selection **clears
     the note selection**; `setNoteSelection(non-empty)` **clears an active
     time selection** (`.cpp` setNoteSelection/commit).
   - Sanitize (Lanes scope): drop lanes with track outside 0..<16 and
     duplicates; an active lanes-scope selection left with no lanes and no
     tempo flag is cleared entirely. Tracks scope is stored as given.
   - `applyPrimaryTrackTransition`: new primary → scope = {primary}, notes
     and time selection cleared.
   - `applyTrackScopeAdjustment`: Plain on the primary → scope = {primary},
     notes cleared, **time selection survives**; Plain on another track →
     primary moves, scope = {clicked}, notes **and time** cleared; Toggle
     add/removes the clicked track (empty result = no-op; primary dropped →
     primary = lowest set track, notes cleared, time survives); Range =
     contiguous used tracks between primary and clicked, ∪ {primary}, time
     survives. `setTrackScope` always forces the primary bit in.
   - Coverage: `timeSelectionCoversTrack` = active ∧ Tracks ∧ scope bit;
     `coversLane` = Lanes → exact lane pair, Tracks → scope bit;
     `coversTempo` = Lanes → flag, Tracks → scope == all used tracks
     (`resolvedTrackScope` intersects stored scope with used tracks).
   - `resetForSongSwap(firstUsedTrack)`: primary = first used track clamped
     0…15, scope = {primary}, notes and time selection cleared.
   - `applyRemap`: scope bits follow the remap; a deleted primary falls
     back to `min(oldPrimary, newCount-1)` clamped; a Tracks-scope time
     selection is cleared iff the primary was deleted; Lanes lanes remap
     and re-sanitize. Every mutation notifies with
     `SelectionTransition{changes, previousTrackTime, trackTime}` where
     `TrackTimeSelection = {startTick, endTick, trackScope}` (Tracks scope
     only; empty when inactive/Lanes).
   Spec ledger: `src/checks/clipboard/selectioncheck_tracks.cpp` —
   `trackScopeGesturesPreserveOrClearAtTheRightBoundary` (A001–A037),
   `coverageQueriesAndLaneScopeSanitization` (A038–A057),
   `outOfRangeTrackMasksAreIgnored` (A058–A064),
   `resetForSongSwapNotifiesExactState` (A065–A079),
   `remapPreservesMeaningfulSelection` (A080–A105).
2. **Current Swift**: `DocumentSession` owns primary/scope/notes without any
   time-selection co-motion (`src/swift/app/DocumentSession.swift:63-202`);
   time selection lives on `AutomationPage.selection`
   (`src/swift/app/drawer/automation/AutomationPage.swift:91,552-561`) and
   every consumer derives it from the automation page —
   `ApplicationSession.swift:525-535` (event-list arbiter), `:1061-1073`
   (grid closure wiring), `:1362-1408` (`EditorCommandRouter`).
   `proof.selectioncheck_tracks.txt`'s preamble names this verbatim: "the
   Swift session carries no time-selection state, so … S006–S013 are proved
   for the scope gesture only". The existing type
   `AutomationTimeSelection` (`AutomationLaneProjection.swift:212-255`)
   already mirrors the fork coverage laws — reuse it; do not add a second
   selection type or a second owner.
3. **Task-35 deferred laws** (task-35-brief.md:291-297, "Report, do not fix
   here") land here: the ruler sweep must arm at manhattan
   `>= QApplication::startDragDistance` (fork
   `timeruler_interaction.cpp:113-118`) instead of a snapped-tick change
   (`RulerMenuPresenter.swift:274-289`); the ruler right-click must defer
   the menu open to release (fork `:55-70,181-186,306-341`) instead of
   committing on press (`RulerMenuPresenter.swift:81-96`,
   `EditorSurface.qml:274-311`). Ctrl arms the fork's multi-track sweep
   (`:98`) — already correct in Swift.
4. **Fork ruler interaction laws** (`timeruler_interaction.cpp`): right
   press captures the raw unsnapped tick plus explicit-chip identity,
   never the snapped anchor; release opens the menu at the release point.
   Target establishment consumes the press coordinate: a press inside the
   active half-open interval keeps selection and cursor (no snap, no seek);
   only the cursor path (outside or no interval) clears the selection and
   commits the exact chip tick or grid-snapped background tick, which
   seeks. Left press defers until movement: below slop, release commits the
   snapped press anchor as edit cursor and seeks; at/after slop the sweep
   runs; sweep release keeps an active selection, clears an inactive one.
   The ruler sel-edge drag (`hitSelEdge`) is **out of scope** — no open
   task-38 ledger row pins it.

# Exact write set

- `src/swift/app/DocumentSession.swift` — time-selection state, sanitize +
  co-motion laws, coverage queries, transition publication, remap co-motion.
- `src/swift/app/drawer/automation/AutomationPage.swift` — `selection`
  becomes a forwarder to the session; `applyTimeSelection`/
  `clearTimeSelection` forward; content rebuild keyed off the session's
  selection publication.
- `src/swift/app/roll/PianoGrid.swift`* — delete `timeSelectionSource` and
  `onClearTimeSelection` (:73,:315-320,:731-738,:835-836); read/clear the
  session directly. *Hot file.*
- `src/swift/app/timeline/RulerMenuPresenter.swift` — sweep arms on
  `grid.dragDistance` manhattan, writes through the session; right-press
  capture split from release-time open with target establishment.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — ruler input: right
  press records, right release opens; publish press/release pointer
  positions to the presenter. *Hot file.*
- `src/swift/app/ApplicationSession.swift`* — delete the closure wiring
  (:1061-1073), router `timeSelectionActive` reads the session (:1368).
  *Hot file.*
- `src/checks/editcheck/SelectionChecks.swift` — selection-model predicates
  (transitions, coverage, sanitize, remap).
- `src/checks/rollcheck/ruler_loop_menu.swift` — presenter sweep-slop and
  deferred-open timing predicates.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — mounted regression for the
  retimed ruler open; new press/release predicates.
- Ledgers (controller-delegated ledger agent, this task's commit):
  `src/checks/clipboard/proof.selectioncheck_tracks.txt`; the
  gesture-timing rows named below in `proof.ruler_loop_menu.txt`.

`ShellWindow.qml` is not touched (menu mounting lives in EditorSurface).
Sizing exception: one behavior family over 9 files with one
verification-surface set — named for the dispatch table.

# Prerequisites

Tasks 36 (hot-file settle) and 37 (`ApplicationSession.swift` co-editor).
Consumes task-34a's session-owned `RollGrid`, task-35's published
`PianoGrid.dragDistance` (:129) and roll right-gesture interlock. Task-42
and task-49 depend on this brief's `session.timeSelection` interface only.

# Interface contract

- `DocumentSession.timeSelection: AutomationTimeSelection?` (private(set)),
  plus `applyTimeSelection(_:)` / `clearTimeSelection()` implementing the
  fork laws in Context ¶1: sanitize (drop lane parameters whose track is
  outside 0..<16 or nil-tempo-only; an active lanes-scope selection with an
  empty remaining lane set and `tempo == false` becomes nil); an active
  stored selection clears the note selection; equal values publish nothing.
- Co-motion in `adjustTrackScope`/`setSelectedNotes`/primary transition
  exactly as Context ¶1 (Plain-elsewhere clears time; Plain-on-primary,
  Toggle, Range preserve it; a non-empty note selection clears an active
  time selection).
- `timeSelectionCoversTrack(_ track: Int) -> Bool` and
  `timeSelectionCoversTempo() -> Bool` resolve against used tracks per the
  fork coverage laws; parameter/lane coverage stays on
  `AutomationTimeSelection.covers`.
- `struct SelectionTransition { previousTrackTime: TrackTimeSelection,
  trackTime: TrackTimeSelection }` with
  `TrackTimeSelection{startTick, endTick, trackScope: Set<Int>, active}`
  (active = Tracks scope ∧ selection active). Published through
  `session.onSelectionTransition` on every selection change, alongside the
  existing `[.selection]` domain publication — the ledger's transition
  payloads pin this record.
- Track-remap handling gains the fork `applyRemap` co-motion (scope mapped,
  deleted-primary fallback, Tracks-scope time selection cleared iff primary
  deleted, lanes remapped + re-sanitized).
- `RulerMenuPresenter`: `beginSweep(contentX:modifiers:)` unchanged in
  signature; the sweep arms when `|dx|+|dy| >= grid.dragDistance` from the
  press point (pointer y included, manhattan) and only then applies
  snapped-tick range updates through `session.applyTimeSelection`; a
  below-slop release commits the snapped press anchor as edit cursor and
  calls `onSeek`. New `captureRulerPress(contentX:pointerY:)` records raw
  tick + explicit-chip tick; `openRulerAtRelease()` performs target
  establishment (Context ¶4) and builds the existing two menu shapes with
  unchanged rows, labels, and ids. `sweepTrackScope` keeps the Ctrl law.
- Clean cutover: no closure shims, no dual ownership; every former
  `automationPage.selection` reader reads the session (directly or through
  the forwarder).

# Implementation steps

1. RED: extend `SelectionChecks.swift` with the selection-model predicates
   (anchors below); add the two presenter timing predicates to
   `ruler_loop_menu.swift`. Record RED.
2. `DocumentSession`: state, sanitize/co-motion, coverage, transition
   publication, remap co-motion.
3. `AutomationPage` forwarder + rebuild wiring; delete its stored selection.
4. Migrate readers: PianoGrid, RulerMenuPresenter sweep path,
   `EditorCommandRouter`, ApplicationSession wiring deletion.
5. Ruler input restructure (presenter capture/release + EditorSurface
   press/release plumbing; sweep slop law).
6. GREEN on the lanes below; mounted sweep/menu regressions stay green.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — selection-model
  predicates (SelectionChecks), presenter timing, all existing suites.
- `deno task verify:shell --filter shell-grid-menu --verbose` — mounted
  sweep + menu regression; new deferred-open predicates.
- `deno task verify:shell --filter shell-grid-input --verbose` — task-35
  pointer laws unaffected.
- `deno task verify:shell --filter shell-clipboard --verbose` — selection
  consumers regression.
- `deno task verify:qml-roll --verbose` — EditorSurface touched.
- `deno task verify:bridge`

# Task-specific constraints

- No new C++; no code comments; no pixel constants (slop =
  `grid.dragDistance`, already style-hint-fed); menu labels/ids unchanged
  (task-46 normalizes labels); menu enablement/retirement semantics belong
  to 38b — do not pull them in.
- Implementers never edit ledgers. Ledger mapping (agent, re-verify each
  row against the landed predicates at freeze):
  - `proof.selectioncheck_tracks.txt`: rewrite the preamble (root cause
    fixed). A001–A005 stay MATCHED on S001–S005. A006–A037 → the new
    `clipboardTrackSelectionChecks` anchors: "plain on another track clears
    the time selection", "plain on the primary track preserves the time
    selection", "toggle hands primary to the surviving track" (upgrades the
    S006 PARTIAL precondition), "range expands inclusively from primary to
    target", "a note selection clears the active time selection", plus
    transition-payload anchors "the transition reports the previous and
    current track-time scope". A038–A057 → "coverage resolves only against
    used tracks", "an active lane selection without lanes or tempo is
    dropped", lane-sanitize anchors. A058–A064 → `RETIRED-REPRESENTATION`
    ("uint32 scope-mask bits; Swift stores `Set<Int>` and its gesture API
    cannot write out-of-range tracks"). A065–A079 → the fresh-session/
    reset anchors ("song swap resets primary scope and clears both
    selections"; rows pinning in-place rebinding of one live model map to
    per-tab session creation, else RETIRED-REPRESENTATION "per-tab
    DocumentSession; no in-place song rebind"). A080–A105 → "remap moves
    the stored scope", "a deleted primary clears the track-scoped time
    selection", "lane scopes remap and sanitize".
  - `proof.ruler_loop_menu.txt`: only the deferred-open/slop/timing rows
    this task's predicates execute (S-anchored messages
    "the ruler menu opens at the release point", "the ruler sweep arms at
    the drag distance", "a below-slop ruler release commits the snapped
    anchor", "a press inside the interval keeps the selection and cursor",
    "a press outside commits the cursor and clears the selection"); all
    menu-semantics rows stay untouched for 38b.
  - Blocked rows left untouched: any row the freeze re-verification cannot
    execute (none known).

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`,
   `deno task proof check --strict-mappings`.
2. Visual (desktop smoke): sweep the ruler left-drag — band highlights only
   after ~10 px of travel, not on the first snapped-tick change; Ctrl+sweep
   extends the highlighted tracks; release keeps the band; click without
   travel moves the edit cursor; right-press then release outside a band
   commits the cursor and opens the cursor menu at the release point;
   right-release inside a band opens the selection-scoped menu with cursor
   and selection untouched.
