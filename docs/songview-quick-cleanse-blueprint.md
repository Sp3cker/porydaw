# SongView Qt Quick cutover blueprint

## Status and authority

Blueprint for the complete rewrite requested by the user. Implementation is not
complete. Starting revision: `afcf179` on `fork-main`.

Inputs: evidence-plan-architect's SongView QWidget-Exodus plan, Reviewer critique,
and Reviewer's OtherStrip implementation/check plan. This document resolves the
conflicts between them. Each component still requires a source-current local plan
before implementation, including exact check edits and interfaces.

`Plan` is not registered in this environment. Use the registered `reviewer` fallback.
The requested thermo audit is provided by `thermo-nuclear-reviewer`.

## End state

- SongView and TimelineQuickView no longer inherit QWidget.
- All editor rendering and interactive surfaces listed below use Qt Quick.
- No QWidget, QMenu, QDialog, QInputDialog, QMessageBox, QToolTip, widget layout,
  widget editor, or widget focus lookup remains in the SongView or editor-drawer
  implementations, including the event list and voice picker.
- SongTab remains part of the surrounding QWidget application. Any necessary
  createWindowContainer adapter lives beside SongTab, outside songview/ and
  editordrawer/, and only embeds the Quick window and forwards host lifecycle.
- MainWindow, workspace, transport, voicegroup browser and unrelated application
  dialogs are not being rewritten. Do not delete shared helpers with remaining
  out-of-scope callers.
- The existing document semantics, undo, selection, clipboard, keyboard routing,
  audition, table editing, drag reorder, column resizing and playhead behavior
  remain available. A renderer migration is not permission to remove behavior.

## Review resolutions

1. Retain the architect's inventory, sequential integration and model reuse.
   Reject its proposed fixed-column/keyboard-only alternatives for Event List.
   Keep interactive column resizing, stretch-last-column and pointer reordering.
   Initial widths and all new geometry use layout font primitives.
2. Keep EventTableModel and its edit logic. Add only the roles/invokables needed
   by QtQuick TableView; do not add a forwarding model or relocate files merely
   to rename them. Editing must preserve exact 64-bit ticks without a JavaScript
   number round-trip.
3. Shared menu rendering earns reuse across real consumers. Use a typed C++
   model with explicit roles and action identifiers, not nested QVariantMap
   command descriptions. Menu enablement and action semantics stay with owners.
   Do not add one shallow presenter class per small dialog.
4. User clarification supersedes the initial app-modal decision: transient forms
   and pickers must be based on the custom Quick context menu's popup hosting and
   quick dismissal. Share the actual overlay/input/lifecycle implementation,
   not a second copy of its behavior. Outside press, Escape, focus loss, resize
   and owner invalidation cancel unaccepted drafts; consume the dismissing press
   and its paired release. Inside text/pointer controls retain their normal keys.
   Keep typed form content separate from menu rows and document effects.
   Inline Tempo/CC prompts remain inline with their existing cancellation policy;
   passive tooltips must not acquire focus or intercept input.
5. Async requests retain a guarded target and document revision; stale acceptance
   performs no edit. Clear pending state before applying or emitting completion.
   Use existing domain owners and named commit paths. Close on detach, replacement,
   readiness loss and destruction; release audition on every exit path.
6. The cited no-QtQuick.Controls instruction is scoped to earlier migrations,
   not a repository-wide ban. For this cutover, reuse the existing primitive
   Quick controls and QtQuick TableView rather than add a second styling system.
7. Shared edit commands remain in SongView::handleEditKey. Event List retains
   EditKeyOrigin::EventList; local text, table navigation and popup controls own
   their advertised keys. Preserve ShortcutOverride and press/release pairing.
8. Keep the macOS CALayer playhead, attaching it to the Quick window's native
   view after shell removal. Do not silently substitute the fallback renderer.
9. Do not replace widget-type assertions with presenter-type assertions. Retain
   observable outcomes and exercise actual QML focus/pointer/text paths. Remove
   wording, child-count and incidental plumbing assertions rather than repin them.

## Worktree and integration protocol

For each row below, in order:

