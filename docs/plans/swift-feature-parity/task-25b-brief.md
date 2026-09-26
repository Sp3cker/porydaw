# Context

Chrome glyph/text parity with fork-main `fceecd88` (tip of `fork-main`).
Scope: inventory items 1b, 4, 8a, 8b. Split of the former task 25: this file
covers chrome glyphs and text; colors (5a-5d) are `task-25-brief.md`. The
write sets are disjoint.

1. **1b pitch popup readout.** fork-main never renders an empty-set glyph:
  `PitchBendGraph::formatLiveValue`
  (`git show fceecd88:src/ui/pitchbendgraph.cpp:861-871`) returns `"0 st"`
  exactly when `m_liveValue == 0 || m_bendRange == 0` (bend lane), plain
  decimal for the mod lane, else `±%.2f st`; range limits `"0 st"` when the
  range is 0. `git grep "∅" fceecd88` and `git log --all -S'∅'` find nothing.
  Swift's strings are already identical
  (`src/swift/app/pitchbend/PitchBendScene.swift:208-219`). The real defect
  is the **font family**: fork renders the readout in
  `typography::bodyMono` = `Atkinson Hyperlegible Mono`
  (`src/ui/pitchbendeditor.cpp:349-350`, `src/ui/typography.cpp`
  `monoFamily`) whose zero is plain; Swift's
  `src/swift/app/pitchbend/PitchBendPresenter.swift:63` publishes
  `"monospaceFont": ["pixelSize": fontPx]` with **no family**, so
  `Qt.font(...)` in `src/ui/songview/quick/PitchBendPopup.qml:47,130`
  resolves the shell's proportional `Atkinson Hyperlegible Next`, whose zero
  glyph is slashed — rendering `0 st` as ∅-like `∅ st`. The inventory's
  QWidget-shows-∅ reading is inverted; the ∅ shape is Swift's.
2. **4 grid combobox affordance.** fork `src/ui/songview/quick/RulerControls.qml`
   (hosted in the ruler gutter at full gutter width, `TimelineCanvas.qml:236-244`)
   lays out one row: a `Grid` label (`primaryText`), then two combobox
   buttons — division (`ruler.divisionText`) and feel (`ruler.feelText`) —
   each a bordered Rectangle (border 1, `buttonOutline`) on
   `buttonBackground`, hover `buttonHoverBackground`, pressed
   `buttonPressedBackground`, label `buttonText`, plus a right-aligned `▾`
   (U+25BE) arrow in `buttonText` (RulerControls.qml:39-178). Appearance from
   `TimeRuler::syncGridControlAppearance`
   (`src/ui/songview/timeruler.cpp:128-152`): `combo_background` → preset
   `control_hover_background`, `combo_text` → `window_text`,
   `combo_outline` → `outline`, `combo_drop_down_hover_background` →
   `control_hover_background`, `combo_drop_down_pressed_background` →
   `control_pressed_background`, `primaryText` → `song_view_primary_text`.
   Feel strings `Straight`/`Triplet` (`timeruler.cpp:113-116`); division
   strings `Auto`/`Clock`/`1/%1` (`timeruler.cpp:65-76`). Swift
   (`src/ui/songview/quick/swiftroll/EditorSurface.qml:180-234`) stacks two
   unbordered centered `Text` items (`Auto`, `Straight`) with no `Grid`
   label, no border, no arrow. Swift's publishers
   (`src/swift/app/roll/PianoGrid.swift:556-559`) already emit
   `Auto`/`Straight` defaults.
3. **8a song-tab close glyph.** fork uses `QTabWidget` with
   `setTabsClosable(true)` + `setDocumentMode(true)`
   (`src/ui/workspaceui.cpp:146-153`); macOS renders the standard unboxed ✕.
   Swift loads `tabart/window-close.svg` — Font Awesome's windowed close
   (outer box + X, `src/ui/songview/quick/swiftroll/SongTabs.qml:245`,
   `tabart/window-close.svg` viewBox `0 0 512 512`) — rendering as ☒.
4. **8b transport glyphs.** fork has **no icon assets** for transport: it
   tints platform standard pixmaps per state
   (`src/ui/transportbar.cpp:230-251` `tintedIcon`: normal
   `transport_text`, hover `button_hover_text`, pressed/checked
   `button_pressed_text` — all resolving to `window_text` in these presets —
   disabled `disabled_text`) over `refreshIcons()`
   (`transportbar.cpp:511-521`): go-to-start `SP_MediaSkipBackward`, play
   `SP_MediaPlay`, pause `SP_MediaPause`, stop `SP_MediaStop`, loop
   `SP_BrowserReload`, follow `SP_MediaSeekForward`, resonance
   `SP_MediaVolume`, highlight `:/icons/flat-music.svg`. On macOS those are
   solid media glyphs (filled triangle, filled bars, filled square, double
   triangles, triangle+edge-bar). Checked buttons show the pink pressed
   background (`control_pressed_background`) under a window-text glyph.
   Swift: hollow Font Awesome outlines for play/pause/follow/loop
   (`resources/transport-*.svg`, rendered via MultiEffect tint in
   `src/ui/shell/TransportButton.qml`), raw text glyphs `◀◀`, `■`, `◖))` for
   go-to-start/stop/resonance (`src/ui/shell/TransportBar.qml:77-172`), and
   follow renders fast-forward `▶▶` instead of a seek bracket-arrow.

# Exact write set

