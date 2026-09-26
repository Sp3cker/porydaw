# Context

ED03 track headers, task 48 (fork-main `fceecd88`). Two deliverables: (1) the fork's over-budget
title/subtitle dimming, resolved to WCAG AA per ADR 0002; (2) converted-window proof for the activity
meter (geometry/DPR/raster), role-scoped republish, and the five header context-menu actions including
disabled duplicate and outside dismissal.

1. **Fork over-budget law** (`git show fceecd88:src/ui/songview/trackheadermodel.cpp`,
   `resolveRecordColors` :224-258): for `record.track >= document.trackBudget()` both `titleColor` and
   `subtitleColor` are dimmed via `mixTowardOklab(ink, backdrop, overBudgetMix)` — `0.6`, or `0.35` for
   the primary selection. Backdrop per state: normal = `QPalette::Window`; primary =
   `song_view_track_header_selection` (also the row base fill); in-scope = the row's overlay color, the
   same selection role at alpha 99 (`detail.cpp:157-160`). `mixTowardOklabImpl` (`detail.cpp:161-170`)
   lerps Oklab L/a/b toward the backdrop; alpha is ignored. The add-track record returns before all
   this (no dim). Budget: `SongDocument::trackBudget` (`songdocument.h:161-168`), clamped
   0..`kHardwareCapacity`(16), set once from the project snapshot's player table (`songtab.cpp:161`,
   `decompproject.cpp:292`).
2. **Swift budget plumbing exists; only the comparison is missing.** `SongDocument.trackBudget`
   (`src/swift/core/SongDocument.swift:268,287,313`) is a clamped `let` defaulting to 16;
   `ProjectSnapshot.trackBudgetFor` (`src/swift/project/ProjectStore+Open.swift:27-31`) maps
   player→limit like the fork; `canAddTrack` already consumes it
   (`src/swift/core/EventEditing.swift:37-39`). `TrackHeadersGeometry.makeSnapshot`
   (`src/swift/app/headers/TrackHeadersGeometry.swift:222-264`) never reads it. Oklab machinery is
   public (`PaletteMath.oklab/mixTowardOklab/hex/contrastRatio`, `GridPalette.swift:22-95`); no palette
   file changes (GridPalette.swift is task-45-hot).
3. **WCAG AA beats the fork constants** (ADR `docs/adr/0002-text-contrast-first.md`: 4.5:1 against the
   surface actually drawn behind the ink, alpha counts). Fork mixes on each theme's real surface
   (`ShellAppearance.swift:40-74,98-178`): vanilla normal title 2.16:1 / subtitle 1.82:1;
   dark-neutral-high 2.51/2.17; immaterial 2.41/2.01. Resolution precedent: ShellAppearance walks an
   ink toward its surface "until it keeps 4.5:1" (`ShellAppearance.swift:35-37`). Law adopted: dim =
   `mixTowardOklab(ink → backdrop, t*)`, `t* = min(forkMix, largest t whose quantized hex keeps ≥ 4.5:1
   on the row's painted surface)`. Computed t* title/subtitle — normal: 0.263/0.076 vanilla, 0.327/0.204
   dark, 0.310/0.128 immaterial; primary: 0.337/0.350/0.287 (cap 0.35 nearly kept); in-scope:
   0.253/0.100 vanilla, 0.333 dark, 0.210 immaterial (title only — see §4). Every over-budget row
   stays strictly dimmer than its in-budget ink (t* > 0 after the §4 repair) and never past the fork
   cap.
4. **In-scope subtitle ink repair (same lines this task edits).** `makeSnapshot:235-240` assigns
   `windowText` to the in-scope row's texts, then `:243-244` overwrite both unconditionally — the
   branch's assignments are dead and the subtitle lands on `secondaryText` over the 0x40 selection
   tint, failing AA today (dark-neutral-high 3.6:1, immaterial 3.4:1), contradicting the comment's own
   contract at :236 ("0x40 tint keeps windowText >= 4.5:1 … secondaryText fails above 0x16-0x27"); the
   ADR table agrees (`secondaryText` never labels a tinted window surface). Repair: in-scope
   non-primary rows use `windowText` for both texts (title already resolves `primaryText`, equal to
   `windowText` in every theme — `ShellAppearance.swift:173-174` — so only the subtitle changes).
   Delete the stale comment.
