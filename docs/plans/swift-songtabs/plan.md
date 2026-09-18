# Swift-backed QML SongTabs prototype

Status: paused at the user's request; see [handoff.md](handoff.md). Corrected appearance accepted as visually close enough. Production suite passed (99 passed, one skipped); final prototype smoke remains blocked by observed native window inactivity at the Space transport check. No commit/push made. Base: 21ebd6cd. Branch: feature/swift-qml-songtabs.

## Spec and global constraints

User's latest binding requirement: NO FEATURES BEYOND THE C++ APPLICATION. Source authority: src/ui/workspaceui.cpp QTabWidget setup and src/ui/workspaceui_tabs.cpp tab lifecycle. Earlier proposed plus/new-demo-tab and all-tabs-dropdown controls are rejected and removed, not future features.

Deliver the existing Swift grid prototype with QML SongTab FocusScope pages. This is not production QWidget retirement. Transport, song/voicegroup browsers, production document/save/audio/workspace code remain unchanged. Keep the original prototype toolbar once, without redesign or additional commands.

Reuse existing prototype QML by extraction. No duplicated grid renderer, fake readiness, smoke-only reusable implementation paths, or second page registry. Tests live under src/checks. Demo fixtures are existing standalone bootstrap data, not user-facing new-song functionality.

Tab strip behavior matches C++: selection, close, drag reorder, title/dirty display, tooltip, left/right overflow scrolling. No plus button, dropdown, new shortcuts, tab focus cache, loading simulator or extra tab feature. C++ tab bar has Qt::NoFocus; mirror that for persistent tab/scroll controls. Retain native accessibility press. Modal prompts retain normal keyboard focus; existing editor keyboard behavior remains unchanged.

Native FocusScope is the focus design. No custom focus manager, queued repair, synthetic forwarding, application-wide input filter additions, inferred selection from activeFocus, or guards for unreachable user interleavings. Popups retain existing native modal/outside-dismiss behavior: dismiss then select, not switch-through-modal machinery. On an actual page hide stop outgoing audio and cancel/close transient UI without restoring hidden-page focus.

Swift owns one QListModel<SongTabSession>, stable IDs, display order and selected identity. Each session owns one existing PianoGrid. Genuine beginMoveRows/endMoveRows preserve QML Repeater page instances, camera, selection and undo. No remove/reinsert imitation or model reset on reorder. Swift never sees Qt windows/items.

Dirty-close supports Discard/Cancel only because prototype does not implement production persistence; no pretend Save. Dirty is grid.canUndo relative to initial/reset fixture. Background close preserves selection; selected close selects adjacent survivor; final close is a genuinely blank workspace matching C++ empty tab widget, with no new empty-state instruction or reopening control. Opening belongs to external host/session integration, represented by demo bootstrap and test fixture setup—not tab-strip UI.

App bootstrap seeds three existing fixture-backed sessions and selects the first for a usable multi-tab demonstration. No smoke-environment branch. Controller remains generic over open/select/close operations; source fixture creation follows existing PianoGrid behavior. Test fixture setup may call controller.openTab to stand in for out-of-scope browser opening; tests must use real pointer input for tab selection/close/reorder/overflow/editor operations.

Use existing fonts/palette and native Qt Controls. Preserve exact existing raster expectations. Native Flickable pixelAligned:true fixes measured half-pixel camera translation under composition; do not round test cameras, change colors, or weaken tolerances. Dialog uses native content-data Label composition, not custom sizing or replacement contentItem.

Visual acceptance: actual production-hosted tab references were captured at fonts 12/13/16 and DPR 1/2. The corrected QML uses the production strip height, top margin, semibold type, logical-pixel borders, inset close control and overflow artwork. The user explicitly accepted the resulting appearance as visually close enough; pixel-identical label widths are not claimed or required. User-supplied Font Awesome Pro light/window-close.svg replaces stock Qt close artwork with its license comment preserved. The Swift runtime contains no production-widget renderer. Temporary reference exporters are removed.

