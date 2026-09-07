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