- `src/swift/app/pitchbend/PitchBendPresenter.swift` — add the mono family
  (`Atkinson Hyperlegible Mono`, the constant already used in
  `src/swift/app/timeline/GridTypography.swift:101`; reuse, do not duplicate
  the literal) to the `monospaceFont` entry. No QML edit: the popup resolves
  `Qt.font(appearance.monospaceFont)`.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml:180-234` — replace the
  two stacked plain `Text` items with one row matching fork RulerControls:
  `Grid` label + two bordered controls with `▾` arrow, bound to
  `root.gridModel.palette` (`buttonHoverBackground` as the resting/hover
  field surface per the `combo_background` mapping, `buttonPressedBackground`
  pressed, `outline` border, `buttonText` ink, `primaryText` label).
  Keep objectNames `timelineRulerDivisionControl`/`timelineRulerFeelControl`
  and the `openGridMenu` wiring; geometry from `baseFontPx` per the file's
  existing pattern and the existing single-pixel stroke token.
- `src/ui/songview/quick/swiftroll/tabart/window-close.svg` — replace with an
  unboxed xmark (plain diagonal cross, no outer frame), same tint pipeline
  (`icon.color` in SongTabs.qml:253-259, unchanged).
- `resources/` — replace `transport-play.svg`, `transport-pause.svg`,
  `transport-follow.svg` with solid single-color shapes (right triangle; two
  bars; right triangle with right edge bar); add
  `transport-gotostart.svg` (double left triangles) and
  `transport-stop.svg` (filled square); keep `transport-loop.svg` and
  `flat-music.svg`. Bind go-to-start and stop to the new assets in
  `src/ui/shell/TransportBar.qml:77-124` (drop their `symbol` text
  fallbacks); leave resonance's text glyph and all sizing/tinting
  (`TransportButton.qml`) untouched.
- Checks: readout/font predicates in `src/checks/rollcheck/pitch_bend.swift`
  (RED first), affordance predicates in
  `src/checks/editorqml/tst_ShellGridMenu.qml`. No new checks for 8a/8b —
  asset content is not predicate-observable without pixel tests; existing
  lanes must stay green.

# Prerequisites

Sequence after task 24 (owns the transport presenter and `ShellWindow.qml`
footer/title on the same surface; `TransportBar.qml` itself is not in task
24's write set). Task 22 owns event-list files only — disjoint from this
write set. `EditorSurface.qml` hosts the pitch-bend popup loader but the
file is unowned by tasks 22/24.

# Interface contract

- `monospaceFont` appearance entry carries the mono family; the readout
  strings stay exactly as today (`"0 st"`, `"+2.50 st"`, mod-lane decimal).
  Observable: the published appearance map, and (mounted) the popup readout
  `Text`'s resolved `font.family`.
- Grid controls: one row; division control shows `gridDivisionControlText`,
  feel control `gridFeelControlText`; each bordered control exposes a `▾`
  child Text and a background Rectangle whose color states are the palette
  roles above; menu activation behavior unchanged
  (`tst_ShellGridMenu.qml` selection predicates keep passing).
- Close glyph: bare ✕, no frame; existing close behavior, sizes
  (`closeExtent`/`scrollExtent`), and state colors unchanged.
- Transport: five solid SVGs, single path fill, transparent background,
  tinted by the existing `MultiEffect` pipeline at the existing
  font-derived sizes; button ids, actions, checked backgrounds unchanged.

# Implementation steps

1. Failing predicates first; record RED: `pitch_bend.swift` asserts the
   appearance map's `monospaceFont` family and pins readout strings
   (`"0 st"` at rest, `"+2.50 st"` at bendRange 2 / liveValue max, mod lane
   decimal); `tst_ShellGridMenu.qml` asserts each control contains a `▾`
   text child and a bordered background resolving to the palette role.
2. Presenter font family; SVG assets; EditorSurface control chrome;
   TransportBar icon bindings.
3. Lanes below; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-pitch-bend --verbose`
- `deno task verify:shell --filter shell-grid-menu --verbose`
- `deno task verify:shell --filter shell-transport --verbose`
- `deno task verify:shell --filter shell-tabs --verbose`
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`:
  recapture the pitch-bend popup, ruler gutter, tab strip, and transport bar
  in `immaterial`; compare against
  `/tmp/porydaw-qwidget-ref/{c-pitchbend,a-main-window}.png` and list
  remaining differences (readout zero must read as the plain Mono zero).

# Visual parity

Counterpart sources quoted in Context. Out of scope and to report if seen:
Swift division control strings `÷N`/`×N` vs fork `1/N`/`Clock` in non-Auto
states — that is a grid-model semantics gap (fork `GridSelection`
Auto/Clock/Musical, `src/ui/songview/grid.h`; Swift `snapScale`), not a
chrome fix; do not relabel without the model. Resonance glyph, loop glyph
shape, and the BENDR/LFO fields' chrome are unchanged.

# Task-specific constraints

- No new C++, no code comments, no pixel constants (sizes stay on the
  existing `baseFontPx`/stroke-token derivations).
- SVG assets are data: single-path solid glyphs, no embedded licenses beyond
  the repo's existing asset conventions (geometric paths authored for this
  repo, not copied Font Awesome outlines).
- No proof-ledger edits by the implementer. Rows to hand the controller's
  ledger agent: any `proof.*.txt` rows pinning pitch-bend readout strings or
  grid-control text (search `grep -rn "0 st\|divisionText\|Straight"
  src/checks/*/proof.*.txt`); disposition: re-map onto the new
  message-anchored predicates, keep GAP where only strings were pinned
  before and rendering remained unobserved.
