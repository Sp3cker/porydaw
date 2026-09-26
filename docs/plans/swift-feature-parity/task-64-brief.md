# Context

Task 64 — event views: bucket projection + chrome/edits/remap. Close the eventviews
family (226 open rows) on the mounted Event List page and delete its four ledgers.
Task 39/39b landed the row menu, same-tick drag, delete matrix and drawer-focus
journeys; this task builds on that surface. Fork-main = `fceecd88` (fork check
sources already deleted; read with `git show fceecd88:<path>`).

1. **Census (verified this freeze)**: viewbuckets_grid 26 (18 GAP, 8 PARTIAL —
   A002/A003/A005–A008/A011/A023), chrome 117 (107 GAP, 10 PARTIAL — A012/A013/
   A015–A018/A023/A024/A043/A044), edits 56 (31 GAP, 25 PARTIAL), remap 27 GAP.
   Stale-preamble correction (task-52 pattern): most chrome GAP reasons say
   "presenter-level Swift cannot establish it" — the shell lane CAN: the page is
   mounted (`EditorSurface.qml` `eventListHost` Loader → `eventListPage`) and
   `tst_ShellEventList.qml` already drives real menus, drags and keys on it.
   Likewise "live column-resize drag" and "double-click cell-open" already exist
   (`EventListPage.qml:847-884` handle MouseAreas → `resizeColumn`;
   `onDoubleClicked` → `beginCellEdit`, :639) — proof gaps, not missing features.
2. **Fork bucket law** (`git show fceecd88:src/ui/songviewmodel.cpp`,
   `viewbuckets_grid.cpp:82-145`): every timeline event lands in exactly one
   bucket (M1). Basic-fixture ledger ×3 variants (ordinary / +unpaired NoteOn@100
   key 72 / +orphan NoteOff@110 key 73): notes 2/3/2, pairedOffs 2/2/2,
   lanePoints 3, voices 1, stripFromEvents 0/0/1, unpaired 0/1/0, orphan 0/0/1,
   tempoEvents 1 (synthetic tick-zero default); identity `notes + pairedOffs +
   lanePoints + voices + stripFromEvents + tempoEvents == timeline.events.size()`
   (9/10/10); `strip.size() >= otherEvents.size()`; an unpaired NoteOn projects
   as a zero-duration note (`startTick == endTick()`, :128-132); 17 chunks →
   `droppedTracks == 1` (:144-145). Swift constituents exist and are count-proved
   (`EventViewsRemapBucketsParity.swift` bucketParitySum over `document.notes(
   in:)`, `lanePoints`, `PlaybackTimeline.events/otherEvents`;
   `OtherEventsStrip.items` already emits the fork strip labels incl. `"Note off
   (key N) without a note on"`); the composition, orphan/unpaired buckets and
   identity have no predicate and no typed projection. The accounting law is the
   deliverable — not a parallel SongViewModel that would duplicate
  `OtherEventsStrip.items`' classification and `document.notes`' pairing.
   `PlaybackTimeline.droppedTracks` already exists (`PlaybackTimeline.swift:159`).
3. **Fork chrome laws** (`chrome.cpp`): track selection echoes `chunkForTrack`
   (:63-69); row mirror = chunk events + tempo rows (chunk 0 only) + 1 EOT at
   `endTick`, across Empty/EotCoincident/Basic shapes (:71-95); mono typography
   (:104-129) — QFont/QFontInfo/spacing-mode clauses are representation, but the
   double-click editor-open (:124) and the editor item's family/tracking are
   mounted-provable; resize drag = press handle center, 4 moves +40 px, release
   → persisted Type width grows > +20, store entry count unchanged (:138-160);
   drawer focus keeps navigation — Down/Up at `drawerBarInput` focus leave
   `currentRow` put, drawer keeps focus (:170-196); wheel 600 notches down →
   `contentY == maximum`, 1200 up → 0 (:198-215, Long shape); filter matrix —
   meta 3 / notes 4 / other channel 4, none 0, all 11 (+EOT), via
   `filterToggled(bit)` (:217-272); view-state round trip — flag records true
   once open, applying false hides, reads back (:274-289); filter menu session
   (:299-415) — toolbar open, 7 rows, ticks mirror CheckedRole, type-ahead `M`
   highlights Meta, hover highlights, click toggles with the menu staying open
   on a rebuilt model that restores highlight by id, Down wraps to row 0, Return
   toggles, Escape cancels, a table-cell press closes the menu and its paired
   release starts no editor; row menu (:417-487) — right-click opens on that row
   (currentRow echo), activating Insert closes first then inserts one event
   (+1 row, +1 undo), the menu retires when its context moves (different current
   row, chunk switch, document edit, selection change) while a stay-open filter
   menu survives row changes; outside-right (:489-545) — a right press outside
   the frame cancels without moving currentRow, reports the dismissed owner, and
   the paired release is swallowed (no re-entry, no editor).
