# Context

AU04 Polyphony Debugger (task 43). Repair the two consumer-visible mismatches against
fork-main `fceecd88`, then close the two polyphony ledgers with executing predicates —
including rendered flash-state WCAG AA contrast. Slot after task 36; assumes task 36's
PreferencesStore cutover landed as briefed (`tst_ShellPolyphony.qml` already seeds
through `bootstrap.preferences` on the current tree).

1. **Fork double-click law** (`git show fceecd88:src/ui/polyphonypanel.cpp`): the
   event log connects only `itemDoubleClicked` → `activateLogRow` (:351-355); no
   `itemClicked` connection exists — single click never seeks. Log tooltip:
   `Double-click an event to jump to its position.` (:353). `activateLogRow`
   (:466-474) emits `jumpToEvent(tick, track, midiKey)` only when the row's
   `Qt::UserRole` tick is valid — set only for positioned events (:526-531); live
   rows (`M4A_POLY_TICK_NONE`, shown `live`, :505-506) cannot jump. Manual (TODO
   tour) `docsrc/manual/polyphony.md:30-37`: "double-click an entry to jump to the
   exact note". Current QML jumps on single click (`PolyphonyPanel.qml:301-304`
   `TapHandler.onTapped` → `activateEvent`); the presenter split is already correct
   (`PolyphonyPanelPresenter.swift:199-204` guards `row.tick >= 0`; session wiring
   `ApplicationSession.swift:138-150` mirrors `mainwindow.cpp:605-617`).
2. **Fork flash fade law**: `kFlashMs = 1000` (:29-30); on any per-track counter
   increase over a valid previous sample (:562-577) the row background becomes
   `polyphony_flash_background` with `setAlphaF(0.55f * (1 - elapsed/kFlashMs))`
   (:602-606) — poll-driven linear alpha 0.55 → 0 over 1 s, background only; text
   color never changes; after expiry `Qt::transparent`. First observation is a
   baseline; decreases do not flash; reset re-arms the baseline (:412-418,
   :480-486). Refresh cadence is the uiTick timer — 100 ms playing, 500 ms idle
   (`mainwindow.cpp:54-55, 1135-1143`); the Swift dock Timer is already 100 ms
   (`ShellWindow.qml:572-577`), so a presenter-computed alpha at poll time is
   cadence-parity. Fork color `PresetColor::polyphony_flash = "#D92626"` in every
   preset (`presetcolors.h:96-99, 355, 416, 473`) — "a fixed identity red faded by
   the panel". Current Swift: binary swap `flash ? polyphonyFlashBackground :
   buttonBackground` + text `flash ? polyphonyFlashText : windowText`
   (`PolyphonyPanel.qml:214, 239`) off a boolean (`PolyphonyPanelPresenter.swift:26,
   187, 193`); `polyphonyFlashBackground "#D88985"` and the invented
   `polyphonyFlashText` (`GridPalette.swift:275-276`) date from the original port
   (`9576156d`) and the contrast pass (`666cd477`,
   `docs/plans/qtbridge-surface/amendments.md:91-97`), not a parity ruling.
3. **Laws already correct — prove, do not rebuild**: counters omit all-zero rows,
   `Track %1` fallback; Reset clears panel state immediately, engine reset deferred
   (`mainwindow.cpp:601-604` ↔ presenter `reset()` :118-121); lower `eventTotal`
   rebases; log inserts newest-first, trims oldest past `kLogCap = 500` (:29,
   :489-497) ↔ presenter :149-170; invert applies `checked && dock visible`
   (`mainwindow.cpp:591-600`) ↔ presenter :106-116; renderer invert is
   session-sticky, never persisted (`audioengine.h:178-185`) — Swift writes no
   preference for it; the audition exemption is audio-side (auditions marked live +
   audible under invert, `audioengine.cpp:677-701`), already proven by
   `polyphonyengine.swift` `auditionRemainsAudibleWithInvert` — engine files out of
   scope.
4. **WCAG AA resolution** (AA beats parity — here parity *restores* AA): with the fade,
   text stays `windowText` over #D92626 composited at 0.55 on `buttonBackground`.
   Start-of-flash contrast ≈ 4.6:1 vanilla (#302C29 on #DD7775), 6.7:1
   dark-neutral-high (#D8D8D8 on #832121), 5.4:1 immaterial (#CBCBCD on #8A282A) —
   all ≥ 4.5; as alpha decays both endpoints pass and surface luminance moves
   monotonically toward the already-passing `windowText`/`buttonBackground` pairing,
   so the whole fade passes. Keeping `#D88985` would fail dark themes once the text
   swap is removed (4.28:1 / 3.38:1) — it exists only to prop up the binary flash.