1. Reviewer fallback produces a local plan from the latest integrated source:
   exact production and check paths; types/properties/signals; lifecycle and
   coordinate conventions; behavioral assertions; verification commands.
2. Create its own worktree using
   `deno task worktree:create -- <name> --base fork-main`.
   Work only in the printed path. No nested submodule checkout or shared build
   directory. Separate worktrees share the main checkout's poryaaaa source.
3. Dispatch disjoint production and check implementation slices together after
   their interface is fixed. Agents edit only: no builds, tests or formatters.
4. Orchestrator formats the union once and runs the targeted deno verification
   plus real Quick interaction smoke. Check relevant LSP diagnostics when available.
5. Thermo reviewer audits the complete component diff against its base and plan.
   Resolve major findings through implementation agents; rerun affected checks and
   request re-review. No component merges with unresolved major findings.
6. Commit only that component and its migrated checks/docs. Merge into fork-main
   only after green verification and approval. Do not push. Start the next row
   from the resulting fork-main; never merge a red intermediate substrate.

Independent implementation slices may run concurrently within a worktree. Rows
consume the preceding merged state: plans may investigate ahead, but must reconcile
against that state before dispatch. No cleanup of unrelated work or old worktrees.

## Ordered component ledger

| Worktree | Complete component scope | Checks and acceptance |
| --- | --- | --- |
| quick-otherstrip-tooltip | OtherStrip native tooltip | host-adapter: real Quick hover shows the marker digest; leave/cancel/empty hit hides it; multiline placement clips to scene. |
| quick-eventlist | Table, toolbar, chunk selector, persistent filter menu, row menu, inline editors, typed shared menu rendering | eventviews, selectionkey-local-input, rollcheck-static; edit, select, filter, scroll/follow, clipboard, keyboard and pointer reorder, column resize, remap and undo. |
| quick-automation-values | Tempo and CC prompt family behind NodeLane; drawer pencil key guard | automation, editor-drawer, selectionkey-local-input, host-adapter, host-seams, mainwindow-routing; both entry points, limits, CC 10/24 offset, cancel/stale no-write, focus return. |
| quick-note-velocity | Note velocity value entry | rollcheck, selectionkey-local-input; accept/cancel, bounds, undo, text shortcuts without timeline leakage. |
| quick-time-signature | Ruler time-signature dialog and both callers | rollcheck; open through actual ruler input, choose 7/8, commit, cancel and undo. |
| quick-insert-time | Bars/beats/fractions dialog and menu action continuation | mainwindow-routing-input, rollcheck; active-song routing, tick conversion/overflow, cancel, unchanged undo restoration. |
| quick-popup-dismissal | User-directed correction: one shared custom-menu popup session for menus and transient form content; remove native application-modal form host | eventviews, rollcheck, selectionkey, mainwindow-routing; inside editing, outside/Escape/deactivation cancellation, swallowed dismissing clicks/releases, owner replacement, submenu navigation and no hidden document writes. |
| quick-voice-picker | Search, selection, 128 voices, press-hold audition, all live callers | editor-drawer, native windowing, rollcheck, trackheaderquickcheck; filtering/no-match, accept/cancel, track addition, voice-change edits and guaranteed audition release. |
| quick-note-menu | Note context actions and outside-right-click retarget | rollcheck; correct target/action, shortcut display, velocity entry, press-retarget and swallowed paired release. |
| quick-time-selection-menu | Shared roll/drawer time-selection actions | rollcheck, automation-editing, selectionkey; span semantics, clipboard enablement, copy/paste/duplicate/delete outcomes. |
| quick-ruler-grid-menu | Division and feel menus | rollcheck, host-adapter; checkmarks, division/triplet changes, keyboard navigation, cancellation. |
| quick-ruler-loop-menu | Loop/time-signature ruler menu | rollcheck; each conditional action, marker changes, time-signature launch and undo. |
| quick-track-header-menu | Track header show/change voice/rename and other existing actions | trackheaderquickcheck, rollcheck, rollwindowingcheck; target preservation, queued mutation, picker and rename focus. |
| quick-automation-menus | Canvas time-selection, clipboard/value-range submenus, lane visibility | automation-editing, editor-drawer; enabled/checked state and actual lane/document effects, dismissal. |
| quick-cc-delete-confirm | Nonempty CC lane deletion confirmation | automation-editing; decline no-write, accept deletion plus undo, stale target cancellation. |
| quick-node-menu | Individual automation node Set Value menu | automation-editing; target node, opening inline value prompt, commit/cancel and undo. |
| quick-voice-change-menu | Voice-change node menu | editor-drawer; targeted picker, cancel, accepted change and undo. |
| quick-songview-shell | SongView/TimelineQuickView inheritance, layouts, lifecycle, input host, external SongTab embedding and native playhead | Full deno task verify; real window resize, tab switching, readiness, replacement, transport and native compositor smoke. |

