# Context

Roll/drawer color parity with the fork-main QWidget app (user direction: rebuilt
surfaces must look like their QWidget counterparts). Scope: inventory items
5a–5d. fork-main reference `fceecd88` (tip of `fork-main`; verified
`git log --oneline -1 fork-main`). Captures: QWidget
`/tmp/porydaw-qwidget-ref/{a-main-window,d-auto-base}.png`, Swift
`/tmp/porydaw-swift-ref/{a-main-window,d-auto-lane}.png`, all theme
`immaterial`. Pixel measurements quoted below were taken from those captures.

1. **5a automation curve color.** QWidget draws the active lane curve in
   `themes::color(themes::Role::song_view_automation_node_ink)`
   (`git show fceecd88:src/ui/songview/quick/automationquick.cpp` line 408,
   context built at 355-368) and ghosts in the same role at
   `ghost.setAlphaF(0.5)` (lines 372-374). Role → preset `automation_ink`
   (`theme_roles.h:180` → `presetcolors.h:300`), values `#EA3C3C` vanilla /
   `#FF4D47` dark-neutral-high / `#FF91C3` immaterial
   (`presetcolors.h:369,429,482`). Capture confirms `#FF91C3` in the QWidget
   drawer. Swift paints active runs `palette.primaryText` and ghosts
   `palette.outline` (`src/swift/app/drawer/automation/AutomationContentPublication.swift:229`)
   — white `#CBCBCD` in immaterial.
2. **5b active automation tab.** QWidget active tab background is
   `appearance.tabSelectedBackground` (`AutomationTabs.qml:294`, fork) =
   role `song_view_automation_tab_active_background` → preset
   `control_pressed_background` (`automationcanvas_tabs.cpp:245`,
   `presetcolors.h:298`), i.e. `#F5B61C`/`#00D3F2`/`#F98CBE`; capture
   confirms `#F98CBE`. Tab text roles `tab_text`/`tab_hover_text`/
   `tab_selected_text` all → `window_text` (`presetcolors.h` mapping; run the
   role-order zip yourself if re-verifying). Resting/hover tab surfaces are
   dedicated presets `automation_tab_background`/`automation_tab_hover_background`
   with `automation_tab_outline` borders: immaterial `#4A4E59`/`#545864`/
   `#616571`, vanilla `#E7E1DB`/`#F0EAE4`/`#8C857F`, dnh `#51555E`/`#5B5F69`/
   `#62666F` (`presetcolors.h:366-368,426-428,478-480`). Pip color is
   `song_view_automation_node_ink` (`automationcanvas_tabs.cpp` "pipColor").
   Swift binds checked → `pagePalette.selectionRing` (`#ABCAD2` blue),
   hovered → `selectionFill`, resting → `chromeBackground`, pip/text similar
   (`src/ui/songview/quick/AutomationTabs.qml:159,166,183-187,198`).
3. **5c loop region tint.** QWidget paints loop **edge glows plus edge lines**
   on the roll body — not a solid band: `addLoopGlow`
   (`timelinequickview_pianoroll.cpp:97-121`) takes role
   `song_view_loop_marker` (→ preset `selection_background`,
   `#ABCAD2` immaterial), sets strong alpha 150/255, weak 18/255, clear 0,
   and draws two horizontal gradients per edge: start edge `[x0, x0+0.2w]`
   strong→weak then weak→clear; end edge mirrored (split at 0.8). Caller
   (lines 395-421): `w = min(space(Eight), x1 - x0)`, Space::Eight = 2.0 ×
   base font px (`src/ui/layout.cpp:39-45`); glow spans the full plot
   height on layer `PianoOverlay`; 1-physical-px vertical lines at x0/x1 at
   full alpha; skipped unless `x1 > plot.left && x0 < plot.right`; open
   ends default x0/x1 to the plot edges. The C++ display-list rect carries
   4 corner colors (`timelinequickscene.cpp:609-630`, linear mix of
   encoded RGB/alpha floats).
   Swift draws only ruler `[`/`]` marks (`src/swift/app/roll/GridScene.swift:613-625`);
   `pianoOverlay` has no loop rects.
