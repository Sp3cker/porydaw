# Context

User report: "there is 0 consistency in the font size. Anywhere in the
application." User ruling 2026-09-25: one Swift typography authority, body
font propagated through QML window/popup roots (no C++).

User ruling 2026-09-25 (second): "We also used to size EVERYTHING based on a
multiple of the base font size. This must be how we still do things." Fork
`src/ui/layout.{h,cpp}` (`git show fceecd88:src/ui/layout.cpp`) resolves all
geometry from the same captured base: `space(Space)` with multipliers
Zero 0, Half 0.125, One 0.25, Two 0.5, Three 0.75, Four 1.0, Six 1.5,
Eight 2.0 → `max(1, round(base * m))` (0 stays 0); `fontPx(m)` =
`max(1, round(base * m))`; `fontPxF(m)` = `base * m` unrounded;
`singlePixel()` = logical hairline. The authority owns these too.

Fork-main `fceecd88` had one typography system
(`git show fceecd88:src/ui/typography.cpp`): `installBundledFonts` captures the
platform base font pixel size once (13 on macOS) and installs body =
Atkinson Hyperlegible Next at `qRound(base * 1.125)` (15) as the application
font. Roles: `bodyMono(body)` = Atkinson Hyperlegible Mono Regular at the body
pixel size, tnum, no hinting; `tableMono` = bodyMono + AbsoluteSpacing -0.5;
`caption(source)` = Next Normal at the captured base (13); `bold(source)` =
DemiBold at the source size; `regular`, `italic`; `fitted(base, h)` = largest
pixel size <= min(base px, caption px) whose ascent+descent <= h;
`noteName(source)` = caption face, Normal on macOS, DemiBold elsewhere. All
faces PreferNoHinting + tnum.

Audits (`agent://TypoShell`, `agent://TypoDocks`, `agent://TypoSongView`,
`agent://TypoDrawer`) and pixel measurements (`agent://TypoMeasure`) show four
competing Swift sources:

1. `Application.font` is never replaced, so it stays the platform system face
   at 13 px. Surfaces bound to it render the wrong family and size
   (ShellWindow passes it to SettingsDialog `ShellWindow.qml:499` and
   SongsDockColumn `:526`).
2. `ShellWindow.root.font` (body, 15 px, `ShellWindow.qml:20-28`) is passed
   down as an *application font* (`:552` SongTabs → EditorSurface, `:620`,
   `:636`) and presenters derive their **base** from its pixel size, so roll,
   event list, pitch popup and drawer laws scale 15 × 1.125 = 17 (double
   scaling: ruler numbers, Event List cells, key labels measure larger than
   the fork).
3. Presenter-local copies of the fork laws (`GridTypography.swift:101-126`,
   `TrackHeadersGeometry.swift:131-133`, `EventListMenus.swift:34-46`,
   `VoiceChangesPublication.swift:155-156`, automation caption maps,
   `PitchBendPresenter.swift` `monospaceFont`).
4. Ad-hoc multipliers in QML (`0.8 *`, `0.85 *`, `1.4 *`, `12 * page.unit`,
   `em * 0.83`, `grid ? grid.baseFontPx : 12`, `HorizontalFit` shrink).

This task builds the authority and fixes the base (sources 1-2 at the root).
Per-surface role binding (sources 3-4) is tasks 30-33, which depend on this
contract.

# Exact write set

- NEW `src/swift/app/typography/Typography.swift` — the fork role table as a
  pure value type (no QtBridge in this file).
- `src/swift/app/ApplicationSession.swift` — own one `Typography`, publish it,
  accept the one base capture.
- `src/swift/app/CMakeLists.txt` — register the new file.
- `src/ui/shell/ShellWindow.qml` — capture the base once, bind the window
  font to the published body role, stop passing `Application.font` or
  `root.font` as an application/base font to children; pass the session
  typography instead where a child takes an `applicationFont`/`baseFontPx`
  input today (keep the child property names this task; tasks 30-33 replace
  them).
- Every Swift presenter **base ingress** (the place a presenter receives
  `baseFontPx` or an application-font pixel size from QML: e.g.
  `EditorSurface.qml` configure paths, `PitchBendPopup` configure,
  EventList `configureTypography`, OtherEvents `configureViewport`, drawer
  `configureLayout`, grid metrics configuration) — the base it receives must
  be `typography.baseFontPx` (13 on macOS), never a body-derived size. Find
  them all (`grep -rn "baseFontPx\|applicationFont\|pixelSize" src/ui
  src/swift/app` scoped); list each in the report.
- Every top-level `Window`, `ApplicationWindow`, `Dialog`, `Popup`,
  `Menu` root under `src/ui` that does not inherit the ShellWindow font
  (separate windows: SettingsDialog, AboutDialog, prompts, native-style
  popups with `popupType: Popup.Window`) binds `font:` to the published body
  role.
