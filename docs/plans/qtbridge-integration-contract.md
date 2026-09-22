# QtBridge integration contract and acceptance gate

Status: integration requirements referenced by the [current charter](swift-backend-charter.md), recorded 2026-09-19. Runtime guarantees below are NOT yet verified by this assessment. This document does not authorize implementation dispatch or close a production cutover. The proposed [ownership design](swift-ownership-cutover/design.md) records unresolved prerequisites and separates bridge capability from production acceptance.

## Purpose and ownership direction

Target: Swift application/domain logic and QML views, with minimal handwritten C++ Qt application code. Preserve user behavior, not old C++ presenter interfaces. Use direct QtBridge presenters and collections rather than per-surface C++ mirrors. Grid and headers are the first two consumers proving the shared integration.

Keep two distinct interoperability seams: QML-to-Swift presentation, and Swift-to-retained native services such as audio. Do not make one universal dispatcher. One authoritative document/history and one command arbitration authority remain required.

Swift domain types must not be designed around C ABI layouts. Imported C structs, pointer/count buffers, callback contexts and raw enum conversion belong inside native integration adapters. Use Swift-native domain types and operations internally. Fixed-width numeric types are appropriate where musical ranges, identities or arithmetic require them; they are not themselves evidence of an undesirable C interface. Retire the legacy document feeds and command transport when their C++ authority and callers retire. Do not add a wrapper for every surface.

## Dependency baseline

Source evidence, not a runtime certification:

- `cmake/QtBridge.cmake` pins QtBridge to `407714006dd21107b70db6547ce75e43df0c8a75` and requires Qt 6.10 CorePrivate.
- Local patch: `src/ui/songview/quick/swiftroll/qtbridge-object-return.patch`.
- Patch scope observed during assessment: object-return macro support, optional bridged-object conversion, public QML element registration, and macro build configuration.
- `PianoGrid.swift` uses direct QtBridge exposure; `GridScene.swift` exposes Swift `QListModel` collections.
- Upstream: https://github.com/qt/qtbridge-swift (early-preview dependency).

Recorded baseline (2026-09-19, worktree `swift-qml-grid` at `bc24c98d`,
collected by source/build-config inspection; runtime scenarios below remain
Unverified until executed):

- Qt: 6.11.0 (Homebrew, `/opt/homebrew/lib/cmake/Qt6`; root `CMakeLists.txt`
  requires 6.11, QtBridge requires 6.10 `CorePrivate`).
- Swift: Apple `swiftc` 6.3.3 (`/usr/bin/swiftc`; recorded in
  `build/CMakeFiles/4.3.2/CMakeSwiftCompiler.cmake`), `Swift_LANGUAGE_VERSION 6`,
  `-cxx-interoperability-mode=default`.
- QtBridge: `qt/qtbridge-swift` pinned `407714006dd21107b70db6547ce75e43df0c8a75`
  via FetchContent (`cmake/QtBridge.cmake:18-26`); sources land in
  `build/_deps/qtbridge-src`, macros rebuilt through an ExternalProject.
- Application: Porydaw `feature/swift-qml-grid` at `bc24c98d` (this file's
  baseline; advancing the pin, patch, Qt or Swift invalidates affected rows).

Local patch `src/ui/songview/quick/swiftroll/qtbridge-object-return.patch`
(74 lines, 4 hunks; **not upstreamed**; applied idempotently by
`PatchQtBridge.cmake` with SHA256-pinned inputs):

| Hunk | QtBridge source | Purpose |
| --- | --- | --- |
| 1 | `Sources/QtBridgeMacros/Extensions.swift:124` | Allow identifier (bridged object) return types from `@QtBridgeable` methods. |
| 2 | `CMakeLists.txt:59` | Propagate host `CMAKE_MAKE_PROGRAM`/Swift compiler/flags into the macro plugin ExternalProject; declare `QtBridgeMacros` as `BUILD_BYPRODUCTS` so Ninja rebuilds it only when stale. |
| 3 | `Sources/QtBridge/QmlInstantiable.swift:50` | Make `registerQmlElement()` public so consumer modules register QML elements. |
| 4 | `Sources/QtBridge/QVariant.swift:95,181` | `QVariant` from `Optional<Wrapped: QObjectBuildable>` (typed null) + `Optional: QVariantGettable`. |

