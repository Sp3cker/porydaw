# Editor Drawer Swift refactor handoff

Updated: 2026-09-21

## Objective

Refactor the production Swift Editor Drawer into smaller, cohesive files so an
agent can work on one behavior without loading the entire drawer implementation.
The practical goal is lower working-memory use and lower cost per task while
preserving the current product behavior, QML contract, and test observations.

Do the structural refactor first. Close C++ parity gaps with new Swift checks in
a later phase. Mixing those two kinds of change makes failures difficult to
attribute and defeats the purpose of establishing a reliable proof ledger.

## Intended checkout and current state

Use this checkout unless the user explicitly redirects the task:

```text
/Users/spencer/dev/cProjects/porydaw/.worktrees/swift-qml-grid
branch: feature/swift-qml-grid
migration integration commit: 682095474e862b90227de941d9a0a5b29ad5926c
```

The mixed migration was committed at the revision above. Recheck branch, HEAD,
status, and upstream before editing because later metadata commits or new work
may exist. The local `.scratch/` directory contains review artifacts and is not
part of the migration. If a separate worktree is requested, create it with the
repository task:

```text
deno task worktree:create -- editor-drawer-refactor --base feature/swift-qml-grid
```

Base the new worktree on the current remote branch, which contains the migration
and hardened proof files. Do not base it on the older pre-integration commit.

## Verified baseline

The focused Swift check lane passes on the current filesystem:

```text
deno task verify --filter swiftcore --verbose
build: ok (10.45s)
swiftcore: ok (8.17s)
verify: 1/24 ok, 23 skipped
```

The dedicated QML lane builds but is not yet a green refactor gate:

```text
deno task verify:qml --verbose
build: ok (11.58s)
editorqml-drawer: 38 passed, 2 failed, 11 skipped
```

Both failures are the existing numeric-field window-shortcut rows:

```text
test_numericFieldWindowShortcutPriority(velocity)
test_numericFieldWindowShortcutPriority(automation)
expected Space-trigger count 1, actual 0
src/checks/editorqml/tst_EditorDrawer.qml:132
```

The earlier drawer parity handoff calls these rows deferred. The next session
must inspect and resolve their root cause before treating the QML lane as a hard
green refactor gate. Do not skip, weaken, or special-case them as a refactor
workaround. They protect the repository rule that window-level shortcuts outrank
focused persistent drawer chrome.

The full registered suite passed 24/24 before the latest proof-only hardening.
A later full run had transient native-window failures in `swiftrollgated` and
`selectionkey`; one focused retry passed both. Avoid repeatedly stress-testing
desktop-input checks while the user is using the desktop.

## Hardened proof ledger

The five current drawer proof files have complete headers, current Swift hashes,
and an exact `S###` index for every remaining `MATCHED` entry:

| Proof | Sites | MATCHED | PARTIAL | GAP | NATIVE | NATIVE-SETUP |
|---|---:|---:|---:|---:|---:|---:|
| `proof.drawer.txt` | 178 | 0 | 0 | 176 | 0 | 2 |
| `proof.velocity.txt` | 125 | 0 | 0 | 123 | 0 | 2 |
| `proof.voice.txt` | 148 | 10 | 15 | 121 | 0 | 2 |
| `proof.voicemenus.txt` | 84 | 0 | 29 | 54 | 0 | 1 |
| `proof.valueprompt.txt` | 103 | 0 | 41 | 28 | 34 | 0 |
| **Total** | **638** | **10** | **85** | **502** | **34** | **7** |

These files are a static correspondence ledger. They do not run and Swift tests
do not literally “pass the proof files.” A proof site becomes `MATCHED` only when
a Swift check executes the original fixture, sequence, and predicate and the
proof cites that exact predicate with an `S###` entry.

The entire drawer source set is now accounted for: the `qFatal` failure sites
at `src/checks/drawerpresentation/fixtures.cpp` lines 128 and 135 carry
`NATIVE-SETUP` entries or a written exclusion rationale in every proof whose
scenarios consume the shared `createVoiceFixture` helpers.