## Tooltip implementation contract

OtherStrip owns toolTipVisible, toolTipText and toolTipPosition properties with one
change signal; appearance follows the existing TrackHeaderModel tooltip theme roles.
Keep the existing capped digest and hit math. Replace show/hide sinks; no focus change.
Publish OtherStrip beside timeRuler in the Quick context. QML anchor coordinates are
plot-local plus otherEventsBandPlotRect origin, not the full band origin. Reuse the
multiline RulerToolTip clamp/flip and font-derived geometry conventions. Register the
QML resource in the existing module. Existing host/tst_hostadapter.cpp hover test
continues injecting input into the real Quick window; assert rendered visibility and
text, then hidden state after leaving. No QToolTip polling or native tooltip cleanup.

## Event List implementation contract

- QtQuick TableView virtualizes rows; the retained QAbstractTableModel remains the
  edit authority. Native integer parsing stays C++; tick editing is string based.
- A cohesive event-list controller replaces widget chrome and owns selection,
  chunk/filter state, action decisions and playhead follow. Do not duplicate document
  selection or event index mapping in QML. Keep pure moveDestForRow constraints.
- Support extended row selection, current row, keyboard navigation, local editor
  clipboard/undo and timeline commands when not editing. Preserve all editable
  column kinds, validation, commit/cancel and meta/tempo conversion.
- Preserve filter check toggles without closing, chunk selection, count, add/delete,
  row context actions, alternating backgrounds, mono font and playhead tint.
- Widths are font-derived initial values; resizing and stretch-last-column remain.
  Pointer drop shows the destination and uses the same legal-reorder authority as
  keyboard movement. No keyboard-only replacement.
- Build the typed menu renderer with these first real consumers. Support enabled,
  checked, separator, shortcut and submenu behavior only as required by real menus.
  Clear session before command execution; cancellation never invokes a command.
- Migrate eventviews fixture and four suites, selectionkey event-list local tier,
  and static editor fixture in the same worktree. Keep model contract assertions;
  add actual cell editing, resize and drag interaction proof, not model-only proof.

## Prompt and picker implementation contract

Tempo/CC follows the existing drawer-plan NodeValuePrompt contract: title, label,
initial value, minimum, maximum, storedOffset; PendingValuePrompt belongs to
AutomationCanvas. Both Set Value and double-click open without writing. CC 10/24
show -64..63 and store +64. Cancel on focus loss/hide/replacement/deactivation;
accept only a matching document revision and restore automation input focus.

Velocity, time signature, Insert Time and the voice picker use the same in-scene
popup mechanics as custom context menus, not application-modal native windows.
Keep asynchronous completion and guarded target identities. Reuse DragInput for
numerical fields; text editing must not inherit menu type-ahead/key interception.
Outside press and Escape cancel drafts without applying them; dismissal must not
also edit the underlying timeline. Verify actual popup content and input routing,
not a separate-window identity or application-modality assertion.

Voice picker preserves every live caller: edit track voice, add track and the
voice-change area. Source reconciliation found AutomationPage::pickVoice was an
unused forwarder; remove it rather than invent a new automation entry point.
Build/filter a small typed model, select the first match, disable acceptance for
no match, and retain audition key 60 and velocity 112. Note-off is mandatory on
release, cancellation, rejection, deactivation, replacement and destruction.

Migrate the existing native-dialog watchdog tests to actual Quick input. Keep their
observable document/undo assertions. Do not invoke accept directly as the only proof
of a rendered editor or input ownership. Delete obsolete modal interception helpers
only when their last consumer has migrated.

