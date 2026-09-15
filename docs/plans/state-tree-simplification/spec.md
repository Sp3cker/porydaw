# State-tree simplification — spec

Scope: SongView document lifetime, the automation presentation model and drawer
refresh classification. Goal: one definition of presentation facts, one
definition of automation command-target validity, and no duplicated freshness
reasoning in those consumers. File-count targets and eliminating every canvas
`document()` call are not goals. Existing user-visible behavior is preserved.

## Independent concerns

| Term | Meaning | Owner |
|---|---|---|
| Document lifetime | Exactly one `SongDocument&` outlives each SongView. No unbound view. | SongTab and check rigs |
| Replacement | Synchronous prepare/adopt/setSong interval; view and event-list observation are suspended until the replacement timeline/projection is installed. | SongView coordinates; EventListController owns its observation/source |
| Readiness | Existing input permission, not document existence. Existing row inclusion and parameter availability still use readiness. | SongTab/InputGate and existing page policy |
| View model | Immutable published automation parameter facts and visible row projection, built from document, timeline, selection and page readiness. | AutomationViewModel/AutomationCanvas |
| Live-state delta | Pure comparison of the seven DrawerPageLiveState fields. | DrawerLiveDelta/diffLiveState |
| Refresh action | Page-specific side effects selected from delta plus local context. Not target validity. | Each drawer page |
| Target epoch | Document revision plus row generation; equal values prove an automation target has not been invalidated. | AutomationCanvas |
| Command target | Intended lane/row/point or tick/value; retained separately from validity. | Pending commands |

## Document lifetime

- `explicit SongView(SongDocument &document, QObject *parent = nullptr)`.
- `SongDocument &SongView::document() const noexcept` and
  `SongDocument &AutomationPage::document() const noexcept`.
- EventListController binds the view's document once. Both binding setters and
  `SongView::disconnectDocument` disappear in the same atomic caller cutover.
- TempoLane has one `SongDocument&` constructor/member, not a page-or-document
  lookup. Its existing document-reference check callers remain unchanged.
- Remove document-presence guards on these bound paths. Keep nullable timeline,
  input-host, slot and popup lifetime guards. `setSong(nullptr, nullptr)` remains
  legal. EventTableModel's nullable source is also retained: a detached table
  source is different from an absent domain document.
- Task 4 removes drawer popup document identity fields/checks. Non-drawer popup
  lifetime fields and independent document-pointer interfaces are not an
  additional migration target; bridge them with addresses where required.

## Replacement bracket

- Task 1 implements event-controller suspension/resumption and migrates the
  entire view/drawer/check API together. Both existing binding setters are
  removed in this one buildable cutover.
- Suspension disconnects and clears each owner's document connection handles.
  The event controller also ends editing, clears row/chunk selection and labels,
  and detaches `EventTableModel` with `setSource(nullptr, -1)`. Its refresh and
  selected-track callbacks cannot reattach the source during suspension.
- `prepareForSongReplacement()` preserves interaction cancellation, invalidates
  context menus without returning focus, clears note selection and suspends both
  observers. The old timeline and grid timing are retained during the bracket;
  the event table is empty, not a stale borrowed snapshot.
- `setSong()` installs the new timeline, axis and view model, performs existing
  song resets/rebuilds, then resumes observation: SongView first, event controller
  last. No event-table publication against the new document and old projection.
- Constructor observation starts only after dependent children exist. The event
  controller binds its reference during construction but waits until the end of
  SongView construction to connect/publish. Resume is idempotent and ordinary
  repeated resume does not reset event-row selection.
- `onDocumentChanged()` retains the old setter lambda's menu invalidation,
  interaction cancellation, three drawer notifications and drawer refresh.
- Preserve `applyMidiStage`'s early return and presentation error on adoption
  failure; both observers remain suspended and the event table empty until a
  successful load. `adoptSmf` cannot currently fail. No rollback code or fake
  failure seam is added; any future failing implementation must preserve prior
  content. Readiness remains responsible for blocking input in that state.