Mechanism anchors (pinned source, subject to pin changes): `@QtTracked` emits
Qt property-change signals from `didSet` (`QtBridgeableMacro.swift:115`);
`QListModel` maps subscript sets to `dataChanged`, `replaceSubrange` to
begin/endInsert/RemoveRows, `reset(to:)` to begin/endResetModel
(`Sources/QtBridge/QListModel.swift:105-180`); rows are index-identified with
no stable key — in-place row reuse is client policy (prefix diff in
`GridScene.swift:129`).

### Prospective: in-process Qt Quick Test hosting (recorded 2026-09-20, prospective)

Recorded so a later task does not claim a capability this pin does not have. Nothing
here is verified runtime capability, and none of it authorizes implementation.

- `Sources/QtBridge/QTest.swift` (`QmlTestModule`, `QtQuickTestConfiguration`,
  `QtQuickTestRunner`) exists in the pinned source but is **not** in
  `QTBRIDGE_SWIFT_SOURCES` (`Sources/QtBridge/CMakeLists.txt:4-22`), so
  `QtQuickTestRunner` is not part of the compiled QtBridge module. Do not treat it
  as an available entry point.
- Available instead: `QtBridgeCpp.QTestAppCpp`
  (`Sources/QtBridgeCpp/include/qtestappcpp.h`, compiled from
  `Sources/QtBridgeCpp/qtestappcpp.cpp`) exposes `setImportPath`, `setPluginsPath`,
  `setInputDir`, `setTestName`, `registerQmlSingleton(uri, major, minor, name,
  QObjectProxy)` → `qmlRegisterSingletonInstance`, and
  `runQtQuickTests(argc, argv)` → `quick_test_main`. A Swift consumer reaches it with
  `import QtBridgeCpp` plus `QObjectBuildable.objectHolder.proxy`
  (`Sources/QtBridge/QObjectBuildable.swift`), which is the sequence `QTest.swift`
  performs internally. `QtBridgeCpp` links `Qt6::Core/Gui/Qml/Quick` but **not**
  `Qt6::QuickTest`, so a consumer that pulls `qtestappcpp.o` in must link
  `Qt6::QuickTest` itself; header resolution works today because the Qt frameworks
  share one `-F` path.
- The production grid scene receives its session as a **context property**
  (`RewriteWindow::attachGridScene`, `RewriteWindow.cpp:457`). Qt Quick Test creates
  its own view, `quick_test_main` accepts no setup object, and unqualified QML names
  resolve against the component's context rather than ancestor properties — so a QML
  test view cannot supply that name merely by adding an ancestor property. This
  does not require a new native test host: the camera/drawer plan extracts the real
  root/input composition into property-injected `EditorSurface.qml`, leaving
  `SwiftRollOverlay.qml` as its production context adapter. Component tests can
  exercise that same composition, with no copied handlers. Native action/keymap
  dispatch and actual window destruction still require separately identified
  native-window evidence.
- A prospective Swift Qt Quick Test executable can use the existing
  `QTestAppCpp` directly and link `Qt6::QuickTest`; no C++ bootstrap, production
  `setInitialProperties` hook or QtBridge patch is required. `setTestName` names
  the report only: use `-input` to select the intended test file. Its path setters
  must be configured because `runQtQuickTests` overwrites both import/plugin
  environment variables. Open asynchronous production sessions only after the
  Qt event loop runs, not by waiting before `runQtQuickTests`.
- The active [camera/drawer plan](swift-editor-consumers/plan.md) and its briefs
  decide whether/when this test executable is needed. These inspected capabilities
  do not claim a target, command or runtime result already exists.

## Lifetime contract

