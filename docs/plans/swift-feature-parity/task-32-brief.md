# Context

Typography slice 3 of 4 (after task 29's authority): song view top + roll.
Fork facts (`git show fceecd88:`): one authority `src/ui/typography.cpp`
(caption(source)=Next@base Normal whatever the source family :110-116; bold
keeps source px +DemiBold :135-142; bodyMono/tableMono :88-108; fitted caps
at caption px :144-148; noteName=caption face :150-161); widget geometry is
`layout::fontPx/fontPxF/space` multiples of the one captured base
(`layout.cpp:44-74,455-467`; `singlePixel()` = flat 1; tokens Zero..Eight =
{0,.125,.25,.5,.75,1,1.5,2}); QStyle-owned chrome has no fork law.

Verified divergences: SongTabs builds DemiBold tab-local fonts
(`SongTabs.qml:70-78`) where the fork inherits body Normal; grid controls use
`0.8×base` (`EditorSurface.qml:543-546`) where the fork uses body
(`RulerControls.qml:105,119,142` ← host font, `timeruler.cpp:137-138`); pitch
captions use `0.85×` (`PitchBendPresenter.swift:62`); menus read
`Application.font` (`EditorSurface.qml:741,834`, `QuickMenuPanel.qml:50`);
prompt cards render 13 px where the fork renders body 15
(`PromptAppearance.swift:15-18` vs `promptappearance.cpp:29`); ruler mono
faces are 1 px too large (`GridTypography.swift:111` bodyPx−1=14 vs fork
captionPx−1=12, `timeruler.cpp:41-46,443-445`); loop markers measure with the
wrong metrics (`GridScene.swift:622` vs fork bold-ruler markerMetrics,
`timerulerquick.cpp:275-291`). The fork's time-signature measure/render split
(measure `bold(body)` `timeruler.cpp:433`, render `bold(rulerMono)`
`timerulerquick.cpp:262`) is fork-faithful and **stays**. M/S and +Add
already equal body by accident (`TrackHeaders.swift:95`).

# Exact write set

Swift:
- `src/swift/app/timeline/GridTypography.swift` — `fonts(metrics:typography:)`
  re-derivation + bold-marker advance helper; `timeline/GridGeometry.swift` —
  delete `rulerMinFontPx`/`rulerLetterSpacing` knobs (re-express via
  `Typography.fontPx/fontPxF`).
- `src/swift/app/roll/GridScene.swift` — loop-marker advance from bold
  metrics (`:622`); hover-chip init font (`:212-215`); `roll/PianoGrid.swift`
  — thread typography into the fonts table (`:1143-1145`).
- `src/swift/app/headers/TrackHeadersGeometry.swift` — delete
  `titleFont`/`subtitleFont` factories (`:131-138`); `TrackHeaders.swift` —
  inject `Typography`, publish role maps (`:93-98,166-169`).
- `src/swift/app/pitchbend/PitchBendPresenter.swift` — inject `Typography`,
  role-map appearance + dragInput tokens (`:61-78`).
- `src/swift/app/drawer/PromptAppearance.swift` — `font(typography:)` = body
  map [shared: 33]; call sites `ApplicationSession.swift:279` [shared: 29],
  `timeline/RulerMenuPresenter.swift:224`.
- `src/swift/app/DocumentWorkspace.swift` — pass `typography` to
  TrackHeaders/PitchBend construction (`:77,82`). [shared: tasks 29/33]
QML:
- `src/ui/songview/quick/swiftroll/SongTabs.qml` — delete `applicationFont`,
  `bodyFont`, `tabFont` (`:9,70-78`); inherit body; token chrome geometry
  (`:66-69,99-103`); dialog/StripButton inherit (`:343-380`).
- `src/ui/songview/quick/swiftroll/SongTab.qml` — stop forwarding
  `applicationFont` (`:12,25`); `src/ui/shell/ShellWindow.qml` — drop the
  `applicationFont:` argument to SongTabs (`:552`). [shared: tasks 29/30]
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — delete
  `applicationFont` (`:9`), the 0.8× `controlsFont` (`:543-546`), both
  `Application.font` reads (`:741,834`); re-source pitch
  `fallbackFont`/`applicationFontMetrics` to body (`:114-118,915,935-946`);
  fork menu laws (`:743-746,789-794,836-840`); hint pass → caption (`:995`).
- `src/ui/songview/quick/swiftroll/MouseHintStatus.qml` — caption font
  property replaces `applicationFont` (`:9,13,23`); `quick/PitchBendPopup.qml`
  — `fallbackFont` = body map (`:15,45-47`); `quick/QuickMenuPanel.qml` —
  `menuFont` fallback `?? Application.font` → inherited root font (`:50`).
  [shared: 30/31/33]
Checks: `themelayout/TypographyLayoutChecks.swift` [29], `editorqml/
tst_Typography.qml` [29], `tst_ShellTabs.qml` (DemiBold pin :453 flips),
`rollcheck/{pitch_bend,time_signature_prompt,presentation}.swift`,
`trackheaders/TrackHeadersChecks.swift`. Verified unchanged:
`TrackHeaderBand.qml` (controlFont already body), `RulerToolTip.qml`
(fork-literal paddings, pass-through font), `DragInput.qml`, both prompt QMLs
(bridge fonts, content-derived `minimumWidth` = fork), RulerControls
literals, `rulerHeight`/`markerHeight` `+1` (fork `singlePixel()` = flat 1).

# Prerequisites

After task 29 (Typography roles + `space`/`fontPx`/`fontPxF`, session
`typographyFonts`/`layoutSpaces`/`baseFontPx`, ShellWindow body binding,
PianoGrid typography injection). Overlaps for parallel scheduling:
`ApplicationSession.swift`, `DocumentWorkspace.swift`, `ShellWindow.qml`,
`tst_Typography.qml`, `TypographyLayoutChecks.swift` (tasks 29/30);
`QuickMenuPanel.qml`, `EditorSurface.qml` (30/31/33 — 33 owns the drawer
side); `PromptAppearance.swift` (33's prompts share it; its `minimumWidth`
×30 / `listHeight` ×110/3 keys are fork `voicepicker.cpp:24-28` laws for
33's pickers). `GridTypography` changes shift `VelocitySceneValues.swift:89`
— sequence 32 before/with 33 and re-run drawer lanes.

# Interface contract

Font targets (rows bundle sibling elements; inherit = no font property;
roles are `session.typographyFonts.<role>` in QML / `session.typography.<role>`
in Swift; derived faces re-express the cited fork law, no pixel literals):

| Element | Fork (fceecd88) | Swift today | Target |
|---|---|---|---|
| Tab title + advance measurement | `workspaceui.cpp:146-152` QTabBar inherits body Normal | `SongTabs.qml:75-78,186` DemiBold map; measure `:70-74,194` bodyFont map | inherit body, delete `tabFont`; `titleMetrics.font` = rendered body font |
| Tab scroll/close buttons, strip tooltips | QTabBar subcontrols/QToolTip inherit | icon-only / attached ToolTip (`:148,257`) | unchanged (inherit) |
| Close-confirm dialog text + Save/Discard/Cancel | `workspaceui_tabs.cpp:492-498` QMessageBox = body | `:343,351` + StripButton `:99-103` applicationFont | inherit body |
| Header title normal / selected / subtitle | `trackheadermodel.cpp:754-756` body / bold(body) / caption(body) | `TrackHeaders.swift:95-98` 1.125 / 1.125+600 / ×1.0 laws | `typography.body` / `bodyBold` / `caption` maps |
| M/S toggles, + Add track, rename editor | fork `TrackHeaderBand.qml:97,331` controlFont = body (`timeruler.cpp:137-138`) | `TrackHeaderBand.qml:142,398,746` controlFont | `typography.body` map (value unchanged) |
| Ruler bar / beat numbers | `timeruler.cpp:41-46,443-445` bodyMono(caption)−singlePixel; beat = ruler px −singlePixel; clamp fontPx(1/12); spacing fontPxF(−1/24) | `GridTypography.swift:111,118-119` bodyPx−1=14 / 13 | Mono, px `max(fontPx(1/12), captionPx−1)` / `max(fontPx(1/12), rulerPx−1)`, spacing `fontPxF(−1/24)` |
| Loop markers | `timerulerquick.cpp:275-291` bold(ruler), measured with its own metrics | `GridScene.swift:622-623` measured with `.sig` | Mono rulerPx 600; measure via bold-metrics advance |
| Time-signature labels | measure `bold(body)` (`timeruler.cpp:433`), render `bold(ruler)` (`timerulerquick.cpp:262`) | `:637,646` same split, wrong px | keep split: measure `typography.bodyBold`, render `.bold` |
| 'Grid' label; division/feel labels + arrows | `RulerControls.qml:142,105,119` = body | `EditorSurface.qml:543-546` → `:581,596,620` 0.8× | `Qt.font(typographyFonts.body)` |
| Keyboard octave labels | `pianoroll.cpp:163` fitted(font(),keyHeight) | `.keyLabel` self-fit (`GridTypography.swift:67,123`) | `typography.fitted(typography.body, rowHeight)` |
| Note-name labels | `pianoroll.cpp:38-41` noteName −2×singlePixel | `:116,124` base−2 | noteName face, px `max(1, noteNamePx−2)` |
| Hover chip | `pianoroll.cpp:45-46` caption | `.chip` base 400 | `typography.caption`; init from typography (`GridScene.swift:212-215`) |
| Roll loading text (dormant) | `timelinequickview_pianoroll.cpp:563-568` caption(roll.font()) | model always empty (`GridScene.swift:957`) | caption if the lane is ever fed |
| Pitch popup: title / labels+axis+Reset / readout / DragInput fields | `pitchbendeditor.cpp:348` bold(body); `:349-350` caption (+ fork `PitchBendPopup.qml:249`); `:351-352` bodyMono; `:337` body | `PitchBendPresenter.swift:61-64,72` 13-bold / 0.85× / mono@13 / 13 system | `typography.bodyBold` / `caption` / `bodyMono` / `body` maps |
| Quick-menu rows/shortcuts | `quickmenulayout.cpp:32-39` appearance font, else body | `EditorSurface.qml:741,787,834` + `QuickMenuPanel.qml:50` | `Qt.font(typographyFonts.body)`; fallback = inherited font |
| Mouse hint bar | `widgethints.cpp:468-483` regular(caption(bar)) | `MouseHintStatus.qml:9,23` applicationFont | `Qt.font(typographyFonts.caption)` |
| RulerToolTip text | fork `RulerToolTip.qml:44` controlFont (body) | pass-through, no local law | callers pass body-derived font (unchanged here) |
| Time-sig/insert-time prompts + PromptButtons | `promptappearance.cpp:13-29` font=qApp font = body | `PromptAppearance.font(base:)` 13 | `typography.body` map |

Geometry targets (`space(X)` = `session.layoutSpaces.<x>`; fork
`singlePixel()` = flat 1):
- Tab chrome: margin-top/padding `half`/`half two` (`layout.cpp:161-165`);
  height `max(bodyLineSpacing, iconExtent) + 2×half + 2` (`layout.cpp:
  503-511`). Close/scroll extents 20/16 and StripButton sizing are
  QStyle-owned — keep, metric-scaled on the resolved body font.
- Menus (`quickmenulayout.cpp:14-30,42-89`): hPadding `two`, vPadding `half`,
  gap `one`, frameBorder singlePixel; rowHeight `bodyMetrics.height + 2×half`;
  checkWidth `rowHeight/2`, arrowWidth `rowHeight/4`; checkX `two` when
  checkable else −1; textX `two (+checkWidth+one)`; menuWidth `2 + textX +
  widestText + two` (+`gap+widestShortcut` / `gap+arrowWidth`); textRight =
  trailing-edge chain.
- Grid controls row: fork literals 8/4/4/8 (`RulerControls.qml:36-39`)
  replace the 0.6/0.3 multipliers; hint bar stays caption-metrics-derived
  (QStatusBar, `widgethints.cpp:94`).
- Prompts: radius `half`, paddings/spacing `one`, borderWidth singlePixel,
  dragThreshold `fontPxF(1.0)` (`promptappearance.cpp:29-38`).
- Pitch chrome: factors already fork-faithful (`pitchbendgraph_render.cpp:
  41-76`); dragInput radius/hPadding `one`, vPadding `half`, borderWidth
  hairline (`pitchbendeditor.cpp:339-343`); ingress stays
  `typography.baseFontPx`.
- GridMetrics/TrackHeadersGeometry factors already match fork
  (`pianoroll_geometry.cpp:26-44`, `trackheadermodel.cpp:74-92`); only their
  base becomes `typography.baseFontPx`.

# Implementation steps

1. RED: swiftcore predicates — GridTypography table equals the Typography
   derivations at bases {12,16,18}; TrackHeaders maps, PitchBendPresenter
   appearance entries and PromptAppearance.font equal their role maps;
   loop-marker advance equals bold-metrics advance. Mounted: tab title
   resolves body family/px/Normal; grid-controls label, menu rows, pitch
   title/caption/mono/dragInput, hint bar and prompt texts resolve their
   published roles (family+pixelSize+weight); tab chrome equals
   `layoutSpaces` tokens.
2. Swift role re-derivation (GridTypography, TrackHeaders, PitchBendPresenter,
   PromptAppearance + call sites, DocumentWorkspace injection); delete the
   1.125/0.85/0.8/clamp laws and the TrackHeadersGeometry factories.
3. GridScene fixes (loop-marker metrics, hover-chip init).
4. QML cutover: SongTabs/SongTab/ShellWindow pass-through removal;
   EditorSurface body/caption bindings + fork menu laws; MouseHintStatus
   caption; QuickMenuPanel fallback; PitchBendPopup fallbackFont.
5. Update pinned checks (tst_ShellTabs DemiBold→Normal; TypographyLayout
   ruler/beat px; pitch_bend mono px) — report each change. GREEN with
   predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-typography --verbose`
- `deno task verify:shell --filter shell-tabs --verbose`
- `deno task verify:shell --filter shell-pitch-bend --verbose`
- `deno task verify:shell --filter shell-grid-menu --verbose`
- `deno task verify:qml-roll --verbose`
- `deno task verify:qml --verbose` (drawer lanes consume GridTypography — re-run after 32/33 settle)
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`
  vs `/tmp/porydaw-qwidget-ref/a-main-window.png`: tab strip, ruler, grid
  controls, headers, pitch popup, hint bar.

# Visual parity

Counterparts: `typography.cpp`, `layout.cpp`, `workspaceui*.cpp`,
`trackheadermodel.cpp`, `timeruler.cpp` + `quick/timerulerquick.cpp`,
`quick/RulerControls.qml`, `pianoroll*.cpp`, `pitchbendeditor.cpp` +
`pitchbendgraph_render.cpp`, `quickmenulayout.cpp` + `QuickMenuPanel.qml`,
`widgethints.cpp`, `promptappearance.cpp`. Expected visible change: ruler
mono shrinks 14/13→12/11 px; grid controls and prompt cards grow 10/13→15;
tab titles lose DemiBold; pitch captions 11→13, readout 13→15 mono; menus
switch to Next 15. TypoMeasure crops (ruler digits, key labels, M 10.5,
Add 11.5) are the before reference.

# Task-specific constraints

- No C++, no code comments, no QWidgets; pixel constants only where the fork
  itself hardcodes them (8/4/4/8 controls, 4/3/4/2 tooltip, 20/16 QStyle
  chrome) with citation; everything else is roles, tokens, or fork-factor
  multiples of `typography.baseFontPx`.
- One authority: after this task no file in the area computes `*1.125`,
  `*0.85`, `*0.8`, `bodyPx-1`, or reads `Application.font`.
- The fork's sig measure/render split is parity — do NOT "fix" it to one font.
- WCAG AA text contrast wins over any font change if a conflict appears.
- No ledger edits by the implementer; likely rows for the controller's ledger
  agent: themelayout font proofs (ruler/beat/bold/sig px), trackheaders
  reconciliation, rollcheck note_rendering + pitch_bend,
  proof.header_reconciliation.txt, shell-tabs pins.
