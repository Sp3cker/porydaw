# Qt/QML implementation audit — Porydaw Swift/QtBridge surface

Source: audit performed on branch `feature/swift-qml-grid` (base commit `1096534c`; the earlier
`3029be56` build break is already fixed on the branch). Worktree at audit time:
`.worktrees/swift-qml-grid`.

Scope of the audit: the Qt/QML *implementation* — QtBridge declaration usage in `src/swift/`,
production QML in `src/ui/`, and the check/proof surfaces that cover them. Not the Swift domain
migration as a whole.

## 0. Mechanism (verified against pinned bridge source)

QtBridge = `qt/qtbridge-swift`, pinned at `407714006dd21107b70db6547ce75e43df0c8a75`
(`cmake/QtBridge.cmake:21-29`), locally patched by
`src/ui/songview/quick/swiftroll/qtbridge-object-return.patch`. No generated files: a Swift
compiler plugin (`build/qtbridge_macros_ep/build/bin/QtBridgeMacros`) expands macros during
`swiftc`; `libQtBridgeCpp` builds each Swift class's `QMetaObject` at runtime via Qt's private
`QMetaObjectBuilder` behind a shared `QObjectProxyImpl`.

Declaration semantics (source: `build/_deps/qtbridge-src/Sources/QtBridgeMacros/QtBridgeableMacro.swift`
and `.../Extensions.swift`; C++ emitter `.../Sources/QtBridgeCpp/swiftmetaobjectbuilder.cpp`):

1. `@QtBridgeable` auto-exposes every **class-body** member that is public, non-static, stored
   (`var`/`let`), and has no source `didSet`. Exposure requires an explicit **supported type**:
   `Int`, `UInt`, `Double`, `Float`, `String`, `Bool`, `[String]`, `[String: QVariantSettable]`,
   `QListModel<…>`, `QTableModel<…>`, or a `@QtBridgeable` class / optional thereof.
2. Inferred types are invisible: `public var x = false` registers nothing and has no NOTIFY;
   `@QtTracked` forces registration and injects `didSet { emitSignal(for:) }`.
3. `public private(set) var` is NOT exposed (`isPrivate` matches the `private` token) — see the
   explanatory comment at `src/swift/app/SongTabsController.swift:133`.
4. Members declared in `extension`s are never exposed — see the comment blocks at
   `src/swift/app/drawer/velocity/VelocityPage.swift:24-28` and
   `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift:25-29`.
5. `@QtTracked` emits on **every** write; there is no old/new comparison on the Swift-write path,
   which is why drawer pages carry hand-written `setPublished` / `matches` equality helpers.
6. Signals are delivered `Qt::QueuedConnection` (`swiftmetaobjectbuilder.cpp:313`): QML observes
   Swift mutations one event-loop turn later. (`docs/plans/qtbridge-integration-contract.md`
   already documents this.)
7. `QAbstractListModel.bind` derives roles from **registered** property names, so an unexposed
   property is `undefined` inside a delegate.

## 1. Measured state

Counts from a scripted scan of `src/swift/**/*.swift` (class bodies directly following
`@QtBridgeable`; approximate, ±2):

| Metric | Count |
|---|---|
| `@QtBridgeable` classes | 53 |
| public stored `var`s in those classes | 824 |
| exposed to QML | 765 |
| — exposed via auto-tracked explicit type | 483 |
| — explicit `@QtTracked`, inferred type (required) | 197 |
| — explicit `@QtTracked`, custom type | 13 |
| — explicit `@QtTracked`, supported type (redundant) | 72 |
| not exposed | 59 |
| — custom/struct-typed public members | 35 |
| — inferred-type public members | 24 |
| `@QtIgnored` occurrences | 566 (526 on members of bridged classes; 156 of those are no-ops on `private`/`static`) |
| `@QtSignal` declarations | 22 |
| `[String: QVariantSettable]` occurrences | 93 across 22 files |
| production QML files | 56 |
| QML registered in the `Porydaw.Ui` module | 49 |

## 2. Findings

### A. Exposure drift (the working-memory tax)
24 public properties are invisible purely because their type was inferred, e.g.
`ApplicationSession.isDisposed` / `.hasReleased` / `.editorLanes` (`src/swift/app/ApplicationSession.swift:74,75,80`),
`MouseHints.windowActive` (`src/swift/app/MouseHints.swift:12`),
`ShellPresenter.closing` / `.closePending` (`src/swift/app/shell/ShellPresenter.swift:127,128`),
`EventListRowHandle.isEndOfTrack` / `.rowTint` (`src/swift/app/eventlist/EventListPresenter.swift:14,15`),
`AutomationRampHandle.primitiveName` (`src/swift/app/drawer/automation/AutomationHandles.swift:83`).
`AutomationRampHandle.primitiveName` is *read by QML* at
`src/ui/songview/quick/drawer/AutomationPage.qml:351` (`objectName: model.primitiveName`) — that read
is on a currently unreachable path (see finding G), which is the only reason it has not surfaced.
No compiler, lint, check, or proof ledger can currently answer "is this member QML-visible?"; that
is what agents must hold in working memory.