Before implementation acceptance, fill an ownership table for the application/workspace, document/session, Swift presenter, collection, row objects, Qt proxies, and observer/callback registrations. For each name: creator, lifecycle owner, other retaining references, isolation context, invalidation event, release condition, and teardown ordering. Do not substitute 'Qt manages it' for an owner.

Required invariants:

- Presentation/model mutations execute on the designated GUI-thread/Swift isolation context. Establish how those contexts coincide; an annotation alone is not proof.
- A presenter receives no document callbacks after session detachment.
- Closing one tab cannot invalidate another tab's objects.
- Removed rows cannot remain valid editing targets merely because delegates retain references. Actions resolve stable domain identity, not a stale list position.
- Tab/application closure causes neither use-after-free nor indefinitely retained document graphs.
- QML visibility is not treated as destruction, and proxy destruction is not assumed to release every Swift reference immediately.
- Initial binding, detachment and teardown have an explicit ordered protocol. Identify when new actions stop, pending delivery is invalidated, observers disconnect, and references release. Test the actual protocol rather than assuming a universal deletion order.

Task 8 terminal ownership table (source-inspected; controller runtime evidence
remains required by the scenario ledger below):

| Object | Creator | Lifecycle owner | Other retaining refs | Isolation | Invalidation/release | Teardown order |
| --- | --- | --- | --- | --- | --- | --- |
| `RewriteWindow` | `main.cpp` | C++ app stack | — | Qt GUI thread | App exit | Detaches the Quick scene before deleting `ApplicationSession` |
| `ApplicationSession` | `RewriteWindow` through `QQmlComponent` | `RewriteWindow` (`CppOwnership` and QObject parent) | QML context borrows its proxy | Qt GUI thread / Swift `@MainActor` | Window teardown | Quick scene is deleted before the session proxy |
| `DocumentSession` + `SongDocument` | `ApplicationSession::replaceSong` | `ApplicationSession` | `PianoGrid` has a required direct session reference | Swift `@MainActor` | Song replacement/close | Register detach continuation → emit `aboutToReleaseGrid` → native host deletes Quick scene and acknowledges → detach/release presenter → close/release session |
| `PianoGrid` | `ApplicationSession` | `ApplicationSession.grid` | QML `gridModel` holds the returned proxy while the scene lives | Swift `@MainActor` on the Qt GUI thread | Song replacement/close | Remains retained until `acknowledgeGridDetached`; signal emission alone does not complete teardown |
| `GridScene` + `QListModel`s | `PianoGrid` | Swift ARC via `PianoGrid.scene` | QtBridge object holders keep their proxies alive while QML reads them | Same as presenter | Presenter release | Released with `PianoGrid`, after the Quick scene |
| Row elements (`SceneRect`/`SceneText`) | `GridScene` rebuilds | `QListModel.storage` | QML delegates read copied roles | Same as presenter | Model replacement/removal | Subscript replacement/reset emits the model notification; no contained-object mutation is relied on |
| Document change callback | `ApplicationSession::replaceSong` | `DocumentSession.onChange` | Weak presenter and weak session/application captures | Swift `@MainActor` | `DocumentSession.close` clears callbacks | Presenter is detached before session close |
| Clipboard byte loan | `RewriteWindow::pd_clipboard_read` | `QClipboard`/local `QByteArray` for the synchronous call | Swift copies into `Data` during the callback | Qt GUI thread | Callback return | No pointer survives the native call |

The pinned QtBridge emitter queues signal activation
(`swiftmetaobjectbuilder.cpp`, `Qt::QueuedConnection`). The host therefore
acknowledges teardown only after deleting the window container, which owns the
`QQuickView`. `songOpenChanged` mounts a new scene; it is not a second teardown
path. Replacement tasks serialize, and host closure prevents a pending
replacement from publishing another scene. Controller verification:
`deno task verify --filter selectionkey --filter swiftqtml --verbose` exercised
replacement and close with `TypeError`/`ReferenceError` warnings treated as
failures; `swiftqtml` passed, and the subsequent focused `selectionkey` run passed
after removing a redundant click from its unrelated keyboard-gesture setup.
The bounded lifetime/input quality re-review approved this protocol.

