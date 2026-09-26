# Context

Task 29 builds the typography authority; this brief binds every SHELL CHROME
text element and every geometry value to it. Area: ShellWindow children
(status text, polyphony meter, grid context menu, Polyphony Debugger dock
title/close), TransportBar (clock, key/scale combos, Fold, Volume caption +
DragInput field, Output caption, dial), TransportButton glyph fallback,
PolyphonyPanel + PolyphonyChannelGroup, AboutDialog, SettingsDialog and its
pages, SongConfirmDialog (shell-owned: instantiated `ShellWindow.qml:630-643`).

Fork ground truth (`agent://TypoShell` verified against `fceecd88` source +
pixel measurements `agent://TypoMeasure`; the audit's role guesses were
wrong in six places): app font = body 15 (`src/ui/typography.cpp:62-64`);
every toolbar/settings widget inherits it (no `setFont` in
`transportbar.cpp`, `settingsdialog.cpp`, `enginesettingsdialog.cpp`,
`songsettingsdialog.cpp`); clock + PCM/CGB meter values are FastLabels
painting `bodyMono(font())` (`src/ui/fastlabel.cpp:15,62`); status-bar hint
region pinned to caption 13 (`src/ui/mousehints/widgethints.cpp:480`);
poly meter re-pinned to app body (`src/mainwindow.cpp:678`); lost-notes
value is a plain QLabel (`mainwindow.cpp:692`); poly cells =
`caption(font())` (`polyphonypanel.cpp:100`); group captions paint with the
widget body font (`polyphonypanel.cpp:204-209`); section headings = `bold` =
DemiBold 600 (`polyphonypanel.cpp:286,298,349`; `typography.cpp:158-165`);
table headers and log rows inherit body. Toolbar-is-body proof: fork caps
M/V ≈ 10.5-11 px vs Swift 9 (ratio ≈ 13/15) on key/scale combo, Volume
label/digits (`agent://TypoMeasure` rows).

# Exact write set

- `src/ui/shell/ShellWindow.qml` — status text, meter texts, dock title,
  context menu font, transport/dialog pass-throughs, geometry tokens.
- `src/ui/shell/TransportBar.qml` — delete `toolbarFont`/`clockFont`
  (:17-18), role/inheritance bindings, geometry tokens.
- `src/ui/shell/TransportButton.qml` — glyph fallback font (:38-39).
- `src/ui/shell/PolyphonyPanel.qml` — `applicationFont`/`boldFont`/
  `headerFont` (:11-17) → typography; `em` re-based to session base.
- `src/ui/shell/PolyphonyChannelGroup.qml` — caption/cell fonts (:17-18,:42-43).
- `src/ui/shell/AboutDialog.qml` — drop `applicationFont` (:21,:43,:51).
- `src/ui/shell/settings/SettingsDialog.qml` — drop `applicationFont`
  (:9,:22,:24-27), Bold tabs (:77,:95), `unit` re-source (:10).
- `src/ui/shell/settings/EngineSettingsPage.qml`,
  `src/ui/songview/.../SongSettingsPage.qml` — drop `applicationFont`,
  `12 * unit` + Bold label laws, Bold controls.
- `src/ui/songview/quick/docks/SongConfirmDialog.qml` — drop `applicationFont`
  (:11-13), label/checkbox font lines (:33,:42,:56). NOT `DragInput.qml`
  (transport caller binds the role; other callers belong to briefs 31-33).
- Checks: `tst_ShellTransport.qml`, `tst_ShellPolyphony.qml`,
  `tst_ShellSettings.qml`, `tst_ShellWindow.qml`, `tst_ShellTheme`'s
  `tst_Theme.qml` (owns `shellGridContextMenu`), `tst_ShellMenus.qml`
  (about), `tst_ShellSongs.qml` (song confirmation). No Swift sources.

# Prerequisites

After task 29 (owns `ShellWindow.qml` root font/capture,
`ApplicationSession`, `Typography`, pass-through removals at :499/:526/:552).
`ShellWindow.qml` is shared with 29 (root block) and briefs 31
(SongsDockColumn :516-536) / 32 (SongTabs loader :549-560); task 30 edits
disjoint ranges (footer :660-767, context menu :769-827, poly dock
:576-628, transport header :644-659, confirm loader :630-643, size :21-22).
`SongConfirmDialog.qml` is under `docks/` but shell-owned — brief 31 must
not write it. `DragInput.qml` is never edited (songview/drawer callers are
briefs 32/33).

# Interface contract

Element inventory — fork role (`fceecd88` file:line) | Swift now | target:

