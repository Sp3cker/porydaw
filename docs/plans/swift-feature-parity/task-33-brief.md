# Context

Task 29's authority (`src/swift/app/typography/Typography.swift`, session `typographyFonts`/`baseFontPx`/`bodyFontPx`/`layoutSpaces`) is landed; tasks 30-32 bind shell chrome, docks, song view. This brief binds the EDITOR DRAWER (velocity, voice changes, automation pages + tabs), prompts, Other-events band, MouseHintStatus and the Event List. Ground truth: fork-main `fceecd88` + `agent://TypoDrawer` rows + `agent://TypoMeasure`, each re-verified against current source (four audit rows were wrong — marked below). Second user ruling 2026-09-25: every geometry value is a layout token or fontPx/fontPxF multiple of the one captured base (fork `src/ui/layout.cpp:45-56,70-77`).

# Exact write set

Swift (under `src/swift/app/`): `drawer/velocity/{VelocityPublication,VelocitySceneValues,VelocityPage}.swift`; `drawer/voicechanges/{VoiceChangesPublication,VoiceChangesProjection,VoiceChangesPage}.swift`; `drawer/automation/{AutomationOverlayPublication,AutomationPage,AutomationContentPublication}.swift`; `drawer/PromptAppearance.swift`; `eventlist/{EventListMenus,EventListPresenter}.swift`; `timeline/RulerMenuPresenter.swift`; `ApplicationSession.swift` (one prompt-font line); `typography/Typography.swift` (one added role). QML (under `src/ui/songview/quick/`): `AutomationTabs.qml`; `drawer/AutomationPage.qml`; `drawer/VoiceChangesPage.qml`; `drawer/AutomationPrompt.qml`; `EventListPage.qml`; `swiftroll/EditorSurface.qml` (line 9 only); `swiftroll/MouseHintStatus.qml`. Checks: `src/checks/editorqml/tst_EditorDrawer.qml`; `tst_ShellEventList.qml`; `src/checks/themelayout/TypographyLayoutChecks.swift`; `src/checks/eventviews/EventListPageChecks.swift`. Unchanged on purpose: `drawer/VelocityPage.qml` (fonts arrive per row in `axisLabels`), `drawer/EditorDrawer.qml` (icon-only Canvas tool buttons, geometry presenter-published), `drawer/OtherEventsBand.qml` (already fed the body role through `EditorSurface.applicationFont`).

# Prerequisites

After task 29 (owns `Typography.swift`, `ApplicationSession.swift`, `ShellWindow.qml`; interim state already feeds `Qt.font(session.typographyFonts.body)` through `applicationFont` pass-throughs). Overlaps for the controller:
- `Typography.swift`/`ApplicationSession.swift`: this task adds ONE role `captionMinimum` (caption face/weight at `fontPx(2/3)`: 9 at 13, 17 at 26 — `automationcanvas_tabs.cpp:229-230`) and repoints one `timeSigPromptFont` line; 30-32 add no roles — serialize after 29.
- `EditorSurface.qml:9` dead default `applicationFont: Application.font` (fed body by SongTabs): deleted here; task 32 owns that file's other consumers (menu rows `:735/:823`, `controlsFont :536-539`, pitch-bend `:908-936`).
- `tst_ShellEventList.qml` (tasks 22/26 landed; exclusive now); `TypographyLayoutChecks.swift` (task 29 lane; additive predicates).
- Task 27 (Other-events band) landed; no file overlap (fonts need no edit).

# Interface contract

Per visible text element: fork cite → Swift current → target.