- Checks: `src/checks/editorqml/tst_Typography.qml` (existing typography
  lane) and a Swift unit file for the role table (reuse the existing
  swiftcore check module that already tests GridTypography, e.g.
  `src/checks/rollcheck/`; find it).

# Interface contract

- `Typography(baseFontPx: Int)` (clamped >= 1). Properties, each a
  `GridFontSpec` (reuse the existing value type and its `map` shape; do not
  add a second font value type):
  `body` (Next, round(base*1.125), 400), `bodyBold` (Next, body px, 600),
  `bodyMono` (Mono, body px, 400), `tableMono` (Mono, body px, 400,
  letterSpacing `base * (-1.0/26.0)`), `caption` (Next, base, 400),
  `captionBold` (Next, base, 600), `noteName` (caption face; weight 400 on
  macOS, 600 elsewhere via `#if os(macOS)`). All specs carry tnum + no
  hinting as `GridFontSpec.map` already does. `bodyFontPx` and
  `baseFontPx` Ints. `fitted(_ role: GridFontSpec, availableHeight: Double)
  -> GridFontSpec?` implements the fork law (max = min(role px, caption px),
  step down by 1 px until ascent+descent <= height; nil if none) using the
  existing native metrics used by `GridTypography.fittedSize`.
- `ApplicationSession`: `public private(set) var typography: Typography`
  (default base 13); `configureTypography(baseFontPx: Int)` — first call
  wins (fork captures once), later calls with a different value are
  ignored; publishes `typographyFonts` (QtBridge map `{body, bodyBold,
  bodyMono, tableMono, caption, captionBold, noteName}` of font maps),
  `baseFontPx`, `bodyFontPx`, and a change signal. Presenters owned by the
  session/workspace read `session.typography` (inject it; no globals,
  no second copy).
- Layout tokens (same file, same base): `Typography.space(_ token:
  LayoutSpace) -> Int` for `.zero .half .one .two .three .four .six .eight`
  with the fork multipliers above, `fontPx(_ m: Double) -> Int`,
  `fontPxF(_ m: Double) -> Double`. The existing
  `GridGeometry.fontPx(base, m)` stays the single rounding law and is called
  with `typography.baseFontPx` (delete any duplicate rounding helper you
  find; do not add a second one). Session publishes `layoutSpaces` (QtBridge
  map `{zero, half, one, two, three, four, six, eight}` → Int) so QML
  paddings/spacings/margins bind tokens instead of literals or ad-hoc
  fractions; tasks 30-33 convert each surface's geometry to tokens or
  `fontPx` multiples of the base.
- ShellWindow: `FontInfo { font: Application.font }` is read exactly once,
  for the capture call; the window `font: Qt.font(shell.session.typographyFonts.body)`;
  `bodyFontPx` reads the session. No other QML reads `Application.font`
  after tasks 30-33; this task removes the ShellWindow pass-throughs.
- Observable result at base 13: every presenter base = 13; roll geometry
  derives from 13 (fork: keyboard width `fontPx(13, 13/3)` = 56); EventList
  body 15, table 15, header 13; ShellWindow font Next 15.

# Implementation steps

1. RED: swiftcore predicates for the role table at base 13 and 26 (exact
   family/px/weight/spacing per role; `fitted` against a small height);
   mounted `tst_Typography.qml` predicates: window font family/px equal the
   session body role; the EditorSurface grid `baseFontPx` equals
   `session.baseFontPx` (not bodyFontPx); SettingsDialog/About roots resolve
   the body family (not the system face).
2. Typography value type; session ownership/publication; ShellWindow capture
   and root binding.
3. Re-point every base ingress to the session base; delete the
   `root.font`/`Application.font` pass-throughs.
4. Separate window/popup roots bind the body role.
5. Run every lane (geometry-derived expectations should follow published
   metrics; if a check pinned a 15-based derived value, update it to the
   published law and report each such change). Report GREEN with predicate
   strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --verbose` (split with `--filter` per lane group
  if > 180 s)
- `deno task verify:qml --verbose`
- `deno task verify:qml-roll --verbose`
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`
  (main window + event list vs `/tmp/porydaw-qwidget-ref/a-main-window.png`,
  `b-event-list.png`).

# Visual parity

Counterpart: fork `src/ui/typography.cpp` (quoted above), `src/main.cpp`
install call, `src/ui/layout.cpp` space tokens. Expected visible change:
roll/drawer/event-list geometry shrinks to the fork's 13-based proportions;
separate dialogs switch from the system face to Atkinson Next 15. Surfaces
still binding ad-hoc sizes remain until tasks 30-33.

# Task-specific constraints

- No C++ (user ruling), no code comments, no pixel constants beyond the
  fork's role laws, no QWidgets.
- One authority: after this task no Swift file computes `* 1.125` or a
  caption size except `Typography.swift` and the existing presenter-local
  laws that tasks 30-33 remove (do not expand them).
- Text contrast unaffected (no color edits).
- No ledger edits by the implementer; list rows whose geometry/font
  expectations changed for the controller's ledger agent.
