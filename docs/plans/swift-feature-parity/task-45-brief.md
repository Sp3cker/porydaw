# Context

SH02 note-face rendering modes (task 45). The three raster families of
`src/checks/rollcheck/proof.note_rendering.txt` — velocityColorRaster (A019–A034),
noteNameRaster (A035–A046), velocityValueRaster (A047–A054). Fork-main `fceecd88`.
Census preamble is stale: the ramp, the View-menu toggles, persistence
(`velocityNoteColors`/`noteNames`, ApplicationSession.swift:662-663,1312-1332) and
`NoteNameLabels` already landed (`1096534c`, task 25 f7c32ee6). What is actually
missing: (1) velocity-value labels during a velocity drag, (2) the preview-velocity
overlay into fills/labels during that drag, (3) mounted pixel predicates, (4) an
AA-clearing label-ink law — the fork's ink chooser fails WCAG AA on part of the ramp.

1. **Fork fill law** (`git show fceecd88:src/ui/songview/trackvoiceops.cpp`):
   `noteColor(track,velocity)` (:127-150) = 16×128 Oklab table — v0 the theme role
   `song_view_note_velocity_zero`, v127 the track identity, between
   `mixTowardOklab(identity, zero, 1 − v/127)`; `velocityNoteColor(velocity)`
   (:151-172) = zero at v≤0, else HSV-linear #5F44E9→#E90904 with t=(v−1)/126,
   8-bit quantized; `noteFillColor` (:173-175) switches on `m_velocityColorMode`.
   Swift `PaletteMath.noteFill/velocityNoteColor` (GridPalette.swift:103-138) already
   mirror this exactly — do not rewrite.