4. **5d note fill velocity law.** Already ported identically: fork
   `SongView::noteColor` (`src/ui/songview/trackvoiceops.cpp:124-149`) mixes
   track identity toward role `song_view_note_velocity_zero` with
   `t = 1 - v/127` in Oklab, v=0 → zero color, v=127 → identity; Swift
   `PaletteMath.noteFill` (`src/swift/app/timeline/GridPalette.swift:103-111`)
   is the same law, identity tables are byte-identical (fork
   `trackidentitycolors.h` fills vs `GridPalette.swift:230-234`), zero
   endpoint themed (`ShellAppearance.swift:169`). Measured: QWidget roll
   notes `#6DC368` ≈ computed `#6AC283` (v≈100 immaterial) ✓. The pale
   `#BBCDB5` notes in the Swift capture are **ghost fills**
   (`PianoGrid.swift:221` `ghost: track != valid`): `PaletteMath.ghostFill`
   (`GridPalette.swift:188-198`) hardcodes vanilla backdrops
   `#D4CCC7`/`#B4ACA6`, while fork `detail::ghostNoteColor`
   (`src/ui/songview/detail.cpp:189-223`) blends into the **themed**
   `song_view_piano_roll_background`/`accidental_lane` roles (same 60/255
   weight, ±0.055 lightness clamp). Dark-theme Swift ghosts glow
   vanilla-pale; fork ghosts recede into the roll.

# Exact write set

- `src/swift/app/timeline/GridPalette.swift` — add
  `automationNodeInk`, `automationTabBackground`,
  `automationTabHoverBackground`, `automationTabOutline` (vanilla defaults
  above); change `PaletteMath.ghostFill` to take the two backdrop hex strings
  as parameters (same math).
- `src/swift/app/shell/ShellAppearance.swift` — extend the private `Colors`
  struct and all three preset literals with the four values; map them in
  `apply`.
- `src/swift/app/drawer/automation/AutomationContentPublication.swift:229` —
  active curve `palette.automationNodeInk`; ghost curve the same ink at 50%
  alpha (`#80`-prefixed hex via the existing alpha helper), not `outline`.
- `src/ui/songview/quick/AutomationTabs.qml:159-198` — checked background →
  `pagePalette.tabPressedBackground` (already `colors.controlPressed` per
  `ShellAppearance.swift:141`), resting → `automationTabBackground`, hovered →
  `automationTabHoverBackground`, border → `automationTabOutline`, pip →
  `automationNodeInk`, label/count text in all states → `pagePalette.windowText`.
- `src/swift/app/roll/GridScene.swift` — ghost fill call site (~766-776)
  passes `p.rollBackground`/`p.accidentalLane`; emit loop glow bands + edge
  lines into `pianoOverlay` next to the time-selection overlay (~853-864),
  from `m.timeAxis.loopStartTick/loopEndTick`.
- Checks: `src/checks/automation/presentation/painting.swift` (curve/ghost
  run colors), `src/checks/rollcheck/note_rendering.swift` (ghost colors per
  preset; pin immaterial `noteFill` v100 → computed hex), loop-glow
  predicates in the rollcheck suite that already seeds loops, and
  `src/checks/editorqml/tst_EditorDrawer.qml` (checked tab background).
- Registered fixture baselines only if they embed the old tab/curve colors
  (`grep -rn "B9E8EE\|selectionRing" src/checks/fixtures`); same commit.

# Prerequisites

Sequence after task 22 (owns `GridPalette.swift`, `ShellAppearance.swift`,
in flight) and task 24 (adds polyphony fields to the same two files). The
fields this task adds are disjoint from both; the controller serializes the
landings. Task 22's `EventListPage.qml` and event-list files are untouched.

# Interface contract