**Follow-on rename (recorded 2026-09-20, prospective).** The editor-consumers plan
extends this same protocol to two presenters: `aboutToReleaseGrid` /
`acknowledgeGridDetached` are renamed to `aboutToReleaseEditor` /
`acknowledgeEditorDetached` with the native caller migrated, close admission (gate
check/reservation, stop admitting new operations) happens before the emit,
cancellation runs between admission and the emit, and presenter release, audio unload
and session close stay behind the acknowledgment. The protocol, its ordering and the
queued-emission constraint are unchanged; nothing here authorizes a synchronous
replacement, an earlier release or a new native lifecycle helper.

Open lifetime facts the probe must observe rather than assume: delegate
retention of removed rows (QML may cache items), pending-notification
delivery across presenter destruction, and whether a stale row reference can
still reach a replaced model.

## Observable model-update contract

| Operation | Required observable behavior |
| --- | --- |
| Presenter property mutation | Existing QML bindings observe the new value. |
| In-place row property mutation | Relevant existing delegates update without an unrelated refresh. Verify separately from replacing the row. |
| Row replacement | Delegates observe the replacement; stale references cannot edit the new row accidentally. |
| Row insertion/removal | Contents and order update; surviving rows preserve domain identities. |
| Reorder | Selection and actions still address the intended track/note, not its former index. |
| Collection reset/document replacement | Stale delegates and callbacks cannot mutate the replacement document. |
| Editing transaction | Grid and headers observe coherent committed state. Specify whether intermediate notifications are hidden or explicitly safe; do not leave batch semantics implicit. |

Select supported update operations based on pinned-source inspection and runtime proof. Do not claim that a collection wrapper automatically propagates changes to objects contained inside it.

## Evidence ledger

Every guarantee needs: requirement, pinned implementation/source anchor, reproduction scenario, exact command, tested revisions/toolchain, observed result, and status (`Unverified`, `Verified`, or `Unsupported`). Source inspection establishes mechanism; runtime execution establishes evidence. Never silently promote one into the other.

### Swift 6.4 qualification

Status: **Qualified for app/checks compilation and bridge capability
primitives — 2026-09-19, controller-executed.** The 6.3.3 baseline and M0
observations below remain historical evidence with their own labels.

Toolchain facts (observed, not assumed):

- Compiler: `/Users/spencer/.swiftly/bin/swiftc`, Apple Swift 6.4
  (`swift-6.4-RELEASE`), target `arm64-apple-macosx26.0`. Selected by the
  runner (`tools/local_build_environment.ts` `swiftToolchainArgument`) from
  the `.swift-version` pin (6.4.0) via `-DCMAKE_Swift_COMPILER`; CMake's
  Apple Swift discovery otherwise resolves `xcrun --find swiftc` and ignores
  PATH. swiftly config `inUse: 6.4.0` matches the pin; a mismatch fails the
  configure loudly.
- Main build and `QtBridgeMacros_External` both bind the swiftly 6.4
  compiler (rules.ninja + external CMakeCache inspected); the macro package
  binary was rebuilt under 6.4 before this qualification.
- `CMAKE_OSX_DEPLOYMENT_TARGET`/`CMAKE_OSX_SYSROOT` are unset — toolchain
  and SDK defaults apply. No explicit C++ interop flags on `PorydawCore`
  (Qt-free); QtBridge targets keep their existing flags from the pinned
  patch (pin `407714006dd…`, 4 local hunks — unchanged from the 6.3.3
  baseline).
- Language mode: `-swift-version 6` / `Swift_LANGUAGE_VERSION 6` on every
  Swift target (mode, not compiler release). Observed emit-module mode
  enforces borrow/consume diagnostics that plain typecheck does not: two
  writer idiom patterns failed only under `-emit-module` (a `borrowing`
  generic parameter whose property access is diagnosed as a consume — fixed
  by passing the 16-byte view structs by value; and internal methods generic
  over a private protocol — fixed by privatizing). Writers must not rely on
  typecheck-only approval for emit-module-compiled targets.