4. **Fork menu key law** (`quickmenuhost.cpp:647-712`, `kTypeAheadResetMs = 1000`
   at :27): Escape cancels; Return/Enter activates `highlightedRow`; Up/Down
   move with wrap over non-separator enabled rows; printable keys without
   Ctrl/Alt/Meta accumulate type-ahead (1 s reset, search starts AFTER the
   current row and wraps, `text.startsWith(prefix, CaseInsensitive)`, a
   multi-char miss retries the last char alone). The Swift menu host
   (`EventListPage.qml:1239-1299`) handles only Escape + underlay
   press-dismiss — keyboard navigation and type-ahead are genuine production
   gaps. The underlay MouseArea (:1250-1253) already owns the paired release,
   matching the swallow laws — proof only.
5. **Fork edits/remap residues** (`edits.cpp`, `remap.cpp`): every journey
   re-opens its own fixture (journey isolation); rawTempoAtomic (:304-410) needs
   the Tempo shape (tick-zero tempo meta 0x51 "07a120" + tick-zero metas) —
   `tempoRowForExactTick(0) == 0`, tick-zero meta set equality survives both
   conversion directions, one undo step each; sameTickReorder residues =
   drop-before-run-start and pinned-note drags (refused, no undo, `!isEditing`);
   deleteMatrix residue = key-delivered Delete ingress; metadataChunkTransition
   (:151-186) = chunk selection through the rendered combo + chunk echo +
   promoted program row lookup; tempoProjectionRows (:189-199) = tick-zero tempo
   row, −1 after a track switch. Swift gaps: presenter fixtures carry no
   tick-zero tempo point (`EventListPlayheadChecks.swift` has `.basic`/`.long`
   only); the row menu never invalidates on context moves (`menuRow =
   currentRow` captured at open, `EventListMenus.swift:100-101`; no retire site
   in `EventListPresenter.swift`); no mounted chunk-combo/echo, drag-variant,
   key-Delete or wheel predicates exist. mus_route101 chunk 1 has 43 events
   (44 rows ≈ 924 px) — vertical overflow holds for the wheel clamps.
6. **Binding ruling — Event List row numbers stay**: the row-number gutter
   (`EventListPage.qml:784-931`, `rowHeaderWidth` law) and its anchor "row
   headers follow the first visible event after vertical scrolling" are frozen.
   No row in this task may be closed by removing, hiding or redesigning it.

# Exact write set

- `src/swift/app/drawer/otherEvents/OtherEventsStrip.swift` — split `items` into
  `classify(timeline:)` returning items plus typed `orphanNoteOffs` and
  `unpairedNoteOns` counters; `items(timeline:)` returns `classify().items`
  (behavior-identical; band rows stay green).
- `src/ui/songview/quick/EventListPage.qml` — menu-host keyboard law inside the
  menu Loader item (:1244-1297): Up/Down wrap, Return/Enter activate, type-ahead
  per Context ¶4.
- `src/swift/app/eventlist/EventListPresenter.swift` — row-menu invalidation
  call sites (currentRow, selection, chunk, document changes), guarded against
  the menu's own open path.
- `src/swift/app/eventlist/EventListMenus.swift` — the invalidation helper
  (`menuKind == .row` only); no menu-model shape changes.
- `src/checks/editcheck/EventViewsRemapBucketsParity.swift` — bucket composition
  block (identity, strip guard, orphan/unpaired, quirk, droppedTracks).
