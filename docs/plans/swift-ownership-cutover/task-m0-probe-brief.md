# Task m0-probe — QtBridge observable-behavior proof harness

Where this fits: first executable task of the ownership pivot
([plan.md](plan.md)); establishes the runtime evidence the
[QtBridge integration contract](../../qtbridge-integration-contract.md)
requires before any M1 presenter work. Controller records ledger outcomes from
your observations; you do not edit the contract.

## Target

New check harness `swiftqtml` under `src/checks/swiftqtml/`:

- `tst_swiftqtml.{h,cpp}` — QtTest executable rows (registered like
  `swiftrollgated`: `src/checks/CMakeLists.txt` executable sources,
  `src/checks/checkcatalog.cpp` catalog entry with handler
  `qtWithThreeArguments`-style args as used by swiftrollgated
  (checkcatalog.cpp:764-771), `src/checks/fwd.hpp` declaration).
- `BridgeProbeCheck.swift` — harness-local Swift presenter + rows, compiled
  into a `swift_qt_ml_check` STATIC target linking `swiftgrid`, following the
  `swift_band_keys_check` pattern (src/checks/CMakeLists.txt:389-423 — copy
  the modulemap/include wiring shape, not literal lines).
- `BridgeProbe.qml` — the real QML surface (qrc-compiled; follow how
  `swiftgrid` registers `qrc:/swiftgrid/SwiftRollOverlay.qml`).
- CMake `qt_add_qml_module` or equivalent as the existing checks do — inspect
  `src/checks/CMakeLists.txt` for the established pattern and reuse it.

The rig: a standalone `QQuickView` (or `QQmlApplicationEngine` + window) in
the test binary loading `BridgeProbe.qml`, which instantiates the Swift
presenter as a QML element by calling its `registerQmlElement()` from a small
`@_cdecl` bootstrap invoked by the C++ test before loading QML (pattern:
`SwiftGridHost.swift` + `sg_register_grid_types`). This exercises the patched
`registerQmlElement` visibility (patch hunk 3) through the real integration —
no production app window is needed and none may be opened.

## Presenter under probe (Swift)

`BridgeProbe` (`@QtBridgeable`, `QmlInstantiable`-derived as `PianoGrid` does
— read `PianoGrid.swift:69-143` for the exact conformance/property idiom):

- `@QtTracked` scalar property (e.g. `statusText: String`) bound in QML.
- `rows: QListModel<BridgeRow>` where `BridgeRow` is a **class**
  (`@QtBridgeable`) with `@QtTracked` `title: String`, `value: Int`, and an
  immutable `domainKey: Int` (stable domain identity, not the list index).
- Methods used by rows/scenarios:
  - `makeRow(title:value:key:) -> BridgeRow` — exercises the patched
    object-return capability (patch hunk 1).
  - `selectedRow() -> Optional<BridgeRow>` — exercises the patched
    `Optional<Wrapped>` QVariant conversion (patch hunk 4); QML reads a
    property off the returned object (nil case must render as null in QML
    without error).
  - `mutateRowInPlace(row: BridgeRow, title: String)` — mutates the row
    object's property directly (no model subscript write).
  - `replaceRow(index: Int, row: BridgeRow)`, `insertRow(at:row:)`,
    `removeRow(at:)`, `moveRow(from:to:)`, `resetRows([BridgeRow])` — thin
    wrappers over `QListModel` subscript/`replaceSubrange`/`reset(to:)`.
- A per-presenter `actionLog` (`QListModel<ActionRec>` or a simple appended
  string log exposed as a tracked property) recording every action addressed
  through a row reference: `actViaRow(row: BridgeRow)` appends
  `row.domainKey` + current `row.title`.

## QML under probe

`BridgeProbe.qml`: the presenter element plus a `ListView` (or `Repeater`)
whose delegate binds `title`/`value` into a `Text` and registers itself in a
QML-side array with a monotonically increasing `serial` assigned in
`Component.onCompleted` (delegate-identity probe: if the delegate is destroyed
and recreated, its serial changes). Also: a `Text` bound to
`probe.statusText`; a button-free `QtObject` storing `var capturedRow` for
stale-reference scenarios (assigned from `delegate` model data or a returned
row object). Give every assertable item an `objectName`.