5. **Ledgers** (`src/checks/polyphony/`): `proof.polyphonypanel.txt` — 32 A rows (30
   GAP + A014/A019 PARTIAL), reason verbatim `feature not yet ported: polyphony
   panel`, no S/Anchor rows; `proof.polyphonygate.txt` — 15 A rows (14 GAP + A004
   PARTIAL). Both headers cite a stale `polycheck` command. The Swift predicates
   already execute (`PolyphonyPanelChecks.swift` under `swiftcore-themecolor` suite
   33, `CoreCheckSupport.swift:235-243`; engine under `swiftcore-playback`); the
   ledgers never recorded S anchors. The mounted lane pins the *wrong* gesture today
   (`tst_ShellPolyphony.qml:175-180` single-click jump). Flash state is rendered
   nowhere: `tst_TextContrast.qml:255-260` audits the dock at rest only;
   `PolyphonyShellProbe.publishFixture` seeds counters once (baseline ⇒ no flash).

# Exact write set

- `src/swift/app/audio/PolyphonyPanelPresenter.swift` — `flash: Bool` → `flashAlpha:
  Double`; `update(_:now:)`; fade/baseline/decrease/restart semantics per contract;
  delete comments inside edited regions.
- `src/ui/shell/PolyphonyPanel.qml` — double-click gate; log tooltip; flash overlay
  rendering; text color constant `windowText`; delegate `real flashAlpha`.
- `src/swift/app/timeline/GridPalette.swift` — `polyphonyFlashBackground = "#D92626"`;
  delete `polyphonyFlashText` (sole consumer PolyphonyPanel.qml:239).
- `src/checks/polyphony/PolyphonyPanelChecks.swift` — injected-instant fade
  predicates; adjust the existing flash expect; extend the positioned-text expect.
- `src/checks/themecolor/ThemeColorChecks.swift` — per-preset flash-start blend +
  resting-pair contrast expects (new `polyphonyFlashContrastChecks` called from
  `runThemeColorChecks`).
- `src/checks/editorqml/PolyphonyShellProbe.swift` — public `bumpOverflowCounter()`.
- `src/checks/editorqml/tst_ShellPolyphony.qml` — gesture split predicates, rendered
  flash-state contrast (+ artifact), short-pane scroll predicate.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  `src/checks/polyphony/proof.polyphonypanel.txt`, `proof.polyphonygate.txt`.

No CMake, engine, `ShellWindow.qml`, or `PolyphonyChannelGroup.qml` changes. Sizing
exception: one behavior family over 7 files with one verification-surface set — named
for the dispatch table.

# Prerequisites

Task 36 accepted (owns `tst_ShellPolyphony.qml` seeding and the `ShellWindow.qml` dock
region this task reads). No other interface deps; the `onJump` camera API is unchanged.

# Interface contract

- `PolyphonyCounterRow.flashAlpha: Double` (bridged): `0.55 * max(0, seconds until
  flashUntil)` at snapshot time. Rows still emitted only for tracks with a nonzero
  counter, ascending track order, `Track %1` fallback. A first observation of nonzero
  counters is a baseline (`flashAlpha == 0`); only an increase over a valid previous
  sample opens/reopens the 1 s window; decreases rewrite the row without touching the
  window; `clear()`/reset/lower-`eventTotal` rebase closes all windows (next sample is
  a baseline again).
- `PolyphonyPanelPresenter.update(_ snapshot: AudioPolySnapshot, now:
  ContinuousClock.Instant = .now)` — stays `@QtIgnored`; production callers (`poll()`,
  probe, checks) compile unchanged; checks pass explicit instants.
- QML counter row: base `Rectangle` keeps `buttonBackground` + border; a child overlay
  `Rectangle` (`objectName: "polyphonyFlashOverlay"`, declared before the cell `Row`
  so text paints above it) gets `color: panel.colors.polyphonyFlashBackground`,
  `opacity: counterRow.flashAlpha` — the fork's `setAlphaF(0.55·(1−t))` composite;
  counter text color `panel.colors.windowText` always.