- `src/checks/eventviews/EventListPageChecks.swift` — filter-matrix ledger,
  row-count law, chunk echo, key-Delete, menu-invalidation and font-scan
  presenter predicates; per-journey fixture re-establishments.
- `src/checks/eventviews/EventListPlayheadChecks.swift` — new shapes `.tempo`,
  `.empty`, `.eotCoincident` (fork `fixtureSmf` verbatim,
  `eventview_fixture.cpp:47-89`); tempo-shape atomicity, tempo-projection and
  rendered-row-lookup predicates.
- `src/checks/editorqml/tst_ShellEventList.qml` — mounted journeys: resize drag,
  double-click open, wheel clamps, drawer-focus stillness, view-state flag,
  filter-menu session, row-menu activation/invalidation, outside-right swallow,
  drag variants, key Delete.
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip
  then delete `src/checks/eventviews/proof.viewbuckets_grid.txt`,
  `proof.chrome.txt`, `proof.edits.txt`, `proof.remap.txt` (fork sources already
  deleted in 67544720).

No CMake changes; none of the hot files (`ShellWindow.qml`,
`ShellPresenter.swift`, `ApplicationSession.swift`, `DocumentWorkspace.swift`,
`EditorSurface.qml`, `PianoGrid.swift`, `tst_EditorDrawer.qml`) are touched.
Sizing exception: one family over 8 files + ledgers, one verification-surface
set — named for the dispatch table.

# Prerequisites

Task 39/39b landed (its ledger notes and S256–S297 predicates are the base this
task extends). Free-parallel with 52/53/54/55 per sprint-3 §5: no shared files
with the in-flight write-sets.

# Interface contract

- `OtherEventsStrip.classify(timeline:) -> Classification` with
  `items: [OtherEventsStripItem]`, `orphanNoteOffs: Int` (orphan 0x8 events),
  `unpairedNoteOns: Int` (open-stack remainder). `items(timeline:)` unchanged in
  behavior and signature; band checks and markers untouched.
