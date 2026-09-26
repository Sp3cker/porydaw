# Context

Event List column sizing and row height parity (task-26 scope note "row height /
Data column proportions" moves here). Divergence verified against fork-main
`fceecd88` with captures `/tmp/porydaw-qwidget-ref/b-event-list.png`
(3998x2244 @2x = 1999x1122 logical) and
`/tmp/porydaw-swift-ref/t26-eventlist.png` (2160x1504 @2x = 1080x752 logical,
the ShellWindow default `bodyFontPx * 72`, ShellWindow.qml:21).

1. **The width/height law already matches; the font inputs do not.** Swift
   `src/ui/songview/quick/EventListPage.qml` is a law-for-law port of fork
   `git show fceecd88:src/ui/songview/quick/EventListPage.qml`:
   `columnCount 7 / resizableColumnCount 6` (lines 21-22 both), `rowHeight =
   max(1, ceil(tableMetrics.height + 6))`, `headerHeight`, `cellHorizontalPadding`,
   `rowHeaderWidth`, `summaryMinimumWidth` (fork lines 78-93, Swift lines 82-95),
   `persistedColumnWidth/minimumColumnWidth/columnWidth` with Summary =
   `max(summaryMinimumWidth, eventTable.width - persistedColumnsWidth())`
   (fork 124-156, Swift 140-163), `columnWidthProvider/rowHeightProvider`
   (fork 969-975, Swift 1002-1005). Pixel measurement confirms both captures
   render the six fixed columns at exactly 70/120/36/56/56/140 logical px.
   The divergence is upstream: **Swift publishes no fonts**, so every
   FontMetrics-derived quantity floats with whatever the platform resolves.
   - Fork law: `EventListController::rebuildAppearance`
     (`git show fceecd88:src/ui/songview/quick/eventlistcontroller.cpp`
     lines 141-210) publishes `bodyFont = QApplication::font()`,
     `tableFont = typography::tableMono(body)`, `headerFont =
     typography::caption(typography::bodyMono(body))`, `controlFont = body`.
     `src/ui/typography.cpp` defines: body = Atkinson Hyperlegible Next at
     `qRound(capturedBaseFontPx * 1.125)` (`bodyScale = 1.125`,
     `installBundledFonts`); `tableMono` = Atkinson Hyperlegible Mono at the
     body's resolved pixel size with `QFont::AbsoluteSpacing` **-0.5**, tabular
     numbers, no hinting; `caption` = proportional face reset to the captured
     **baseFontPx**; on macOS the platform default resolves to baseFontPx 13,
     body 15.
   - Swift: `EventListAppearance.roles(palette:)`
     (src/swift/app/eventlist/EventListMenus.swift:34-64) publishes colors
     only — no font keys — so the page falls back
     (src/ui/songview/quick/EventListPage.qml:40-46): `controlFont =
     Qt.application.font` (unstyled system face/size), `bodyFont = controlFont`,
     `tableFont` = generic `"monospace"` at that size (Menlo on macOS: no
     negative tracking, wider advances), `headerFont = bodyFont` (no caption
     size drop). Consequences measured in the captures: fork rows are 42 phys
     px = 21 logical (Atkinson Mono @15px metrics height ~14.4 + 6); the t26
     Swift rows are 44 phys = 22 logical (Menlo @13px height ~16 + 6); the
     task-22 vanilla Swift capture (`b-event-list.png`) rows are 42 phys = 21
     logical only because that run resolved a 12px fallback. Row height thus
     tracks the platform font, not the fork's typography. Menlo's wider
     advances also inflate `summaryMinimumWidth` ("End of track" with no
   -0.5 tracking), which at the 1080-logical default window collapses Summary
   to its minimum, elides the header to "Summ…" and gives the horizontal
   scrollbar a real thumb (handle measured at x1755-2064 phys in t26); the
   fork capture shows Summary taking the remaining ~936 logical px with an
   empty thumb range. Note the fork window in the reference is 1999 logical
   wide while the Swift capture uses the 1080 default — the fork's own law
   squeezes Summary identically at narrow widths (Summary bottoms out at
   `summaryMinimumWidth` and the table scrolls); parity means the same law
   with the fork's fonts, not a wider window and not hiding the always-present
   scrollbar lane (`externalVisible: controller.visible`, fork QML 1031-1053).
2. **Default column widths are unchecked pixel constants.** The fork seeds
   `m_columnWidths{70.0, 120.0, 36.0, 56.0, 56.0, 140.0}`
   (eventlistcontroller.h:182; resize clamp `max(24.0, width)` at cpp
   1013-1023) and its QML treats a *missing* entry as "use default"
   (fork QML 124-129). Swift duplicates the literal twice:
   `EventListPresenter.swift:46` (`columnWidths` initial value — the effective
   authority, consumed by `savedColumnWidth`, lines 303-305) and
   `EventListPage.qml:23` (`defaultColumnWidths`, reachable only when
   `controller` is null — dead, since `presenter` is a required property).
   Repo rule: geometry comes from font metrics. The established conversion is
   `fontPx(base, multiplier)` (src/swift/app/timeline/GridGeometry.swift:4-6)
   with fork pixel values expressed as fractions of the 13px seed (e.g.
   `keyboardWidth = fontPx(b, 13.0 / 3.0)` for the fork's 56,
   GridGeometry.swift:76; PitchBendGeometry.swift uses the same style).
   Defaults derived as `fontPx(baseFontPx, k / 13.0)` for k in
   {70, 120, 36, 56, 56, 140} equal the fork exactly at base 13 and reproduce
   the fork proportions at any base font. Letter spacing follows the same
   convention as the ruler's `-1.0/24` em (GridGeometry.swift:92): the fork's
   absolute -0.5 at seed 13 is `-1/26` em of the base.
3. **Everything else is already fork-correct**: header labels/alignment,
   minimum-width clamp `max(ceil(2 * tableMetrics.height), label advance +
   2 * headerHorizontalPadding)`, row-number gutter, scrollbar breadth
   `max(10, ceil(tableMetrics.height * 0.85))`, resize handles (8px MouseArea
   per column 0-5). No QML geometry-law change is in scope.

# Exact write set

- `src/swift/app/eventlist/EventListPresenter.swift` — store the typography
  base (seed 13), add `configureTypography(baseFontPx:)`, rebuild
  `appearance` from `EventListAppearance.roles(palette:baseFontPx:)`,
  replace the `columnWidths` literal with an empty store plus a
  default-fallback in `savedColumnWidth`; bump `columnWidthsRevision` from
  `configureTypography`.
- `src/swift/app/eventlist/EventListMenus.swift` — `EventListAppearance.roles`
  gains a `baseFontPx` parameter and publishes `bodyFont`, `tableFont`,
  `headerFont`, `controlFont` maps built with `gridBodyFamily`/`gridMonoFamily`
  and `fontPx` (same module, GridTypography.swift:29-30 and
  GridGeometry.swift:4-6).
- `src/swift/app/eventlist/EventListSelection.swift` — `dispatchResizeColumn`
  (lines 77-84) pads the store to six entries from the current defaults
  before assigning, keeping the `max(24, width)` clamp and revision bump.
- `src/ui/songview/quick/EventListPage.qml` — delete `defaultColumnWidths`
  (line 23) and its null-branch use (line 143; branch falls back to
  `minimumColumnWidth(column)`); add `objectName:
  "eventListColumnHeaderLabel" + sectionColumn` to the header label Text
  delegate. The four font properties (lines 40-46) and every geometry law
  stay untouched.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — a `FontInfo` on
  `root.applicationFont` beside `applicationFontMetrics` (~line 114), and a
  `configureTypography(Math.max(1, Math.round(...)))` push in
  `eventPage.onLoaded` (lines 497-505) and on application-font change,
  mirroring the pitch-bend precedent at lines 919-931.
- `src/checks/eventviews/EventListPageChecks.swift` — new
  `eventListTypographyParity` section invoked from
  `runEventListPageChecks`.
- `src/checks/editorqml/tst_ShellEventList.qml` — new mounted test covering
  the font contract, default-width derivation, and Summary/overflow
  geometry.

# Prerequisites

Sequence after task 26 lands (it owns the `EditorSurface` `eventListHost`
mount and the mounted layout predicates in `tst_ShellEventList.qml` that this
brief extends). Task 27 (Other-events band) also edits `EditorSurface.qml`
(`rollBandContent`, `configureViewport`); this brief's `EditorSurface` diff is
confined to the `eventListHost` block and one `FontInfo` sibling — the
controller serializes the two landings, either order, no shared lines. No
palette, shell-window, or roll files are touched; Brief25Colors and task 24
are disjoint.

# Interface contract

- `configureTypography(baseFontPx:)`: clamps the base to >= 1, stores it,
  rebuilds `appearance` (colors from the session palette unchanged, fonts
  from the new base) and bumps `columnWidthsRevision` so the page's
  `persistedColumnWidth` bindings re-evaluate. Idempotent; called at mount
  and on application-font change; never clears user-resized entries.
- Published fonts (map shape of `GridFontSpec.map`, GridTypography.swift:10-27;
  consumed by the page's existing `font`-typed properties via value-type
  coercion): `bodyFont`/`controlFont` = Atkinson Hyperlegible Next at
  `fontPx(base, 1.125)`; `tableFont` = Atkinson Hyperlegible Mono at the same
  pixel size with `letterSpacing = base * (-1.0 / 26.0)`, `tnum`, no hinting;
  `headerFont` = Atkinson Hyperlegible Next at `fontPx(base, 1.0)` (the fork
  caption law: header at baseFontPx, body at base * 1.125, so the header is
  always smaller than the body). Theme refresh (`refreshAppearance`,
  ShellPresenter.swift:484) keeps the stored base.
- Default widths: `savedColumnWidth(column)` returns the stored resize when
  present, else `fontPx(base, k / 13.0)` with k = 70, 120, 36, 56, 56, 140
  (exactly the fork defaults at base 13; the fork QML's missing-entry law).
  `columnWidths` starts empty; `dispatchResizeColumn` grows it to six entries
  padded with current defaults; the >= 24 clamp and revision bump are
  unchanged. `resizeColumn` from QML keeps clamping to
  `minimumColumnWidth(column)` first, as today.
- Page geometry laws are frozen as the fork contract: `rowHeight =
  max(1, ceil(tableMetrics.height + 6))` (compact rows: 21 logical at the
  shipped 13/15 fonts), Summary = `max(summaryMinimumWidth,
  eventTable.width - persistedColumnsWidth())`, horizontal scrollbar lane
  always present with `maximum = max(0, contentWidth - width)` (thumb only
  under real overflow).
- Summary-fit invariant (the acceptance core): whenever
  `eventTable.width >= persistedColumnsWidth() + summaryMinimumWidth`, the
  mounted table has `contentWidth == width`, `eventListHorizontalScrollBar`
  reads `maximum == 0`, and the Summary header label
  (`eventListColumnHeaderLabel6`) is not truncated; under that width Summary
  pins to `summaryMinimumWidth` and the scrollbar range opens — the fork's
  squeeze, reproduced.

# Implementation steps

1. Write the failing predicates first and record RED.
   - `EventListPageChecks.swift` (swiftcore): fresh presenter publishes the
     four font maps with the law above (family strings, body/caption pixel
     sizes, `-base/26` tracking) at the 13 seed; `configureTypography(26)`
     doubles pixel sizes, tracking and all six default widths
     ([70,120,36,56,56,140] -> [140,240,72,112,112,280]);
     `configureTypography(10)` yields `round(10 * k / 13)`; `resizeColumn(1, 200)`
     survives a later `configureTypography` while untouched columns re-derive;
     `refreshAppearance` after a theme swap keeps the fonts.
   - `tst_ShellEventList.qml`: after the existing mount in
     `test_filterAndEditOnMountedPage` style, assert `page.tableFont.family
     === "Atkinson Hyperlegible Mono"`, `page.controlFont.family ===
     "Atkinson Hyperlegible Next"`, `page.tableFont.pixelSize ===
     page.controlFont.pixelSize`, `page.headerFont.pixelSize <
     page.controlFont.pixelSize`, `page.tableFont.letterSpacing ===
     -page.headerFont.pixelSize / 26` (within 1e-6), and per column c < 6
     `page.persistedColumnWidth(c) === Math.max(page.minimumColumnWidth(c),
     Math.round(page.headerFont.pixelSize * k_c / 13))`; `page.rowHeight ===
     Math.ceil(tableFontMetrics.height + 6)` from a test-declared
     `FontMetrics { font: page.tableFont }`. All are RED today (families are
     system/monospace, tracking 0, header == body, widths absolute).
2. Presenter typography: add the base storage + `configureTypography`, extend
   `EventListAppearance.roles(palette:baseFontPx:)` with the four font maps,
   switch `columnWidths` to the empty store with the `savedColumnWidth`
   default fallback, and pad the store in `dispatchResizeColumn`.
3. `EditorSurface` push: `FontInfo` on `applicationFont`; call
   `configureTypography(Math.max(1, Math.round(applicationFontInfo.pixelSize)))`
   in `eventPage.onLoaded` and when the application font changes.
4. QML page cleanup: drop the `defaultColumnWidths` literal and null-branch
   constant use; add the header-label objectNames.
5. Add the mounted geometry guards (GREEN once steps 2-4 land, they pin the
   contract): at the 1100x720 fixture — `eventListTable.contentWidth <=
   eventListTable.width + 0.5`, `eventListHorizontalScrollBar.maximum === 0`,
   `eventListColumnHeaderLabel6.truncated === false`,
   `page.columnOffset(6) + page.columnWidth(6) <= eventListTable.width + 0.5`;
   then narrow the shell to the computed squeeze width (trackHeaderWidth +
   rowHeaderWidth + persistedColumnsWidth + summaryMinimumWidth - epsilon,
   restored afterwards) and assert the fork squeeze: Summary ==
   `page.summaryMinimumWidth`, label truncated, `maximum > 0`.
6. Run the lanes below; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-event-list --verbose`
- `deno task verify:shell --filter shell-menus --verbose`
- `deno task verify:qml-roll --verbose` (EditorSurface is touched)
- `deno task verify:bridge`
- Controller visual acceptance: relaunch per skill
  `porydaw-qwidget-reference-capture`, capture the Event List in the
  reference theme at a window at least as wide as the fork reference (or
  maximized), and compare against `/tmp/porydaw-qwidget-ref/b-event-list.png`:
  Tick/Type/Ch/Data 1/Data 2/Data/Summary all visible with Summary taking the
  remaining width, compact rows, no horizontal thumb. Report measured column
  ratios and row height next to the fork numbers above.

# Visual parity

Counterpart: fork-main `fceecd88` `src/ui/songview/quick/EventListPage.qml`
(column/row laws, lines 20-157, 778-830, 952-1090),
`src/ui/songview/quick/eventlistcontroller.cpp` (`rebuildAppearance`
141-210, `resizeColumn` 1013-1023, `headerLabels` 240-244),
`src/ui/songview/quick/eventlistcontroller.h:182` (width defaults),
`src/ui/typography.cpp` (`installBundledFonts`, `bodyMono`, `tableMono`,
`caption`), `src/ui/layout.cpp` (font-multiplier space tokens, 33-45).
Reference capture: `/tmp/porydaw-qwidget-ref/b-event-list.png`. Measurement
notes for the report: the t26 Swift capture carries an open chunk-menu
overlay on the left (blue selection fill) — measure columns right of it; the
two captures use different window widths (1999 vs 1080 logical), so compare
column *widths and row heights*, not Summary share, unless recaptured at a
matching width. Known remaining differences out of scope: track-header width
and the ruler span over the header column (pre-existing Swift layout, task-26
note), Other-events strip (task 27), cell editor faces beyond the numeric
tracking contract (A016-A018 decide in the ledger).

# Task-specific constraints

- No new C++, no code comments, no pixel constants: default widths and
  tracking are `fontPx(base, k / 13.0)` / `base * (-1 / 26)` fractions of the
  base font (k in {70, 120, 36, 56, 56, 140} is the fork's own default set,
  eventlistcontroller.h:182); the additive row/header padding laws (+6/+8,
  /3, *0.85, *2) are the fork's verbatim rules and stay as shipped in the
  ported page.
- Fonts flow only through the presenter appearance map (one authority, the
  session `GridPalette` for colors; no cached font copies in QML); the page's
  fallback fonts remain for the impossible null-controller path.
- No palette/role or contrast edits; existing WCAG AA pairs are untouched.
- The horizontal scrollbar lane stays mounted whenever the list is visible
  (fork `externalVisible` law); only its range may be empty. Do not "fix" the
  squeeze by hiding chrome or widening columns.
- No proof-ledger edits by the implementer. Rows to hand the controller's
  ledger agent: `src/checks/eventviews/proof.chrome.txt` A012-A018
  (monoTypography: cell/editor family, AbsoluteSpacing, letterSpacing -0.5 —
  the new font contract and mounted family/tracking predicates may map them),
  A019-A025 (columnResizeDrag — resize still works through the padded store),
  and the "No predicate asserts the mounted table's cell geometry" rows
  (A075, A084, A116) for the new Summary/overflow geometry predicates; the
  agent decides dispositions.