- QML event rows: `TapHandler { acceptedButtons: Qt.LeftButton; onTapped: if
  (tapCount === 2) panel.presenter.activateEvent(eventRow.index,
  panel.Screen.devicePixelRatio) }` — single click does nothing. The event-log
  `Rectangle` gains `HoverHandler` + `ToolTip.text: qsTr("Double-click an event to
  jump to its position.")`.
- `PolyphonyShellProbe.bumpOverflowCounter()` — republishes the fixture snapshot with
  one track's steal counter incremented so the production pane enters the flash
  window; returns void.
- New check anchors (message-anchored for the ledgers):
  - swiftcore `swiftcore/PolyphonyPanel::flashFadeLaw` (PolyphonyPanelChecks.swift):
    "first observation is a baseline without flash", "counter increase restarts a
    linear fade from full emphasis", "counter fade decays linearly toward zero", "the
    fade expires at one second", "a counter decrease does not restart the fade", "a
    new increase restarts the fade window".
  - swiftcore `swiftcore/PolyphonyPanel::flashContrast` (ThemeColorChecks.swift), per
    mode: "…windowText on polyphonyFlashBackground@0.55 over buttonBackground
    contrast … (floor 4.5)" and "…windowText on buttonBackground contrast … (floor
    4.5)", blended with the existing `themeCompositeHex` using `#8CD92626`
    (α = 140/255 ≈ 0.55) over each preset's control surface.
  - `tst_ShellPolyphony.qml`: "single-clicking a positioned log row does not jump",
    "double-clicking a positioned log row requests the event's document tick",
    "flashing counter text meets WCAG AA on its faded row surface", "a short pane
    keeps the log reachable by scrolling"; existing anchors "live overflow cannot
    request a document cursor jump" (now via double-click) and "counter increase
    highlights its track" (now `flashAlpha > 0.5`).
- Preservation contract: `activateEvent`'s positioned-vs-live guard, the `onJump`
  tuple + session wiring, the 100 ms dock poll timer, ring/cap/rebase logic, invert
  visibility gate, channel-cell rendering, and every existing objectName are
  unchanged. Frozen widget baselines
  (`src/checks/fixtures/visual/macos-*/polyphony/*.json`) stay valid — the fixture
  never flashes (baseline) and no geometry moves.

# Implementation steps

1. Presenter: replace the boolean with `flashAlpha`, add the `now:` parameter,
   compute `0.55 * max(0, remaining)`; keep `flashUntil` bookkeeping
   (increase-only writes, baseline on count change, clears on rebase). Delete
   comments in touched regions.
2. Palette: flash background → `#D92626`; delete `polyphonyFlashText`.
3. QML: overlay rectangle + constant text color; `required property real flashAlpha`;
   double-click gate; log tooltip.
4. `PolyphonyPanelChecks.swift`: convert `snapshotProjection`'s flash expect to
   `flashAlpha > 0.5` (message unchanged); add the `flashFadeLaw` block with injected
   instants (0 / +100 ms / +600 ms / exactly +1 s / +1.5 s, a mid-window decrease, a
   second increase restarting); extend the positioned-row text expect with the
   `(voice 5)` fallback token (fixture has no voice names).
5. `ThemeColorChecks.swift`: `polyphonyFlashContrastChecks` over `themePresetRows`,
   two expects per mode as contracted.
6. Probe: `bumpOverflowCounter()` (steal[2] += 1 republish).
7. `tst_ShellPolyphony.qml` (`test_viewActionAndEventNavigation`): keep the
   single-click live no-jump; add single-click positioned no-jump; switch the jump to
   `mouseDoubleClick`. After the fixture mounts: `probe.bumpOverflowCounter()`,
   locate the flashing row via `polyphonyOverflowRow_1`'s parent delegate, assert
   `flashAlpha > 0.5`, scroll the row into the viewport (the :158-163 pattern),
   then `Audit.measure` (import `"TextContrastAudit.js" as Audit`) on its
   `polyphonyCounterText` against `grabImage` of the scene root — assert non-null
   and `ratio >= required`; save the frame as `polyphony-flash.png` next to the
   profile artifacts (`grabToImage` + `probe.artifactPath` pattern). Add the
   short-pane predicate: shrink the reference pane (still ≥ the fork's scroll
   threshold) and assert the Flickable's `contentHeight > height`. Typography,
   profile, and reset predicates stay untouched.