## Check rows (each asserts through QML object state — `findChild` +
`QObject::property` after `selectionkey::settle()` (double flush), the
pattern at `src/checks/selectionkey/primitives.h:38-45`; import that helper or
copy the settle function into the harness — prefer importing if the check
target already links selectionkey objects; otherwise a local copy is
acceptable and must be identical in behavior)

1. `testPresenterPropertyBinding` — mutate `statusText` via a Swift method;
   QML-bound Text shows the new value after settle.
2. `testInPlaceRowMutation` — three rows; call `mutateRowInPlace` on the
   middle row object. Observe and assert what QML actually shows. Two
   sub-cases must be distinguished and both asserted:
   (a) direct object mutation — record whether the delegate updates (if the
   bridge does not propagate contained-object mutation to the delegate,
   assert the observed non-propagation precisely: delegate still shows old
   title after settle);
   (b) `replaceRow(index, sameRowAfterMutation)` (subscript write →
   `dataChanged`) — delegate shows the new title AND delegate serial is
   unchanged (no delegate churn).
3. `testRowReplacement` — `replaceRow` with a NEW row object: delegate shows
   new values; then call `actViaRow(oldRow)` — actionLog records the OLD
   row's key (the reference stays alive in Swift), and the new row's
   properties are untouched by that call.
4. `testInsertRemovePreservesTargets` — insert at head, remove middle;
   QML-visible order/count updates after settle; `actViaRow` on a row
   reference captured before the mutations still addresses that row's
   domainKey in actionLog (identity follows the object, not the index).
   Also assert delegate serials for surviving rows: unchanged iff the
   bridge kept their items (record which happened).
5. `testReorderTargetsIntendedRow` — `moveRow(0, 2)`; QML order updated;
   `actViaRow` on the pre-move reference logs the intended row.
6. `testResetWithStaleQmlReference` — assign `capturedRow` in QML from an
   existing row; `resetRows` with fresh rows; settle; invoke (from QML, via a
   method call triggered from C++ through `QMetaObject::invokeMethod` on the
   QML object, or directly in Swift holding the old ref) `actViaRow(captured
   old row)`; assert actionLog names the OLD row (detached, harmless) and the
   new model's rows are unchanged; no QML errors.
7. `testPendingMutationThenTeardown` — mutate a row property, then
   immediately destroy the QML view (`deleteLater()` + process events, no
   settle in between); then settle; assert no crash and the presenter object
   is gone (`findChild` returns null). QtBridge queued emissions must not
   resurrect or crash (observe; record any QML warnings via
   `qInstallMessageHandler` capture if the existing checks have a pattern for
   it — inspect tst_swiftrollgated.cpp first; if none, assert no crash and no
   late property change on a fresh view instance).
8. `testObjectReturnCapability` — `makeRow` result read in QML (property
   access works); `selectedRow()` non-nil → QML reads `title`; nil → QML sees
   `null` without a type error (assert via a QML-side `isNull` boolean
   property the QML sets from `!probe.selectedRow()`).

Constraints on the probe: rows are mutated on the GUI thread only; the Swift
presenter is `@MainActor` if the production idiom requires it (match
`PianoGrid`). No production Swift file changes in this task. No new `sg*`
C ABI symbols in production code — the harness-local `@_cdecl` bootstrap for
QML element registration is harness-local, named `sqp_register_probe_types`,
and lives in `BridgeProbeCheck.swift`.

## Preserved behavior / non-goals

- Touches no production source, no existing check.
- Does not prove production header parity, document ownership, or authorize
  any retirement (contract §Acceptance).
- Failing expectations are RESULTS, not bugs to code around: if the bridge
  does not propagate contained-object mutation, the row asserts the observed
  behavior and the row title/summary says so. If a scenario crashes, report
  BLOCKED with the minimal reproduction — do not catch/ignore to force green.

## Acceptance

- `src/checks/swiftqtml/` complete; registered in the three registration
  points; builds green (controller-run).
- All 8 rows executable, each asserting QML-observed state; each row's
  outcome (including deliberate non-propagation assertions) stated in the
  task result under `implementation` with one line per row:
  `row -> observed outcome`.
- Controller records contract ledger rows from your reported observations.