5. **Meter/render laws are already ported — only proof is missing.** `TrackActivity.physicalHeight`
   (`src/swift/app/headers/TrackActivity.swift:89-94`) and `activityHeight` (:114-118) match fork
   `track_activity_render` (`git show fceecd88:src/ui/activity/trackactivityrender.cpp:34-56`):
   intensity capped only while playing, height = `round(intensity · (rowHeight − separatorWidth) ·
   dpr)/dpr`; `headerActivityDim` (`TrackHeadersGeometry.swift:267-287`) matches `colors()` Oklch
   dimming. Swiftcore S001-S027 (`src/checks/trackheaders/tst_trackactivitymeter.swift`) prove the law
   with *parameter* dpr; the open rows want converted-window evidence: real window DPR (A010/A031),
   raster captures (A018/A019/A023/A024/A039-A042/A046-A048/A052-A055), per-row scoped republication
   (A013-A016 et al.). Production drive: `DocumentWorkspace.swift:163-165` polls
   `audio.consumeTrackActivityLevels()` → `trackHeaders.advanceActivity`; the check reaches the same
   entry point through `RollQmlBootstrap` (`src/checks/rollqml/RollQmlTests.swift:203`, already a
   registered QML element) because `AudioActivityLevel` (`src/swift/app/audio/AudioTelemetry.swift:
   4-11`) is not QML-constructible.
6. **Menu is already fork-shaped; proof gap only.** Fork `trackheadermenu.cpp:46-69
   buildHeaderMenuItems`: five rows — `Change voice...`, `Show voice in voicegroup`, `Rename
   track...`, `Duplicate track`, `Delete track`; Duplicate `enabled = document.canAddTrack()`; outside
   press/Escape/resize/foreign takeover cancels and drops the target. Swift `showHeaderMenu`
   (`src/swift/app/headers/TrackHeaders.swift:414-428`) matches labels, order, ids 1-5, disable law;
   `activateHeaderMenuAction` (:351-368) re-validates the pending target against document+revision
   (stale remap drops). Mounted dismissal wiring exists: `EditorSurface.qml:746-761` (Loader with
   `Keys.onEscapePressed` + outside-press `MouseArea` → `dismissHeaderMenu`); rows expose `enabled`
   (`tst_SwiftRollTrackHeaders.qml:315`). **Not mounted anywhere:** the `changeTrackVoiceRequested`
   signal (`ApplicationSession.swift:565,1091-1092`) has no QML consumer in `src/ui` — the picker
   handoff is drawer/Shell-owned; those ledger rows stay open with that named reason.
7. **Mounted lane state.** `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml` opens `mus_route101`
   (player BGM budget 16 — fixture `sound/song_table.inc` + `sound/music_player_table.inc`: BGM 16,
   SE1-3 3, SE_1TRK 1); five-row menu, rename open, reorder marker, outside dismissal are proven
   (ledger headers cite A004/A017-A019/A047-A048/A142-A143). Disabled duplicate is unobservable on
   route101 (2 note tracks, budget 16); `se_fanfare_1trk` runs on SE_1TRK, budget 1, 1 used track →
   `canAddTrack == false`: no add row, Duplicate disabled — no fixture change, only a second lane
   file (the lane auto-discovers every `tst_*.qml` in `rollqml/`, one run per file —
   `RollQmlTests.swift:99-133`). Over-budget dimming is unobservable mounted (every fixture song has
   used ≤ budget); it is proven in swiftcore + themecolor instead.
8. **Ledgers** (`src/checks/trackheaders/`, reference `f3069ef6`): activitymeter 16 GAP + 27 PARTIAL
   (13 MATCHED, 4 RETIRED); menu 23 GAP + 10 PARTIAL (122 MATCHED); mutations 17 GAP + 34 PARTIAL
   (107 MATCHED). GAP reason is uniform: "No executing check: the native C++ lane no longer builds or
   runs … see converted-window evidence below where available." PARTIAL reasons: Qt `dataChanged`
   count/first/last/role-list have no presenter counterpart; focus restoration unobserved
   (`headerInput` private); picker/audition rows are drawer-owned. The activitymeter header's
   `Converted-window command: deno task verify:qml --verbose` is stale — the lane runs under
   `verify:qml-roll`.

# Exact write set

- `src/swift/app/headers/TrackHeadersGeometry.swift` — over-budget dim law (internal helper +
  `makeSnapshot` integration), in-scope subtitle ink repair, delete the stale comment at :236.
- `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml` — `objectName: "timelineHeaderActivity_" +
  track` on the row's activity `Item` (:269-295); nothing else.
- `src/checks/trackheaders/headerfixture.swift` — `TrackHeadersFixture.init` gains `trackBudget:
  Int = 16` passed into `SongDocument` (existing callers unchanged).