8. Run the lanes below; record RED→GREEN where behavior changed (the old single-click
   jump predicate must fail before step 3 and pass after).

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-polyphony --verbose` — gesture split, flash
  contrast + artifact, reset, typography, 4 DPR profile children vs frozen baselines.
- `deno task verify --filter swiftcore-themecolor --verbose` — projection,
  ring/jump/cap/rebase, fade law, invert gate, flash contrast math.
- `deno task verify --filter swiftcore-playback --verbose` — engine gate regression
  (counters/ring, live sentinel, invert, audition exemption; unchanged code).
- `deno task verify:shell --filter shell-text-contrast --verbose` — resting-panel
  contrast regression across the three themes.
- Runtime prerequisite: macOS host audio for `invertVisibilityGate` (a thrown
  `NativeAudio()` already reports as failure, not skip).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions.
- No pixel constants; geometry stays base-font multiples; no palette literals in QML
  (the overlay reads `colors.polyphonyFlashBackground`; `#8CD92626` appears only in
  the ThemeColorChecks math as the α=0.55 composite input, like the hover-chip
  composite).
- `polyphonyFlashText` deletion is total: no alias, no fallback role.
- Accepted fork deviations (record in ledger reasons, do not code around): QML
  `ToolTip` shows immediately vs QToolTip's system delay; the dock Timer polls at
  100 ms whenever visible+songOpen vs the fork's 500 ms idle cadence (fade law and
  visibility gating unaffected).
- Implementers never edit ledgers; the controller delegates them to the ledger agent.
- Ledger mapping (agent: add S rows with the anchors above, flip Dispositions,
  refresh the stale `polycheck` header commands to this brief's lanes):
  - polyphonypanel: A001–A002 → "ring drains oldest first"; A003–A004 → "newest live
    drop appears first"; A005–A011 → "positioned steal formats bar beat track and
    key" (A010 via the voice token); A012–A016 → "positioned row jumps to the
    precise note"; A017 → "live sentinel cannot jump"; A018 → "smaller ring total
    rebases an old run"; A019 → "ten 60-event bursts retain only the latest 500" (+
    "newest retained event is first"); A020/A028/A029/A032 (screenshots) and
    A022–A027/A030 (layout/grid) → `test_visualProfiles` function anchor (evidence:
    the four profile-child functions in `build/proof-evidence/shell-polyphony.json`);
    A021 → "the mounted polyphony pane follows its dock"; A031 → "a short pane keeps
    the log reachable by scrolling".
  - polyphonygate: A001/A005/A008/A013 → "hidden checkbox retains state without
    inverting audio" (prepared-audio precondition, occurrence selectors as needed);
    A002 → "the debugger starts hidden"; A003 → new swiftcore expect "a fresh attach
    leaves renderer invert off"; A004 → "hidden checkbox retains state without
    inverting audio"; A006 → "ShellWindow dock reacts to the presenter visibility
    change"; A007/A009/A012/A014 → "reopening checked panel enables audio invert"
    (+ QML "reopening restores the checked option"); A010 → "closing panel suspends
    invert but remembers checkbox"; A011 → + "closing preserves the invert checkbox
    state"; A015 → "unchecking an open panel disables renderer invert".
  - Flash/gesture/contrast predicates have no fork A rows; record them as S rows
    (predicate inventory) so `--executed` classifies them.

# Controller verification

After the writer settles and no check processes remain:

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — both polyphony ledgers show executing
   anchors and no unmapped MATCHED sites.
2. Visual: re-run `deno task verify:shell --filter shell-polyphony --verbose`; inspect
   the artifacts (`polyphony-<dprN-fontM>-<state>.png`, `polyphony-flash.png` under
   the check's project root) — the flash frame shows the translucent red row over
   the normal surface with unchanged text ink; geometry frames match previous
   captures.
3. Native smoke (desktop): launch the built app, open the Polyphony Debugger, play a
   dense song — counter rows flash red and fade over ~1 s, the log jumps only on
   double-click, live rows never jump, Reset clears both tables, hide/reopen keeps
   the checkbox while suspending solo-overflow audio.