| Element (Swift file:line) | Fork | Target |
|---|---|---|
| ShellWindow empty-song msg `:570` | none (empty tab) | inherit body (drop line) |
| Poly dock title `:600-601` | body regular, `mainwindow.cpp:587` no setFont | inherit body (drop Qt.font+Bold) |
| polyClose × `:604-610` | platform close glyph | unchanged (inherits) |
| Status text `:671` | caption `widgethints.cpp:480` | `Qt.font(typography.caption)` |
| PCM/CGB/· captions, lost value, notes-lost `:688,710,716,739,754,763` | body `mainwindow.cpp:678-701` (lost value QLabel :692) | inherit body (drop lines) |
| PCM/CGB values `:702,730` | bodyMono FastLabel `mainwindow.cpp:684,689` + `fastlabel.cpp:15,62` | `Qt.font(typography.bodyMono)` |
| MenuBar items `:251-492` | native NSMenu both | unchanged (platform) |
| Context menu `:774`, item caption/hint `:795-811` | QMenu app font body | menu font = `Qt.font(typography.body)`, items inherit |
| Transport clock `:183` (+`clockMetrics :34`) | bodyMono `transportbar.cpp:312-317` | `Qt.font(typography.bodyMono)` |
| Root/type combos `:238,259` | body `transportbar.cpp:318-352` | inherit body |
| Fold `:302` | body `transportbar.cpp:353-362` | inherit body |
| Volume/Output captions `:333,366` (+`captionMetrics :38`) | body `transportbar.cpp:381-388,412-419` | inherit; metrics = `typography.body` |
| Volume DragInput field (`inputAppearance.font :41`) | body QSpinBox `transportbar.cpp:392-405` | `Qt.font(typography.body)` |
| Output dial/tooltips | no text / platform tooltip | unchanged |
| TransportButton glyph `:38-39` | no fork text path (SVG `transportbar.cpp:230-262`) | drop pixelSize law, inherit body; `radius :23` keeps glyph-derived |
| Panel solo checkbox `:53`, Reset `:150`, notice `:106`, header row `:187`, row cells `:236`, empty `:250`, log rows `:293` | body `polyphonypanel.cpp:216,286+,315-332` | inherit body |
| Panel headings `:78,141,263` | bold(body)=DemiBold 15 `polyphonypanel.cpp:286,298,349` | `Qt.font(typography.bodyBold)` (fixes weight 700→600) |
| Group caption `:17-18` | body regular `polyphonypanel.cpp:204-209` | inherit body (drop px+DemiBold) |
| Group cell labels `:42-43` | caption 13 regular `polyphonypanel.cpp:100` | `Qt.font(typography.caption)` (kills 0.83) |
| About body Label `:51` | body (QMessageBox app font) | inherit; `aboutMetrics` → dialog font |
| Settings tabs `:77,95`, buttons, headings `Engine:37,57,75` `Song:32,62,80,100`, all controls, note `Song:142` | body regular (no setFont in the three fork dialogs) | inherit body (drop Bold + `12*unit` font laws) |
| SongConfirm labels/checkbox `:33,42,56` | body (QMessageBox) | inherit body |

Plumbing: ShellWindow passes `typography: shell.session.typographyFonts` and
`layoutSpaces`-derived values to TransportBar and PolyphonyPanel (Panels pass
the map to PolyphonyChannelGroup); `baseFontPx` inputs become
`shell.session.baseFontPx`. SettingsDialog keeps `unit` but sourced from the
session base (`unit = session.baseFontPx / 12` — same 13/12 value as today's
`Application.font` path, now from the authority).

Geometry (token/multiple of the one base; `fceecd88` citations):
- ShellWindow `:21-22` size `bodyFontPx*72/*48` → `fontPx(92)`, `fontPx(57)`
  (`mainwindow.cpp:154`). Poly dock width `:583` → `session.baseFontPx * 32`
  (fork: dock sizeHint, no pinned law). Title height `:593`
  `bodyMetrics.height*1.8` → `max(bodyMetrics.height, iconExtent) +
  2*layoutSpaces.half + 2` (`layout.cpp:503-507` chromeRowHeight).
  `:597` padding → `layoutSpaces.two`. Footer height `:661` → caption
  metrics height (`widgethints.cpp:96`); margins `:668-680` →
  `layoutSpaces.two`; `:682` space-width spacing stays (metric-derived).
  Menu `:790` padding → `layoutSpaces.one`; `:793` gap stays (metric).
- TransportBar: `toolExtent :19` keeps `min(base,12)*2.75` re-sourced to
  session base (stands in for style icon default, `transportbar.cpp:262`);
  `inset :20` → `layoutSpaces.one`; `:21` height → `toolExtent +
  layoutSpaces.two - 2`; `edgeMargin :23`/`spacing :72` → `fontPx(1/6)`,
  `fontPx(1/12)`; combo/fold/DragInput widths `:218-221,289,315-317,348-349`
  keep their calibrated constants but re-source base to session
  (`baseFontPx*4+7` etc.); outputFits `:24-30` re-sources base only.