- Bucket predicates (swiftcore, `EventViewsRemapBucketsParity.swift`, reusing
  the existing `bucketSumID`), message-anchored per fork variant: "the strip
  never drops the timeline's other events" (count ≥); "orphan note offs project
  into the strip bucket" (0/0/1); "unterminated note ons stay countable" (0/1/0);
  "an unterminated note projects zero duration" (tick-100 note: unterminated,
  `endTick == tick`); "every timeline event lands in exactly one song-view
  bucket" (the identity, three variants); "a seventeenth track drops exactly one
  engine track" (17-chunk `MidiFile` → `PlaybackTimeline.build(…).droppedTracks
  == 1`).
- Menu-host keys (QML): while `controller.menuOpen`, the focused menu item
  handles `Key_Up/Key_Down` (wrap, skipping separator/disabled rows),
  `Key_Return/Key_Enter` (activate `highlightedRow`, no-op at −1), and printable
  keys without Ctrl/Alt/Meta as type-ahead (accumulate, 1000 ms reset timer,
  search starts after the highlighted row and wraps, case-insensitive label
  prefix, multi-char miss retries the last char). `Key_Escape` keeps today's
  dismissal. Highlight moves go through the existing `hoverRow` path so
  ticks/hover paint identically.
- Row-menu invalidation: when `menuOpen && menuKind == .row`, a subsequent change
  of `currentRow`, `selectedRows`, `chunkIndex`/`chunk`, or a document change
  closes the menu (`dispatchDismissMenu`). The right-click open path (which
  selects the row, then opens) must not self-dismiss — the open dispatch sets
  the menu after the selection settles. Filter and chunk menus never invalidate
  on row/selection changes.
- Fixture shapes (`EventListPlayheadShape`): `.tempo` = `.basic` primary +
  `.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])` first; `.empty` =
  single chunk, no events, endTick 120; `.eotCoincident` = one marker meta at
  tick 120 == endTick. All three carry the metadata + channel chunks verbatim.
- Mounted anchors (tst_ShellEventList.qml), message-anchored: "a track
  selection echoes its chunk through the page"; "the table mirrors the chunk's
  events plus tempo rows and one EOT"; "double-click opens the tick cell
  editor"; "a real handle drag widens the persisted column"; "the resized store
  keeps six entries"; "drawer focus keeps the event rows put"; "wheel past
  either end clamps the table"; "hiding each category shrinks the table to its
  ledger count"; "an empty mask leaves only the EOT row"; "the view state
  records the event list once visible"; "a hidden event list stays hidden across
  the tab's reload"; "showing the event list restores the flag"; "the filter
  menu opens with the seven category rows"; "menu ticks mirror the checked
  role"; "type-ahead selects the matching category"; "hover highlights the
  category row"; "activating a category keeps the session open on a rebuilt
  model"; "the rebuilt menu restores the highlight by id"; "Down wraps onto the
  first category"; "Return toggles the highlighted category"; "Escape cancels
  the filter menu without activating"; "a table-cell press while the menu is
  open only closes the menu"; "the paired release never starts an editor";
  "right-clicking a row opens its menu on that row"; "activating Insert closes
  the menu and inserts one event"; "a moved row context retires the row menu";
  "a chunk switch retires the row menu"; "a document edit retires the row menu";
  "a selection change retires the row menu"; "row changes leave the filter menu
  open"; "an outside right press cancels the menu without moving the current
  row"; "the paired right release reopens nothing"; "a drop before the run
  start refuses the reorder"; "a drop across the pinned note refuses the
  reorder"; "the Delete key removes the selected rows".
- Presenter/swiftcore anchors: "a tick-zero tempo point projects the first table
  row"; "tempo and raw conversions preserve the tick-zero meta set"; "each
  conversion is one undo step through the presenter"; "selecting a chunk through
  the rendered menu echoes the chunk"; "the promoted program event resolves to a
  rendered row"; "the tempo row leads the conductor chunk and vanishes on a
  track switch"; "move, add and duplicate report their outcomes"; "focus loss
  closes the editor with the commit landed"; "the drawer keeps focus through the
  commit and the inert Delete"; per-journey guards "the <journey> journey
  re-establishes its own fixture rows".
- Preservation contract: task-39's S256–S297 predicates, the row-number gutter,
  type/chunk menu models, `commitCellEdit` semantics, column-width laws
  (task-28), Summary-fit geometry, and every existing objectName are unchanged.

# Implementation steps

1. Bucket accounting first (proof, no behavior change): `classify` split;
   predicates per the identity block over the three parity variants plus the
   overfull file.
2. Menu-host keys + type-ahead in `EventListPage.qml` (RED first: type-ahead and
   Down/Return do nothing today).
3. Row-menu invalidation call sites in the presenter (RED first: context moves
   leave the menu open today). Guard the open path.
4. Playhead fixture shapes; tempo-shape atomicity re-runs of the task-39 clause
   set inside the new fixture; tempo-projection and row-lookup predicates;
   journey-isolation re-establishments for the tick64/tickHighBit/conversions/
   insertCopy PARTIALs.
5. Presenter predicates: filter matrix (seven bits, fork ledger counts),
   row-count law across the three new shapes, chunk echo after `selectedTrack`
   change, key-Delete matrix halves, font-scan extension (last row + columns
   2-4 family/tracking).
6. Mounted journeys on mus_route101 (`openEventListFixture` pattern) per the
   anchor list; drag variants extend task-39's
   `test_dragReordersOnlySameTickRows` delivery on the tick-0 run; wheel clamps
   drive `mouseWheel` on `eventListVerticalScrollBar` with tryCompare clamps;
   view-state flag via the View-menu toggle + tab reload (tst_ShellTabs
   precedent :1357/:1438).
7. Run the lanes; report GREEN with predicate messages + file:line for the
   controller's ledger handoff.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-event-list --verbose` — all mounted
  journeys + regressions (row menu, drag, drawer focus, typography).
- `deno task verify --filter swiftcore --verbose` — bucket identity block,
  eventedits suite regressions, session-suite playhead/presenter predicates
  (evidence `build/proof-evidence/swiftcore-eventedits.json`,
  `swiftcore-projectsession.json`, `shell-event-list.json`).
- `deno task verify:bridge`, `deno task format --check`.
- RED evidence for the two production gaps (menu keys, invalidation) and for the
  tempo-shape journeys before their predicates pass.

# Task-specific constraints

