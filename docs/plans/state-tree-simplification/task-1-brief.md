# Task 1 — Atomic non-null document and observation cutover

## 1. Context

One buildable cutover owns document lifetime, replacement observation and all
view/drawer/check callers. A reference-returning `SongView::document()` must not
land before its pointer-typed consumers are adapted. The event controller's
independent observation/source lifecycle is included, not deferred. Task 2
consumes `AutomationPage::document()` by reference. Shared contracts: [spec.md](spec.md).

## 2. Exact write set

Ownership/replacement changes:
- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/ui/songtab.cpp`

Document access, constructor and null-guard migration:
- `src/ui/songview/quick/eventlistcontroller.h`
- `src/ui/songview/quick/eventlistcontroller.cpp`
- `src/ui/songview/drawercoordination.cpp`
- `src/ui/songview/editkeyrouting.cpp`
- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview/trackvoiceops.cpp`
- `src/ui/songview/viewstate.cpp`
- `src/ui/songview/editactions.cpp`
- `src/ui/songview/pianoroll_commands.cpp`
- `src/ui/songview/pianoroll_gestures.cpp`
- `src/ui/songview/pianoroll_gestures_active.cpp`
- `src/ui/songview/pianoroll_interaction.cpp`
- `src/ui/songview/pianoroll_geometry.cpp`
- `src/ui/songview/timeruler.cpp`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/ui/songview/trackheadermenu.cpp`
- `src/ui/songview/trackheadermodel.cpp`
- `src/ui/songview/quick/automationquick.cpp`
- `src/ui/songview/quick/timelinequickscene.cpp`
- `src/ui/songview/quick/velocityquick.cpp`
- `src/ui/songview/quick/voicechangequick.cpp`
- `src/ui/editordrawer/automationpage.h`
- `src/ui/editordrawer/automationpage.cpp`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- `src/ui/editordrawer/automationcanvas_gesture.cpp`
- `src/ui/editordrawer/automationcanvas_menu.cpp`
- `src/ui/editordrawer/automationcanvas_pointmenu.cpp`
- `src/ui/editordrawer/automationcanvas_deleteprompt.cpp`
- `src/ui/editordrawer/automationcanvas_tabs.cpp`
- `src/ui/editordrawer/automationcanvas_taptempo.cpp`
- `src/ui/editordrawer/tempolane.h`
- `src/ui/editordrawer/tempolane.cpp`
- `src/ui/editordrawer/nodelane/tempoadapter.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea.h`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangemenu.cpp`
- `src/checks/support/editorrig.cpp`
- `src/checks/support/songfixture.cpp`
- `src/checks/automation/raster/rasterfixture.cpp`
- `src/checks/selectionkey/automationprobe.cpp`
- `src/checks/drawerpresentation/velocity.cpp`
- `src/checks/drawerpresentation/voice.cpp`
- `src/checks/rollcheck/identity.cpp`
- `src/checks/rollcheck/pencil.cpp`
- `src/checks/rollcheck/remap.cpp`
- `src/checks/rollcheck/static/geometry.cpp`
- `src/checks/trackheaders/tst_trackheadermodel.cpp`
- `src/checks/trackheaders/tst_trackactivitymeter.h`
- `src/checks/trackheaders/tst_trackactivitymeter.cpp`
- `src/checks/trackheaders/trackheaderinput.cpp`
- `src/checks/host/tst_hostintegration.cpp`
- `src/checks/host/tst_hostseams.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp`
- `src/checks/voicegroupsave/fixture.cpp`
- `src/checks/workspace/selftest_timeline.cpp`

The six additional check callers were discovered during the complete
reference-API migration and belong to this atomic cutover.

## 3. Prerequisites

None.

## 4. Interface contract

```cpp
explicit SongView(SongDocument &document, QObject *parent = nullptr);
SongDocument &SongView::document() const noexcept;
SongDocument &AutomationPage::document() const noexcept;
explicit TempoLane(SongDocument &document) noexcept;
```

`SongView` and `EventListController` bind one `SongDocument&` for life. Delete
both `setDocument` APIs and `SongView::disconnectDocument`. `TempoLane` has one
reference member and one constructor: remove its page pointer and dual lookup.
Delete `VelocityArea::hasDocument` and its callers' document-presence tests.
`parametersEnabled()` still returns `m_page.ready()`; readiness and nullable
timeline checks retain their existing meaning.

`SongView` gains private `observeDocument()`, `suspendDocumentObservation()`,
`onDocumentChanged()` and two owned `QMetaObject::Connection` handles. Its
suspension operation also suspends the event controller using its own lifecycle contract.
The existing `setDocument` document-change lambda becomes `onDocumentChanged`.

EventListController gains `suspendDocumentObservation()` and
`resumeDocumentObservation()`, each owning its existing document signal paths.
Suspension disconnects and clears its two connection handles before outward
notifications, ends local editing, clears chunk/row selection and labels, and
sets the event model source to `(nullptr, -1)`. The bound document reference
never changes. `refresh()` and `syncTrackSelection()` must not reattach the
source while suspended; explicitly reset disconnected handles to empty and use
that observation connection state, not an extra document-valid flag. Resume
connects once, rebuilds labels and revision, chooses the first available chunk,
resets event-row selection, binds the model source and synchronizes count/play
row/visible track. Already-observing resume is a no-op: it must not clear selection
or duplicate connections. Preserve the existing detach/attach presentation; no
temporary pointer setter survives.

