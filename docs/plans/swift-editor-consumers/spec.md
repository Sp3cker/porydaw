# Complete Swift/QML editor drawer contract

This specification extends the accepted camera integration and drawer container
through the shared playhead and all three production editor pages. Follow
[Global Constraints](plan.md#global-constraints) and the bounded task brief for
the task being implemented.

## Session ownership and publication

`DocumentSession` is the sole owner of the current `SongDocument`,
`PlaybackTimeline`, `EditorCamera`, selected track/notes, edit cursor, and
document history. `ApplicationSession` is the concrete integration owner for
the current document presentation: `PianoGrid`, `EditorDrawerPresenter`, shared
playhead, page owners, and `NativeAudio`.

Document mutation rebuilds the canonical timeline before the existing
`onPlayback` and `onChange` publications. Presentation-only camera mutation uses
`DocumentSession.mutateCamera`; equal camera/projection values publish nothing.
Neither path permits a presenter-owned history, selection copy, timeline, or
camera.

Drawer preferences are application presentation state. Page models are
document-bound and are replaced with the document. Page visibility, resizing,
camera navigation, playhead presentation, and prompt state do not dirty a song,
consume Redo, or publish audio.

## Accepted camera and composition

The accepted `EditorCamera` is the only horizontal and pitch viewport authority.
Grid and drawer pages use its existing transforms and mutations. Preserve:

- negative pre-roll, fractional scroll, timeline-end bounds, and unbound homing;
- anchored time/pitch zoom, reveal, restore, and production wheel policy;
- font-derived limits and actual font/DPR metric pushes;
- one coherent document refresh after edits; and
- no QML `Flickable` or reciprocal binding acting as a second scroll authority.

The production root is the property-injected `EditorSurface.qml`.
`SwiftRollOverlay.qml` remains a thin context adapter. The production composition
is also the tested composition: do not copy input handlers into fixtures.

The drawer occupies the bottom of the surface. Its total height determines the
roll height pushed through `PianoGrid.configureViewport`. Drawer bodies use the
same plot origin/width as the roll and the same camera projection.

## Drawer container and page seam

The accepted container owns three fixed section kinds in stack order Velocity,
Voice Changes, Automations and toggle order Voice Changes, Automations,
Velocity. It owns chrome, layout, fitting, resizing, visibility, preference
records, focus requests, content loading, and synchronous cancellation.

Each production page implements:

```swift
@MainActor
public protocol EditorDrawerPage: AnyObject {
    var sectionKind: DrawerSectionKind { get }
    var contentUrl: String { get }
    var bodyPolicy: EditorDrawerBodyPolicy { get }
    var interactionActive: Bool { get }
    func cancelSectionInteraction()
}
```

`interactionActive` is read synchronously by the drawer presenter and joins the
container resize state to form `EditorDrawerPresenter.interactionActive`. It is
not a QML focus heuristic and is not retained after cancellation. Test pages
implement it exactly as production pages do.

One attached page per kind is held strongly until explicit detach. Attach all
document-bound pages before the production scene mounts. Hiding, resizing, or
collapsing keeps the page owner and loader alive. On replacement/close, cancel
while the scene exists, request scene removal, await the existing host
acknowledgment, then detach and release pages and the document session.

No generic plugin registry, live URL swap, weak fallback, page-local viewport,
or per-page teardown acknowledgment.

## Shared playhead

### Authority and lifetime

`ApplicationSession` retains exactly one MainActor Swift shared-playhead owner.
One cancellable polling task exists only while a document is attached. It reads:

- `NativeAudio.playheadSamples`;
- `NativeAudio.transport`; and
- the current `DocumentSession.timeline` and camera.

Every sample maps exclusively through `PlaybackTimeline.tick(for:)`. No elapsed
wall time, local interpolation, QML animation clock, or page timer may infer
position. Pause, stop, seek, loop wrap, tempo publication, camera change, and
document replacement refresh this same owner immediately. Polling is cancelled
before document retirement and on host close.

The published QML state is one tick, projected plot x, timeline-attached
visibility, playing state, and a diagnostic presentation count. The owner may
retain a Swift-only follow-enabled switch for checks; it defaults to true and
is not exposed as new UI.

The playhead remains present while paused or stopped when a timeline is attached.
Its rendered segment is visible only when its projected x is inside the plot.
The edit cursor remains a separate document-session value and continues to own
stopped editing context where production behavior requires it.

### Projection and rendering

Camera-only updates re-project the same tick without rebuilding grid/page
content. Playhead sample updates likewise update only playhead publication.
Content-build diagnostics must remain unchanged across repeated playhead-only
updates.

`EditorSurface.qml` hosts one `SharedPlayhead` production component over the
canonical timeline column. It renders separately clipped segments through:

- the roll plot; and
- every visible drawer page body.

No segment crosses the keyboard/value gutters, resize handles, hidden sections,
or drawer chrome. Every segment reads the same x and color from the shared
presenter/palette; pages do not own playhead items or clocks.

### Follow-scroll

Follow runs only when transport is playing, follow is enabled, no explicit
suspension is active, and neither the grid nor drawer aggregate reports an
active interaction. Let `x = camera.contentX(tick:)` and `w` be the camera
viewport width. If `x < 0` or `x > 0.85 * w`, set camera horizontal scroll to:

```text
tick * pixelsPerTick - w / 10
```

Use the camera mutation path so normal clamping/publication applies. Do not
follow while paused/stopped, during a grid gesture, drawer resize, page gesture,
prompt transaction, or explicit temporary suspension. Ending/cancelling the
interaction permits the next authoritative poll to follow. Loop wrap is an
ordinary sample discontinuity, not a second state machine.

## Page transaction contract

Each page has one Swift owner retained by `ApplicationSession` for the current
document. It exposes bridged primitives/models to QML and implements the drawer
page seam. QML delivers real pointer, keyboard, accessibility, prompt, and menu
input to that owner.

A gesture freezes its target set and before-values at begin. Motion publishes
preview only. Release performs one semantic document mutation and therefore one
history entry. Cancellation restores presentation from the document and commits
nothing. Undo/Redo rebuilds every affected page from the current document. A
track/document/page switch, hide, pointer ungrab, Escape, window deactivation,
and scene retirement all use the same synchronous cancellation path.

Page presenters derive from the selected track, document selection, edit cursor,
shared playing/tick state, current bank slots, and the camera. They must not
cache stale document identities across replacement.

## Velocity page

Velocity uses the production `VelocityMap` semantics and the existing
`SongDocument.setVelocities` / `nudgeVelocities` operations. It displays the
selected track's notes aligned with the shared camera and a value axis derived
from the active voice context.

Required behavior:

- selected-note handles, values, hover/readout, labels, axis range, and shared
  playhead rendering match production;
- click/drag editing freezes the selected target set and before-values;
- multi-note drag clamps as one delta without collapsing relative values;
- prompt/set/nudge commands use one transaction and preserve selection;
- no-op, cancelled, hidden, detached, and stale-target interactions record no
  history and stop any audition/preview;
- live preview and commit use the same velocity mapping;
- Undo/Redo and document/track/voice-context changes refresh content without
  losing the page owner; and
- playhead-only updates do not rebuild velocity content.

The page owns no horizontal camera, no audio clock, and no replacement global
shortcut dispatcher. Use existing application commands where already available;
do not invent a native action to satisfy a test.

## Voice Changes page

Voice Changes projects `DOC_CC_VOICE` lane events for the selected track through
the shared camera and resolves slots through the current document bank. Active
voice context follows the playing shared tick while transport is playing and the
edit cursor while stopped.

Required behavior:

- markers, labels, hover/readout, current-context indication, overlap ordering,
  hit testing, selection, insertion, move, deletion, and shared playhead match
  production;
- the production voice picker and point/context menus use current bank-slot
  symbols and remain valid only for the document/track/point identity that
  opened them;
- voice audition uses the retained native service only through an already
  available capability or a Swift wrapper around that capability. Missing
  native capability is a recorded blocker, not permission to expand QtBridge or
  fake audition;
- picker/menu/pointer cancellation is synchronous and commits nothing;
- completed edits form one document transaction and Undo/Redo restores markers
  and context; and
- playhead changes within the same context span may update the readout without
  rebuilding static marker content.

## Automation domain and projection

Automation domain work is a deep Swift module independent of QML. It covers the
production parameter set and existing document APIs: volume/pan/control-change
lanes, tempo, lane points, range edits, move/delete, XCMD semantics, clipboard
policy, and selection.

The model owns:

- stable parameter and point identity;
- camera-aligned time projection and parameter-specific value projection;
- curve/segment construction, interpolation, snapping, hit testing, labels, and
  lane counts;
- selected active/inactive parameter state;
- frozen pencil, node-drag, range, prompt, delete, and clipboard transactions;
- collision, clamp, stale-target, track/document replacement, and no-op rules;
- playing voice context versus stopped edit-cursor context; and
- content/presentation diagnostics separating rebuilds from shared-playhead
  movement.

All mutation routes use existing `SongDocument` semantic operations. Do not add
parallel MIDI encoding, a copied history layer, or test-only mutation hooks.

## Mounted Automation page

The production Automation QML page renders parameter tabs, gutter/value labels,
curves, points, selection/hover/ghost state, shared playhead, prompts, context
menus, and tap-tempo UI from the Swift model.

Required behavior includes:

- parameter switching without document mutation or losing explicit per-parameter
  selection;
- pencil insertion/drag, node drag, range selection/edit, point value prompts,
  delete and clipboard commands;
- Tempo and CC parity, including snapping, interpolation, endpoint/collision
  rules, and label/readout behavior;
- prompt/menu identity invalidation on track, document, parameter, point, or
  history replacement;
- local text entry and modal keys without stealing global transport outside
  those explicit surfaces;
- tap tempo matching production input/reset/commit behavior;
- synchronous cancellation of pointer grabs, frozen previews, prompts, menus,
  audition, and follow suspension; and
- no static content rebuild for shared-playhead-only updates.

The page uses the existing drawer container, camera, playhead, application
command routing, and acknowledged scene lifetime. It does not add another
window, bridge, bootstrap, dispatcher, or clock.

## Focus, commands, and lifetime

Persistent drawer chrome and non-text page controls activate with pointer,
Enter/Return, and accessibility press. Bare Space remains the window transport
command. Text fields, IME, modal prompts, and explicit audition surfaces keep
their intentional local handling.

When a section hides or a page/document is replaced, cancel its active
interaction before publishing unavailable/hidden state. Focus moves to another
available visible section or the roll. Focus decisions use the current call's
focus observation; there is no remembered focus owner.

All page attachments and playhead polling are document-bound. Drawer chrome
preferences survive replacement; document data, page transactions, prompts,
audition, playhead task, and loaded page callbacks do not.

## Verification ownership and parity ledger

Direct `swiftcore` checks own pure projection, transaction, history, follow, and
publication invariants. The `editorqml-drawer` lane owns the production
composition, real input, focus, accessibility, prompts/menus, rendered output,
and production page component mounting. `swiftrollgated` retains actual-window,
native shortcut, physical DPR, and acknowledged lifetime evidence.

Translate relevant behavior from:

- `src/checks/drawerpresentation/` for playhead, Velocity, Voice Changes, drawer
  rendering, gesture transactions, and content-build diagnostics;
- `src/checks/automation/` and `src/checks/automation/presentation/` for
  Automation semantics, interaction, menus/prompts, cancellation, selection,
  parity, and rendered behavior; and
- the sibling worktree's current production/check changes and reference images.

Reference-image authority:

- `velocity-lane` and `editor-drawer`: macOS DPR 1/2, font 12/16;
- `automation-tabs`, `velocity-prompt`, and `voice-picker`: macOS DPR 2,
  font 12/16; and
- any additional pane-specific baseline named by a task brief after inspecting
  the sibling worktree.

Offscreen output does not prove physical DPR, OS-level shortcuts, or native
teardown. Final acceptance launches the normal production app, mounts every
page with representative real content, captures every pane, and records the
exact tested font/DPR profile.

As pages return, reassess the ten stale absent-UI exclusions individually.
Automation-domain rows become Swift/page coverage where applicable. Voicegroup
save rows remain outside the drawer milestone. The four native MIME clipboard
gaps remain separately named until their own capability exists. Passing a
smaller manifest never closes an exclusion.
