# Swift production mount — stopping-point handoff

Updated 2026-09-18. User explicitly requested a pause and a document for the next agent. **Do not treat the whole production mount as complete.**

## Start here

1. Read `../swift-backend-charter.md`, this directory's `plan.md`, `spec.md`, and `task-4-brief.md`, plus the applicable SDD execution rules and Qt skills.
2. Resume **Task 4: gated production mount + integration harness**. It has not been implemented or dispatched. Tasks 1–3 are implemented, reviewed, verified, committed, and pushed.
3. Use `2b585ed2` as the accepted implementation checkpoint for the next task. Freeze task-scoped review diffs against it. Preserve unrelated work described below.
4. Implement the three independent Task 4 slices below with shared contracts fixed before dispatch; controller owns integration and all builds/checks.
5. Complete Task 4 review and runtime gates, then whole-change review and modern Swift ownership/performance audit. Commit and push accepted checkpoints.

Worktree: `/Users/sallegrezza/dev/cProjects/porydaw/.worktrees/swift-qml-grid`.
Branch/remote: `feature/swift-qml-grid`, `origin` (`Sp3cker/porydaw`).
Environment: macOS arm64, Swift 6.4/language 6, Qt 6.11.0.
No builds or writers remain running at handoff. Native desktop is free.

## Accepted checkpoints and unrelated work

- `10e414a4`: prerequisite focus fix and migration retirement rules.
- `21ebd6cd`: source-correct production mount contracts.
- `639287d7`: Tasks 1/2 — shared Swift library and revision-guarded document feed.
- `ebe9c1d0`: independently added Wave 4 writable-flip plan. Preserve; this session did not implement it. Wave 3 read-only mounting remains the next implementation task.
- **`2b585ed2`: Task 3 — document-fed, read-only Swift grid; pushed.**
- Whole implementation review baseline from this orchestration: `ddb2214b`. Exclude unrelated intervening work from review ownership.

Intentionally unstaged user work at stopping point:

- `docs/plans/swift-backend-charter.md`: added declarations-first Swift ordering policy. Honor it; do not discard or silently claim it in this checkpoint. Task 3's private `NativeFontMetrics` helper was moved unchanged after `GridTypography` to follow it.
- Untracked `.claude/skills/{qt-cmake-project,qt-qml-profiler,qt-qml-review,qt-qml,qt-ui-design}/`.
- Untracked `docs/plans/swift-backend-jurisdiction/task-{1,2,3}-review-r0.diff`.

The handoff document is committed separately after the implementation checkpoint. No Task 4 implementation is hidden in the working tree.

## User decisions / non-negotiables

- This wave is a **read-only real-document mount**, not an editable production cutover. Do not retire the shipping C++ renderer or import later writable-flip work.
- User approved public QtBridge QML registration and correctly typed nullable QObject factory returns. No fake editor, partial getter workaround, compatibility alias, or hidden fallback.
- User approved commit/push of verified checkpoints without repeated permission. Push every commit.
- Modern performance-oriented Swift 6.4: use scoped Span/OutputSpan where useful; prove pointer bounds/lifetimes; avoid unnecessary copies, allocations, COW detach, and feature-count churn. Public surface before private implementation helpers.
- Keep window focus, keymap, and document ownership in the host. No second dispatcher, focus memory, or QML Space interception.
- Production constructors stay inert. Demo data/audio setup is explicit in the standalone app only.
- Reuse existing QML renderer components. No prototype-only replacement widget inventions.
- Workarounds require user approval; prefer the responsible root-cause fix.
- Run build/check commands through `deno task`, never direct CMake/Ninja. Tool timeouts must stay at or below 300 seconds; diagnose a timeout before retrying.
- Agents skip builds/tests/lint/formatters; controller runs settled gates. Native input checks need an undisturbed desktop; do not repeatedly stress-test desktop-dependent failures.

## Implemented foundation

### Task 1: production Swift library

