# QtBridge surface convention — spec

Normative target state for the Swift↔QML declaration surface. Companion to
[audit.md](audit.md) (evidence) and [plan.md](plan.md) (execution). Bridge
mechanism citations point into the pinned QtBridge checkout
(`407714006dd21107b70db6547ce75e43df0c8a75` + `qtbridge-object-return.patch`),
materialized at `.worktrees/swift-qml-grid/build/_deps/qtbridge-src/`; paths
below are relative to that root unless they start `src/` or `tools/` (repo
root). Requirements use RFC 2119. Every rule names the check that enforces it:
`B0/B1/B2` are guard checks (§4), lanes are `deno task` lanes.

## 1. Exposure semantics (ground truth)

`@QtBridgeable` exposes a class-body member iff ALL hold
(`Sources/QtBridgeMacros/Extensions.swift:41-43` `isValidForRegistration`;
`QtBridgeableMacro.swift:214-238`):

1. stored instance member (`var` **or** `let`), not computed, no source
   `didSet`;
2. access modifier is anything except the literal `private` keyword —
   `internal` (no modifier), `fileprivate`, `package` still expose
   (`Extensions.swift:35-39` checks only `.private`);
3. not annotated `@QtIgnored` (`QtBridgeableMacro.swift:221-223`);
4. the type annotation is one of (`Extensions.swift:115-121,139-194`):
   `Int`, `UInt`, `Double`, `Float`, `String`, `Bool`, `[String]` /
   `Array<String>`, `[String: QVariantSettable]` /
   `Dictionary<String, QVariantSettable>`, `QListModel<…>`, `QTableModel<…>`
   — **or** the member carries `@QtTracked` (any type then registers through
   `QVariantGettable` conformance).

Inferred types (`public var x = false`) never expose on their own: the type
gate is `bindings.first?.typeAnnotation` (`Extensions.swift:21-23`), and
registration also accepts `@QtTracked` regardless of a type annotation
(`QtBridgeableMacro.swift:259-262`). A
`@QtBridgeable`-class-typed property (incl. `Optional`) is **never
auto-exposed** — `@QtTracked` is required for it. `public private(set) var`
does not expose (`isPrivate` matches the `private` token;
`src/swift/app/SongTabsController.swift:133-134` documents the workaround).
Extension members never expose (class-body pass only).

Change emission: every exposed `var` gets `didSet { emitSignal(for:) }` —
identically whether `@QtTracked` was written or auto-attached
(`QtBridgeableMacro.swift:395-438`; explicit attribute short-circuits the
auto-attach at :407, single injection either way). Every exposure registers a
`<name>Changed` NOTIFY (`QMetaObjectBuilder.swift:204,274`;
`swiftmetaobjectbuilder.cpp:218-226`). Emissions are queued
(`Qt::QueuedConnection`, `swiftmetaobjectbuilder.cpp:295-306`): QML observes a
Swift write one event-loop turn later. Row-object mutation inside a
`QListModel` does **not** propagate; replace the row (audit §0.7,
integration-contract M0 table).

## 2. Normative declaration rules (Swift side)

- **R1 honest visibility.** A stored instance member of a `@QtBridgeable`
  class body that is not declared `private`, not computed, and has no source
  `didSet` MUST carry at least one of: an explicitly typed §1 supported
  type, `@QtTracked`, or `@QtIgnored`. A member with none of the three is
  silently unregistered (invisible to QML) even when spelled `public` — that
  is the violation. Inferred types are permitted when `@QtTracked` is
  present; adding the annotation to such a member is optional hygiene, not a
  requirement. Living offenders at plan time: 8 unannotated (2
  `EventListRowHandle` roles, 6 `AutomationPage` internals) and 16 members
  with a non-supported type, all in `AutomationPage.swift`; plus
  `AutomationHandles.primitiveName`, deleted with the ramp machinery.
  *Enforced: B1 `UNANNOTATED_MEMBER`, `UNTRACKED_CUSTOM_TYPE`.*
- **R2 macro-minimal tracking.** A member whose annotation is a §1 supported
  type MUST NOT carry `@QtTracked` (strict no-op, §1 — 78 removable today:
  65 in `src/swift`, 13 in check harnesses).
  `@QtTracked` is REQUIRED iff the member's type is not §1-supported and the
  member is QML-facing — in practice `@QtBridgeable` class references (13
  correctly annotated today), `Optional` thereof, and custom value types.
  *Enforced: B1 `REDUNDANT_TRACKED`, `UNTRACKED_CUSTOM_TYPE`.*