- `src/checks/trackheaders/TrackHeadersChecks.swift` — budget-styling predicates (fixtures with
  `trackBudget: 1`).
- `src/checks/themecolor/ThemeColorChecks.swift` — `trackHeaderBudgetContrastChecks` called from
  `runThemeColorChecks`'s suite block.
- `src/checks/rollqml/RollQmlTests.swift` — `RollQmlBootstrap.pushTrackActivity(presenter:track:
  left:right:elapsed:playing:)`.
- `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml` — meter DPR/raster/scoped-republish,
  five-row/dispatch/escape/outside/no-click-through/focus, rename-commit and reorder-commit
  predicates.
- `src/checks/rollqml/tst_SwiftRollTrackHeaderCapacity.qml` — new file, `se_fanfare_1trk` capacity
  lane.
- Ledgers (controller-delegated ledger agent): `proof.tst_trackactivitymeter.txt`,
  `proof.trackheadermenu.txt`, `proof.trackheadermutations.txt`.

No CMake change (no new Swift sources; the capacity file is auto-discovered). No `TrackHeaders.swift`,
`EditorSurface.qml`, `GridPalette.swift`, or `ShellWindow.qml` edits — hot or unnecessary. Sizing
exception: one behavior family (ED03 proof + styling) over 8 files with one verification-surface
set — named for the dispatch table.

# Prerequisites

Menu/fixture proof runs after task 36 lands (its writers own the shell/EditorSurface mount context
this lane observes). The styling slice and its checks are parallel-safe immediately: no hot file, no
interface consumed from 36/38/45. No other interface deps.

# Interface contract

- `TrackHeadersGeometry.dimmedInk(ink: String, backdrop: String, surface: String, cap: Double) ->
  String` (internal, pure): Oklab-mix `ink → backdrop` at `t* = min(cap, tAA)`, where `tAA` is the
  largest t ∈ [0, cap] whose 8-bit-quantized mix hex keeps `PaletteMath.contrastRatio(mix, surface)
  >= 4.5`; bisection resolution 1e-3 with the quantized-hex re-test at each step. Single authority:
  the themecolor suite calls this same function.
- `makeSnapshot` color law (fork structure, AA-clamped factors): inks — primary `selectionText`
  both; in-scope non-primary `windowText` both; normal `primaryText` / `secondaryText`. If `track >=
  session.document.trackBudget`: `titleColor/subtitleColor = dimmedInk(ink, backdrop, surface, cap)`
  with backdrop/surface/cap — primary: `palette.selectionRing`/`palette.selectionRing`/0.35;
  in-scope: selectionRing RGB / `#40`-selection composited over `windowBackground` / 0.6; normal:
  `windowBackground`/`windowBackground`/0.6. In-budget rows, the add row, and every other snapshot
  field are unchanged. `session.selectedTracks.contains(track)` keeps defining in-scope;
  `session.selectedTrack` keeps defining primary.
- `RollQmlBootstrap.pushTrackActivity(presenter: TrackHeadersPresenter, track: Int, left: Int,
  right: Int, elapsed: Double, playing: Bool) -> Void` — builds the 16-entry `[AudioActivityLevel]`
  (zeros elsewhere), calls `presenter.advanceActivity(levels:elapsedSeconds:playing:)`.
- New QML objectName: the per-row activity `Item` is findable as `timelineHeaderActivity_<track>`;
  the two active bars remain unnamed children.
- New check anchors (one message per fork clause; never compound booleans shared across rows).
  Swiftcore: "a track beyond the budget dims its title toward the window surface", "a track beyond
  the budget dims its subtitle toward the window surface", "a selected over-budget row dims on its
  selection surface", "an in-scope over-budget row dims over its tinted surface", "rows within the
  budget keep their full ink", "the add-track row never dims", "over-budget dimming never exceeds
  the fork mix", "an in-scope row labels both texts with the window ink". Themecolor per mode:
  "…dimmed title on … surface contrast … (floor 4.5)" and the subtitle twin for each of the three
  row states (6 expects/mode via `dimmedInk` on `themeAppliedPalette` roles, in-scope surface
  composited at α = 64/255). qml-roll: "the converted window exposes the mounted header band", "the
  meter snaps to whole device pixels at the window's ratio", "meter height follows the window's
  device pixel ratio", "an unchanged physical height repaints the same meter raster", "activity
  republishes only the driven row", "the meter paints its active bar at the snapped device-pixel
  height", "the header menu lists the fork's five actions", "duplicate below capacity stays
  enabled", "duplicate at capacity stays disabled", "clicking the disabled duplicate neither
  dispatches nor dismisses", "duplicate adds a track from the mounted menu", "delete removes a
  track from the mounted menu", "change voice closes the menu and requests the picker", "show voice
  in voicegroup closes the menu without writing", "escape dismisses the open header menu", "an
  outside press dismisses without reopening on release", "an outside press writes nothing", "the
  band keeps keyboard focus across outside dismissal", "rename commits from the mounted editor",
  "reorder commits from a mounted drag", "the capacity song shows no add row".
