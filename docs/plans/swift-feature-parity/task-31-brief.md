# Context

Typography parity for LEFT DOCKS (tasks 30-33 slice). User report: "there is 0
consistency in the font size. Anywhere in the application." Fork-main `fceecd88`
rendered every left-dock surface in `typography::bodyFont` — the Atkinson
Hyperlegible Next application font installed once at `qRound(base * 1.125)`
(`git show fceecd88:src/ui/typography.cpp:83`) — with exactly two styled
exceptions: sample-picker section headers `typography::bold`
(`typography.cpp:150`, `samplepicker.cpp:196-200`) and the typed fallback row
`typography::italic` (`typography.cpp:141`, `samplepicker.cpp:294-295`). Used
voicegroup rows were never bold: the fork marks them with a 30% accent tint
only (`voicegroupbrowser.cpp:568-580`). Second user ruling 2026-09-25:
everything is sized from multiples of the one captured base (fork
`src/ui/layout.{h,cpp}`); the task 29 authority now publishes
`session.typographyFonts`, `session.baseFontPx`, `session.bodyFontPx` and
`session.layoutSpaces` (`ApplicationSession.swift:42-53`).

Audits: `agent://TypoDocks` (full rows), `agent://TypoMeasure`; verified
against current source. Task 29's interim state has landed:
`ShellWindow.qml:526-527`/`:636-637` pass the session body/base through the
old child property names — this task deletes those pass-throughs.
Swift divergences here: SongsPanel renders the 13 px system face via the old
`applicationFont` chain; VoicegroupPanel/VoiceEditor/SamplePicker set
`font.pixelSize: baseFontPx` everywhere and flip 12↔13 px with song state
(`grid ? grid.baseFontPx : 12`); used rows are Bold 700; the picker lost
DemiBold sections and the italic typed row (SongConfirmDialog already
resolves body — task 30 owns it).

# Exact write set

- `src/ui/songview/quick/docks/`: `SongsDockColumn.qml`, `SongsPanel.qml`,
  `VoicegroupPanel.qml`, `VoiceEditor.qml`, `SamplePicker.qml`
- `src/ui/shell/ShellWindow.qml` — only the SongsDockColumn instantiation
  (`:516-527`)
- `src/checks/editorqml/tst_ShellSongs.qml`,
  `src/checks/editorqml/tst_ShellVoicegroup.qml`

# Prerequisites

After task 29 (contract: `session.typographyFonts.*`, `session.baseFontPx`,
`session.layoutSpaces`). Overlaps: task 30 (shell chrome) also edits
`ShellWindow.qml` (disjoint hunks: transport/poly/settings/about vs dock
column) and owns `SongConfirmDialog.qml` + its Loader hunk (`:630-643`) per
the split agreed with Brief30TypoShell (its `tst_ShellSongs.qml` hunk adds
only songConfirmationDialog role predicates — disjoint hunks); task 32 owns
`src/ui/songview/quick/QuickMenuPanel.qml`, whose `menuFont` fallback still
reads `Application.font` (`QuickMenuPanel.qml:50`) — this task stops
depending on it by passing explicit `appearance.font`, but the fallback
needs an owner (32 or 29); task 33 (drawer) is disjoint; the check files
are otherwise exclusive to this slice.

# Interface contract

Element inventory — target binding per element. "inherit" = delete the font
property; Controls resolve the window/dialog body; plain `Text` does NOT
inherit `ApplicationWindow.font` (Qt propagates window fonts to child
*controls* only), so custom content items bind their control's resolved font.
Fork citations name the widget whose inherited font was `bodyFont`.

SongsPanel (`fceecd88:src/ui/songlistpanel.cpp`): filter search + placeholder
(:65-68; cur :45-51), category combo + popup delegate (:78-82; cur :74-98),
sort combo (:83-88; cur :113-128), song row text (:299; cur :169-179 → bind
`font: row.font` on the `Text`), count label (:120, dimmed via disabled
palette; cur :210-217) → all inherit body. Tooltips (sort, row warning; cur
:122-123, :184-186) → inherit (fork: platform QToolTip default, unstyled both
sides). Context-menu rows (:101-118; cur :220-269) → popup root
`font: Qt.font(applicationSession.typographyFonts.body)` plus the same map in
`appearance.font` for QuickMenuPanel.