- **R3 intentional non-exposure.** A stored member that must not be
  QML-visible carries `@QtIgnored`. `@QtIgnored` MUST NOT appear on
  `private`/`private(set)` or `static` members, where access or static-ness
  already prevents registration (`isValidForRegistration` returns before the
  ignore check — `Extensions.swift:41-43`). On a non-private computed member
  or a member with `didSet` it is inert but permitted as documented intent.
  *Enforced: B1 `REDUNDANT_IGNORED`.*
- **R4 access.** QML-facing state is `public`. Setters that must be
  controller-only stay `public` with the ownership documented at the class
  (pattern: `src/swift/app/SongTabsController.swift:133-137`); `private(set)`
  hides the member from QML entirely.
- **R5 placement.** QML-facing members live in the class body, never in an
  `extension`. Non-QML helpers MAY live in extensions.
- **R6 one channel per observer domain.** QML observers get a `@QtSignal`;
  Swift-side observers get the presenter's closure hooks. An event MUST NOT
  be forwarded from a closure hook into a second signal nobody observes
  (the `DocumentWorkspace.Callbacks` → session-signal pattern this plan
  deletes). Every `@QtSignal` MUST have at least one observer (QML
  `on<Name>` handler in the scanned QML universe, or a Swift
  connection/subscription); every QML `on<Name>` handler over a bridged
  object MUST correspond to a signal that is emitted on some path.
  *Enforced: B2 `SIGNAL_NEVER_OBSERVED`, `HANDLER_NEVER_EMITTED`.*
- **R7 signal shape.** `@QtSignal` parameters MUST be §1 settable types
  (primitive/map/string-list; `QtBridgeableMacro.swift:479`). Handlers receive
  arguments positionally (`setParameterNames` is never called).
- **R8 returned objects.** A slot returning a `@QtBridgeable` object to QML
  MUST use the non-sugar optional form `Optional<T>` if nil is possible —
  sugar `T?` return types are **silently unregistered**
  (`Extensions.swift:123-125` + `QtBridgeableMacro.swift:188-191`). The Swift
  owner MUST retain returned objects for the QML lifetime (a QML `var` holds
  only the proxy; integration-contract M0 "Patched object return" row).
  *Enforced: B1 `SUGAR_OPTIONAL_RETURN`.*
- **R9 init discipline.** Never mutate tracked/published state from `init`
  of a `QmlInstantiableStatus` class; publish after the holder memoizes.
- **R10 equality.** `@QtTracked` emits on every write with no old/new
  comparison; heavy rebuilt state (variant maps) uses the existing
  `setPublished`/`matches` equality-gate pattern rather than per-write
  emission.

## 3. Normative QML rules

- **Q1 registration.** Every `src/ui/**/*.qml` MUST be reachable: listed in
  the `qt_add_qml_module(porydaw_app …)` QML_FILES block
  (`CMakeLists.txt:211-268`), loaded by a Swift `contentUrl`
  (`QmlEngineAccess.moduleResourcePrefix` → `qrc:/qt/qml/Porydaw/Ui/…`,
  `src/app/qml_engine_host.cpp:9-12`), or referenced by name from other
  reachable QML. *Enforced: B0 `UNREACHABLE_QML`.*
- **Q2 no duplicates.** Exactly one composition component per surface; check
  fixtures point at the production file, never a copy.
- **Q3 reachability model.** Swift objects reach QML as QML elements
  (`PorydawShellApp.instantiableTypes` = `[ShellPresenter, ApplicationSession]`,
  module `PorydawApp`, `src/swift/app/shell/PorydawShellApp.swift:16-18`) and
  by property/slot traversal from those roots
  (`src/ui/shell/ShellWindow.qml:26-29`). Context properties are not used;
  do not reintroduce them (finding H).
- **Q4 style keep.** Versionless Qt 6 imports; `Connections { function onX() {} }`;
  `required property` in delegates; `model.X` reads only inside delegates
  whose model resolves to a `QListModel`/`QTableModel` of a bridged row type
  (roles derive from registered property names — audit §0.7).

## 4. Guard contract