## Shared popup implementation decision

One QuickPopupSession belongs to each TimelineQuickView and its existing Quick
window. QuickMenuHost borrows that session for menu panels; the same session loads
typed form QML through openForm. Remove QuickModalHost and modalHost/modalWindow
interfaces, rather than retain a compatibility wrapper or add a second form host.

The session owns the actual shared scene overlay, outside-press underlay, window
lifecycle filtering and paired-release suppression. Menu-only rows, submenu
layout, type-ahead and keyboard navigation remain in QuickMenuHost. Forms receive
normal Quick text-input dispatch and retain their terminal key handling.

Cancellation reports whether restoring local focus is appropriate. Outside press
and Escape can restore the owning band; deactivation, owner teardown and
replacement must not reactivate the application or steal focus from the next
popup. Cancel the old session before publishing a new owner's pending state.
Keep suppression of an outside press's release alive even after the dismissed
overlay is destroyed or a right-click retarget opens another menu.

Existing pitch-bend editing and inline rename retain their established live-edit
commit-on-dismiss semantics. They are not unaccepted numeric/picker drafts.
Passive tooltips remain noninteractive; inline Tempo/CC remains lane-local.

## Menu implementation contract

Site-local action identifiers and builders preserve enablement and targets. The
shared typed renderer owns rendering and navigation, not document edits. Preserve
outside-click dismissal, submenu traversal, checked state and focus restoration.
Note retargeting consumes the outside right press and its matching release exactly
once. Cancel sessions on owner invalidation. A click that opens a value prompt or
picker must finish the menu session before opening the next surface.

Automation has three canvas menus plus individual-node and voice-change menus;
none may be missed because it lives outside automationcanvas_menu.cpp. CC deletion
confirmation is a separate component/worktree from those menus.

## Shell implementation contract

After every leaf has merged, replace spacer-derived layout with direct geometry
from the existing metrics and drawer bounds. Preserve the canonical published band
rectangles and input coordinate systems. The Quick window fills the external host;
the root paints the editor background. No extra Quick window for the event list.

SongView remains the document/view coordinator, now QObject. TimelineQuickView owns
or observes its Quick window with one explicit lifetime policy; the SongTab adapter
must not double-delete a window owned by createWindowContainer. Move resize, focus,
activation, DPR, readiness and cancellation responsibilities to the appropriate
QWindow/embedding owner. Migrate every QWidget-assuming caller found by references,
including automation filters, pitch-bend popup positioning, check rigs, screenshots
and native playhead attachment. Do not add QWidget-shaped compatibility methods.

Retain both native and Quick playhead checks. Audit macOS attachment and clipping
against the actual Quick NSView, not the old MainWindow view. Preserve tab teardown
and engine/document lifetime ordering.

## Verification and closure

Use deno tasks exclusively for builds/checks/formatting. Each component's local
plan confirms filter names against the live registry before execution. Orchestrator
runs `deno task verify --filter <filter> --verbose` with all relevant filters; verify
builds the checks first. Never run redundant parallel format/build gates.

Do not launch native GUI harnesses, activate windows, or inject desktop input while
the user is using the machine. User interaction with the test windows invalidates
focus/outside-click failure evidence. Use registered offscreen checks and explicitly
offscreen/software Quick interaction probes instead; never report these as native
window-system verification. Native-only coverage remains separately pending until
it can run without interfering with the user. Do not weaken assertions or alter
behavior to chase a user-interrupted native run.

Each UI component needs real Quick event delivery and rendered-surface proof, using
existing EditorRig/native window harnesses and a production-app smoke where needed.
Permanent regression coverage must defend a plausible behavioral failure. Do not
add source-text tests or assert a new presenter merely exists.

After a component passes smoke, remove throwaway artifacts, update affected existing
docs/changelog where applicable, finish thermo re-review, then commit and merge.
Final integrated fork-main runs the full check suite. Source inventory must confirm
all listed widget surfaces and widget-only dependencies are gone; the external
SongTab embedding adapter is documented explicitly. Any failing assertion is a
blocker to handoff, not an accepted baseline.