VoicegroupPanel (`fceecd88:src/ui/voicegroupbrowser.cpp`): "voicegroup_"
label (:233; cur :34-39), vgArgCombo (:234-248; cur :40-61), header
Voice/Type/ADSR (:264; cur :87-105), unassigned row title + ADSR labels
(updateRow :1200; cur :149-158, :195-204), type icon tooltip (cur :192-193) →
inherit body. Used row title + ADSR labels (markUsedRow :568 tint only) →
inherit body AND delete `font.bold: row.used` (cur :154, :200) — tint stays.

VoiceEditor (`fceecd88:src/ui/voicegroupbrowser.cpp`): notice (:317; cur
:56-65), Type label/combo (:328; cur :72-107), Sample/Wave/Drumkit/Synth
label (:337-391; cur :115-122), synth combo (:337; cur :136-149), drumkit
combo (:337; cur :150-160), new/edit sample buttons (:374, :382; cur
:161-180), Waveform label+combo (:425-431; cur :188-201), Duty LFO label +
four spins (:437-458; cur :209-235), Sweep label+spin (:399-414; cur
:243-258), Duty label+combo (:416-419; cur :265-278), Period label+combo
(:421-423; cur :285-298), ADSR label+spins (:464-478; cur :305-328), New…
button (:485; cur :334-341), Save button (Swift-only; cur :342-350), spin
tooltips → all inherit body (delete every `font.pixelSize:
editor.baseFontPx`).

SamplePicker (`fceecd88:src/ui/samplepicker.cpp`): trigger button (:91;
cur :81-90), search + placeholder (:112-114; cur :128-163), sample rows
(:232-233), detail label (:133; cur :205-216) and Loop badge (:240 `∞`; cur
:217-223) → inherit body; popup root (cur :92) →
`font: Qt.font(applicationSession.typographyFonts.body)`. Section headers
Keysplits/Samples/Phonemes/Waves (`addSection` :196-200 → `typography::bold`
DemiBold 600; cur :173-191): contentItem Label binds
`!modelData.symbol ? Qt.font(applicationSession.typographyFonts.bodyBold)
: entry.font`. Typed fallback row ("Use …", `typography::italic`
:294-301) → inherit body plus `font.italic: true` on that row's label.

Session plumbing: `SongsPanel`, `VoiceEditor`, `SamplePicker` gain
`required property QtObject applicationSession` and own
`readonly property real baseFontPx: applicationSession.baseFontPx`
(replacing the passed-in `baseFontPx`/`applicationFont`). SongsDockColumn
deletes `applicationFont`/`baseFontPx` (`:12-13` → one readonly derived from
the session) and passes `applicationSession` to SongsPanel (`:70-71`).
VoicegroupPanel replaces `grid ? grid.baseFontPx : 12` (`:17`) with
`applicationSession.baseFontPx` — one stable base, no song-state jump — and
passes the session to VoiceEditor (`:250`) and on to SamplePicker (`:132`).
ShellWindow deletes `:526-527`; the SongConfirmDialog Loader hunk
(`:630-643`) is task 30's. No Swift changes (no dock presenter computes
fonts).

Geometry (ruling: token or base multiple, fork citation each). Multipliers
stay frozen — calibrated against the QWidget baselines — re-based to
`applicationSession.baseFontPx` (fork heights were metric sizeHints plus
`layout.cpp` stylesheet paddings, cited per bullet):
- SongsPanel: `pad` (`:16`) → `applicationSession.layoutSpaces.one` (fork
  `space(One)` margins+spacing, songlistpanel.cpp:58-62); search height
  `ceil(base*(1.5+1/3))` (`:49`), page step `base*1.4` (`:58`), row heights
  `ceil(base*9/8)`/`11/8` (`:156`), count height `ceil(base*1.15)`
  (`:213`), sort width `base*7.25` (`:116`), menu `base*15`/`ceil(base*1.7)`
  rows/textX/textRight (`:227-249`) keep their multiples.