All implementers skip builds/tests/linters/formatters; Main owns settled-tree validation. Read-only local inspection remains required. Changes stay inside the new worktree. The user authorized commit and push after final check parity. Follow Qt/QML/CMake guidance and the existing QtBridge build/bundle path.

## Frozen interfaces

- SongTabsController and SongTabSession: task-1-brief.md. QML binds display QObject role; Swift argument labels follow QtBridge-supported pattern, QML slots remain positional.
- SongTab.qml: reused existing grid rooted in FocusScope; required gridModel, font/typography inputs, readonly popup state. Main derives selected grid/audio/pitchBridge for existing toolbar and actual UI actions.
- SongTabs.qml: stateless strip plus persistent page Repeater, native dirty-close Dialog, blank empty page. Scroll controls songTabScrollLeft/songTabScrollRight; selection songTabSelect_<id>, close songTabClose_<id>; no songTabAdd/songTabOverflow controls. Page songTab_<id> retains existing descendant names.
- QListModel.move(from:to:): task-4-brief.md; final destination index and failable native beginMoveRows.

## Tasks

1. Swift controller and App bootstrap — SDD-track; SongTabsController.swift and App.swift. Three demo sessions belong only in App initialization; no conditional smoke setup.
2. Reuse QML page and implement C++-parity tab strip — SDD-track; Main.qml, SongTab.qml, SongTabs.qml, GridPalette.swift (canonical tab colors only). Cohesive page extraction, native FocusScope.
3. Native interaction/raster verification — SDD-track; songtabs_smoke.cpp/.h, grid_smoke.cpp, interaction_smoke.cpp (failure attribution only), prototype CMakeLists.txt. Five-file exception is one verification/registration change.
4. Genuine QtBridge list move — SDD-track; existing qtbridge-object-return.patch. No second bridge/model or page registry.

Disjoint original owners keep their write sets for fixes. Frozen interfaces allow parallel authoring; Main gates/reviews the settled union. No partial acceptance on an unbuildable tree.

## Controller verification

- deno task prototype:swift-grid --smoke: all original strict native grid raster, gesture, audio, undo, policy, cancellation checks plus tab state retention, real reorder, close, empty/reopen fixture setup, narrow native scroll controls. Test-only fixture opening is not a new UI feature.
- PORYDAW_VISUAL_SCREEN_DPR=2 deno task verify --verbose: final production suite passed, 99/100 harnesses successful and one skipped, including all eight production visual suites. No baseline changes. A separate earlier DPR1/font16 run exposed a pre-existing accidental B3-hover baseline absent from its fixture; it was not rewritten.
- Actual native application capture and accessibility/pointer interaction: multiple tabs, full-width/narrow strip, correct labels/contrast/clipping. Native scenarios run sequentially.
- Main formats changed C++ once after settled fixes; Swift compilation and real QML loading cover absent Swift/QML language servers. clangd lacks prototype target configuration; actual native C++ compilation supplies equivalent parse evidence.

Prior behavioral gate: PASS, including all eight tab scenarios and original strict grid/audio/gesture/undo/cancellation checks, with no QML warnings. The earlier screenshots showed an approximation, not the required production tab appearance; they are not accepted as visual parity evidence.

Harness corrections establish actual native prerequisites: request/wait for window activation once before keyboard scenarios; await a requested rendered frame after fixture session creation before pointer input. QObject existence alone did not establish a delivered scene. Native pointer helpers move before pressing; no tooltip suppression, application focus repair, test tolerance changes or alternate renderer. Temporary popup inventories and jurisdiction diagnostics were removed. All four task reviews and final integration review approved with no blocking findings.

## Retirement boundary

Production SongTab remains QWidget. No production/save integration is claimed. Reusable QML/controller design uses no fixture-test hooks; bootstrap fixtures and src/checks are not permanent application policy. The user's SongTab request is a narrow exception to the Swift charter chrome exclusion, never authorization for transport/browser features.