- TransportButton extent `:19-22`/icon `:49` same re-source treatment.
- PolyphonyPanel `em :18` := `session.baseFontPx`; every existing
  `em * n/12` term then equals the fork law `fontPx(n/12)`
  (`polyphonypanel.cpp:176-178` cells 46/34/4/18/3, `:268` margin 8/12,
  `:337` table min 90/12, `:379` column 320/12, `:364` wide threshold
  fontPx(50) — also fixes Swift's wrong 750 px threshold to fork 650).
  `gap :19` → `layoutSpaces.two`; heading height `:23` stays `em*1.5`.
  ChannelGroup `:23,:49` spacing → `fontPx(4/12)`; caption height `:14`
  `em*1.5` ≡ fork caption band `fontPx(18/12)` at base 13.
- SongConfirm `:19,:30` re-source base to session; spacing → `layoutSpaces.four`.
- Settings pages keep their oracle-calibrated `unit` expressions (base
  multiples once unit = session base/12); 560×580 stays (`settingsdialog.cpp:45`).

# Implementation steps

1. RED first: add the mounted role/geometry predicates (below) to the seven
   check files; record failures against the current ad-hoc fonts.
2. ShellWindow: role bindings + token geometry; pass typography/session base
   to TransportBar, PolyphonyPanel; drop transport `toolbarFont`/`clockFont`
   pass-throughs (`:653-658`) and confirm-dialog `applicationFont` (`:636`).
3. TransportBar/TransportButton: delete font laws, bind roles, re-source geometry.
4. PolyphonyPanel/ChannelGroup: typography map in, `em` := base, roles for
   headings/cells, inheritance elsewhere.
5. Dialogs: drop `applicationFont` everywhere; SettingsDialog `unit` from
   session base; pages lose Bold/`12*unit` font laws; About/SongConfirm
   inherit; metrics re-pointed.
6. Run lanes; report GREEN with predicate strings and file:line; list any
   15-based geometry expectations updated to the published base law.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shellwindow --verbose`
- `deno task verify:shell --filter shell-transport --verbose`
- `deno task verify:shell --filter shell-polyphony --verbose`
- `deno task verify:shell --filter shell-settings --verbose`
- `deno task verify:shell --filter shell-menus --verbose`
- `deno task verify:shell --filter shell-theme --verbose`
- `deno task verify:shell --filter shell-songs --verbose`
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`
  vs `/tmp/porydaw-qwidget-ref/a-main-window.png` (toolbar grows to fork caps
  M/V 10.5-11; status text shrinks to caption; window 1196×741 at base 13).

Predicate shape (failing-first, message-anchored, no pixel constants): mount
ShellWindow, resolve elements by objectName, compare resolved
`font.family`/`font.pixelSize`/`font.weight` against the matching
`session.typographyFonts.<role>` entry (clock and PCM/CGB values == bodyMono;
lost value and inherited elements == body family/`bodyFontPx`; status text
and cells == caption; headings == bodyBold 600); geometry predicates compare
against `fontPx(m)`/`layoutSpaces.<tok>`/explicit base multiples of
`session.baseFontPx` (`shellWindow.width == fontPx(92)`, `transport.inset ==
layoutSpaces.one`, `panel.em == session.baseFontPx`, cell width fontPx(46/12)).

# Visual parity

Counterparts: `fceecd88` `src/ui/typography.cpp`, `src/ui/fastlabel.cpp`,
`src/ui/transportbar.cpp`, `src/mainwindow.cpp:154,584-610,673-701`,
`src/ui/mousehints/widgethints.cpp`, `src/ui/polyphonypanel.cpp`,
`src/ui/layout.cpp:503-507`, settings dialogs. Expected visible change:
toolbar combos/Fold/Volume/Output/DragInput grow 13→15 (Atkinson), settings
dialog switches system 13 → Atkinson 15 regular (headings lose fake bold),
poly headings 700→600 DemiBold, poly cells 12.45 DemiBold → caption 13
regular, group captions 15→inherit, status text 15→13, dialogs keep body 15.
Remaining known non-font differences: poly cell boxes stay Swift-sized until
a geometry task adopts every fork dim (this brief already maps them to
fontPx laws where fork cites them); native menu bar/tooltip fonts platform.

# Task-specific constraints

- No C++, no code comments, no pixel constants beyond fork-cited laws and
  the documented oracle constants; WCAG AA text contrast wins over any
  palette-adjacent change (none planned); no `Application.font` reads (task
  29 removed the last ShellWindow ones; this task removes the
  SettingsDialog default `Qt.application.font`).
- One authority: after this task no shell-chrome file computes a font size;
  roles come from `session.typographyFonts`/inheritance, sizes from
  `fontPx`/`layoutSpaces`/metrics.
- No proof-ledger edits by the implementer. Likely rows for the controller's
  ledger agent: `proof.shell-theme.txt` context-menu/`tst_Theme` rows citing
  menu font size; `proof.chrome.txt`/eventviews rows are untouched; shell
  transport/polyphony/settings rows in the editorqml ledgers whose geometry
  expectations move from body-15 to base-13 multiples (poly em, window
  92/57, toolbar token law) — each such change must be reported.