## Voice picker completion evidence

- **Implementation**: Typed asynchronous voice picker (`songview::VoicePicker` and `VoicePickerPrompt.qml`) hosted on the shared `QuickPopupSession` via `openForm`. All live callers migrated (track header voice edit, track header add track, and drawer voice-change area). Dead `AutomationPage::pickVoice` forwarder removed. Audition retains key 60 and velocity 112 with guaranteed note-off (velocity 0) on release, rejection, cancellation, replacement, and destruction. Stale bridge guards (`picker != m_voicePicker`) reject out-of-order `accepted` and `rejected` signals from superseded sessions.
- **Verification**: Build checks passed. Registered `editor-drawer` suite passed (`voicePickerTransactions` 3 passed, 56 ms). Forced-offscreen `trackheaderquickcheck` (`addTrackOpensPickerAndRebuildsHeader`) and roll check (`headerAddTrack`) passed twice each.
- **Native coverage limits**: Native `headerSelectionAndVoicePicker` explicitly pending due to active user desktop; no native launch performed. Temporary diagnostic probes removed. No commit hash recorded prior to commit creation.

## Note menu completion evidence

- **Implementation**: Note context menu migrated to typed `QuickMenuModel` and `QuickMenuHost` on the shared `QuickPopupSession` within `PianoRoll`. Retargeting on outside right-press swallows the paired release, guards against stale document revisions, and enforces close-before-velocity ordering. Measured initial menu geometry is supplied prior to QML component creation, ensuring immediate layout without collapsed `ListView` hit areas.
- **Verification**: Build checks passed. Registered `eventviews-chrome` passed. Forced-offscreen roll checks (`velocityNoteMenuRetarget`, `velocityNoteMenuStaleActivation`, `velocityPromptAcceptUndoLatch`, `velocityPromptCancelStale`, `popupSessionDismissal`, `velocityPromptBounds`, `velocityPromptOutsideRightNoRetarget`) and `selectionkey-local-input` (`velocityPromptOwnsKeys`) passed.
- **Native coverage limits**: Native verification deferred per desktop policy. Temporary diagnostics and probes removed.

## Time-selection menu completion evidence

- **Implementation**: Shared asynchronous time-selection context menu (`songview::TimeSelectionAction` rows built by `SongView::buildTimeSelectionItems`, opened and dispatched by `SongView::openTimeSelectionMenu`/`handleTimeSelectionAction`) rendered through the shared `QuickMenuHost`/`QuickMenuModel` on the canvas `QuickPopupSession`. Both live routes — roll right-press inside the selection and the drawer active-selection branch — anchor to Quick-window scene coordinates (`DrawerPageTimeSelectionMenuRequest::scenePosition`). Opening snapshots document identity, revision, and the exact selection (ticks, scope, lanes, tempo, stored track scope); ordinary activation closes the session before dispatch consumes the snapshot, and any mismatch, replacement, or readiness loss is a silent no-write. Owner range commands, action order, shortcut display, build-time Paste enablement, and the live edit-cursor Paste dispatch are unchanged; dismissal returns focus only when the session's restoreFocus says so. The inactive-selection drawer fallback stays native for the automation-menus row.
- **Verification**: Real rendered-row command smoke passed for every menu action, including Paste enablement and Clear. Registered `automation-editing` passed with the rewritten `selectionContextMenuRoutesInsideActiveSelection`; rollcheck gained permanent `timeSelectionMenuOpensWithPasteEnablement` and `timeSelectionMenuStaleAndCancelNoOp` (Escape dismissal no-write with focus return, stale-activation no-write). Thermo delta review passed.
- **Native coverage limits**: Native verification deferred per desktop policy. Temporary diagnostics and probes removed.

## Ruler grid menu completion evidence

