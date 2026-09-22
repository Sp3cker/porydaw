# Swift Rewrite Guidelines

How C++ widget surfaces are being rewritten as Swift + QML in this repo. Written
during the editor-drawer refactor (`docs/plans/reactive-drawer-refactor.md` is the
worked example). Follow this when rewriting `roll/`, `headers/`, or any other
QML-backed surface.

## The architecture

Unidirectional, synchronous, boring:

```
QML event → decode once at the Qt seam → reduce(&state, event) → [effects]
          → execute effects (document/camera/selection) → publish(state) → QML
```

- **No reactive framework.** No RxSwift/Combine/TCA. The flow is synchronous and
  `@MainActor`-confined; a `Subject → scan → subscribe` pipeline wraps three
  function calls in subscription machinery without deleting the reducer, the
  scene build, or the Qt adapter. Revisit only if a real multi-stream async
  requirement appears (audio telemetry is the candidate).
- **No app-wide store.** Each surface owns its state locally. `DocumentSession`
  stays the owner of document, selection, camera, and history.

## File organization: behavioral names, kept

Files are named by responsibility, and that convention is preserved through the
refactor — do not rename to `State.swift`/`Store.swift`/`Effects.swift`:

| File | Owns |
|---|---|
| `XPage.swift` | Qt-facing object: `@QtBridgeable` class-body members, published properties, decode+send+return methods, effect execution |
| `XInteraction.swift` | The reducer: state struct, event enum, transition/effect types, `reduce`. Pure — no Qt objects, session, clock, or native fonts |
| `XScene.swift` | Pure value scene: what gets drawn, as plain `Equatable`/`Sendable` structs |
| `XProjection.swift` | Pure geometry and hit-testing over scene values |
| `XPublication.swift` | The single publish pass: reconcile state/scene into published primitives + item models |
| `XTransactions.swift` | Frozen gesture arithmetic, semantic mutation drafts, document-effect application |
| `XContext.swift` / `XAxis.swift` | Domain policy values (maps, detents, context resolution) |

Shared seams live one level up (`drawer/DrawerInput.swift`,
`drawer/DrawerSceneValues.swift`): Qt button/modifier decode happens **once**,
plain rect/text/metric descriptors are shared across domains.

## Purity rules — the actual point

- Scene and state types contain **zero** Qt objects, session references, native
  font handles, or QVariant dictionaries. If a "value" type holds a
  `@MainActor` handle, it is lying — fix it.
- Native text measurement is a real external dependency. Measure in the adapter,
  cache the metrics, feed immutable values to the builder. Never guess character
  widths to make a builder "pure."
- Frozen gesture captures stay: a gesture needs press-time note values, per-note
  maps, and revision even when live facts change. Value state does not eliminate
  temporal capture — it makes it explicit (one capture inside the gesture case,
  not parallel `gesture`/`frozen`/`frozenCamera` fields).

## Publication invariants

1. The reducer never writes a Qt property; the publisher never changes domain
   state, selection, document, camera, or audition state.
2. Scalar equality guards before assignment — QtBridge emits signals in `didSet`
   with no equality check, so equal writes are not free.
3. Compare **plain row descriptors before allocating bridged rows**. Use the
   `QListModelSync` value-row overload; keep `QListModel` instances stable;
   changed rows get `model[index]` writes, appear/disappear rows get
   insert/remove signals. Never suppress structural notifications because
   surviving scalars are equal.
4. Publish dependent data before activation flags: prompt fields before opening,
   model rows before indexes that refer to them, focus target before focus
   revision.
5. Keep a dependency-keyed scene cache — static content, camera projection,
   interaction rows, transient/readout blocks invalidate separately. "One
   publish" never means "rebuild everything per mouse move."

## Reentrancy

`DocumentSession` effects (`setSelectedNotes`, `mutateCamera`) invoke callbacks
**synchronously** — a release can trigger document refresh before the outer
handler returns. Therefore: install reduced state before executing effects; use
an outer-dispatch depth guard so reentrant callbacks ingest facts but only the
outermost dispatch publishes; never publish a saved pre-effect scene.

## The oracle: C++ + proof ledgers

- `src/ui/editordrawer/` (and the C++ surface being replaced) plus
  `src/checks/**/proof.*.txt` are the spec. Each `A###` entry is one pinned
  assertion site with a source hash.
- Update dispositions only for genuinely satisfied assertions. **Never bulk-mark
  MATCHED** because a similarly named Swift scenario passes — method names lie
  (`clickBelowSelectedNodeChangesOnlySelection` commits a velocity change).
- Native assertions (mouse-grabber, focus, raster, real input) stay native.
  Pure reduce/build tests cover what they can; they do not authorize deleting
  C++ checks.
- Existing Swift behavior is not authoritative where its proof entry is
  GAP/PARTIAL — the C++ is.

## Design rules

- **Correct member visibility over check satisfaction.** Check files use
  `@testable import PorydawApp`; never widen production access, add getters, or
  reshape a type because a test can't reach it. Reworked code is not written to
  be tested — it is written to be right; tests adapt through `@testable`.
- **Complexity gate.** If the refactor is becoming more complicated or verbose
  than the code it replaces — more layers, more boilerplate, event factories —
  stop. Partial adoption is a valid outcome (the container keeps named mutating
  methods; no event enum was forced on it).
- **Clean cutover.** Migrate every caller; delete the old dispatch methods, Qt
  bit-mask enums, and snapshot wrappers. No compat shims.
- **Synchronous semantics are the contract.** Consumed vs accepted vs committed
  are distinct outcomes; do not collapse them into `effects.isEmpty`.

## Swift 6.4 performance

- `borrowing`/`consuming` parameter ownership on hot paths to avoid COW copies.
- `Sendable` value types throughout the pure layer.
- No avoidable allocation or copying in per-pointer-move paths: scene builds,
  hit tests, and publish diffs run per mouse event.
- `Span`/`InlineArray` where they genuinely fit fixed scene rows; do not contort
  code to use a feature.
- Array COW avoids eager copies but does not make repeated mutation of shared
  arrays free — reuse storage where straightforward, without retaining whole
  historic scenes to look functional.

## What does NOT get this treatment

- **Timeline policy** (`EditorCamera`, `PitchProjection`, `GridGeometry`,
  `TimelineSnapPolicy`) — already value types with named operations. Do not wrap
  them in event enums for consistency.
- **`SharedPlayhead`** — already the exemplar: pure policy + one imperative
  owner + equality-guarded apply. Copy it, don't refactor it.
- **Commands** (`EditKeyArbiter`, `NoteCommands`) — already pure functions /
  discrete effect boundaries.
- **Audio** (`AudioRenderEngine`, `AudioTimelineHandoff`, `NativeAudio`) —
  realtime engine with preallocated buffers and pointer handoff. No scene
  building, model diffing, or subscriptions in the render path. Ever.

## Process

- Work happens in a dedicated worktree (`deno task worktree:create`, or manual
  `git worktree add` + nested submodule init when the base's poryaaaa SHA
  differs from the main checkout's).
- Agents edit; the orchestrator builds, runs `deno task verify` /
  `verify:qml`, and formats. Agents never run gates.
- Commit at each green milestone with a phase-naming message; never commit red.
- New production files: the implementing agent reports them; CMakeLists
  registration is serialized through one owner per wave to avoid merge
  contention.