During the production-only refactor, leave proof dispositions unchanged. The
proofs hash Swift check files, not production files, so a production file move
does not require proof hash churn. If check files are reorganized later, update
their proof paths, line anchors, and hashes in the same focused change.

## Architectural boundary to preserve

`EditorDrawerPresenter` owns the container-facing bridge and delegates policy to
the pure `EditorDrawerLayout` value. `EditorDrawerPage` is the Swift page seam.
`DocumentWorkspace` owns one `VelocityPage`, `VoiceChangesPage`, and
`AutomationPage` per document and attaches them to the presenter.
`ApplicationSession` exposes those stable objects to QML.

The three page classes are `@QtBridgeable`. The macro registers only members
declared in the class body. Keep every QML-visible property, signal, and callable
entry point in the class declaration. Non-bridge implementation can live in
same-module extensions and helper value types. Do not introduce extra bridge
objects or change the QML API merely to reduce line counts.

Preserve these invariants:

- QML URLs, property names, method names, signals, object names, and raw enum
  values remain stable.
- A page attaches before its first document publication and cancels
  synchronously before its document or callback owners retire.
- Hiding, replacing, or globally cancelling a section ends its interaction
  before the new layout is published.
- Gesture, picker, prompt, and menu targets retain their captured document
  revision and identity; camera movement or later selection must not retarget
  them.
- `EditorDrawerLayout` remains the only owner of stacking, clamping, resize,
  focus, and preference policy. The presenter only publishes its change set.
- The shared playhead remains composition-owned. Drawer pages consume its
  publication and never create another clock or QML-to-Swift mutation path.
- Persistent QML chrome does not claim bare `Space`. `Enter`/`Return`, pointer
  activation, and accessibility press remain the local activation paths.
- `NATIVE` proof obligations stay native. A model or presenter assertion is not
  evidence for focus, pointer delivery, window routing, or raster output.

## Structural reference: the retired C++ drawer

The refactor should recover the old drawer's proven **module shape**, expressed
idiomatically in Swift. The legacy implementation is more than a behavioral
oracle: its ownership boundaries are the starting architecture unless the
current Swift/QML boundary gives a concrete reason to differ.

Use these legacy seams as the map:

| Legacy owner | Responsibility to preserve in Swift |
|---|---|
| `EditorDrawer` | Thin composition and publication owner |
| `DrawerSections` | Section availability, visibility, stacking, body geometry, resize and active-page policy |
| `DrawerChrome` | Toggle/handle/detent presentation and chrome interaction |
| `VelocityArea`, `velocityarea_interaction.cpp`, `VelocityAxis` | Velocity page coordination, gesture state and value-axis policy as separate concerns |
| `VoiceChangeArea`, `voicechangemenu.cpp` | Voice projection/interaction separated from captured menu transactions |
| `AutomationPage`, `AutomationViewModel`, `AutomationProjection` | Page coordination, document-derived lane state and coordinate projection |
| `CCLanes`, `TempoLane`, `nodelane/*` | Lane policy plus small gesture, hover, pencil and batch-commit modules |

The intended Swift correspondence is:

- `EditorDrawerPresenter` remains the thin composition/publication owner.
- `EditorDrawerLayout` owns the `DrawerSections` state machine; chrome input may
  call it, but may not acquire a second copy of layout or preference policy.
- Each page class remains the stable QML seam corresponding to its old area or
  page owner.
- `Scene` and `Projection` values replace painting/view-model calculations; they
  should not absorb transactions or interaction lifetime.
- `Interaction`, `Transactions`, modal/menu, and policy files correspond to the
  old focused gesture and lane modules instead of being folded back into a giant
  page class.

Do not reproduce QObject/QWidget plumbing, paint-event structure, headers paired
one-for-one with implementations, or the exact C++ class graph. QML now owns the
declarative surface and `@QtBridgeable` imposes a Swift-specific class-body seam.
The goal is the old drawer's separation of policy, projection, interaction,
transactions and composition, not a transliteration of C++ syntax.

Before each page slice, inspect its legacy owner and record a short old-to-new
responsibility map in the working notes. A move is successful when an agent can
change one responsibility by loading the page shell plus one focused module,
without reading every drawer source file.

