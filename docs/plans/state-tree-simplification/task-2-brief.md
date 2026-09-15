# Task 2 — `AutomationViewModel`: one definition of presentation state

## 1. Context

Presentation facts are re-derived per query from three sources: the `CCLanes`
row table (`src/ui/editordrawer/cclanes.cpp:90-107`), `LaneSelection` coverage
over `EditorSelectionModel` (`src/ui/editordrawer/laneselection.{h,cpp}`), and
`AutomationCanvas::selectedParameters` / `parameterEventCount` /
`parameterHasEvents` / `parameterPips`
(`src/ui/editordrawer/automationcanvas_tabs.cpp:84-132,274-283`), which walk
`document->lanePoints()` on every QML property read and every `laneCountText`
call (`src/ui/songview/quick/automationquick.cpp:329-336`). The "label shows
selected without events" bug class lives in that spread. This task builds the
facts once, as a value, at the moments they can change (spec: *View model*).

Title storage is dead and must not be migrated. `NodeLaneSlot::text`
(`CCLanes::RowTextCache *`, `src/ui/editordrawer/automationcanvas.h:262`) is
written (`src/ui/editordrawer/automationcanvas.cpp:327,337`) and never read;
every title consumer reads `NodeLane::title()` or the `CCLanes::laneLabel`
static. The previously planned `&row.title` borrow would dangle across model
replacement, so the smallest safe design deletes the borrow together with its
dead storage (`RowTextCache`, both `rowText()` overloads, `m_rowText`). The
view model is a plain value: after this task no pointer into presentation
state survives a rebuild.

Task 1 supplies the reference-returning page document interface. Task 4 owns
row-generation invalidation inside `rebuildRows`; this task preserves that
structural entry and keeps selection-only replacement free of cancellations.

## 2. Exact write set

- `src/ui/editordrawer/automationviewmodel.h`
- `src/ui/editordrawer/automationviewmodel.cpp`
- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_tabs.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- `src/ui/editordrawer/automationcanvas_gesture.cpp`
- `src/ui/editordrawer/automationcanvas_menu.cpp`
- `src/ui/songview/quick/automationquick.cpp`
- `src/ui/editordrawer/automationpage.h`
- `src/ui/editordrawer/automationpage.cpp`
- `src/ui/editordrawer/cclanes.h`
- `src/ui/editordrawer/cclanes.cpp`
- `src/ui/editordrawer/laneselection.h`
- `src/ui/editordrawer/laneselection.cpp`
- `src/ui/editorviewstate.h`
- `CMakeLists.txt`
- `src/checks/automation/automationfixture.cpp`
- `src/checks/automation/automationactions.cpp`
- `src/checks/automation/automationpainting.cpp`
- `src/checks/automation/automationpreviews.cpp`
- `src/checks/automation/automationrouting.cpp`
- `src/checks/automation/presentation/tst_automationpresentation.cpp`
- `src/checks/automation/raster/rasterfixture.cpp`
- `src/checks/automation/hover/hoverfixture.cpp`
- `src/checks/drawerpresentation/valueprompt.cpp`
- `src/checks/host/hosttestsupport.h`
- `src/checks/host/tst_hostadapter.cpp`
- `src/checks/host/tst_hostintegration.cpp`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp`
- `src/checks/selectionkey/automationprobe.cpp`
- `src/checks/selectionkey/gesturecommands.cpp`
- `src/checks/selectionkey/localinputtier_text.cpp`
- `src/checks/selectionkey/windowtier_keyboard.cpp`
- `src/checks/selectionkey/windowtier_lifetime.cpp`
- `src/checks/clipboard/laneselection_test.cpp`
- `src/checks/automation/domain/tst_automationdomain.cpp`

The automationviewmodel pair is new; the laneselection pair is removed.
Root CMakeLists.txt owns the app source list; src/checks/CMakeLists.txt stays
unchanged because checks link the app target. Check migrations are specified
in step 5, not a separate compatibility layer.

## 3. Prerequisites

Task 1 — `AutomationPage` holds `SongDocument &` (`document()` returns a
reference, null-document guards gone). This task needs nothing else: rows and
coverage derive from the document, the nullable timeline, and the selection
model only — never from `EditorViewState` (today's row gate is
`ready && timeline && primaryTrack >= 0`, `cclanes.cpp:99-103`, and
`ready` ≡ `timeline() != nullptr`, `automationpage.cpp:82-85`).

## 4. Interface contract

```cpp
// src/ui/editordrawer/automationviewmodel.h
struct AutomationViewModel {
    struct Row {
        EditorAutomationRowId id;
        std::size_t eventCount;   // document points; adapter tick-0 default excluded
        bool coversLane;          // LaneSelection::coversLane semantics, baked at build
        bool coversNodes;         // LaneSelection::coversNodes semantics, baked at build
        bool selectionHasEvents;  // coversNodes && any point tick in activeTickRange
    };
    std::optional<std::pair<Tick, Tick>> activeTickRange; // LaneSelection::activeTickRange value
    std::vector<Row> rows;  // parameter facts: Tempo first, then primary-track CCs
    std::size_t visibleRowCount = 1; // visible prefix; Tempo always has a slot
    std::span<const Row> visibleRows() const noexcept;