Construction binds the document before any dependent child is created. Establish
SongView observation only after all children are initialized; resume the event
controller after SongView's connections, at the end of construction. The event
controller constructor binds the reference but does not publish its source or
connect document signals while SongView is partially constructed.

`prepareForSongReplacement()` keeps existing cancellations, invalidates context
menus without restoring focus, clears note selection (the old setter's swap
reset), and suspends both observers. Do not reset the grid clock or discard the
old timeline. The event table is detached/empty as above, not frozen over raw
indices into an about-to-change document.

`setSong()` installs the supplied timeline, time-axis binding and view model
before resuming observation. Preserve its existing song/grid/selection resets.
Resume SongView first and the event controller last, after the existing song
rebuild has established the replacement projection and selection. Repeated
attachment cannot duplicate signal delivery. A null timeline remains legal.
The removed setter's selection/header/drawer refresh work is accounted for by
replacement preparation and `setSong`; no pre-timeline document publication is
introduced to imitate its old order.

Failure preserves the existing return/error path. `adoptSmf` currently cannot
return false; do not invent rollback. If that changes later, its failure must
leave prior content intact. The view retains its prior timeline, both observers
remain suspended, and the event table remains empty until a successful load.
Readiness remains the input gate. No fabricated failing-adoption test seam.

## 5. Implementation steps

1. Bind the SongView reference, implement the constructor and replacement order
   above, and delete the old binding API. Keep teardown ordering and
   `EditActions::rebind(nullptr)` intact. Do not change document mutation APIs.
2. Change SongTab construction and remove its setter call. Adapt the controller
   reference/member accesses, remove its old setter and obsolete document-null
   branches, and preserve the observation-state guards and model detachment.
3. Apply the same mechanical document-access migration across the closed list.
   Remove only document-presence terms; retain timeline, track, host, session,
   slot and revision conditions. References are the default for local access;
   take an address when an unchanged Qt/popup interface needs a pointer (for
   example `PitchBendEditor` and `QObject::connect`). Non-drawer pending document
   lifetime fields are not part of this plan's popup simplification and remain.
   Drawer pending identity/revision checks remain until task 4; compare addresses
   where needed. Collapse TempoLane and remove `hasDocument` in this same batch.
4. Migrate every check-side constructor and remove setter calls. Documents must
   outlive views: add owned documents to bare geometry/activity rigs and local
   host-seam cases; existing document-backed rigs pass their current document.
   TempoLane's existing document-reference check constructors need no edits.
   Replace the voice-picker and host `document-null` scenarios with
   `prepareForSongReplacement()` and resume via `setSong` after assertions;
   rename the host route to `song-replacement`. Keep picker cancellation,
   unchanged-document and gesture-cancellation assertions. Remove the
   mainwindow-routing pointer-identity assertion rather than re-pin it to the
   reference spelling; retain its readiness, timeline and view-state checks.
5. Verify the complete cutover before task 2. Do not stop with SongView migrated
   but drawer/check callers still expecting its pointer API.

## 6. Acceptance predicate

All constructors and callers compile together; no SongView/controller binding
setter remains. Document-null guards on the permanently bound view/drawer
access paths are gone; legitimate nullable model source, popup lifetime,
timeline and input-host guards remain. Empty-document construction and
`setSong(nullptr, nullptr)` are legal. Song replacement cancels interactions,
keeps event-table rows detached during adoption, and publishes replacement rows
only after the replacement timeline/projection is installed.

Use a throwaway replacement scenario with the event list visible: prepare,
adopt changed SMF in place, verify the controller table remains empty despite
explicit refresh, attach its newly built timeline, verify final rows, and edit
again to prove observation resumed. Existing host checks cover session routing,
not proof of this intermediate notification ordering.

Named checks (execution ownership is in plan.md; native desktop is required for
WindowSystem suites, including rollcheck, host and selectionkey scenarios):

```sh
deno task verify --filter eventviews --verbose        # event-table edits/remap/chrome/playhead
deno task verify --filter rollcheck --verbose         # constructor-backed roll edits and geometry
deno task verify --filter trackheader-model --verbose # header mutation and document loading
deno task verify --filter trackactivitymetercheck --verbose # bare-document activity rigs
deno task verify --filter trackheaderquickcheck --verbose   # header menu/click consumers
deno task verify --filter host --verbose              # bare views, replacement cancellation, teardown
deno task verify --filter mainwindow-routing-lifecycle --verbose # tab lifecycle consumer
deno task verify --filter automation --verbose        # drawer edits/presentation and TempoLane
deno task verify --filter editor-drawer --verbose     # voice picker replacement cancellation
deno task verify --filter velocity --verbose          # velocity guards and editing
deno task verify --filter laneselectioncheck --verbose # lane selection with a real document
deno task verify --filter pitch-bend-editing --verbose # pointer-taking popup bridge
deno task verify --filter selectionkey --verbose      # all four keyboard routing suites
```

## 7. Task-specific constraints

- The document API, observation lifecycle and every caller migrate atomically.
  Do not independently dispatch file subsets that leave incompatible callers.
- No compatibility getter/setter or artificial document-valid flag. Observation
  connection state and the event model's absent source are legitimate lifecycle
  state and must not be removed as if they were nullable domain ownership.
- Preserve refresh branch outcomes; only reference syntax/guard changes in
  `refreshLiveState` here. Task 3 owns classification.
- Run LSP references before migration. The planner observed a partial clangd
  index; corroborate with scoped constructor/accessor searches rather than
  treating a short reference list as exhaustive. Newly discovered callers mean
  an explicit write-set correction, not an ignored compile failure.