APPLE-only static target `swiftgrid`, Swift module `SwiftGrid`, explicit production sources excluding `App.swift` and self-tests; transitively linked through `porydaw_app`. Native adapters reuse the existing production math/engine code. Shared QtBridge FetchContent setup lives in `cmake/QtBridge.cmake`, pinned to `407714006dd21107b70db6547ce75e43df0c8a75`.

Preserve the verified build decisions:

- CXX archive/link selection for `porydaw_app` and final app/check executables. Swift's transitive linker preference otherwise consumes a PCH or invokes incompatible libLTO against Xcode bitcode (`Unsupported stack probing method`). Do not disable IPO/LTO/PCH.
- Swift runtime import/library directories come from the selected `swiftc -print-target-info` with native SDK, not hardcoded runtime libraries or RPATHs. Empty discovery is fatal.
- `Qt6::CorePrivate` discovery occurs in the required parent scope.
- Valued `PORYDAW_VERSION` macro is non-Swift only.
- Edit command policy uses checked `Sendable` on the actual stored vocabulary, not unchecked annotations or unrelated enums.

### Task 2: per-feed document values

Files under `src/ui/songview/quick/swiftgrid/`:
`document_feed.{h,cpp}`, `module.modulemap`, `swift_grid_document_feed.{h,cpp}`.
Swift receiver: prototype directory's `SgdDocument.swift`.
Harness: `src/checks/swiftdocfeed/`.

`SwiftGridDocumentFeed` is a global-namespace QObject, constructed from `const SongDocument&`. It mints a fresh UInt64 token per feed lifetime, registers an empty delivery slot and observes changes, but **does not initially deliver**. API: `documentId()`, `delivery()` returning `SgdDelivery*`, `pushSnapshot()`. Destruction disconnects/unregisters.

The C ABI carries only POD header/notes/raw time signatures through per-token delivery slots. `sgd_set_delivery`, `sgd_clear_delivery`, register/unregister functions are in `document_feed.h`. Slots are GUI-thread borrowed storage, not a current-document singleton or retained document/cache.

Swift `@MainActor DocumentFeed` accepts one immutable token, rejects wrong-token/stale/equal revisions before dereference/allocation, copies accepted scoped spans once into owned arrays, and invokes a weak callback. Initial revision zero is valid. Isolated destruction clears registration. Raw signature values (including numerator 0 and denominator power 255), unsigned ticks, and full-width IDs/revisions are preserved.

### Task 3: real-document read-only model/rendering

Changed Swift files: `PianoGrid`, `App`, `AudioSession`, `GridGeometry`, `GridScene`, `GridTypography`; plus one horizontal-origin forwarding line in `Main.qml`.

- `PianoGrid` conforms to `QmlInstantiableStatus`; completion binds its receiver. Public scalar `bindDocument(documentToken: String)` uses a named first parameter because the macro does not support `_` there.
- Full-width token/revision cross QML as decimal strings, not UInt properties (QtBridge narrows those) or QML numbers. `documentToken` is immutable once bound; `documentTrack` re-filters the accepted snapshot.
- Observation: `renderedNoteCount: Int`, `appliedRevisionText: String`.
- Read-only guards cover note/selection/history/menu/pitch mutation paths; viewport pan/configured metric scale/hover remain live. Production loading skips demo JSON/audio publication.
- QtBridge property observers use `willSet`: the macro skips properties with `didSet`, while generating its own `didSet`.
- `makePitchEditor(...) -> Optional<PitchEditor>` returns nil for read-only/invalid selection. This explicit generic spelling works with the existing macro; do not add an unrelated macro syntax rewrite.
- Real division and raw signatures use frozen production TimeAxis semantics. Visible ticks are bounded to viewport plus one viewport overscan each side. Label measurements are on demand, not whole-song tables or fixed four-beat assumptions.
- Native font metric sessions are created during viewport setup, not inert model construction. Pure font descriptors seed valid scene font maps before native measurement.
- Full document extent does not depend on selected track. Empty/shorter refreshes preserve the current viewport floor/pan.