- **Artifact.** `tools/qtbridge_surface.ts` (Deno TypeScript, std only, no
  build dependency). It **shares the zero-dependency lexer routine
  (`skipElement`) with `tools/proof_anchor.ts`** for comment- and
  string-safe scanning rather than writing a third parser; the Swift
  declaration model and the QML reachability model are local to the guard.
  **Invocation.** `deno task verify:bridge` (read-only check) and
  `deno task bridge:baseline` (controller-owned `--update-baseline
  --allow-growth` regeneration) — new `Subcommand`s in `tools/cli.ts`
  (`:29-37` union, help + dispatch cases) + entries in `deno.json` `tasks`;
  additionally the check runs at the top of `runVerify()`
  (`tools/cli.ts:310`, before the build at `:365`) so every `verify*` lane
  gates on it without compiling first.
  Runs read-only analysis; exit 0/1. The script lands in `deno.json`'s
  `fmt`/`lint` include (`tools/**/*.ts`, `deno.json:22-27`), so the CI
  format job (`.github/workflows/build.yml:24`) covers it via
  `deno task format:check`.
- **Swift model (exact, not heuristic).** A line-oriented parser replicating
  §1: within `@QtBridgeable` class bodies, classify each stored member by
  annotation/attribute. The supported-type list is embedded as a constant
  mirroring `Extensions.swift:139-155` with the pin hash recorded beside it;
  a pin bump re-verifies it (plan risk R-3).
- **QML universe.** Module-registered = parse the `QML_FILES` block
  (`CMakeLists.txt:211-268`). Path-loaded = every
  `QmlEngineAccess.moduleResourcePrefix + "…"` literal in `src/swift`.
  Check-lane QML = `src/checks/**/*.qml` (fixtures/staging compositions).
  Name references resolve across all three plus `src/checks/**/*.swift`
  staging tables (e.g. `src/checks/editorqml/EditorQmlTests.swift:73-92`).
- **Checks.**
  - `B0 UNREACHABLE_QML`: a `src/ui` QML file neither registered,
    path-loaded, nor referenced by name (catches audit D).
  - `B1` exposure (rules R1-R3, R8): findings listed there.
  - `B2` signals (R6): `@QtSignal` declarations vs `on<Capitalized>` handlers
    in the QML universe vs Swift `connect`/`emit` sites (catches audit B,
    incl. `informationRequested`: handled, never emitted).
- **Failure policy.** Findings whose key (`<CHECK> <path> <detail>`, line
  numbers excluded so unrelated line shifts cannot break a lane) is not in
  the baseline fail the run (CI-grade). Baseline keys that no longer
  reproduce also fail (`STALE_BASELINE`), and `--update-baseline` refuses to
  add new keys unless `--allow-growth` is passed, so the baseline shrinks by
  construction rather than by discipline. Baseline file:
  `tools/qtbridge_surface_baseline.json`; `deno task bridge:baseline`
  (controller-owned at checkpoints) regenerates it, and implementers never
  hand-edit it. Verification-mode `deno task verify:bridge` runs read-only.
- **False-positive policy.** The guard reports only names it can resolve:
  element ids bound to `PorydawApp`/registered element types, `on<Name>`
  handlers, and source-syntax classifications. Unresolved identifiers
  (`property var` chains, dynamic strings) are out of scope and silent.
  Delegate-role reads (`model.X`) are **not** checked in this phase (chains
  pass through untyped `property var`, e.g. `AutomationPage.qml:346,349`) —
  R1 removes the silent-invisibility failure mode at the source instead.
  B2 errs toward silence on the observed side: a same-named `on<Name>`
  handler anywhere in the QML universe excuses a signal, so the guard cannot
  by itself prove a signal dead — the dead-signal inventory remains
  sweep-established, and `HANDLER_NEVER_EMITTED` only inspects
  `Connections { function onX() }` blocks whose target resolves.
  `SUGAR_OPTIONAL_RETURN` covers `public` slot functions returning an
  identifier type; internal helpers and composite returns (`[String]?`) are
  out of scope by design, and a pin bump is the trigger to revisit the
  syntactic model.
- **Ground-truth alternative (rejected for now).** A `porydaw_checks`
  harness dumping each class's runtime `QMetaObject`
  (`SwiftMetaObjectBuilder::metaObject()` is already public) would be exact
  across pin bumps but costs a patch hunk + harness + manifest staging; the
  syntactic model is exact while the pin holds. Revisit on any QtBridge pin
  change (plan risk R-3).

## 5. Deletion list (normative)

1. `src/ui/songview/quick/TimelineCanvas.qml` (643L),
   `DrawerChromeLayer.qml` (267L), `RulerControls.qml` (207L),
   `QuickPopupLayer.qml` (61L), `OtherStripToolTip.qml` (60L) — unregistered,
   unreferenced (audit D; re-verified by B0 after landing).