- New palette roles and values (hex, per preset) exactly as in Context items
  1-2; `ShellAppearance.apply` maps them for all three presets.
- Curve colors: active `automationCurve` runs use `automationNodeInk`; ghost
  runs use it at 50% alpha. Published `fillColor` strings are the observable
  contract.
- Tab contract: checked → `tabPressedBackground`, text → `windowText` in
  every state; resting/hover/border per the new roles.
- Loop glow: color base `selectionRing`; alpha ladder strong `150/255`,
  weak `18/255`; per edge two ramps (0→0.2 and 0.2→1 of the glow width for
  the start edge, mirrored for the end edge) quantized into bands of width
  `spaceHalf` (existing font metric, ≥1 px) with linear alpha in encoded
  space (fork `mix`, `timelinequickscene.cpp:616-629`); total glow width
  `min(2 × baseFontPx, x1 - x0)`; full roll-body height, clipped to the plot;
  1-device-px edge lines at full alpha; nothing when no loop tick is set;
  open ends clamp to the plot edges. Primitive names `loopGlowStart`,
  `loopGlowEnd`, `loopEdgeStart`, `loopEdgeEnd` in `pianoOverlay`.
- Ghost fill: identical law, backdrops `rollBackground` (natural) /
  `accidentalLane` (accidental). Vanilla output is unchanged from today's
  hardcoded values.
- Contrast: verify every changed text/background pair with the existing
  `PaletteMath.contrastRatio`; note and report (do not substitute) that
  fork's own active-tab pair `windowText #CBCBCD` on `#F98CBE` measures
  ≈1.8:1 — parity with shipped chrome is authorized by the 2026-09-25 user
  direction; record the measurement in the report.

# Implementation steps

1. Failing predicates first; record RED: curve/ghost run colors
   (`painting.swift`), checked tab background (`tst_EditorDrawer.qml`),
   loop-glow rects absent (`rollcheck`), ghost fill ignores theme
   (`note_rendering.swift` immaterial case).
2. Palette roles + `ShellAppearance` mapping (all three presets).
3. `AutomationContentPublication` and `AutomationTabs.qml` bindings.
4. `GridScene` ghost backdrops, then loop glow emission.
5. Lanes below; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:qml --verbose` (drawer tabs and curve runs)
- `deno task verify:qml-roll --verbose`
- `deno task verify:shell --filter shell-grid-menu --verbose` (ruler loop
  markers unchanged) and `--filter shell-note-visuals --verbose` (framebuffer
  probes over the roll)
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`:
  recapture the drawer and roll in `immaterial`; compare curve ink, active
  tab, loop edges/lines, and ghost notes against
  `/tmp/porydaw-qwidget-ref/d-auto-base.png` / `a-main-window.png`.

# Visual parity

Counterpart sources quoted in Context. Note for the report: the Swift
`a-main-window` capture ghosts track 2 while the QWidget capture shows it
active — a capture-state difference (both apps ghost non-selected tracks;
fork `timelinequickview_pianoroll.cpp:231`, Swift `PianoGrid.swift:221`), so
compare ghost-vs-ghost and active-vs-active, not the raw captures. Out of
scope: automation ghost-edge underline (`automation_ghost_edge`), the missing
OtherEvents band (item 2), automation tab row count (item 3).

# Task-specific constraints

- No new C++, no code comments, no pixel constants: glow width and band width
  derive from `baseFontPx`/`spaceHalf`; band count is derived, not fixed.
- One palette authority: the session `GridPalette`; no cached copies.
- No proof-ledger edits by the implementer. Rows to hand the controller's
  ledger agent: `proof.automationpainting.txt` sites mapped "No Swift
  presenter predicate observes the rendered mesh" (new color predicates may
  map; agent decides); `proof.note_rendering.txt` A016/A017 and the
  velocity-color ghost row (S018/S019 expectations change — re-map, keep GAP
  where pixels stay unobserved); `proof.keyboard.txt` ghost rows
  (presence/ring only — agent confirms).