QtBridge patch now adds typed nullable QObject QVariant conversion: nil must be a QVariant with the wrapped QObject metatype and null pointer, **not invalid QVariant**. Smoke starts with a non-null return sentinel and requires it to become nullptr.

Keep all existing patch sections, including original nonoptional object-return support and public registration. The macro ExternalProject declares `QtBridgeMacros` as `BUILD_BYPRODUCTS` instead of `BUILD_ALWAYS`, so ordinary builds do not relink it. `cmake/QtBridge.cmake` tracks patch/script via both `CMAKE_CONFIGURE_DEPENDS` and content hashes in PATCH_COMMAND. Both are needed: configure rerun alone does not invalidate FetchContent's patch stamp.

## Task 4: ready decomposition

Read the exact write set and acceptance predicate in `task-4-brief.md`. Suggested concurrent ownership:

1. **Qt C++ mount/lifecycle owner** (`qt-cpp-reviewer`, implementation mode): `timelinequickview.h`, `.cpp`, `_window.cpp`, new `swiftgrid/grid_host.h`. No unrelated input/key/window rewrite.
2. **Swift/QML/resources owner**: new `SwiftGridHost.swift`, `SwiftRollOverlay.qml`, prototype `CMakeLists.txt` source/resource additions only. Read Qt QML/UI/CMake skills; reuse existing `PianoRollCanvas.qml`, `TimelineQuickItem.qml`, and local dependencies.
3. **Integration harness owner**: new `src/checks/swiftrollgated/` and checks CMake/catalog/fwd registrations. Use real `WorkspaceUi`/mounted surface and checked-in fixtures; no duplicate Swift test model or test-only production hooks.

Controller fixes shared contracts before dispatch, owns integration, validation, and checkpoints. Resource/object names below are **proposed, not yet implemented**; freeze them with the batch contract:

- Resource basename `swift_grid_qml`, prefix `/swiftgrid`, URL `qrc:/swiftgrid/SwiftRollOverlay.qml`.
- Object names `swiftRollOverlay`, `swiftGridModel`, `swiftRollViewport`, `swiftRollInput`.
- If static resource initialization is needed, match `Q_INIT_RESOURCE(swift_grid_qml)` from a global-namespace helper, not inside the songview namespace.

Fixed spec contracts:

- APPLE plus `qEnvironmentVariableIsSet("PORYDAW_SWIFT_ROLL")`, read once at TimelineQuickView construction. Empty environment value still enables it. Flag off allocates/registers no Swift mount state.
- Sole C ABI `void sg_register_grid_types(void)`: Swift main-actor, once-only `PianoGrid.registerQmlElement()`. No object factory/manual retain/proxy extraction/app/engine creation.
- `import SwiftGrid 1.0` (intentional versioned import required by this module).
- Overlay required properties `documentToken: string`, `selectedTrack: int`; QML-owned nonvisual `gridModel` is a read-only PianoGrid. Expose `noteCount` and decimal-string `appliedRevisionText`.
- Use existing `m_quickView->engine()` / borrowed `m_view`; there is no `quickEngine()` API.
- Order: create/register empty feed → register types/resources → `QQmlComponent::createWithInitialProperties` with token/track → completion binds receiver → verify component and `feed->delivery()->fn` → set visual parent/canonical geometry/visibility and track forwarding → explicit `pushSnapshot()`.
- Opaque clipped overlay absorbs editing input without acquiring focus or installing keys/Shortcuts. Normalized view pan/zoom/hover stay live. Do not pass window/engine/document objects to Swift.
- Teardown: disconnect track forwarding and observer, unregister/destroy feed **before** deleting overlay/model. Cover partial mount, repeated detach, and externally destroyed transferred window.

### Lifecycle risk — resolve before implementing cleanup