2. `src/ui/songview/quick/TrackHeaderBand.qml` (772L) — duplicate of
   `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml` (785L, the registered
   production file, `CMakeLists.txt:238`). The `track-headers` editorqml
   reference pane repoints to the production file
   (`src/checks/editorqml/EditorQmlTests.swift:89-91`).
3. Handler-less `@QtSignal`s and their dead plumbing (audit B; symbol table
   in brief 05): `aboutToReleaseGrid`, `addTrackRequested`,
   `gridContextMenuRequested` (+ `ApplicationSession.requestGridContextMenu`
   and its call at `EditorSurface.qml:118`), `headerContextMenuRequested`,
   `revealTrackVoiceRequested` (+ the `DocumentWorkspace.Callbacks`
   forwarding fields/wiring for the forwarded three), `rollFocusRequested`;
   plus the `informationRequested` signal-and-handler pair
   (`ShellPresenter.swift:406` / `ShellWindow.qml:222`). Presenter closure
   hooks (`onAddTrackRequested`, `onContextMenuRequested`,
   `onRevealTrackVoiceRequested`) STAY — they are the Swift-observer channel
   that checks bind directly.
4. `QmlEngineAccess.setContextProperty`
   (`src/swift/app/QmlEngineAccess.swift:16-18`) and
   `pd_qml_set_context_property` (`src/app/qml_engine_host.h:11`,
   `src/app/qml_engine_host.cpp:21-26`) — zero callers (audit H).
5. Unreachable ramp presentation machinery (audit G; evidence:
   `AutomationParameter.swift:195` sets `interpolation = .step` for every
   parameter, so `AutomationProjection.swift:301` never yields `.ramp` and
   `ramps` is always empty): the QML ramp `Repeater` and its `model.*`
   reads (`AutomationPage.qml:345-362`), `AutomationPage.ramps`
   (`AutomationPage.swift:140`), `syncRamps`
   (`AutomationOverlayPublication.swift:320-328`), the ramp publication
   branches (`AutomationContentPublication.swift:126,151,238,257-262`),
   the detach clear (`AutomationLifecycle.swift:41`), the
   `AutomationRampHandle` class (`AutomationHandles.swift:76-102`), and the
   never-called check helper `automationRampItems()`
   (`src/checks/editorqml/tst_EditorDrawer.qml:3187-3190`). `interpolation`
   (`AutomationParameter.swift:165`) is app-internal — never persisted to
   the document — and is deleted iff unread after the above (its only read
   is the projection branch). The `AutomationInterpolation` enum and
   `.ramp` math (`value(at:from:to:)`) STAY: live consumers at
   `AutomationDrawingTransactions.swift:108` and
   `src/checks/automation/domain/tst_automationdomain.swift:218`.

## 6. Deferred conventions (explicitly not this plan)

- Typed replacements for `[String: QVariantSettable]` maps (audit C): 93
  sites; requires bridged value types the pin lacks. Keep the
  `setPublished`/`matches` equality-gate pattern (R10). Revisit on pin bump.
- `property var` elimination in existing QML (audit F): convention for new
  code (prefer typed properties); no sweep.
- Pixel-lattice settings pages and `SongTabs` hit extents (audit E): visual
  redesign work, needs human-verified captures. `SongTabs.qml:64-70`
  documents its extents as deliberate C++-layout/Fusion-metric parity —
  changing them alters hit targets. In scope as a plan Direct task: the
  `#D88985` literal (`src/ui/shell/PolyphonyPanel.qml:212`, via a real
  `GridPalette` role). Also deferred: the `EventListPage`
  `defaultColumnWidths` duplication — the presenter is already the primary
  source (`EventListPage.qml:140-145` prefers `controller.savedColumnWidth`)
  and the QML array only serves the null-controller bootstrap edge; any
  dedupe changes transient pre-mount geometry for no agent-tax win. The
  `Qt.labs.qmlmodels` import is **rejected**, not deferred:
  `EventListPage.qml:984-993` genuinely uses `TableModel`/
  `TableModelColumn` and no stable replacement exists at this Qt pin.
- QML-side delegate-role checking (guard B3): see false-positive policy.

## 7. Acceptance mapping

| Rule | Enforced by |
|---|---|
| R1-R3, R8 | `deno task verify:bridge` (B1) |
| R6 | `deno task verify:bridge` (B2) |
| Q1, Q2 | `deno task verify:bridge` (B0) + `deno task verify:qml --verbose` (pane repoint) |
| R4, R5, R7, R9, R10, Q3, Q4 | review lens (spec sections cited in briefs) |
| Deletions §5 | lane matrix in plan.md §Verification |
