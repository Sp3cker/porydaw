# Swift SongTabs continuation handoff

## User direction — latest takes precedence

The user accepted the corrected tab appearance: **“it is visually close enough now, please get check parity and then commit.”** Do not resume visual tuning or demand pixel-perfect tab-label widths. They subsequently requested: **“please stop soon and leave a summary document for the next agent to continue from.”** Work is paused here, not declared complete. Commit/push remains authorized after the remaining checks pass; no commit or push has been made.

## Checkout and scope

- Worktree: `/Users/sallegrezza/dev/cProjects/porydaw/.worktrees/swift-qml-songtabs`
- Branch: `feature/swift-qml-songtabs`; original base `21ebd6cd`.
- This is the standalone Swift/QML grid prototype, not production QWidget retirement or production persistence integration.
- Existing plan and four task briefs are in this directory. This handoff supersedes their older visual-acceptance/no-commit status.
- All build/verification commands use `deno task`, with tool timeouts at most 300 seconds. Native input scenarios must run sequentially on an available desktop.
- No new tab features: no plus button, dropdown, keyboard-navigation feature, focus cache, custom focus repair, synthetic key forwarding, or duplicate page registry.

## Implemented and retained

Swift owns one `QListModel<SongTabSession>`, stable IDs, selection and session lifecycle. App bootstrap seeds three existing fixture-backed sessions. QML uses persistent native `FocusScope` pages. Genuine QtBridge `beginMoveRows`/`endMoveRows` preserves instances and state on reorder. The original grid was extracted into `SongTab.qml`; toolbar, audio/grid/undo paths remain connected to the selected page. Tab selection, title/dirty indication, close, reorder, tooltips and overflow scrolling exist. Dirty-close is Discard/Cancel, not pretend Save. Last close leaves an actually blank workspace.

Corrected rendering uses production-style strip height, top margin, semibold typography, logical-pixel borders, inset 20px close controls and existing far-right overflow buttons. User accepted this version. The close icon is the user-supplied Font Awesome Pro light `window-close.svg`; its license comment is preserved. Overflow arrow PNGs are exports of the existing native Fusion controls, including enabled/disabled and DPR1/2 variants. No QWidget renderer is embedded in the Swift runtime.

### Relevant changed paths

Under `src/ui/songview/quick/swift-grid-prototype/`:

- Modified: `App.swift`, `CMakeLists.txt`, `GridPalette.swift`, `Main.qml`, `qtbridge-object-return.patch`.
- New: `SongTabsController.swift`, `SongTab.qml`, `SongTabs.qml`, `tabart.qrc`, `tabart/` (one SVG and eight overflow-arrow PNGs).

Under `src/checks/swiftgridprototype/`:

- Modified: `grid_smoke.cpp`, `interaction_smoke.cpp`.
- New: `songtabs_smoke.cpp`, `songtabs_smoke.h`.

New documentation directory: `docs/plans/swift-songtabs/`.

Production `src/checks/visual/chrome.cpp` was temporarily instrumented for references and restored. Temporary QML screenshot-export code was also removed. Do not commit external `/tmp` references or reintroduce exporters.

## Verification: exact current state

### PASS: complete production suite

Run from this worktree:

```sh
PORYDAW_VISUAL_SCREEN_DPR=2 deno task verify --verbose
```

Final result:

```text
verify: 99/100 ok (91.94s, 1 skipped)
run_checks: PASS (all harnesses in 91.94s)
```

Includes all eight production visual suites, production `tabcheck`, selection-key routing, audio, transport, grid, rendering and other default harnesses. No baselines changed. Build took 14.23s; full command 106.62s. One harness was skipped; output did not name it. A separate earlier DPR1/font16 visual run had exposed a pre-existing B3-hover baseline mismatch; it was not rebaselined. Do not claim every DPR/profile passed.

### NOT PASSING: final prototype native-input smoke

The corrected QML now builds and loads without the earlier QML errors. Two new control-property collisions were fixed: inline scroll property `left` became `pointsLeft`; Button delegate `required property var display` became `required property var model` with `session: model.display`.

Latest default-font run:

```sh
deno task prototype:swift-grid --smoke
```

Passed original math, policy, real PCM, strict grid raster, note gestures, pitch-curve, popup-keyboard and **real-audio-play-pause-stop-and-playhead** checks. Then failed:

```text
Space transport diagnostic: windowActive=0 windowVisible=1 activeFocusItem='transportStop' gridShortcutsEnabled=1 currentPage='songTab_1' noteMenuOpen=0 pitchEditorOpen=0 rootAudioMatches=1 selectedId=1 selectedIndex=0 audioPlaying=0
SWIFT_GRID_SMOKE FAIL: focused Stop button stole Space from the window transport command
```