- **Implementation**: Ruler grid division and feel menus migrated from the blocking native `QMenu` to a persistent `QuickMenuHost` with separate division/feel `QuickMenuModel`s on `TimeRuler`, rendered on the shared canvas `QuickPopupSession`. Rows carry the raw setter values (division denominators including Auto 0; feel 0/1) and rebuild checked state at every open; every ordinary pick — including the already-checked row — closes the session before `activated()` dispatches to the existing `SongView::setGridMinDenom`/`setGridFeel`. `RulerControls` passes Quick-window scene coordinates (`mapToItem(null, …)`; the `menuTarget` plot-side mapping is gone), and a new `gridMenuActivated(bool division)` completion signal lets the invoking control restore its own focus — no stored predecessor, no shared close-policy change. Shared dismissal (outside press/Escape/deactivation with swallowed paired release) is unchanged; `closePopups` cancels the owned session without focus theft, then closes the retained legacy `m_openMenu` ruler context menu, which intentionally stays native for the next worktree.
- **Verification**: Scoped offscreen only: the registered `ruler-grid-menu` rollcheck slots and the host-adapter suite passed; real rendered-Quick smoke passed — feel-menu keyboard continuity reopened without forced refocus, and division picks (Auto, 1/4, 1/32) applied through rendered rows; checked-row click closed with no document change. GUI/source thermo audit passed; temporary fixtures were removed and the suite rerun clean.
- **Native coverage limits**: Native verification deferred per desktop policy — no native window was launched. The ruler right-click context/loop menu intentionally remains native as the next component row.

## Ruler loop menu completion evidence

- **Implementation**: The last native ruler context/loop menu migrated to a persistent `QuickMenuModel` on the shared `TimeRuler::m_menuHost` over the canvas `QuickPopupSession`, with typed `songview::RulerMenuAction` row ids (set loop start/end, remove loop, selection-scoped rows only while a selection is active, edit/remove time signature). Right press+release anchors the menu at the release point in Quick-window scene coordinates (`mapFromGlobal` over the input host bridge) while acting on the snapped press tick, and the press-local signature-chip hit is snapshotted at open. A guarded `PendingRulerMenu` target (document pointer, revision, click tick, chip tick/values, selection + track scope) publishes only after a successful host open, is consumed before any command, and is dropped stale on mismatch — selection-scoped rows additionally require the live selection to equal the open-time snapshot. Remove loop and loop-from-selection keep their two separate undo commands; remove time signature stays gated to an explicit (non-implicit) clicked chip; edit time signature opens the existing `TimeSignaturePrompt` bridge only after the session closes and keeps focus. `TimeRuler::inputCancelled` narrows FocusLost/PointerUngrabbed teardown so the menu survives its own focus handoff and release ungrab while the band's menu host owns the session (Hidden/WindowDeactivated keep full teardown), and `prepareForSongReplacement` cancels ruler-owned popups on song swap. `QMenu`/`m_openMenu`/native exec are fully removed; grid menus keep both open orders through the shared `ensureMenuAdapters` factory and the unchanged `gridMenuActivated` QML focus repair.
- **Verification**: Real rendered-row command smoke passed (insert blank, duplicate, remove contents); both initial-open orders (grid-first and ruler-first) and right-drag→menu→Escape no-mutation passed; all three rollcheck loop-menu slots plus both menu-entries cases and prompt accept/cancel passed with the fixture registered clean. Verifier triage corrected two fixture probe assumptions (cumulative two-step undo expectation; provably off-chip tick-row probe) with no production change; the unchanged `timelineRulerScope` raster assertions remain native-pending under forced-software QSG vertex-color layers with no assertion weakened, and that function's menu portion was proved separately by a real-input throwaway. GUI/source thermo audits passed; temporary fixtures and wrappers removed byte-exact, clean rebuild.
- **Native coverage limits**: Native verification deferred per desktop policy — no native window was launched. The unchanged `timelineRulerScope` raster assertions stay pending until forced-software rendering can exercise them without the QSG layer limitation; no renderer changes were made.

## Track header menu completion evidence