Velocity (labels arrive via `axisLabels` rows):
1. Graduations "Vol N"/ladder "127…0" — fork `noteName`+`bold(noteName)` (`velocityarea.cpp:60-61`, `velocityquick.cpp:104,122`); Swift `.keyLabel` fitted to the roll `keyHeight` (`VelocityPublication.swift:229-238`, `GridTypography.swift:67,73`, `VelocitySceneValues.swift:94-104`, ~9 px) → `session.typography.noteName`; delete the `TypographyKey`/`rowHeight` fit path (the roll's own fit stays, task 32).
2. Marker labels (relative gesture) — fork `bold(noteName)` (`velocityquick.cpp:133`); Swift `.bold` Mono 14/600 → `captionBold` (≡ `bold(noteName)` as values on every platform).
3. Label height — fork `QFontMetrics(noteName).height()` (`velocityquick.cpp:76`); Swift `max(densityD1, plotHeight/8)` (`VelocitySceneValues.swift:127`) → role-metrics height; delete `plotHeight/8`. No-session seed (`:96-102`) derives from `Typography(baseFontPx:)` roles, not a literal.

Voice changes (one change point, `publishTypography` `VoiceChangesPublication.swift:153-161`):
4. Gutter title — fork `bold(caption)` (`voicechangearea.cpp:38`, `voicechangequick.cpp:112`) → `captionBold` (was local `titleFont`).
5. Gutter hint — fork `regular(caption)` (`:39`,`:123`) → `caption`.
6. Marker labels — fork `m_captionFont` (`:255`) → `caption` (`VoiceChangesPage.qml:339` binding unchanged).
7. Hover label — fork `noteName` (`voicechangearea.cpp:41`, `voicechangequick.cpp:278`); Swift binds `captionFont` (`:374`) → publish `noteNameFont`, rebind.
8. Readout — fork `m_captionFont` (`:202`) → `caption` (`:395` unchanged).
9. Plot message — fork `m_captionFont` (`:134`) → `caption` (`:413`).

Automation tabs — fork rule is FIT, not elide: `parameterAppearance` publishes `font`=caption 400 + `minimumFont`=caption at `fontPx(2/3)` (`automationcanvas_tabs.cpp:226-233`); fork `AutomationTabs.qml:248-253` `HorizontalFit`+`minimumPixelSize`+`ElideNone`:
10. Tab labels — fork caption 400; Swift `titleFont` 600 + floor `round(base/2)` (`AutomationTabs.qml:40,158-161`) → bind `captionFont` (400), keep `HorizontalFit`/`ElideNone`, `minimumPixelSize: minimumFont.pixelSize`. 'Echo volume' still shrinks — never below the fork floor, exactly like the fork.
11. Count badge "N events" — fork `minimumFont` (fork `AutomationTabs.qml:268`; audit's "caption" wrong); Swift `captionFont` (`:170`) → `minimumFont`.
12. Tap label — fork `tab.font`=caption (`:146`) → `captionFont` (`:111` unchanged).
13. BPM draft — fork `minimumFont` (`:284`; audit wrong) → `minimumFont` (was `captionFont` `:178`).
14. Tab geometry — inset: fork `space(One)`=3 (`automationcanvas_tabs.cpp:230`) vs Swift `round(base/3)`=4 (`:16`) → `layoutSpaces.one`; stroke: fork `singlePixel` (`:236`) vs `max(1,round(base/13))` (`:17`) → 1; pip: fork `fontPx(0.5)`=7 (`:234`) vs `base/2` (`:149,200`) → published `pipExtent`; `minimumCellHeight fontPxF(4/3)` (`:233`; Swift `:45` form ok); tapControl height → published `minimumCellHeight` (fork `AutomationTabs.qml:123`) replacing `tab.height - 2*stroke` (`:96`).

Automation lane:
15. Scale labels "127"/"0" — fork `regular(caption)`, `labelInset space(One)`, tick `3*space(Half)` (`automationcanvas.cpp:28`, `automationquick.cpp:313-334`); Swift `captionFont` + `round(base/4)` (`AutomationContentPublication.swift:207-221`) → `caption`; pad as `fontPx(0.25)` (= `space(.one)`).
16/17. Hover + preview value labels — fork `noteName` (value-label cache `nodelane/hover.cpp:34-36` via `automationcanvas.cpp:33`; audit said caption); Swift `captionFont` (`AutomationPage.qml:435,455`) → publish `noteNameFont`, rebind.
18. Context readout — Swift-added surface (fork `m_laneTitleFont` `bold(caption)` `automationcanvas.cpp:27` has no draw site in `fceecd88`); keep `captionBold` (`:477`); controller confirms.
19. Plot message — `caption` (`:495`).

Prompts (velocity/automation/time-sig/insert-time/voice picker):
20. Title/label/input/buttons — fork = application font = BODY 15 (`promptappearance.cpp:13-16` with `QGuiApplication::font()` callers `pianoroll_commands.cpp:627`, `rangeedit.cpp:203`, `automationcanvas_deleteprompt.cpp:43`, `voicepicker.cpp:24`; drawer chrome prompt `controlFont: root.rulerFont` = input-host font = body, `TimelineCanvas.qml:729`, `timeruler.cpp:144-145`; audit's "caption 13" wrong). Swift `PromptAppearance.font` = Next 13 (`PromptAppearance.swift:15-18`; consumers `VelocityPage.swift:291,347`, `VoiceChangesPage.swift:271,335`, `RulerMenuPresenter.swift:224`, `ApplicationSession.swift:279`) → `Typography.body`; metrics → tokens (`promptappearance.cpp:26-36`: radius `space(.half)`, dialog/horizontal/button padding + spacing `space(.one)`, vertical `space(.half)`, `dragThreshold fontPxF(1)`, borderWidth 1; `listHeight fontPx(110/3)` `voicepicker.cpp:27`; `minimumWidth base*30` has no fork law — content-driven per fork `PromptCard.qml:14`, `VelocityPrompt.qml:91`; verify or drop `AutomationPrompt.qml:78 base*18`).

Other events + hint strip:
21. Gutter label "Other events (N)" — fork body via ambient app font (`otherstripquick.cpp:44-60`); Swift already fed body — keep.
22. Hover tooltip — fork `controlFont: root.rulerFont` = BODY (`TimelineCanvas.qml:651-657`; audit said caption) — already body.
23. MouseHintStatus text — fork body (widget inherits the app font); Swift fed body via `EditorSurface.qml:990` — delete the `Application.font` defaults (`MouseHintStatus.qml:9`, `EditorSurface.qml:9`).

Event List (`EventListMenus.swift:34-46` local law → roles; fork `eventlistcontroller.cpp:141-210`):
24. Toolbar button label + arrow — fork binds `controlFont` explicitly (fork `EventListPage.qml:308,325`); Swift omits font (`EventListPage.qml:313-343`, renders system 13) → `font: page.controlFont`. Plain Text does not inherit window fonts.
25. Count label — body via `controlFont` (`:754`) ✓ value; re-sourced.
26/27. Column + row headers — fork `caption(bodyMono(body))` = Next 13 (`eventlistcontroller.cpp:194-195`) → `caption` (`:829`,`:947`).
28/29. Numeric cells + editor — fork `tableMono(body)` → `tableMono` (`:1012`,`:500`); text cells — fork body → `body` (`:1013`).
30. `EventListAppearance.roles` reads `session.typography` (body/tableMono/caption; keys `bodyFont/controlFont/tableFont/headerFont` keep their QML names); delete the `fontPx(…1.125/1.0)` laws and the `configureTypography(baseFontPx:)` ingress if task 29 left it (`EventListPresenter.swift:93,97,99-102`; the presenter is session-owned and reads the session directly); delete the `Qt.application.font`/`monospace` fallbacks (`EventListPage.qml:40-44`) for session role maps. Fork also publishes italic variants (`:186-191`); Swift has no consumer — report, do not add. Row heights/paddings (`:80-94`) are verbatim fork metric-derived laws (fork `:77-91`) — unchanged; they become correct as the metrics re-point.

# Implementation steps

1. RED predicates first (below); record failing output.
2. `Typography.captionMinimum`; automation/voice publications construct fonts from `session.typography` (delete `AutomationCaption`/`VoiceCaption` pixel laws and the `fontFamily` literals; metrics holders keep their sgf measurement, initialized from `GridFontSpec`); publish `minimumFont`, `pipExtent`, `minimumCellHeight`, automation+voice `noteNameFont`.
3. Velocity: role fonts + role-metrics label height; seed from `Typography(baseFontPx:)`.
4. PromptAppearance re-point (body + tokens); update the four consumers.
5. EventList roles + QML toolbar bindings + fallback deletion.
6. AutomationTabs rebindings + geometry tokens; MouseHintStatus/EditorSurface default-read deletion.
7. Run lanes; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-typography --verbose`
- `deno task verify:shell --filter shell-event-list --verbose`
- `deno task verify:shell --filter shell-drawer-parity --verbose`
- `deno task verify:qml --verbose`
- `deno task verify:qml-roll --verbose`
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture` (main window + event list vs `/tmp/porydaw-qwidget-ref/a-main-window.png`, `b-event-list.png`): velocity numbers at noteName size, markers bold Next, 'Echo volume' floored, badge/BPM small, prompts 15.

RED predicates (mounted, message-anchored, no pixel constants): resolve each rendered/delegated font and compare family/pixelSize/weight to `session.typographyFonts.<role>` — elements 1-2 via a mounted velocity axis row's `labelFont` map; 7/16/17 via `noteNameFont`; 10-13 via mounted tab Text objects including `minimumPixelSize == minimumFont.pixelSize` and `fontSizeMode == Text.HorizontalFit`; Event List delegate fonts equal the published `tableFont`/`bodyFont`/`headerFont`/`controlFont` maps (`tst_ShellEventList.qml`); swiftcore: the drawer publications and `EventListAppearance.roles` equal `Typography` roles at base 13 and 26, `captionMinimum` == caption at `fontPx(2/3)`, prompt font == body; geometry: tab `inset == session.layoutSpaces.one`, pip == published `pipExtent`, velocity `labelHeight` == noteName metrics height.

# Visual parity

Counterparts: `velocityarea.cpp`+`velocityquick.cpp`, `voicechangearea.cpp`+`voicechangequick.cpp`, `automationcanvas*.cpp`+`automationquick.cpp`+fork `AutomationTabs.qml`, `nodelane/hover.cpp`, `promptappearance.cpp`, `otherstripquick.cpp`, `eventlistcontroller.cpp`+fork `EventListPage.qml`, `DrawerChromeLayer.qml`, `TimelineCanvas.qml`. Expected visible change: velocity axis labels grow ~9→13 px Next (markers bold Next, no Mono), prompts 13→15 Next, tab badge/BPM shrink to the 9 px floor, long tab labels stop shrinking below it, Event List toolbar matches the count label, everything keyed to the session base.

# Task-specific constraints

- No C++, no code comments, no pixel constants (tokens/role maps/base multiples only; the 13/3 keyboard-column and 110/3 list laws stay fontPx multiples), no QWidgets.
- WCAG AA text contrast wins; no color edits here.
- One authority: after this task no drawer/event-list Swift file computes a font size or family; `GridTypography` survives only for roll surfaces (task 32).
- No ledger edits by the implementer; likely rows for the controller's ledger agent: `src/checks/eventviews/proof.chrome.txt` A010-A012 (mono/table reasons re-source, values unchanged), velocity ledgers under `src/checks/velocity/` (axis label geometry), automation/voice ledgers under `src/checks/automation/` and `src/checks/drawerpresentation/` if any pin label sizes.