Qualification commands (executed 2026-09-19, branch
`feature/swift-qml-grid` after `ea10dee2` + working tree):

- `deno task build:checks` → build ok (PorydawCore now includes
  `PlaybackTimeline.swift`; `PorydawPlayback` target + `swiftcore` playback
  slot wired).
- `deno task verify --filter swiftcore --verbose` → PASS (midiCodec,
  musicalSemantics, playback — differential vs C++ oracle, real engine).
- `deno task build:app` → build ok.
- `deno task verify --filter swiftqtml --verbose` → PASS (bridge capability
  primitives re-proven under 6.4).
- Reference filters `loopcheck primecheck trackactivitycheck exportcheck`,
  `smfcheck velocity-model` → PASS (unchanged references).

Standard-library interface inspection during the plan audit (not a runtime
probe): the selected toolchain's
`usr/lib/swift/macosx/Swift.swiftmodule/arm64-apple-macos.swiftinterface`
declares `InlineArray` with `@available(anyAppleOS 26.0, *)`, and `UniqueArray`
and `UniqueBox` with `@available(anyAppleOS 27.0, *)`. The compiler's
`-print-target-info` reports default target `arm64-apple-macosx26.0`;
`CMAKE_OSX_DEPLOYMENT_TARGET` remains empty. The two unique containers therefore
require an approved deployment change before adoption. No availability fallback
or target bump is authorized by this plan.