`QWindow::destroyed` may be too late: QQuickView's derived destructor can tear down root/engine earlier. Do not assume its late QObject signal establishes feed-before-model destruction. Verify an earlier root/overlay lifecycle hook and explicit ownership, with harness evidence that the endpoint is already unregistered when the model dies. Separate QObject ownership from visual parentage may help, but is not a mandated workaround.

Source map from preflight (line numbers approximate):

- `timelinequickview.cpp`: constructor around 99–378, QQuickView creation 124, borrowed `m_view` 133, engine context 142–159, TimelineCanvas load 160, `m_root` 166; canonical band publishing 730–783.
- `TimelineCanvas.qml`: root `rollBandRect`, `rollBandVisible`, `rollBandPlotRect`; existing roll canvas around 250.
- `_window.cpp`: destructor 78 calls detach; `takeWindowForEmbedding()` 83 moves owning pointer but keeps borrowed window. `detachWindow()` 93 is idempotent; root clear 156 and `setSource({})` 158 currently unload QML. Unmount must precede unload. Existing path has no complete external transferred-window cleanup.
- `SongView::document()` exists; selected-track signal is `selectedTrackChanged(int)`. **Inspect the actual current-track accessor** rather than mistaking `ViewState::selectedTrack` around header line 170 for it.
- Initial load is not a missing notification: SongTab adopts SMF before setSong; `SongDocument::adoptSmf` publishes mutation/revision/documentChanged. Still explicitly push immediately after mounting an already populated document.

Harness must cover flag-off first (before any registration), flag-on with empty value, initial rendering without an edit, track changes, C++ edit/undo/redo, non-24/raw-signature geometry, two concurrent documents with interleaved updates, close one/update the other, fresh remount token/binding, mutation/focus inertness plus live viewing input, normal/repeated detach, and external transferred-window destruction. Observe the actual mounted renderer/framebuffer and real endpoint lifetime.

## Verification evidence and remaining gates

Completed before pause:

- `deno task prototype:swift-grid --smoke` — **PASS**, 22.19s. All original editable rows and new document/read-only mutation, typed-null, pan/metric-scale/hover, track/revision/invalid-track, raw-signature and empty-snapshot rows passed.
- `deno task verify --filter swiftdocfeed --filter rollcheck-static --verbose && deno task build:app` — **PASS**, 2/101 checks, production app links; ordinary build automatically reapplied updated dependency patch. Earlier prerequisite gate also passed `selectionkey-core`.
- Final `deno task build:app` after the declaration-order-only NativeFontMetrics relocation — **PASS**, 13.24s. No behavior changed after the full smoke; review confirmed byte-identical relocation.
- Task 3 model, geometry, and nullable-bridge/smoke reviews: Spec PASS / quality Approved. Geometry re-reviewed after relocation; no critical/important findings remain.
- Commit hook format check passed. Main.qml deterministic lint retained 22 pre-existing findings; none on the added horizontal-origin line. Swift LSP unavailable; actual compiler gates used.

Do not repeat resolved mistakes:

- Qt 6.11 `Qt.application.font` is CONSTANT; changing QGuiApplication's font does not update that QML binding. The smoke changes the existing `appFontInfo` object's public font, invokes the real root `configureViewport()`, and restores it. No global font workaround or new hook.
- Signature segments can use different normal/fine beat emphasis. The smoke accepts either valid beat palette at exact non-bar positions; bars, count, geometry, and raster assertions remain strict. Do not duplicate Grid math or extend ABI for this.
- Empty font-map fallback recreates an actual startup error; keep the total pure descriptor mapping.
- `kNoTick` is intentional as an exclusive range end; do not clamp it like a point.
- Two earlier varying old native input failures did not recur in the completed full smoke. Cause was not proven; no test weakening or source workaround was added.

Still required after Task 4:

```sh
deno task build:app
deno task verify --filter swiftrollgated --filter swiftdocfeed --filter selectionkey-core --filter rollcheck-static --verbose
deno task prototype:swift-grid --smoke
deno task verify --verbose
```