- VoicegroupPanel: rowHeight `1.33`, headerHeight `1.83`, typeWidth `3.75`,
  adsrWidth `8.33` (`:18-21`); vgRow height `2.17`, margins `0.33`, spacing
  `0.16`, label width `6.08`, combo height `1.83` (`:30-44`) — fork vgRow
  literals (4,2,4,0 margins, spacing 2, voicegroupbrowser.cpp:230-231);
  header rightMargin `0.58` (`:81`) = fork `space(Two)` scrollbar lane;
  Voice/ADSR `leftMargin 0.25` (`:90`, `:152`) → `layoutSpaces.one`; icon
  extent `base*1.25` (`:166`, `:175`) = fork `fontPx(1.25)`
  (voicegroupbrowser.cpp:273); row inset `0.67` (`:141`); 1 px borders =
  `singlePixel`.
- VoiceEditor: spacingPx `0.16` (fork `space(Half)` form spacing,
  voicegroupbrowser.cpp:313), regularHeight `1.83`, spinHeight `2.08`,
  noticeHeight `1.17`, buttonHeight `1.67`, fieldLabelWidth `3.6`/`4.1`
  (fork QFormLayout label column), type row `1.85`, picker row `1.5`,
  toolbutton `2.08`, spin minWidth `3.3`, buttons top margin = spacingPx
  (fork `space(Half)`, voicegroupbrowser.cpp:479).
- SamplePicker: popup spacing `max(1, round(base/3))`, width
  `max(row, base*28.33)`, height `base*35`, row height `base*1.83`
  (`:96-100`, `:178`) — fork chrome literals 4/4/4/4+4
  (samplepicker.cpp:110-112) approximated by base multiples. SongsDockColumn
  minimums `base*7`/`base*6.5` (`:29-30`) stay session-base multiples.

Observable at session base 13: all dock text Atkinson Next 15 px body; picker
sections DemiBold 600; typed row italic; used rows Regular + tint; nothing
reads `Application.font`, sets `font.pixelSize`, or flips with song state;
every geometry value equals its token/multiple of `session.baseFontPx`; the
songs baseline lookup key (`Math.round(panel().baseFontPx)` → fixture
profile 12/16) still resolves.

# Implementation steps

1. RED in `tst_ShellSongs.qml` / `tst_ShellVoicegroup.qml`: helper comparing
   a mounted element's resolved `font.family/pixelSize/weight` to the
   published role map (message names element + role; no pixel constants);
   assert the inventory plus `panel.baseFontPx === session.baseFontPx` before
   any project opens; geometry predicates comparing heights/widths to
   `Math.ceil/Math.round(session.baseFontPx * m)` and margins to
   `session.layoutSpaces.one`. Record RED output.
2. Session plumbing (properties above), delete every font binding per the
   inventory, bind the two popup roots, restore bodyBold sections and the
   italic typed row, delete `font.bold: row.used`.
3. Tokenize geometry (`layoutSpaces.one` where the fraction is 0.25; others
   stay explicit multiples now resolving from the session base).
4. Run the lanes; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-songs --verbose`
- `deno task verify:shell --filter shell-voicegroup --verbose`
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`
  (main window vs `/tmp/porydaw-qwidget-ref/a-main-window.png`: dock column
  text family/size, used-row tint without bold, picker sections).

# Visual parity

Counterpart: `fceecd88` `src/ui/typography.cpp:83/141/150`, `src/ui/layout.cpp`
(space tokens, geometry stylesheets), `src/ui/songlistpanel.cpp`,
`src/ui/voicegroupbrowser.cpp`, `src/ui/samplepicker.cpp`. Expected: the
Songs pane switches to Atkinson Next 15; the voicegroup pane stops
shrinking to 12 px when no song is open; used rows lose bold (tint
remains); picker section headers go DemiBold and the typed row italic.
`agent://TypoMeasure` rows `voicegroup combo 0.737`, `table rows 0.765`,
`songs filter 0.857`, `count 0.857` should move to ≈1.

# Task-specific constraints

- No C++, no code comments, no pixel constants (compare against published
  role maps / `session.baseFontPx` multiples), no QWidgets.
- WCAG AA text contrast wins: no color edits; the used-row tint and disabled
  count dimming stay exactly as themed.
- Keep the frozen baseline comparisons in `tst_ShellSongs.qml`
  (`compareRegion` vs `songListBaselineJson`) passing; do not retune
  geometry multipliers.
- No ledger edits by the implementer; likely proof rows for the ledger
  agent: `src/checks/host/proof.*` rows citing Songs/voicegroup dock fonts
  or the songs context-menu appearance, and widget-geometry rows pinned to
  the old 12/13 px dock fonts.