### B. Dead / duplicated notification channels
`@QtSignal`s emitted with no handler anywhere (Swift, QML, or check lanes):
`aboutToReleaseGrid` (`src/swift/app/ApplicationSession.swift:492`), `addTrackRequested`,
`gridContextMenuRequested`, `headerContextMenuRequested`, `revealTrackVoiceRequested`,
`rollFocusRequested`. `informationRequested` is handled in `src/ui/shell/ShellWindow.qml` but never
emitted. For several of them the same *event* also travels a second channel
(Swift closure → `DocumentWorkspace.Callbacks` → session signal) while the live path is the
presenter's own signal (`TrackHeadersPresenter.contextMenuRequested` →
`src/ui/songview/quick/editor/EditorSurface.qml:128`). The repo's own rule is one observer per
event, no second dispatcher.

### C. Untyped variant maps
93 `[String: QVariantSettable]` properties (rects, fonts, appearance bundles): a typo becomes a
silent `undefined` in QML, and four surfaces each hand-roll `rectMatches` / `fontMatches` because
the maps are not `Equatable` (so `@QtTracked` would otherwise emit on every rebuild).

### D. Dead QML weight
Unregistered in `Porydaw.Ui` and referenced by nothing (verified by name sweep across `src/`):
`src/ui/songview/quick/TimelineCanvas.qml` (643L), `.../DrawerChromeLayer.qml` (267L),
`.../RulerControls.qml` (207L), `.../QuickPopupLayer.qml` (61L), `.../OtherStripToolTip.qml`
(60L) ≈ 1238 lines. Separately `src/ui/songview/quick/TrackHeaderBand.qml` (772L) duplicates
`src/ui/songview/quick/swiftroll/TrackHeaderBand.qml` (785L); the `quick/` copy survives only as an
`editorqml` fixture (`src/checks/editorqml/EditorQmlTests.swift:90`).

### E. QML geometry / contrast rule violations
`AGENTS.md` requires font-derived geometry and the palette/text-contrast rule:
`src/ui/songview/quick/drawer/settings/SongSettingsPage.qml:30,60,78,98,118,134` and
`.../settings/EngineSettingsPage.qml:35,55,73` build a hand-rolled pixel lattice
(`y: 101 + 54 * (page.unit - 1)`); `src/ui/songview/quick/swiftroll/SongTabs.qml:67-68` hard-codes
`closeExtent: 20` / `scrollExtent: 16` (comment admits they mirror C++ Fusion metrics) while
neighbouring lines derive from `applicationFont.pixelSize`; `.../eventlist/EventListPage.qml:23`
duplicates `EventListPresenter.columnWidths`; `.../drawer/PolyphonyPanel.qml:212` hard-codes
`"#D88985"`.

### F. QML typing nits
`Qt.labs.qmlmodels` import (`.../eventlist/EventListPage.qml:2`); 28 `property var` in
`.../drawer/AutomationPage.qml`; `property var` where a typed property works elsewhere.

### G. Unreachable machinery (decide: delete or bridge)
Every automation parameter currently sets `interpolation = .step`
(`src/swift/core/…/AutomationParameter.swift:195`), so the ramp path is unreachable: the
`AutomationRampHandle` QML reads, the `ramps` model, the QML Repeater, and the check helper
`automationRampItems()` (never called) are unexercised. The dead check helper is why finding A's
QML read went unnoticed.

### H. Unused native seam
`QmlEngineAccess.setContextProperty` + `pd_qml_set_context_property` have zero callers
(a Qt 6-discouraged pattern).

### I. Documentation placement
The only document describing mechanism/lifetime/update contracts is
`docs/plans/qtbridge-integration-contract.md`; it lives under `docs/plans/` (not agent-loaded),
its ownership table is still C++-era (`RewriteWindow`), and the agent-facing rules
(`AGENTS.md`, `.omp/rules/`) say nothing about QtBridge declarations.

### J. Clean axes (keep)
Versionless Qt 6 imports; `Connections { function onX() }` syntax; `required property` in
delegates; `@MainActor` on 100% of bridged classes; primitive-only signal parameters.

## 3. Proposal under evaluation

1. Add an agent-loaded rule file (e.g. `.omp/rules/qtbridge-surface.md`) stating: exposure requires
   a supported type annotation; `@QtTracked` only for custom/inferred types; `@QtIgnored` for public
   non-QML members (private members need none); one channel per event; single owner for QML-facing
   state; never mutate tracked state from `init` of a `QmlInstantiableStatus` class (lazy
   `objectHolder` memoization).
2. Add a mechanical bridge-surface guard (script or check) that cross-references QML property reads
   and `onX` handlers against registered properties and `@QtSignal`s — replacing the invisible-rule
   reasoning behind findings A and B.
3. Normalize the 24 inferred-type public members (annotate, or `@QtIgnored`).
4. Delete dead weight: the 5 unregistered QML files; the duplicate `TrackHeaderBand`; the 6
   handler-less signals; the unused context-property seam; and either delete the unreachable ramp
   machinery or bridge it deliberately.
5. Reconcile `docs/plans/qtbridge-integration-contract.md` with the Swift shell (or supersede it).

Open decisions: (a) ramp machinery — delete or bridge; (b) `@QtTracked` convention — minimal
(macro-native, fewer annotations) or explicit-everywhere; (c) delete the ~1238 dead QML lines;
(d) whether the guard is a Deno script, a `porydaw_checks` harness, or both.