- **Implementation**: The track header context menu migrated from the blocking native `QMenu` to a persistent `QuickMenuModel`/`QuickMenuHost` pair owned by `TrackHeaderModel` over the shared canvas `QuickPopupSession` (bound by `TimelineQuickView` alongside the roll and event list), implemented in the new `trackheadermenu.cpp` to keep menu lifecycle out of the already-large model. Typed `TrackHeaderModel::HeaderMenuAction` row ids carry the legacy labels and order; Duplicate is enabled iff `canAddTrack` at open. Opening snapshots a guarded `PendingHeaderMenu` (`QPointer<SongDocument>` identity, revision, raw engine track) and publishes it only after a successful host open; activation consumes the target before dispatch. Show-voice is the immediate nonmutating `revealTrackVoice`; Rename begins synchronously post-close with the existing in-band editor focus adoption; ChangeVoice/Duplicate/Delete reuse the single `queueHeaderMutation` primitive around the real `SongView` operations. Rebuild/remap/document replacement/teardown cancel through `cancelTransientState` → owned, `session->owns`-guarded no-focus session cancel; outside press dismisses without retarget. The queued ChangeVoice/Duplicate/Delete lambdas carry the whole validated snapshot and recheck owner document identity plus revision inside the queue immediately before the semantic call, so a remap landing between pick and delivery cannot reinterpret the raw index (the separate inline commit-rename queue is unrelated and unchanged).
- **Verification**: Offscreen/software only. Checks' deterministic RED regressions for the in-queue remap (stale ChangeVoice opening the wrong-track picker; stale Delete leaving the track count unchanged) went GREEN once the snapshot guard landed; all 7 new header-menu slots, the rename/reorder slots (with the async-assertion correction QTRYing the document name rather than the synchronously-cleared editing state), and the migrated rollcheck `headerContextMenu` passed. Temporary real-input probes — menu→picker accept and menu→rename typing/Return — proved correct target, unchanged sibling rows, and undo restore. Thermo B2 review drove the queue-guard design; no source or test changes after refreeze.
- **Native coverage limits**: Native verification deferred per desktop policy — offscreen/software runs only; no native window was launched, and native raster coverage remains pending under the known forced-software QSG limitations.

## Automation canvas menu completion evidence

- **Implementation**: Lane, add-lane, and inactive-time context menus migrated to typed `QuickMenuModel` and `QuickMenuHost` on the shared `QuickPopupSession`, scene-positioned and guarded by document identity, revision, and lane identity. The real Range submenu is preserved, while active time selections delegate to the existing shared time-selection menu. Nonempty CC deletion intentionally retains `QMessageBox` pending the next separate component; only this continuation is queued with an immutable snapshot and pre/post guards to avoid QML-handler nested-loop destruction. Post-mutation actions use immutable row IDs because `documentChanged` synchronously rebuilds slots.
- **Verification**: Six focused registered slots passed (8 Qt totals including init/cleanup); real-input Hide, empty Remove, nonempty Remove No/Yes target-only+sibling+undo, range choices, and owned-vs-foreign lifecycle passed. Stale revision and newer foreign-popup queued-gap smoke passed twice with no old question or deletion. Final post-fix Clear retains correct empty CC row and undo; Remove confirmation smoke passed twice. Frozen bytes restored, temporary probes/wrapper/config removed, and sanctioned rebuild passed. Thermo and GUI final delta audits passed with no open findings.
- **Native coverage limits**: Native verification deferred per desktop policy; all runtime was forced offscreen/software with no native window launch or desktop input.

## CC delete confirmation completion evidence