Run deterministic lint on new/changed QML, format the settled C++ union, and obtain actual native surface/framebuffer evidence. The full final suite has **not** been run for the completed wave because Task 4 remains absent. Complete Task 4 spec/quality review, whole-change review, modern Swift ownership/performance/declaration-order audit, cleanup of only owned scratch artifacts, then commit/push.

Known non-blocking toolchain warnings: upstream Qt Swift Clang-import cycles, QtCorePrivate version coupling, local clang-format 21 vs CI 22. Do not suppress or expand scope merely to remove them.

## Wave 3 close-out (2026-09-18)

Decision: a same-day default-mount experiment (compile-time Swift default, no
runtime flag) was reverted at the user's direction. The overlay stays behind
`PORYDAW_SWIFT_ROLL`; default-on returns only at the Wave 4 editable cutover
per the charter retirement table. Evidence that drove the revert: with the
overlay default-mounted, eight input-routing harnesses fail because the
overlay absorbs wheel/pointer that the checks route to the C++ roll band
(`rollcheck-static gatedAndReadyRollZoom` asserts `camera().pxPerBeat()`
change); all eight pass with the overlay unmounted. Kept from that work: host
palette push (`SwiftRollMount::applyHostPalette` + `PianoGrid.reloadVisuals`)
and initial note-range centering, both now asserted by `swiftrollgated`.

Closed items:

- Task-4 review minors: unused overlay `setViewportScroll`/`setViewportScrollX`
  removed; `inputCancelled(2)` named (`cancelReasonHidden` mirroring
  `TimelineInputCancelReason::Hidden`). The third minor (mount-time geometry
  sync) was withdrawn after thermo-nuclear review: `m_bandLayout` is always
  empty at construction, so a constructor-time `updateBandGeometry` is a no-op
  that hides the real first-publish convergence; the call was removed.
- Host palette push derives grid cadence and pre-roll colors through the
  canonical oracle helpers (`detail::gridLineColor`, `mixTowardOklab`) instead
  of bespoke math; `rulerDetailText`, `noteBorder`, and `hoverChip*` stay on
  GridPalette's own Swift derivations. `swiftrollgated` pins rollBackground
  and that initial centering engaged (`centeredOnNotes` plus non-top scroll;
  exact `initialScrollY` equality is unassertable — the model recomputes it
  after the one-shot centering consumed the first value).
- `swiftrollbench` + `swiftrollbench-swift`: frame-cost bench rows
  (vgloadbench pattern) — one build, two lanes via manifest environment.
  2026-09-18 evidence on this machine (mus_route101): scroll median 17.3ms
  Swift vs 17.6ms C++ (0.98x), p95 24.2 vs 26.0ms; zoom-phase cadence ~0.99x
  (the overlay maps ctrl+wheel to scroll until Wave 4 input work). Within the
  2x perf bar: PASS. The cpp lane retires with the C++ roll at cutover.

Gate results: `build:app` PASS; filtered verify (`swiftrollgated`,
`swiftdocfeed`, `selectionkey-core`, `rollcheck-static`) 4/4 PASS; full
verify 94/104 — the 8 visual harnesses (chrome/quick/browsers/dialogs at
font12/16) fail identically with and without the Swift grid and predate this
close-out (row-height and raster deltas against frozen baselines; artifacts
under `/var/folders/.../porydaw-visual-artifacts/`); unresolved, not
rebaselined. `prototype:swift-grid --smoke` passed on this tree's
prototype-lane inputs; three later runs failed three different native-input
rows during active desktop use (documented interference pattern; do not
stress-rerun) — rerun once on an idle desktop to reconfirm.
`selectionkey-gesture` flaked inside the full run and passed isolated.

Wave 4 dispatch gate: perf-bar evidence recorded above; awaiting user
acceptance and checkpoint authorization.