- No new C++; no code comments (delete stale ones in touched regions); no pixel
  constants — drag deltas (+40 px), notch counts and fixture ticks are
  check-side stimulus mirroring the fork's own numbers; the 1000 ms type-ahead
  reset is the fork's time constant, not geometry.
- One message-anchored predicate per fork clause; mounted proof for input
  delivery (drag, wheel, keys, clicks); presenter-level only where the mounted
  lane cannot observe. No test-only bridge seams.
- Keep `mus_route101`; no new shell fixtures or lane registrations.
- The row-number gutter stays (Context ¶6); typography/geometry/palette laws are
  frozen; WCAG pairs untouched.
- Implementers never edit ledgers; the controller's ledger agent updates the
  four proof files in the same commit:
  - viewbuckets_grid: A001/A019/A022/A026/A038 → `RETIRED-REPRESENTATION`
    (native rig/tab fixture guards; the Swift lane stages its own fixture —
    task-52 tst precedent); A002/A003/A005–A008/A011 → the identity anchors;
    A004/A009/A010 → strip-guard/orphan/stripFromEvents anchors; A012–A016 →
    quirk anchors; A017/A018 → droppedTracks anchor; A023 → representation
    (pins the native SongView-owned timeline pointer; the Swift axis is a value
    type); A047/A048/A050 → representation (paintSmoke window-grab raster of the
    deleted native lane).
  - chrome: fixture/conversion guards A005/A006/A007/A010/A011/A019/A020/A025/
    A026/A034/A035/A041/A042/A045/A046/A051/A052/A081/A082/A113/A114 →
    representation; A004 → track-echo anchor; A012 → extended font-scan anchors;
    A013/A017 → representation (QFont AbsoluteSpacing mode has no QML
    observable); A015/A016/A018 → double-click/editor-font anchors; A022–A024 →
    drag/store anchors; A028–A033 → drawer-stillness anchors; A038–A040 →
    wheel-clamp anchors; A043/A044 → matrix anchors; A047–A050 → view-state
    anchors; A054–A080 → filter-menu session anchors; A083–A112 → row-menu
    anchors (A119's owner-identity clause and other QuickPopupSession internals
    → representation); A115–A133 → outside-right anchors.
  - edits: fixture-open/EventWidgets guards (A067/A068/A120/A121/A173/A174/A187/
    A188) → representation; lookup guards close inside their journey predicates;
    the 39b "Mapping: S28x" GAP rows re-verify against the tempo-shape evidence
    and flip only with executed predicates in that fixture state;
    already-RETIRED rows (A146/A149/A150/A152/A162/A164/A170/A177/A190) stay;
    A192 → representation (native drawerBarInput item); A011–A013/A020–A022/
    A048–A050/A112/A113 → journey-isolation anchors.
  - remap: A001–A003/A033/A034/A039/A040/A044/A045/A048/A054/A055 →
    representation (native fixture guards); A005–A031 → representation (Qt
    signal-order observations, sprint-3 §4); A035 → outcome-report anchors;
    A046/A047 → rendered-combo/echo anchors; A051 → row-lookup anchor; A056/
    A057 → tempo-projection anchors.
- After every row is MATCHED/RETIRED, delete all four proof files in this task's
  final commit. If any row resists (e.g. the view-state apply clause proves to
  need task-65's persistence wiring), leave that row PARTIAL with the deferral
  named — never force a flip.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`, `deno task proof check
   --strict-mappings` (pre-deletion state shows all four ledgers closed), then
   `deno task proof sites --area eventviews` reports no ledger files.
2. Visual/native smoke (desktop): open a song, show the Event List —
   double-click a tick cell opens the editor; drag the Type resize handle live;
   wheel past both ends clamps; arrows at drawer focus leave the rows put;
   filter menu (7 categories, ticks mirror state, type "m" jumps to Meta, click
   toggles and the menu stays open, Down wraps, Return toggles, Escape cancels,
   clicking a cell closes without editing); right-click a row (Insert closes and
   inserts one event; moving the context retires the menu); right-click outside
   an open menu (cancels; the release does nothing); select rows and press
   Delete; hide the list, reload the tab (stays hidden), show it again; confirm
   the row-number gutter is unchanged.
