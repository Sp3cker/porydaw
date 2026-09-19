# Task 3 — Swift grid consumes the document (read-only mode)

## Context

Consume Task 2's per-binding value receiver and produce the read-only grid
Task 4 mounts. Read [plan.md Global Constraints](plan.md) and
[spec.md §3](spec.md). This is real document rendering, not demo coordinates
with imported notes overlaid on them.

## Exact write set

- `src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift`: empty read-only
  construction, input guards, receiver binding, snapshot mapping/track filter.
- `src/ui/songview/quick/swift-grid-prototype/App.swift`: explicit demo setup
  on the standalone grid after empty construction.
- `src/ui/songview/quick/swift-grid-prototype/AudioSession.swift`: empty
  constructor and explicit demo-only audio initialization; no eager fixture
  access/native session creation from production grid construction.
- `src/ui/songview/quick/swift-grid-prototype/GridGeometry.swift`: minimally
  parameterize `GridMetrics` timebase/signature inputs; preserve demo defaults
  and existing math APIs.
- `src/ui/songview/quick/swift-grid-prototype/GridScene.swift`: consume those
  metrics/signatures in grid/ruler generation instead of literal 24/96/4/4.
- `src/ui/songview/quick/swift-grid-prototype/GridTypography.swift`: measure
  visible bar/beat/signature labels on demand; no whole-song width arrays or
  fixed four-beat indexing.
- `src/ui/songview/quick/swift-grid-prototype/Main.qml`: forward horizontal
  viewport origin through `setViewportScrollX(x:)`; preserve other input routing.
- `src/checks/swiftgridprototype/grid_smoke.cpp` and `grid_smoke.h`: read-only,
  document-rendering, and viewport regression rows.
- `src/ui/songview/quick/swift-grid-prototype/qtbridge-object-return.patch`
  and `PatchQtBridge.cmake`: approved nullable QObject return support and
  application of its QVariant source change; preserve existing patch behavior.
- `cmake/QtBridge.cmake`: track the patch and application script as configure
  inputs so ordinary incremental production builds apply dependency changes.

`SgdDocument.swift` is consumed unchanged; grid-facing mapping/subscription
belongs in `PianoGrid.swift`, not a second Task 2 edit.

## Prerequisites

Task 2's `SgdDocument` / per-instance `DocumentFeed` public contract and Task
1's settled module/link dependencies for verification.

## Interface contract

- Spec §3/§4 are authoritative for `readOnly`, `bindDocumentFeed`,
  `loadDocument`, `setDocumentTrack`, filtering, revision and lifecycle.
  `PianoGrid.init()` creates empty state; prototype App explicitly initializes
  demo audio then calls `resetDemo()`. `AudioSession.init()` is inert;
  `initializeDemo()` alone performs the current fixture/native-session setup.
- Conform `PianoGrid` to `QmlInstantiableStatus`; add `documentToken: String`
  and `documentTrack: Int`. `componentComplete()` calls the same public scalar
  `bindDocument(documentToken: String)` used by a host-created model. This
  parses/binds once, installs the receiver and connects the per-token callback.
  `loadDocument(SgdDocument, ...)` and receiver mapping remain Swift-internal;
  they are not QML variant APIs. Track property changes re-filter.
- Publish `renderedNoteCount: Int` and `appliedRevisionText: String` for the
  visual host; the latter is empty before first snapshot, then canonical
  decimal UInt64. Keep the actual guard revision Swift-only; never expose it
  via QtBridge's narrower UInt QVariant conversion. Task 4's overlay binds
  its `noteCount`/`appliedRevisionText` outputs to these values.
- One grid owns one immutable receiver binding. Bind before initial delivery;
  weak callback capture avoids a cycle. Track switches re-filter the current
  accepted snapshot; no reset of the receiver's revision guard.
- Musical data changes only from accepted host snapshots/track selection in
  read-only mode. User input cannot mutate notes, controller data, selection,
  local undo or feed revision. Pan/zoom/hover remain operative.