The [SE-0527 acceptance decision](https://forums.swift.org/t/accepted-in-principle-se-0527-uniquearray/86943)
excluded public `RigidArray` and the proposed `Containers` module; the proposal
body still describes that earlier design. Do not use its blanket implementation
status as proof that every proposed API shipped.

Not established by these rows: callback realtime safety, InlineArray/Span/@c
representation decisions (task 5's bounded comparison owns those), or final
consumer behavior. Source availability annotations do not prove runtime cost.

### M0 capability probe — recorded 2026-09-19

Harness: `src/checks/swiftqtml/` (registered check `swiftqtml`; harness-local
`BridgeProbe` presenter + `QListModel<BridgeRow>` class rows + real QML
Repeater delegates). Command (executed, observed):
`deno task verify --filter swiftqtml --verbose` → PASS, and direct
`porydaw_checks --swiftqtml <scratch> mus_route101 mus_petalburg` →
`Totals: 10 passed, 0 failed`, zero captured Qt/QML messages. Toolchain: the
recorded baseline above (Qt 6.11.0, Swift 6.3.3, QtBridge `407714006dd…`,
patch as tabled), application at `aa9a5107` + this task's working tree.
These rows verify bridge capability primitives only — the production-scenario
rows below stay Unverified until the M1a two-consumer harness exercises them
on real surfaces.

| Capability | Observed result | Status |
| --- | --- | --- |
| Presenter property mutation → existing QML binding | `statusText` change reached the bound `Text` after settle (queued emission). | Verified |
| Contained-object mutation propagation | Direct `BridgeRow` property set does **not** emit model `dataChanged`; the delegate keeps the old value. Row-object mutation alone is not a QML-visible update path. | Verified (limitation) |
| In-place row update via subscript (`model[i] = row`) | Emits `dataChanged`; delegate shows the new value with **unchanged delegate serial** (no delegate recreation). | Verified |
| Row replacement (new object at index) | Delegate shows new values, no churn; a retained reference to the old object stays live and distinct — actions through it address the old (detached) object, never the replacement. | Verified |
| Insert/remove | Count/order update in QML; surviving delegates keep their serials; actions through references captured pre-mutation resolve the same domain row after the shift. | Verified |
| Reorder (`moveRow`) | Order updates; action through a pre-move reference addresses the intended row (object identity, not index). | Verified |
| Collection reset with stale QML-captured row reference | Fresh rows render; the stale reference's action is harmless (logged against the detached object); replacement rows untouched; view stays error-free. | Verified |
| Pending mutation + immediate view/presenter teardown | No crash, no resurrection (`QPointer` null), fresh view isolated, zero QML warnings. (Bounded: presenter+`QQuickView` destruction with queued emissions — not the full tab-close protocol, which `swiftrollgated` covers.) | Verified (bounded) |
| Patched object return (`makeRow`) | QML reads returned object's properties — **only while a Swift-side retainer holds the object**: a QML `var` stores just the C++ proxy; when Swift's last reference drops, the proxy is deleted and the QML var dangles (observed SIGSEGV in the QML binding read when the retainer was removed; restored + documented in the harness). Presenters returning objects to QML must retain them for the QML lifetime. | Verified |
| Patched optional object return (`selectedRow() -> BridgeRow?`) | Non-nil readable (with presenter-side retention); nil renders as typed null (`<null>`, `selectedIsNull` true) without a QML type error. | Verified |
| QML element registration (patch hunk 3) | Harness registers and instantiates its presenter as a QML element via `registerQmlElement()`. | Verified (exercised by harness) |
| QML→Swift slot calls with bridged-object **arguments** | **Unsupported — crashes**: invoking an object-argument slot from QML segfaults the process inside QtBridge/QtQml argument marshaling (controller-observed SIGSEGV ×2 on 2026-09-19, pre-isolation runs; lldb backtrace: QtQml `OUTLINED_FUNCTION_2` accessor dereferencing garbage; invocation `invoke(root, "attemptObjectArgumentCall")`). Source mechanism: the pinned macro registers only primitive slot parameters. Post-fork in-process reproduction is not viable (Qt render-thread/event state is not fork-safe — two isolation designs failed pre-invocation), so the harness asserts the boundary statically with this evidence; the QML helper remains as the future-fix probe point. | Unsupported (crashes; evidence above) |

Initial status for all following scenarios: **Unverified by this assessment**.

- Rename a visible track in place without replacing its row; observe actual delegate text.
- Insert/remove/reorder tracks; act on the same stable identity afterward.
- Commit an edit and undo/redo; observe grid and headers from the same session.
- Replace/reset the collection while a transient editor/menu references an old row; stale action must not mutate the replacement.
- Close a tab with a pending notification and open transient UI; verify no post-detachment delivery and observe release/bounded retention.
- Keep another tab open during closure; verify its model and actions remain functional.
- Reopen a document and close the application; verify safe teardown and no retained document graph.

Use focused in-repo scenarios under `src/checks/` that exercise real QML bindings/delegates and the actual integration owner. Pure Swift field assertions do not prove QML propagation. 'Did not crash' alone does not prove release. Keep regressions for plausible lifetime, identity and notification bugs; avoid tests pinning incidental signal counts or internal field forwarding.

An implementing task must register the covering checks and record exact `deno task` verification commands here before marking any row verified. There is no newly implemented harness or runnable new filter claimed by this document.

## Acceptance and maintenance

Direct Swift-to-QML integration is accepted only after the two-consumer scenarios pass with recorded evidence. A smaller baseline probe establishes only its exercised bridge capability. Full production header retirement additionally requires complete metadata, activity, actions, appearance, menus, input and migrated caller coverage as specified in the ownership design; the existing note/signature feeds do not supply all of these. At that gate, remove the replaced C++ header presenter and surface-specific push/pull transport, not merely rename them. Document transport, input delivery, mounting and oracle adapters each retire at their own replacement/caller gate, not automatically at the document ownership milestone.

Bridge defects belong in the shared integration and have a focused regression scenario. Do not compensate with surface-specific C++ presenter mirrors. A proposed workaround requires approval under repository rules. Keep any necessary bridge fixes cohesive and central; record upstream disposition and retest on upgrades.

Reference this document from the revised charter/task briefs instead of duplicating its requirements. Preserve single-authority keyboard, popup, text-entry, cancellation, undo and save behavior throughout the pivot.