- **Implementation**: Nonempty CC lane deletion confirms through a dedicated `CcDeleteConfirm.qml` form bound to a direct `AutomationCanvas` bridge (`automationcanvas_deleteprompt.cpp`) on the canvas's shared `QuickPopupSession` via `openForm`; the legacy native `QMessageBox` with its queued continuation is gone. `Cancel` takes initial focus via `callLater` (a bare Return cancels), the two buttons form a Tab/Backtab loop, and a terminal `Keys` sink keeps timeline commands from leaking. `handleMenuAction` measures document-written `lanePoints` once and passes that `writtenEventCount` into `openCcDeletePrompt`, which refuses to open at zero — a synthetic-only default row (engine default, no writes) keeps the unchanged empty-Remove body with no confirmation and no write. Populated default Volume/Bend rows read `Delete CC events (default row remains)` and delete only their written events while the visible default row stays; the two-button Delete/Cancel prompt states the truthful written-event count and that the default row remains, and ordinary document Undo restores the deleted events in that retained row; other lanes keep `Delete CC lane`. The immutable guarded snapshot (document, revision, lane, row id, title, count) is captured before any cancellation of a displaced session and revalidated after; the pending target publishes before the QML form is created; lifecycle and focus are owns-gated on every teardown/replacement path; post-mutation actions touch only snapshot ids because `documentChanged` synchronously rebuilds slots. No hide-on-delete or undo overhaul.
- **Verification**: Sanctioned `deno task build:checks` passed, and the offscreen/software `automation-editing` run passed all 9 new `ccDeletePrompt*` slots plus the 6 neighboring canvas-menu slots (17 Qt totals including init/cleanup): accept deletes only the target lane with undo restore; Cancel, Escape, outside right press, and an initial Return decline without writing; a stale document cannot delete the target; foreign popups survive invalidation. The pre-fix already-Quick snapshot produced the expected RED at `ccDeletePromptSyntheticOnlyVolumeSkipsConfirmation` (the old form counted the projected synthetic node and left a popup open); the written-events fix went GREEN. A throwaway real-input smoke (since removed; 4 Qt totals) proved the Tab/backtab loop both ways with the document frozen, Space on the focused Delete accepting in exactly one transaction with band focus return and undo restore, and pending-form tab teardown without crash. An initial missing `AutomationPage` include and two ignored waits were repaired without suppression; RED/probe source was restored byte-exact, temporary wrapper/config/snapshots were removed, and the final sanctioned rebuild was green. Thermo and GUI final audits passed.
- **Native coverage limits**: Native verification deferred per desktop policy — all runtime was forced offscreen/software with no native window launch or desktop input; native/default-backend raster coverage remains pending.

## Node menu completion evidence

- **Implementation**: The node point menu (Set Value / Delete) is the canvas's second typed `QuickMenuModel`/`QuickMenuHost` pair (`automationcanvas_pointmenu.cpp`) on the shared `QuickPopupSession`, dispatched through its own `NodeMenuAction` enum and model — separate from the lane menu's, not one shared id space. Opening snapshots a guarded `PendingNodeMenu` (document identity, revision, row id, exact tick+value occurrence) and revalidates across the open's synchronous callbacks, so a stale open ends only a menu this canvas owns. Node hits keep press-path precedence over an active time selection; an outside right-press retargets or stays dismissed on a miss with the paired release swallowed; the pending target is consumed before dispatch, and stale revision, rebuild remap, or vanished occurrence writes nothing. Delete keeps the existing written tick-group deletion but is enabled only for a document-written point at the tick — projected engine defaults open Delete-disabled while Set Value promotes them into written events through the already-inline Quick value prompt. The shared `QuickMenuPanel` delegate now derives `Item.enabled` from its active state, the canonical accessibility state, with the frame absorbing the clicks disabled rows let fall through.
- **Verification**: Forced offscreen/software only, both deliberate RED probes then GREEN: enabling the unwritten Delete row and removing the delegate `Item.enabled` binding each fail their slot — the latter exactly at the accessibility disabled-state assertion — green on byte-exact restored source. Registered `automation-editing` passed 24/24 Qt totals (9 `ccDeletePrompt` + 7 `pointMenu` + 6 menu neighbors + init/cleanup): delete-undo, duplicate-tick prompt targeting, Escape/outside dismissal, synthetic-default disabled Delete with working Set Value promotion, stale/foreign no-writes. Shared-panel regressions reran green (`trackheaderquickcheck` 9, rollcheck `headerContextMenu` 3). Real-input smokes: disabled-row clicks stay menu-contained with bytes unchanged; a focus return that wrote externally during SetValue rejects the late prompt/edit; a visible origin proxy deletes the offscreen written source tick with undo restoring; pending-menu/prompt tab teardown and the earlier focused-prompt stale-write guard passed; in-process `QAccessible` proves the disabled bit, not a native screen reader. Temporary probes removed.
- **Native coverage limits**: Native verification deferred per desktop policy — forced `QT_QPA_PLATFORM=offscreen` plus software Quick backend only, no native window launch or desktop input; native/default-backend raster and window-manager focus coverage remain pending.