- `GridMetrics` defaults remain 24 ticks-per-beat and implicit 4/4 for the
  prototype. Document mode supplies real division and ordered signatures;
  note geometry, hit testing, viewport extents, subdivisions, bar numbering,
  ruler labels and time marks share that one parameterized geometry path.
  Preserve actual tick values and raw UInt8 signature numerator/denomPow2.
  Reuse existing Swift `TimeMap` / `TimeSigPoint` / `TimeAxis` for signature
  normalization, bounded beat-stride shifts and precedence; do not reject
  imported signatures or expand denominators in the feed. No re-quantization,
  parallel geometry implementation or frozen Wave-1 edits.
- QtBridge's scalar macro requires named Swift arguments; QML invocation is
  positional and unchanged. `makePitchEditor` returns `Optional<PitchEditor>`
  (the existing macro accepts this generic type spelling). Read-only or invalid
  selection returns nil without constructing an editor. The bridge must
  produce a typed null QObject QVariant, never an invalid QVariant that leaves
  meta-call return storage unwritten. Existing successful factory behavior stays.

## Implementation steps

1. Move fixture/native audio setup out of both constructors into the explicit
   App demo path. No missing-fixture fallback is needed or allowed in
   production. Guard mutation entry points (direct undo/redo, reset, menu,
   selection, pitch/controller paths), not merely QML editing gestures.
2. Bind the receiver and map accepted document values into selected-track
   `GridNote`s without altering viewport scroll/zoom. Expose applied `UInt64`
   revision without narrowing it into the demo's local revision counter.
   Invalid selected track renders an empty note set; unrelated data is ignored.
3. Parameterize existing `GridMetrics`; replace fixed-timebase consumption in
   `GridScene.rebuildStatic` / `rebuildRuler`. Preserve geometry/raster defaults,
   implicit 4/4 semantics and coincident signature last-event precedence.
   Consume existing Swift `TimeAxis` semantics for raw signature values,
   including numerator zero and denomPow2 >=31; production remains the oracle.
   No edits to Tick/TimeAxis/PitchProjection or C++ math.
   Iterate only visible time marks and measure only needed labels. Horizontal
   scroll delivery drives that visible range. Keep raw signatures in the feed;
   signature text follows production normalization and denominator display clamp.
4. Add real input smoke rows covering mutation inertness, view pan/zoom/hover,
   track-filtered loads and higher-revision refresh on the existing window's
   grid. At the end of editable smoke, C++ registers a synthetic endpoint slot,
   sets readOnly/documentTrack, invokes the same scalar `bindDocument` with a
   decimal token, and calls its registered delivery callback with POD snapshots.
   Inspect the actual rendered scene; clear/unregister before window teardown.
   No second Swift test grid, custom-value QVariant call or test-only production
   hook. Binding is immutable; all document rows use that one endpoint.
   Exercise at least one non-24 division, a signature change, coincident
   signatures, raw zero numerator/high exponent, and empty/invalid-track data;
   assert rendered positions and
   marks against production semantics, not just note counts.
   Initialize the nullable factory return destination with the existing model
   pointer and require null afterward; an initially null destination cannot
   prove delivery. Zoom coverage uses the existing configured metric-scale API;
   no standalone wheel-zoom gesture is implied or added.
5. Preserve every existing editable smoke outcome, including raster/typography,
   input and standalone audio; explicit demo initialization reproduces the
   original lane's behavior without touching production audio ownership.

## Acceptance predicate

- `deno task prototype:swift-grid --smoke` — existing visual/input rows plus
  read-only mutation, live viewport/hover, real-timebase/signature rendering.
- `deno task verify --filter swiftdocfeed --verbose` — real Swift receiver
  remains correct.
- `deno task verify --filter rollcheck-static --verbose` — production raster
  oracle unchanged. Native desktop required for smoke; controller runs gates
  after writer settlement under plan verification policy.

## Task-specific constraints

The GridGeometry/GridScene permission corrects fixed demo assumptions only;
no TimeCamera/Grid/PitchBendKernel conversion, Wave-1 numeric rewrite, or
second geometry subsystem. If correct real data needs a frozen source change,
report the exact dependency rather than normalizing ticks to demo units.
Existing demo APIs are retained for current acceptance, not promised forever.