The final in-flight small-font run also completed before this handoff:

```sh
PORYDAW_VISUAL_FONT_PX=12 deno task prototype:swift-grid --smoke
```

It passed the same original checks through real audio, then failed the same Space check with `windowActive=0`, `windowVisible=1`, and `activeFocusItem='<null>'`. Other diagnostic fields matched. Runtime: 8.65s. Font16 has not been run after the correction.

**Root cause is not established.** Window inactivity is observed; desktop interference is only a hypothesis, not a proven diagnosis. A subsequent correctly parenthesized AppleScript reported `cmux` as frontmost after the process exited; this does not prove what deactivated the window during the test. An earlier malformed AppleScript mentioned loginwindow; do not interpret that error as evidence the desktop was locked.

One preceding run failed earlier at `Play did not advance the real poryaaaa transport`; the two latest runs passed that audio scenario. Do not hide these failed runs or claim the final prototype suite passes.

### Where to investigate next

- `grid_smoke.cpp`, around lines 826–828: already calls `window->requestActivate()` and `QTest::qWaitForWindowActive(window)` once before `exercise(...)`. Preserve this native test prerequisite.
- `interaction_smoke.cpp`, roughly lines 200–260: real transport controls followed by the failing focused-Stop/Space priority scenario; existing diagnostic includes active window, active focus, popup and selected-page state.
- This failure occurs **before the newly corrected tab smoke scenarios execute**. Their final settled version therefore remains unverified.
- Prior to the visual correction, the complete prototype smoke including all eight tab scenarios passed. That historical result is not final-tree acceptance.
- Do not repeatedly stress-run human-input tests to troubleshoot. Establish the activation cause and keep original routing/raster assertions intact. No production focus-manager workaround; workarounds require approval.

## Final tab-check contract

`songtabs_smoke.cpp` retains behavior/state-retention/reorder/close/empty/reopen/overflow checks and production-style geometry/font/page-boundary checks.

The user accepted approximate visual parity. Exact fixture-label width assertions (84/89/101px) were removed, not re-pinned to the actual 87px at base13. Close placement is relative to actual tab width (`width - 21`, 20px control, y4); body height28 and strip/font metrics at bases12/13/16 remain checked. Caption painted extent must stay between tab edge and close control. It deliberately does **not** require `Text.contentWidth <= Text.width`: an unclipped center-aligned Text can paint outside its layout width without overlapping the close control. Selected-state changes extend through the close-control surround; supplied SVG must produce a visible contrasting glyph. Original grid raster colors/tolerances were not relaxed.

`grid_smoke.cpp` supports test-only `PORYDAW_VISUAL_FONT_PX` before scene readiness. Fixture creation awaits a requested `frameSwapped` before pointer interaction; QObject existence alone is not scene readiness. Persistent application controls remain NoFocus; modal controls use native focus behavior.

Changed C++ checks were formatted with `deno task format`; local clang-format is21 while CI pins22, and the formatter warned accordingly. Actual native build succeeded.

## Visual evidence — already accepted, do not retune

Outside the repository:

- `/tmp/porydaw-tab-reference/corrected-native-window.png` — actual launched native window accepted by the user.
- `/tmp/porydaw-tab-reference/qml-native-font13-dpr2-selected-first.png` — cropped corrected strip.
- `/tmp/porydaw-tab-reference/font{12,13,16}-dpr{1,2}-{selected-first,hover-second,close-hover,narrow-overflow}.png` — actual production-hosted references.
- Corresponding native metrics JSON files and temporary exporter source are in that directory.

The old `PORYDAW_SONGTABS_QML_REFERENCE_DIR` and production reference export hooks are removed; merely setting those variables will no longer export screenshots. The native preview hub process `songtabs-visual-corrected` was stopped. No test command remains running. Agent `TabNativeReference` was told to stop editing.

## Remaining steps for next agent

1. Diagnose the observed native window deactivation at the Space transport check. Distinguish environment/input interference from application or test lifecycle behavior; do not assume either.
2. Obtain a complete settled prototype smoke pass, including the tab scenarios. Check the supported font scales if retaining their new geometry contract. No further visual refinement is requested.
3. Update `plan.md` with exact final results and remove its stale in-progress state. Production suite already passed; rerun only checks affected by subsequent fixes.
4. Commit the scoped prototype/check/document changes and push `feature/swift-qml-songtabs` to its corresponding GitHub remote branch, per user authorization and repository rules. No commit currently exists for this work.