## Current size and concentration

The largest production Swift files are:

| File | Lines | Main responsibility |
|---|---:|---|
| `automation/AutomationScene.swift` | 1,037 | scene resolution, publication, bridge row types |
| `automation/AutomationProjection.swift` | 1,001 | parameter vocabulary, lane snapshots, projection, rows |
| `automation/AutomationPage.swift` | 951 | bridge surface, page state, lifecycle and command entry points |
| `voicechanges/VoiceChangesPage.swift` | 841 | bridge surface, lifecycle and publication |
| `velocity/VelocityPage.swift` | 819 | bridge surface, lifecycle and publication |
| `EditorDrawerLayout.swift` | 811 | public records plus the pure container state machine |
| `automation/AutomationInteraction.swift` | 695 | pointer and gesture dispatch |
| `velocity/VelocityScene.swift` | 635 | pure scene values and row construction |

The existing directory already has useful seams for policy, transactions,
interaction, projection, and scene construction. Extend those seams instead of
inventing a new framework or a generic drawer-page base class.

## Refactor sequence

Each phase is behavior-preserving. Keep a phase reviewable and green before
starting the next one.

### Phase 0: stabilize the baseline

1. Recheck branch, HEAD, status, and active writers.
2. Add a proof or exclusion rationale for the two fixture `qFatal` sites.
3. Diagnose the two numeric-field `Space` failures and make `verify:qml` green
   with a root-cause fix. This is not permission to add forwarding, a second
   shortcut dispatcher, focus memory, or a QML `Space` handler.
4. Record a scoped diff before moving production code so concurrent drawer
   changes are not overwritten.

### Phase 1: split the container records from the state machine

Create `src/swift/app/drawer/EditorDrawerTypes.swift` containing the cohesive
public value vocabulary currently at the front of `EditorDrawerLayout.swift`:

- `DrawerSectionKind`
- `EditorDrawerMetrics`
- `EditorDrawerSectionGeometry`
- `EditorDrawerSnapshot`
- `EditorDrawerFocusRequest`
- `EditorDrawerSectionPreference`
- `EditorDrawerChangeSet`

Keep `EditorDrawerLayout.swift` focused on the mutable pure layout state machine,
including its private storage and resolution helpers. Keep
`EditorDrawer.swift` as the page protocol, bridged section state, and presenter.
Add the new source to `src/swift/app/CMakeLists.txt` next to the other drawer
container files.

This is the smallest low-risk slice and establishes the move/build/review
workflow before touching page state.

### Phase 2: establish the page-shell pattern with Velocity

Keep `VelocityPage.swift` as the `@QtBridgeable` shell:

- published QML properties and models
- owned page state
- initializer and attach/detach boundary
- every QML-callable method as a class-body forwarding method

Move non-bridge content construction and publication helpers into one cohesive
`VelocityPublication.swift` extension. Candidate methods are the content rebuild,
scene-input construction, axis/handle publication, model synchronization,
typography/cache resolution, and readout publication currently below the
class-body input forwarders.

Do not create a second state owner. Prefer moving existing methods over wrapping
each property in another abstraction. Some `private` helpers may need to become
module-internal so a same-module extension can use them; keep that widening to
the minimum and do not make them `public`.

`VelocityInteraction.swift`, `VelocityTransactions.swift`,
`VelocityProjection.swift`, `VelocityContext.swift`, and `VelocityAxis.swift`
already have coherent responsibilities. Leave them alone unless the move proves
a concrete ownership problem. `VelocityScene.swift` is slightly over the review
threshold; split it only if scene construction and scene-value helpers form two
clear 200–400 line concepts after the page move.

### Phase 3: apply the pattern to Voice Changes

Keep `VoiceChangesPage.swift` as the bridged property/entry-point shell. Move its
non-bridge refresh, scene input, publication, and model synchronization methods
to `VoiceChangesPublication.swift` or a comparably named single cohesive file.

Retain the existing boundaries:

- `VoiceLanePolicy.swift`: program/context policy
- `VoiceChangesTransactions.swift`: captured mutations
- `VoiceChangesInteraction.swift`: input and modal dispatch
- `VoiceChangesScene.swift`: scene values and construction
- `VoiceChangesProjection.swift`: bridge row types and projection

Do not alter occurrence identity, stale-document rejection, picker capture,
audition release, or menu-target lifetime while moving code.

### Phase 4: split the two Automation catch-alls

Split `AutomationProjection.swift` by its existing `MARK` boundaries:

- `AutomationParameter.swift`: parameter identity, catalog, metadata and prompt
  conversion
- `AutomationLaneProjection.swift`: lane points, identities, snapshots,
  selection and display-row stack
- `AutomationProjection.swift`: geometry, snapping and the projection engine

Aim for roughly 250–400 lines per file. Do not create one file per small record.

Split `AutomationScene.swift` along its existing responsibilities:

- retain scene input/snapshot/resolution values in `AutomationScene.swift`
- move content and curve/node publication to
  `AutomationContentPublication.swift`
- move overlays, prompts, menus, typography and model synchronization to
  `AutomationOverlayPublication.swift`
- move the four bridged row/handle types to `AutomationHandles.swift`

Then reduce `AutomationPage.swift` only where non-bridge lifecycle and rebuild
methods can move cleanly into an extension such as `AutomationLifecycle.swift`.
Keep QML-callable command methods in the class body. A larger cohesive bridge
shell is preferable to a new coordinator or split bridge surface.

Keep the existing transaction, edit, modal, selection, interaction, and tap
tempo files intact unless a concrete dependency exposed by these moves demands
a surgical correction.

### Phase 5: restructure checks only after production is stable

The largest Swift check files are `drawerpresentation/voice.swift` (1,268 lines)
and `drawerpresentation/drawer.swift` (769 lines). Splitting them can further
reduce task context, but it invalidates proof paths, hashes, and `S###` line
anchors. Do it as a separate change after the production refactor passes.

Split checks by original scenario groups, update `src/checks/CMakeLists.txt`, and
refresh every affected proof in the same change. Do not change a disposition
solely because a predicate moved.

## Parity closure after the refactor

Once structure is stable, use the hardened proofs as a backlog in vertical
slices:

1. Pick one original scenario, not an entire proof file.
2. Add a Swift assertion that initially exposes the missing predicate.
3. Make it pass through production Swift without test-only production hooks.
4. Run the focused check and relevant QML/native lane.
5. Change only the covered `GAP`/`PARTIAL` entries to `MATCHED`, add exact
   `S###` links, and refresh the Swift check hash.

Suggested order is container layout, Velocity model/transactions, Voice Changes
model/transactions, voice menus, then automation. Leave native focus, pointer,
window-routing, and raster obligations in their native lanes.

## Verification cadence

Use repository tasks only; do not invoke CMake directly.

For a mechanical file move or source-list edit:

```text
deno task build:app
deno task lsp:swift
git diff --check
```

At the end of every coherent refactor phase:

```text
deno task verify --filter swiftcore --verbose
deno task verify:qml --verbose
```

After all structural phases:

```text
deno task verify --verbose
deno task lsp:swift
git diff --check
```

Do not run the full suite after every file move. Use the fast application build
while moving code, the focused Swift/QML gates at phase boundaries, and one full
registered-suite gate at the end. Do not repeatedly rerun desktop-input failures
while the user is active on the desktop.

## Completion criteria

The refactor is complete when:

- each file has one discoverable responsibility; most implementation files are
  200–400 lines and anything over 600 has a documented bridge or cohesion reason
- no tiny fragments or single-use abstraction layer was introduced
- the QML-visible API, URLs, raw values, ownership and cancellation order are
  unchanged
- production behavior and proof dispositions are unchanged by the structural
  phase
- `swiftcore`, the QML drawer lane, the full registered suite, Swift indexing,
  and `git diff --check` pass
- changed files are scoped, reviewed, committed, and pushed without absorbing
  unrelated migration work

Do not delete a C++ check after this refactor. Retirement requires its proof to
have no unresolved `GAP` or `PARTIAL` site and requires native obligations to
remain covered by an appropriate native or external production-app journey.