    const Row *find(EditorAutomationRowId id) const noexcept;
    // Moved from LaneSelection, identical behaviour; coverage guards read
    // find(id)->coversLane / ->coversNodes (absent row = false):
    bool hitTest(EditorAutomationRowId id, qreal x, const AutomationProjection &,
                 qreal dpr, const songview::EditorSelectionModel &selection) const noexcept;
    std::vector<std::pair<int, uint8_t>> visibleLanes(
        const songview::EditorSelectionModel &selection) const noexcept;
    std::pair<bool, std::vector<std::pair<int, uint8_t>>> laneSet(
        EditorAutomationRowId first, EditorAutomationRowId last) const noexcept;
};

AutomationViewModel buildAutomationViewModel(const SongDocument &document,
                                             const MidiTimeline *timeline,
                                             const songview::EditorSelectionModel &selection,
                                             bool pageReady);
```

Builder rules (each named for the code it preserves):

- `activeTickRange`: `LaneSelection::activeTickRange` body verbatim
  (`laneselection.cpp:26-33`) — nullopt unless `selection.timeSelection().active()`,
  else `{min(startTick, endTick), max(startTick, endTick)}`.
- Track mask: `songview::detail::usedTrackMask(timeline)`
  (`src/ui/songview/detail.h:58`, body `detail.cpp:44-54` — byte-identical to
  the deleted `AutomationPage::usedTrackMask`). No mask parameter, no mask field.
- Tempo row: always present at `rows[0]`, id `{Tempo, 0, 0}` — it mirrors the
  node stack, which pushes the Tempo slot unconditionally
  (`automationcanvas.cpp:327`). `eventCount` = `document.tempoPoints().size()`;
  coverage = `selection.timeSelectionCoversTempo(mask)`;
  `selectionHasEvents` = coversNodes && any tempo point tick in
  `[activeTickRange->first, activeTickRange->second)` (half-open — the
  `selectedParameters` predicate, `automationcanvas_tabs.cpp:93-99`).
- CC rows: appended for each controller in `CCLanes::supportedControllers()`
  for a primary track in `[0, 255]`, matching `parameterRow`, regardless of
  timeline/readiness, so selector event counts retain document-only semantics. Id
  `{ControlChange, uint8_t(primaryTrack), controller}`;
  `eventCount` = `document.lanePoints(track, controller).size()`;
  `coversNodes` is false when inactive or when the CC row is not visible,
  preserving `LaneSelection::covers`'s old row-membership guard; otherwise use
  `selection.timeSelectionCoversLane(track, controller, mask)`. `coversLane`
  additionally requires Lanes scope. `selectionHasEvents` uses coversNodes
  and the half-open range above. No valid primary track means no CC facts.
- Visible rows: `visibleRowCount` is `rows.size()` exactly when
  `pageReady && timeline && selection.primaryTrack() >= 0`, otherwise 1.
  `visibleRows()` returns that prefix without allocation. Thus timeline-null
  state retains document event counts but exposes only the Tempo node slot.
  Invariant: `visibleRows()[i].id == m_nodeStack[i].id`.
- `find`: linear scan over `rows` by id; nullptr when absent.
- `hitTest`: `LaneSelection::hitTest` body (`laneselection.cpp:70-81`) with the
  guard `const Row *row = find(id); if (!row || !row->coversLane) return false;`
  and the raw `selection.timeSelection()` start/end ticks read live exactly as
  today.
- `visibleLanes`: `LaneSelection::visibleLanes` body
  (`laneselection.cpp:83-96`) iterating visible CC rows only — start at index 1; the
  Tempo row's `(track, controller)` pair is `(0, 0)` and today's CC-only table
  never emitted it.
- `laneSet`: `LaneSelection::laneSet` body (`laneselection.cpp:98-123`);
  `findRowById` over `visibleRows()` never matches a CC id against the Tempo row, but a
  Tempo-spanning walk must start at the first CC row (index 1), never index 0.
  `{true, {}}` for Tempo/Tempo unchanged.

Canvas members (`src/ui/editordrawer/automationcanvas.h`):

```cpp
const AutomationViewModel &viewModel() const noexcept { return m_viewModel; }
// Check-side identity→handle accessor; element type changes from AutomationRow:
std::span<const AutomationViewModel::Row> rows() const noexcept { return m_viewModel.visibleRows(); }
private:
AutomationViewModel m_viewModel;  // replaces CCLanes m_rowData + LaneSelection m_laneSelection
void rebuildViewModel();          // rebuild from page document, timeline, owner selection and readiness
```

`NodeLaneSlot` loses the `text` member (`automationcanvas.h:262`); `id`, `lane`,
`body`, `isTempo()`, `visit` stay. `AutomationCanvas::rebuildRows()`
(`automationcanvas.cpp:286-307`) keeps `cancelInteraction`, the two menu
cancellers, hover invalidation, `contentGeometryChanged()`, and both emits
(`parameterPresentationChanged` + `parameterSelectionChanged`, lines 305-306);
its row-table refresh becomes `rebuildViewModel();` ahead of
`contentGeometryChanged()`. `requestSelectionQuickUpdate()`
(`automationcanvas.cpp:211-220`) is unchanged — it already emits
`parameterSelectionChanged` (line 219), so the Selection branch adds no second
emit.

Selector index space is untouched: `parameterCount`/`parameterRow`/
`parameterLabels`/`activeParameter` keep CC indexes 0-7 and Tempo last
(`automationcanvas_tabs.cpp:18-31,40-54`). The model's row order (Tempo first)
uses a visible prefix for the node stack, not selector indexing; facts map through
`parameterRow(index)` → `find(id)`, never by index alignment.
Returned pointers and spans are ephemeral query borrows. Do not retain them
across model publication or a reentrant operation; the node stack owns only
adapter references, never model references.

## 5. Implementation steps

1. Write `src/ui/editordrawer/automationviewmodel.{h,cpp}` per the Interface
   contract. Edge cases: `lanePoints`/`tempoPoints` are read from the document
   once per parameter row: get `eventCount` from the resulting container's size
   and scan only when covered and the active range is present. A null timeline
   makes the mask zero, but does not imply all coverage is false: explicit
   Tempo lane scope can still cover Tempo. Hidden CC rows remain uncovered
   because of the preserved row-membership guard, not an assumed mask effect.
   Storage is bounded by `1 + CCLanes::supportedControllers().size()`.
2. Rewire the canvas. Constructor builds `m_viewModel` as its first statement
   (replacing the `m_rowData`/`m_laneSelection` member initializers,
   `automationcanvas.cpp:30-35`). `rebuildNodeStack()`
   (`automationcanvas.cpp:314-338`): Tempo slot from `rows[0].id` +
   `&m_tempoLane`; CC adapters and slots from `visibleRows()` after Tempo; drop the
   `rowText` wiring and the `text` member; the invariant
   `visibleRows()[i].id == m_nodeStack[i].id` holds for every slot.
   Coverage/selection consumers:
   - `automationcanvas.cpp:170` (`hasMultipleSelectedNodes`),
     `_gesture.cpp:353,381-384`, `_input.cpp:64-66`, `_tabs.cpp:91`,
     `automationquick.cpp:261-262`: `m_laneSelection.coversNodes/coversLane(id)`
     → `const Row *row = m_viewModel.find(id)` then `row && row->coversNodes`
     (or `->coversLane`); the multiplicity memo at
     `automationcanvas.cpp:154-186` keeps reading
     `m_page.liveState().documentRevision` — the model carries no revision field.
   - `_gesture.cpp:346,381`, `_input.cpp:58`, `_tabs.cpp:86`,
     `automationquick.cpp:207`: `m_laneSelection.activeTickRange()` → the
     `m_viewModel.activeTickRange` field; `_input.cpp:186`'s `active()` →
     `m_viewModel.activeTickRange.has_value()` (identical: the field is empty
     iff the selection is inactive).
   - `_menu.cpp:134`: `m_viewModel.visibleLanes(m_page.m_owner.selectionModel())`.
   - `automationcanvas.cpp:637`: `m_viewModel.laneSet(startSlot->id, endSlot->id)`.
3. `_tabs.cpp` fact readers: `selectedParameters()`
   (`automationcanvas_tabs.cpp:84-104`) gates on `m_viewModel.activeTickRange`
   and selects indexes whose `parameterRow(index)` maps to a row with
   `selectionHasEvents`; `parameterEventCount(row)` (117-127) returns
   `find(row)->eventCount`, 0 when absent; `parameterHasEvents`,
   `parameterPips`, `ghostParameters`, `canGhostParameter`,
   `toggleGhostParameter` keep their shapes over those two. `laneCountText`
   (`automationquick.cpp:329-336`) is unchanged — it already goes through
   `parameterEventCount`, which now reads the model.
4. `src/ui/editordrawer/automationpage.cpp` Selection branch
   (`refreshLiveState`, lines 147-148): insert `m_canvas->rebuildViewModel();`
   before `m_canvas->requestSelectionQuickUpdate();`. Every selection change
   funnels here synchronously: `EditorSelectionModel::commit` →
   `coordinateSelectionChange` (`src/ui/songview.cpp:331-333,952-1016`,
   timeSelectionChanged → `refreshAutomationPage()` at 1013) →
   `refreshLiveState` (`src/ui/songview/drawercoordination.cpp:181-186`), so
   this one rebuild point covers canvas-local clears (`_input.cpp:76-77,324-328`)
   and band publishes (`automationpage.cpp:247-258` → `setTimeSelection`) alike.
   `rebuildViewModel()` is a pure value swap: no menu/hover invalidation, no
   emits, no interaction cancellation — the selection path never did those.
   Delete `AutomationPage::usedTrackMask` (declaration
   `src/ui/editordrawer/automationpage.h:75`, body
   `automationpage.cpp:97-107`); its last two callers
   (`automationcanvas.cpp:33,300`) are replaced in step 2. The remaining
   refresh branches (`scrollOnly` early return, `preservePan` full update,
   final `rebuildRows()`) keep their outcomes exactly — including
   playhead-only refreshes reaching `rebuildRows()` when not panning.
5. Close the cutover. Delete `src/ui/editordrawer/laneselection.{h,cpp}`;
   delete the `CCLanes` instance API — ctor, dtor, `rows()`, both `rowText()`
   overloads, `rebuildRows()`, `titleFor()`, `RowTextCache`, `m_page`,
   `m_rows`, `m_rowText` (`cclanes.h:52-69`) and the anonymous-namespace
   `laneRow` helper (`cclanes.cpp:19-22`, only `rebuildRows` used it) — keeping
   all statics and `CCLaneAdapter` whole; delete `NodeLaneSlot::text`; delete
   `struct AutomationRow` (`src/ui/editorviewstate.h:33-35`); swap the root
   `CMakeLists.txt` source entries. Retarget the check files listed in the
   write set with one rule: the model row index now equals the node stack slot
   (Tempo at 0), so identity→handle mapping drops the +1
   (`LaneHandle{index + 1}` → `LaneHandle{index}`, `automationfixture.cpp`'s
   `row = lane.index - 1` → `row = lane.index`, bounds checks via
   `LaneHandle::valid()`); `gesturecommands.cpp:125` names `AutomationRow` —
   use `const auto &`; `hosttestsupport.h:32-40` takes
   `std::span<const AutomationViewModel::Row>` and still compares `.id`s only. Retarget
   `src/checks/clipboard/laneselection_test.cpp` onto `buildAutomationViewModel`
   over a document-backed rig (reuse the existing automation-suite fixture
   pattern in the same executable; the hand-built `usedTracks` arguments become
   rig used-track facts), keeping identical assertions for lane/track scope
   separation, hidden-lane exclusion, Tempo-vs-lane coverage, `laneSet`
   endpoint payloads, hit tests, and `activeTickRange`. Rename the file's
   `LaneSelectionTest` class to `AutomationCoverageTest`; the catalog row
   name `laneselectioncheck` and the qExec argument string stay unchanged. In
   `src/checks/automation/domain/tst_automationdomain.cpp:278-303` the
   `LaneSelection` coverage block retires into that retargeted check (the
   domain rig has no timeline to drive the builder); `rangesAndSelection`
   keeps its adapter/value/point assertions.

## 6. Acceptance predicate

- `grep pattern="LaneSelection|RowTextCache|m_rowData|m_laneSelection" path="src"` → zero hits.
- `grep pattern="\bAutomationRow\b" path="src"` → zero hits (struct deleted, all
  retargets landed).
- `grep pattern="AutomationPage::usedTrackMask|setUsedTrackMask" path="src"` → zero hits.

Named checks (controller runs under plan.md; desktop required for native
interaction suites):

```sh
deno task verify --filter automation-presentation --verbose  # selector labels/pips, selectedParameters scope indicators incl. selectedInactiveParametersKeepScopeIndicators (painting.cpp:440-477), left-edge lane event counts
deno task verify --filter laneselectioncheck --verbose       # retargeted: coverage scoping, hidden-lane exclusion, laneSet endpoints, hit tests, activeTickRange
deno task verify --filter automation-editing --verbose       # multi-lane selection drags read coversNodes; rows()-helper retarget across the automation suite
deno task verify --filter automation-hover --verbose         # hover ring/ghost read selection ranges via the model
```

Additional named checks for migrated identity-to-handle helpers:

```sh
deno task verify --filter automation-raster --verbose
deno task verify --filter selectionkey --verbose
deno task verify --filter rendering-playhead --verbose
deno task verify --filter host-adapter --verbose
deno task verify --filter host-integration --verbose
deno task verify --filter editor-drawer --verbose
deno task verify --filter automation-domain --verbose
```

Coverage gap: exercise a populated document with a null timeline and valid
primary track in a throwaway scenario. Verify CC event counts/pips remain the
document counts while only the Tempo row is exposed through `rows()`. Then
attach the timeline and verify visible identities align with node handles.
This is preservation of the existing document-only count contract, not an
authorized change in torn-down selector behavior. The deleted title borrow
requires no replacement lifetime mechanism or adapter rebuild on selection.

## 7. Task-specific constraints

- No point vectors on the model (spec). Paint and hit-test keep reading
  `NodeLane::points()`; consistency holds because rebuilds are synchronous in
  the same delivery that changes those points.
- The model rebuilds wherever `AutomationCanvas::rebuildRows()` runs today —
  `refreshLiveState`'s final branch (playhead-only when not panning included,
  `automationpage.cpp:151-152`) and `rebuildModel()`
  (`automationpage.cpp:234-238`) — plus the Selection branch of step 4. Make
  no "never rebuilds" promise anywhere.
- Do not change `EditorAutomationRowId`/`EditorAutomationRowKind`,
  `EditorViewState` or its remap, `parameterRow`/`parameterCount`/
  `parameterLabels`/`activeParameter`, `CCLanes` statics, or
  `requestSelectionQuickUpdate()`.
- `rebuildRows()` remains the single structural rebuild entry; the epoch task
  adds its `m_rowGeneration` bump inside it. Do not preempt that work.