## View model

- Canonical builder:
  `buildAutomationViewModel(const SongDocument &, const MidiTimeline *, const songview::EditorSelectionModel &, bool pageReady)`.
  EditorViewState changes still drive existing refreshes, but are not a separate
  builder parameter. Existing ready/timeline/primary-track visible-row inclusion
  stays; selector event counts remain document-derived even without a timeline.
- Rows carry identity, written event count, lane/node selection coverage and the
  populated-selection indicator. One storage vector holds parameter facts;
  `visibleRows()` exposes its Tempo-first prefix for node slots without copying.
  Shared fields are the visible-prefix count and active tick range. No redundant
  revision, mask, selection-active or title storage.
- `selectionHasEvents` indicates covered written events in the active range. It
  drives selector appearance; selecting an empty lane remains permitted.
- Point vectors are not copied into the model. NodeLane remains the existing
  authoritative point-reading interface. Publication stays synchronous with
  document/selection updates; no deferred model refresh is introduced.
- Remove LaneSelection and CCLanes' row-owning instance API at cutover; retain
  CCLanes' static helpers and lane adapters. Remaining selection queries move
  with their existing semantics, including required selection-model arguments.
- Delete the unused `NodeLaneSlot::text` pointer and CCLanes title caches; retain
  actual title readers through NodeLane/static labels. No pointer or span into
  model storage survives replacement. Selection-only publication must not
  rebuild adapters or cancel an active gesture merely to repair storage lifetime.
- Rebuild at `rebuildRows()` and selection-only refresh. Preserve the actual
  automation refresh policy: a playhead-only update while not panning can still
  reach `rebuildRows()`. There is no promise of a playback optimization or a
  cache in this refactor. Scroll-only refresh retains the camera-tail path.

## Live-state delta and refresh action

- `DrawerLiveDelta` compares revision, time zoom, horizontal scroll, edit cursor,
  track color, playhead and playing. `any`, `onlyScroll`, `onlyPlayhead` are pure.
- Each page uses its own pure classifier and ordered side-effect mapping. No
  shared action enum or max/lattice ordering. Task 3 records complete mappings.
- Velocity classification includes interaction and axis-context facts, not only
  the delta; preserve the current lazy context evaluation and cancellation
  behavior. Voice preserves its special pan path that does not assign `m_live`.
- Selection-only automation refresh preserves task 2's model publication before
  selection presentation notifications.

## Target epoch

- `AutomationTargetEpoch { uint64_t documentRevision; uint64_t rowGeneration; }`;
  `targetEpoch()` reads document revision and the canvas-owned generation.
- Advance row generation at the start of `rebuildRows`, before cancellation can
  reenter. A layout-only adapter rebuild over unchanged row identities does not
  advance it; commands resolve adapter pointers after reentrant operations.
- Pending automation popups and tap-tempo state store the epoch instead of
  document identity/revision fields. Retain command targets and prompt copy.
- After consuming pending state, establish the QObject lifetime guard before
  any outward signal, popup operation or focus return. After each pre-mutation
  reentrant operation, check lifetime before accessing members; validate epoch
  after the final such operation, then resolve the target and mutate without
  another reentrant operation in between. Read-only target/value preparation is
  permitted between validation and mutation; 'last statement' is not a literal
  source-text requirement.
- Preserve each handler's current focus timing. In particular value-prompt
  acceptance emits `valuePromptChanged` before mutation but normally returns
  focus afterward: do not move focus before mutation to fit a uniform template.
- Remove redundant row-identity/point-presence revalidation only where equal
  epoch proves it. Keep normal hit/miss checks at initial target capture and
  existing expected-document-revision protection in commit helpers.
- Voice pending commands keep revision and track validity; only document identity
  fields/comparisons disappear. Canvas/voice QObject lifetime guards remain.
- Verification must exercise invalidation after a handler consumes its pending
  command, not merely cancellation before dispatch. Task 4 records that case.
