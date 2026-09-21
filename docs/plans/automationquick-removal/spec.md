# automationquick removal — spec

Dead-code excision. The legacy C++ automation drawer surface
(`AutomationCanvas` family, `automationquick.cpp`, `automationnodelanequick.*`,
the `automationBand` in `TimelineCanvas.qml`, `CcDeleteConfirm.qml`) is
uncompiled: none of it appears in `CMakeLists.txt` (`porydaw_app`/`porydaw`),
`src/checks/CMakeLists.txt`, or `checkcatalog.cpp`, and `TimelineCanvas.qml`
is not in any resource bundle. The production automation drawer is pure
Swift (`src/swift/app/drawer/automation/`) + bound QML
(`src/ui/songview/quick/drawer/AutomationPage.qml` et al.) with zero C++
touchpoints.

Non-goals: `velocityquick.cpp`, `voicechangequick.cpp`, `timerulerquick.cpp`,
`playheadquick.cpp`, `otherstripquick.cpp` and their area classes stay live —
the velocity-voice-split plan keeps that migration seam. `TimelineQuickView`,
`TimelineCanvas.qml`, `VelocityArea`, `VoiceChangeArea`, C++ `AutomationPage`,
`EditorDrawer`, `SongView` stay (dead but out of scope); they are edited only
to remove references to the deleted automation surface. No Swift changes. No
behavior changes — nothing deleted or edited is compiled.

## Vocabulary

- Removed surface: `AutomationCanvas` and every file that exists only to
  serve it — the `automationcanvas*.cpp` family, `automationquick.cpp`,
  `automationnodelanequick.{h,cpp}`, `CcDeleteConfirm.qml`, and the
  `TimelineQuickLayer::Automation*` / `Automation*TextRole` /
  `setAutomation*TextRecords` members of `TimelineQuickScene` that only
  `automationquick.cpp` fed.
- Referencing dead files: uncompiled sources that include or name the removed
  surface. They are edited to coherence (references removed), never deleted
  unless they exist solely for the removed surface.
- Dead check twins: uncompiled `.cpp`/`.h` files under `src/checks/` that
  reference the removed surface. Their live `.swift` twins (compiled into
  `swift_core_check`) and `proof.*.txt` fixtures stay untouched.

## Boundary rule

After the plan lands, no file in the repo references `AutomationCanvas`,
`automationquick`, `NodeLaneQuickPaint`, `CcDeleteConfirm`,
`automationCanvas` (context property), or the automation members of
`TimelineQuickScene`. Enforced by grep in the hygiene gate. The rule is met
by deleting or editing files — never by adding guards, stubs, or `#if 0`.