- Preservation contract: menu labels/ids/disable law, pending-target revision guard,
  `advanceActivity` envelope and publish path, geometry/font publishing, row handle fields, the
  0x40 overlay alpha, and every existing objectName are unchanged. Frozen visual baselines stay
  valid: budget-16 surfaces repaint identically.

# Implementation steps

1. Styling: add `dimmedInk` to `TrackHeadersGeometry.swift`; rewrite the color block of
   `makeSnapshot` per the contract (dead in-scope assignments removed, stale comment deleted);
   parameterize `TrackHeadersFixture`.
2. Swiftcore predicates in `TrackHeadersChecks.swift` with `trackBudget: 1` fixtures (2 note
   tracks): move selection (`session.selectedTrack = 1`) and scope (`session.selectedTracks`)
   across the over-budget row to cover all three states; assert the anchors above, plus
   dim-not-past-cap via Oklab-distance comparison and strict dim (over-budget ink ≠ in-budget ink,
   distance-to-backdrop strictly smaller).
3. Themecolor block: for each `themePresetRows` mode, `themeAppliedPalette` → the six contrast
   expects via `dimmedInk`. Add the activity-Item objectName to `TrackHeaderBand.qml` and
   `pushTrackActivity` to `RollQmlBootstrap` (elapsed 60 drives the envelope to its target in one
   step).
4. `tst_SwiftRollTrackHeaders.qml` additions (existing helpers `item`, `near`, `waitForNative`).
   Meter: push (255, 128) on track 0; `tryCompare` row-0 heights to `Math.round(intensity *
   meterHeight * dpr) / dpr` for both channels with `meterHeight = h.rowHeight -
   h.separatorWidth`, `dpr = s.Screen.devicePixelRatio`; assert `height * dpr` integral; assert
   row-1 delegate heights still 0 and titles unchanged; re-push the same levels and compare
   `grabImage` of `timelineHeaderActivity_0` equal; count device-pixel rows in the strip matching
   `activityActiveColor` (±8/channel) vs `round(intensity · meterHeight · dpr)` (route101 track-0
   identity `#CD5454`). Menu: right-click row 0 → five rows, fork texts, ids 1-5 in order, row 4
   enabled; pick Duplicate → rows grow, menu closes; pick Delete → rows shrink; pick Change voice
   → menu closes + `SignalSpy` on `session.changeTrackVoiceRequested` fired with the track; pick
   Show voice in voicegroup → menu closes, rows/titles unchanged; Escape after reopen → `menuOpen`
   false; outside press (existing finder) → `menuOpen` false, no reopen on release, rows
   unchanged, `timelineTrackHeadersInput.activeFocus` still true. Mutations: rename —
   double-click, `keyClicks("Renamed")`, Return → title "1 · Renamed", `renamingTrack == -1`;
   reorder — press-drag-release one row → mounted row order swaps.
5. New `tst_SwiftRollTrackHeaderCapacity.qml`: copy the lane's bootstrap/init/cleanup shape with
   `bootstrap.start("se_fanfare_1trk")`; assert single header row, no add-track row; right-click →
   five rows, `headerMenuRow_4` disabled; click it → `menuOpen` stays true, row count unchanged;
   Escape and outside dismissal close.
6. Run the lanes; record RED→GREEN for the styling predicates (step 1 before step 2) and the new
   mounted anchors.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (activitymeter ledger command; covers budget
  styling, contrast, all presenter suites; menu/mutations suites also run under this filter —
  their pinned variant is `--qt projectSession -maxwarnings 100000`)
- `deno task verify --filter swiftcore-themecolor --verbose` (contrast math block)
- `deno task verify:qml-roll --verbose` (both track-header lane files: meter DPR/raster, five
  actions, capacity, rename/reorder commit)
- Runtime prerequisite: a windowing environment that reports a real `Screen.devicePixelRatio`
  (the lane already requires `windowShown`).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel constants (mix
  factors 0.6/0.35 and the 4.5 floor are color law, not geometry); no palette literals in QML;
  `GridPalette.swift` untouched.