2. **Fork label raster** (`git show fceecd88:src/ui/songview/quick/
   timelinequickview_pianoroll.cpp:505-570`): one shared text model.
   `showVelocityValues` = velocity drag active OR the `roll.velocity_drag` hold
   (Ctrl/Cmd, keymap.cpp:168-171) matched against live keyboard modifiers. While
   shown, note-name records are suppressed (`nameFontVisible = !showVelocityValues
   && noteNameMode`). Per non-ghost visible note: value text
   `QString::number(previewVelocity(id).value_or(velocity))`, fit
   `noteRect.width() >= advance(text) + velocityLabelFitAllowance` (allowance =
   `lyt::fontPx(1/2)`, pianoroll_geometry.cpp:40), record on the full note box,
   AlignHCenter|AlignVCenter, ink `contrastingTextColor(fill)` (detail.cpp:180-190 —
   better WCAG ratio of the keyboard's natural/black key inks). Draw preview with
   the hold: `QString::number(m_lastVelocity)` on the preview box, same fit.
   Name records: text `keyName(key)` (detail.cpp:80-88), left-aligned in the
   half-space-inset box, only above `kNoteNameMinKeyH = 12` key height
   (songview.h:86) and when the fixed face's occupied height fits
   (pianoroll.cpp:145-161) — already ported in `NoteNameLabels.swift`.
   Fills during a drag also read `previewVelocity` (:242-249) — the dragged note
   re-hues live. Velocity-label face: `typography::fitted(appFont,
   floor(keyHeight − 1 physical px))` then pixelSize−1, hidden when the fit fails
   (pianoroll.cpp:148-151, pianoroll_geometry.cpp:230-232); no row-height gate —
   the fork check proves value ink at 8.6 px and 9.0 px key heights.
3. **Fork checks to close** (`git show fceecd88:src/checks/rollcheck/
   note_rendering.cpp`): velocityColorRaster (:259-350) — endpoint/zero/opaque/
   monotonic-hue law, ghost pixels byte-identical across the mode flip, sampled
   interior == `velocityNoteColor(100)`, mode-off restore, document untouched;
   noteNameRaster (:354-558) — ghost invariance, abutting short same-pitch pair
   unlabeled while a distant wide note keeps its label (ink contrast ≥ 2.5 vs the
   fill), label present at the exact padded row fit and hidden one pixel shorter,
   per-fill ink ≥ 4.0 on the v100 and v1 velocity fills; velocityValueRaster
   (:560-712, data rows 8.6/9.0) — during a Ctrl+drag on a sacrificial note, value
   ink appears inside another note's box and no pixel outside the box±its-height
   margin changes, document restored.
4. **WCAG AA resolution** (AA beats parity; computed over the exact ramps):
   the fork chooser (keyboardNatural #F4F4F4 / keyboardBlack #202224, fixed in all
   three themes) bottoms out at **3.84:1 on the velocity ramp (v=121, #E93907;
   17 velocities below 4.5)** and **3.83:1 on identity fills (#CD5454 v=127;
   5–21 fills per theme depending on the zero color: vanilla #8B847E,
   dark-neutral-high #A0A0A0, immaterial #979AA3)** — the fork's own "~3.8:1"
   comment. Fallback pair #FFFFFF/#000000 floors at **4.61:1** (velocity ramp,
   v=125) and **4.99:1** (identity ramp). Law: keep the fork keyboard ink whenever
   it clears 4.5:1, else the better of the fallback pair — floor ≥ 4.5 everywhere,
   fork ink preserved wherever it is legible. The fork's two probed fills pass
   either way (v100 10.63:1, v1 5.47:1).
5. **Current Swift seams**: `PianoGrid.previewVelocity(_:)` (PianoGrid.swift:
   164-168) exists but `GridSceneInput.notes` carries document velocities only —
   fills and labels never see the preview; `GridScene.rebuildNotes` emits name
   labels at :944-956 with no value path; `updatePointer(x:y:)` (:689) drops the
   modifiers MoveCoalescer already delivers (EditorSurface.qml:450,483-494).
   Mounted lane `shell-note-visuals` (tst_ShellNoteVisuals.qml:159-330) samples
   identity fills/borders/rings only.

# Exact write set

- `src/swift/app/timeline/GridPalette.swift` — `PaletteMath.aaContrastInk`;
  members `noteLabelAaLight`/`noteLabelAaDark`; `noteLabelInk(forFill:)`.
- `src/swift/app/timeline/GridTypography.swift` — `.noteValue` font kind, fitted
  velocity-label face (advance, occupied height, visibility gate).
- `src/swift/app/roll/NoteNameLabels.swift` — `NoteNameFace.velocity`;
  `valueLabels(...)` builder; `textColor` switches to the AA law; delete the
  "velocity-value labels are out of scope" doc lines.
- `src/swift/app/roll/GridScene.swift` — `GridSceneInput.showVelocityValues`;
  value-label emission, name suppression, draw-preview value label; faces carry
  velocity.
- `src/swift/app/roll/PianoGrid.swift`* — `updatePointer(x:y:modifiers:)`
  (defaulted param), pointer-modifier tracking, `showVelocityValues` derivation,
  preview-velocity overlay into `sceneInput().notes`.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — thread `modifiers` into
  `gridModel.updatePointer` (one line in the MoveCoalescer dispatch).
- `src/checks/rollcheck/note_rendering.swift` — extend `checkVelocityColorMode`
  and `checkNoteNameMode`; new `checkVelocityValues`.
- `src/checks/themecolor/ThemeColorChecks.swift` — `noteLabelContrastChecks`.
- `src/checks/editorqml/GatedVisualsProbe.swift` — `velocityFace(velocity:
  zeroColor:)`.
- `src/checks/editorqml/tst_ShellNoteVisuals.qml` — three new raster test
  functions (task 45 owns the file first; task-51a's dpr2 leg rebases after).
- Ledger (controller-delegated ledger agent, this task's commit):
  `src/checks/rollcheck/proof.note_rendering.txt`, rows A019–A054 only.

*PianoGrid.swift is sprint-hot (38/42); EditorSurface.qml is task-38-hot — take
the controller-sequenced slot after 38 lands, or land first and name the rebase.
Sizing exception: one behavior family (note-face text/fill display modes) over
10 files with one verification-surface set — named for the dispatch table.

# Prerequisites

None blocking — modes, ramp, labels plumbing all exist. Sequencing only:
after task 38 for the two *-files, else first-writer names the rebase;
tst_ShellNoteVisuals.qml before task-51a (agreed with BriefRollResidual).

# Interface contract

- `PaletteMath.aaContrastInk(fill: String, light: String, dark: String,
  fallbackLight: String, fallbackDark: String) -> String` — the fork
  `contrastingTextColor` pick when its ratio ≥ 4.5, else the better-ratio
  fallback. `GridPalette.noteLabelAaLight = "#FFFFFF"`,
  `noteLabelAaDark = "#000000"` (fixed, all themes, like the polyphony cell
  inks); `noteLabelInk(forFill:)` delegates with keyboardNatural/keyboardBlack.
  `NoteNameLabels.textColor` and every value-label ink use it.
- `GridFontKind.noteValue`: body face fitted to
  `floor(keyHeight − pixel)` then −1 px (min 1); `GridTypography.init(fonts:
  rowHeight:pixel:)` (pixel defaults so TypographyLayoutChecks compiles
  untouched) exposes `noteValueAdvance(_ text: String) -> Double`,
  `noteValueOccupiedHeight`, `noteValueVisible` (false when the fit fails —
  fork nullopt), and the face rides `fontSpec(.noteValue)`.
- `GridSceneInput.showVelocityValues: Bool = false`. `NoteNameFace` gains
  `velocity: Int`. `GridScene` publishes into `pianoNoteTextModel`: when
  `showVelocityValues` and the face is visible, one record per non-ghost
  visible note — text `String(velocity)` (preview-overlaid), rect the full
  note box, AlignHCenter(0x4)|AlignVCenter(0x80), ink `noteLabelInk(forFill:)`,
  fit `width >= noteValueAdvance(text) + fontPx(baseFontPx, 0.5)`; name records
  are suppressed while values show; ghosts never labeled either way. With
  `drawPreview` and `showVelocityValues`: one record `String(lastVelocity)` on
  the preview box under the same fit.
- `PianoGrid.updatePointer(x: Double, y: Double, modifiers: Int = 0)` —
  existing callers compile unchanged; the control-modifier state is tracked
  from press and move samples. `showVelocityValues` = velocity gesture active
  OR (draw-family gesture AND latest pointer sample carried the control
  modifier); cleared on release/cancel. During a velocity gesture,
  `sceneInput().notes` overlays `previewVelocity(noteId)` onto the dragged
  note's velocity (fills re-hue live in both color modes; labels read it).
- Preservation: name-label law, ghost fills, `pianoNoteFills` caching keys,
  View-menu dispatch/persistence, existing objectNames, and every existing
  predicate message stay unchanged. Frozen widget baselines unaffected (no
  geometry moves; labels are new delegates at existing font laws).

# Implementation steps

1. Palette ink law + typography face (pure additions); delete the stale
   NoteNameLabels doc lines.
2. `NoteNameLabels.valueLabels` + `NoteNameFace.velocity`; GridScene emission
   with suppression and the preview record.
3. PianoGrid plumbing: modifier tracking, `showVelocityValues`, preview
   overlay; EditorSurface one-line thread.
4. `note_rendering.swift`: extend `checkVelocityColorMode` (opaque 2…127 loop;
   hue monotonic 1…127; revision-unchanged across mode flips) and
   `checkNoteNameMode` (abutting short pair vs distant wide note seeded via the
   `ghostSeed` free-cell pattern; exact-fit row `occupiedHeight + 2·spaceHalf
   + 1` labels, one shorter hides; document restore). New
   `checkVelocityValues` at keyHeight 8.6 and 9.0: beginPointer with the
   control modifier + updatePointer dy on a seeded note → per-note value
   records (text/rect/alignment/ink/fit boundary one allowance short), name
   suppression, ghost skip, dragged-note fill == `noteFill(track, preview)` and
   velocity-mode fill == `velocityNoteColor(preview)`, preview-box label while
   drawing with the modifier, endPointer clears, undo restores revision+state.
5. `ThemeColorChecks.swift`: per preset — velocity-zero fill equals the preset
   disabledText role and is opaque; chooser floor ≥ 4.5 over velocity fills
   0…127 and identity fills 16×128; keyboard ink kept wherever it clears 4.5.
6. `GatedVisualsProbe.velocityFace`; `tst_ShellNoteVisuals.qml` three
   functions: (a) velocityColorRaster — `presenter.activate(
   "view.velocity_colors")` (tst_ShellMenus.qml:256 pattern), ghost-region
   pixel diff across the flip, interior sample == probe velocity fill at the
   published velocity, toggle-off restore sample; (b) noteNameRaster — names
   on, wide-note label ink pixels contrast ≥ 2.5 vs the sampled fill, ghost
   diff; (c) velocityValueRaster — mousePress(Ctrl)+mouseMove on a note
   (tst_ShellGridInput.qml:154-155 pattern), grab: ink inside the probed
   note's box differs from idle, no differing pixel outside box±box-height
   margin, release+undo leaves the document clean. Guard each on its fixture
   preconditions (visible other-track note for ghost rows).
7. Run the lanes; record RED→GREEN for the value-label predicates (must fail
   before step 3) and the ink-law change (old chooser expectation first).

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — note_rendering suites:
  ramp endpoints/monotonicity, name fit/suppression, value records, preview
  overlay, document integrity.
- `deno task verify --filter swiftcore-themecolor --verbose` — per-theme
  zero/opacity, ≥ 4.5 ink floors over both ramps, keyboard-ink preservation.
- `deno task verify:shell --filter shell-note-visuals --verbose` — the three
  mounted raster functions (native window; no audio needed).
- `deno task verify:qml-roll --verbose` — roll-window regression.
- `deno task verify:bridge`, `deno task format --check`.

# Task-specific constraints

- No new C++; no code comments — delete stale ones in edited regions; no
  palette literals in QML (probe helpers carry the math); sizing only through
  the fork's font laws (fitted faces, `fontPx(1/2)` allowance, half-space
  insets).
- Accepted fork deviations (record in ledger reasons, do not code around):
  the hold-without-pointer display (values while Ctrl is held with no pointer
  event) is unreachable in Qt Quick without new native code — values show
  during velocity drags and modifier-sampled draw drags, which is everything
  the pinned fork check exercises; the modifier is sampled from pointer
  events, not live-polled.
- Implementers never edit ledgers; the controller delegates
  `src/checks/rollcheck/proof.note_rendering.txt` to the ledger agent.
- Ledger mapping (agent: refresh the stale "not ported" reasons, add S rows,
  flip Dispositions):
  - A019/A035/A047 → the covering functions' fixture expects (seed guards).
  - A020/A021 → themecolor "velocity-zero fill equals the preset disabledText
    role" / "…is opaque" (per mode).
  - A026/A027/A028 → existing swiftcore "velocity 1 publishes the purple
    endpoint in palette format" / "velocity 127 publishes the red endpoint…" /
    "velocity zero uses the neutral palette fill".
  - A029/A030 → new "every velocity fill from 2 to 127 is opaque" / "velocity
    hue falls monotonically from purple to red".
  - A031/A036 → mounted "velocity-color mode changes no ghost note pixel" /
    "note-name mode changes no ghost note pixel" (upgrade the PARTIALs).
  - A032/A033 → mounted "velocity-mode note interior matches
    velocityNoteColor" / "disabling velocity-color mode restores the identity
    fill pixels".
  - A034/A046/A053/A054 → swiftcore document-integrity expects ("…leaves the
    document revision unchanged", "…restores the document").
  - A037–A040 → swiftcore width-probe expects ("an abutting short same-pitch
    note carries no label" ×2, "a distant wide note keeps its label").
  - A041 → mounted "wide-note label ink contrasts with its fill".
  - A042/A043 → "a row at the exact padded fit still labels" / "one pixel
    shorter the label hides instead of shrinking".
  - A044/A045 → "label ink is chosen against the bright velocity fill" /
    "…dark velocity fill" (swiftcore ink choice) + themecolor floor rows.
  - A048/A049/A050 → the drag probe's fixture expects.
  - A051/A052 → mounted "velocity drag renders value ink inside the note box"
    / "velocity drag changes no pixel outside the note box clip".
  - S rows (no fork A row): "velocity values replace note names while shown",
    "the dragged note's fill follows its preview velocity", "the draw preview
    carries the last velocity while the modifier is held", the themecolor
    floor rows.
- Other families in the ledger (A001–A018, A055+) are out of scope and stay
  untouched.

# Controller verification

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — only A019–A054 moved.
2. Visual: re-run `deno task verify:shell --filter shell-note-visuals
   --verbose`; confirm the value-ink grabs show digits centered on note faces
   during the drag and nothing outside the boxes changes.
3. Native smoke (desktop): launch the app, toggle View > Color Notes by
   Velocity and Show Note Names — fills sweep purple→red by velocity, names
   appear on wide notes at tall zoom and hide when rows shrink; Ctrl-drag a
   note vertically — every current-track note shows its live velocity number,
   the dragged note re-hues, release commits one undoable edit.