- WCAG deviation record (ledger reasons + code reality): dim factors are AA-clamped below the
  fork's 0.6/0.35; record per-theme clamped values (Context §3) as the accepted deviation from
  `trackheadermodel.cpp:241-258` — parity of *structure* (which rows dim, toward which backdrop)
  is kept, parity of magnitude is not.
- Implementers never edit ledgers; the controller delegates the three ledgers to the ledger
  agent. Mapping (S rows for anchors with no fork A row; one anchor message per fork clause;
  refresh the activitymeter header's converted-window command to `deno task verify:qml-roll
  --verbose`):
  - activitymeter: A004 → "the converted window exposes the mounted header band"; A010/A031 →
    "meter height follows the window's device pixel ratio"; A018/A019 → the grab-succeeds step
    inside "the meter paints its active bar at the snapped device-pixel height" (split its grab
    and count into two anchors, one per row); A023/A024 → "an unchanged physical height repaints
    the same meter raster"; A042 → the column-scan half of the paint anchor; A039/A040/A041 →
    paused-fill variants of the DPR/paint anchors (probe with `playing: false`); A046-A048/
    A052-A055 → per-row split of "activity republishes only the driven row" plus existing
    S025/S026; A012 → window-exposure anchor; A002/A003/A005/A011 and every dataChanged
    count/first/last/role-list PARTIAL (A013-A016, A025-A028, A032-A035, A056-A059) →
    RETIRED-REPRESENTATION, one line each citing QListModel row-handle replacement and the
    retained-identity S rows; A036-A038 → the raster geometry halves of the paint anchor (strip
    logical size × dpr = device pixels).
  - menu: A003 → "the header menu lists the fork's five actions" (split into five per-row
    anchors); A021 → "clicking the disabled duplicate neither dispatches nor dismisses";
    A030/A031 → "change voice closes the menu and requests the picker" (split: close anchor +
    spy anchor); A045/A048 → rename-open anchor (existing test function, add anchor messages);
    A061 → show-voice anchor; A071 → "duplicate adds a track from the mounted menu"; A087 →
    "delete removes a track from the mounted menu"; A110 → "escape dismisses the open header
    menu"; A140/A145/A152 → outside-dismissal anchors split per clause (dismiss, no-reopen,
    no-write); A097/A123/A133 → the existing presenter predicates ("structural remap cancels
    menu without starting editor", "action …: remap precedes delayed activation") — verify they
    executed in this run, else leave open; A013/A067/A073/A089/A101/A102/A149 → "the band keeps
    keyboard focus across outside dismissal" and its per-action twins (focus after duplicate/
    delete dispatch); rows whose clause is the picker window/focus/audition (A027/A033-A035/
    A038/A043/A049/A053/A057) stay open with reason "picker handoff surface (drawer/Shell) not
    mounted; `changeTrackVoiceRequested` has no QML consumer".
  - mutations: A001/A005/A007/A010/A011/A016/A022 → "rename commits from the mounted editor"
    split per clause (commit writes, rebuild count, undo stays presenter-side); A027 →
    title-update clause of the same; A046 → "reorder commits from a mounted drag"; A075 →
    add-row activation stays presenter-proven (S030-S057) — mounted add is capacity-blocked on
    route101 and picker-blocked elsewhere; leave open with that reason. Picker/audition PARTIAL
    rows (A090-A150 family) stay untouched.
- `tst_SwiftRollTrackHeaders.qml`'s existing functions and anchors are preserved except where
  this brief adds predicates; the ledger agent refreshes the verified QML SHA.
- No fixture files change; no new fixture songs.

# Controller verification

After the writer settles and no check processes remain:

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`, `deno task proof
   check`, `deno task proof check --executed`, `deno task proof check --strict-mappings` — the
   three trackheaders ledgers show executing anchors for the rows above and no unmapped MATCHED
   sites.
2. `deno task verify:qml-roll --verbose` on a real display: both track-header files pass; inspect
   the meter raster predicate output (device-pixel counts) if artifacts are written.
3. `deno task verify --filter swiftcore --verbose`: budget-styling and contrast anchors present
   in the report.
4. Native smoke (desktop): open a song on a budget-limited player (or a project whose player
   table caps tracks below the song's track count) — over-budget rows render visibly dimmer but
   still legible; in-scope subtitle ink survives theme switches; right-click menu shows all five
   rows with Duplicate disabled at capacity.
