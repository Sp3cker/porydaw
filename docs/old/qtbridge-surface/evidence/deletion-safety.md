# Deletion-safety evidence (managed-scout, read-only)

Source: `DeadWeightEvidence` scout run against `feature/qtbridge-surface-cleanup` @ `1096534c`.
Review-gate caveat: the scout's independent fact-check step failed on an external quota limit (402),
so the controller re-checked the load-bearing items below directly before they were relied on.

## 1. Unregistered QML cluster — verdicts

| File | Lines | In-`src/` references | Registered in CMake | Staged by a lane | Other branches | Verdict |
|---|---|---|---|---|---|---|
| `src/ui/songview/quick/TimelineCanvas.qml` | 643 | `EventListPage.qml:26` (comment), proof ledgers `themelayout/proof.tst_themelayout_settings.txt:161` | no | no | identical copy on `feature/swift-qml-grid-rollqml-checks`, `feature/swift-keybindings`, `feature/swift-project-store`; `fork-main` holds the legacy 732L C++-era version registered at its `CMakeLists.txt:540` | SAFE TO DELETE |
| `src/ui/songview/quick/DrawerChromeLayer.qml` | 267 | `TimelineCanvas.qml:636` only | no | no | identical on the three sibling branches; `fork-main` has the 518L pre-cutover version (`CMakeLists.txt:546`) | SAFE TO DELETE |
| `src/ui/songview/quick/RulerControls.qml` | 207 | `TimelineCanvas.qml:233` only, proof ledgers `automation/proof.automationpointmenus.txt:784`, `automation/proof.ccdeleteconfirmation.txt:856`, `visual/proof.quick.txt:50` | no | no | identical on the three sibling branches; `fork-main` same 207L (`CMakeLists.txt:543`) | SAFE TO DELETE |
| `src/ui/songview/quick/QuickPopupLayer.qml` | 61 | none anywhere under `src/` | no | no | identical on the three sibling branches; `fork-main` same 61L (`CMakeLists.txt:549`) | SAFE TO DELETE |
| `src/ui/songview/quick/OtherStripToolTip.qml` | 60 | `TimelineCanvas.qml:562` only | no | no | identical on the three sibling branches; `fork-main` same 60L (`CMakeLists.txt:547`) | SAFE TO DELETE |

No branch or worktree carries newer work on any of the five; `docs/` hits are retired plans under
`docs/old/` plus historical briefs.

**Consequence the brief must handle:** four proof-ledger *comments* explain GAP rows by naming
`TimelineCanvas.qml` / `RulerControls.qml` as the unmounted host. Deleting the QML makes those
comments stale, so the deletion brief owns a ledger-row wording update
(`src/checks/themelayout/proof.tst_themelayout_settings.txt`,
`src/checks/automation/proof.automationpointmenus.txt`,
`src/checks/automation/proof.ccdeleteconfirmation.txt`,
`src/checks/visual/proof.quick.txt`) — ledger ownership per `.omp/rules/ledger-delegation.md`.

## 2. `quick/TrackHeaderBand.qml` duplicate

- Registered: `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml` (`CMakeLists.txt:239`).
  Not registered: `src/ui/songview/quick/TrackHeaderBand.qml`.
- `src/checks/editorqml/tst_EditorDrawer.qml:155` instantiates `EditorSurface {}`
  (`swiftroll/EditorSurface.qml:150` → `TrackHeaderBand {}`), so the lane already renders the
  swiftroll copy through QML same-directory import precedence.
- The `quick/` copy is referenced only as a string literal in
  `src/checks/editorqml/EditorQmlTests.swift:90` (`ReferencePaneIdentity(component:)`), compared
  against run metadata at `EditorQmlTests.swift:415`.
- Diff: 14 insertions / 1 deletion (772L vs 785L). Substantive: the swiftroll copy adds
  `import Porydaw.Ui` and routes pointer/hover through `MoveCoalescer` (`headerMoves.enqueue` +
  flush on pressed/released/doubleClicked/canceled/exited); the `quick/` copy dispatches
  `headersModel.updatePointer` / `updateHover` uncoalesced on every `onPositionChanged`.
- Identical interfaces: `bandRect` (rect), `bandVisible` (bool), `model` (TrackHeadersPresenter),
  `controlFont` (font); identical drawn root `objectName: "timelineQuickTrackHeaders"`.
- Verdict: `quick/TrackHeaderBand.qml` SAFE TO DELETE once `EditorQmlTests.swift:90` points at the
  swiftroll path (no harness or visual-fixture change needed). Check-source edit ⇒ ledger check per
  `.omp/rules/ledger-delegation.md`.

## 3. Signal inventory (all audit claims CONFIRMED)

| Signal | Declared | Emitted | Handlers | Live channel today |
|---|---|---|---|---|
| `aboutToReleaseGrid` | `ApplicationSession.swift:499` | `:565` in `dispose()` | none | none (teardown is synchronous) |
| `addTrackRequested` | `ApplicationSession.swift:511` | `:957` via `DocumentWorkspace.Callbacks` | none | none (C++ add-track never ported) |
| `gridContextMenuRequested` | `ApplicationSession.swift:504` | `:501` in `requestGridContextMenu` | none | `SwiftGridHost.contextMenuRequested` → `EditorSurface.qml:117-123` → `contextMenuAt` |
| `headerContextMenuRequested` | `ApplicationSession.swift:510` | `:965` via `Callbacks` | none | `TrackHeadersPresenter.contextMenuRequested` → `EditorSurface.qml:126-130` |
| `revealTrackVoiceRequested` | `ApplicationSession.swift:513` | `:962` via `Callbacks` | none | none (voice-editor jump unported); check lanes bind the Swift closure `TrackHeaders.onRevealTrackVoiceRequested` directly |
| `rollFocusRequested` | `TrackHeaders.swift:386` | `:305` in `finishRename()` | none | none; paired closure `onRestoreRollFocus` (`TrackHeaders.swift:67`) is never set |
| `informationRequested` | `ShellPresenter.swift:406` | never | `ShellWindow.qml:222-226` | none; Swift emits `criticalRequested` instead (`ShellPresenter.swift:377,383,389`) |

## 4. Unused context-property seam

`pd_qml_set_context_property` (`src/app/qml_engine_host.h:11`, impl `src/app/qml_engine_host.cpp:21-28`)
and its Swift wrapper `QmlEngineAccess.setContextProperty` (`src/swift/app/QmlEngineAccess.swift:16-18`)
have zero callers anywhere; only explanatory comments mention the legacy pattern
(`src/checks/rollqml/tst_SwiftRoll.qml:61`, `tst_SwiftRollWindowing.qml:58`). SAFE TO DELETE.

## 5. Guard feasibility (shapes the guard contract)

- Registration: `CMakeLists.txt:211-271` → `qt_add_qml_module(porydaw_app URI Porydaw.Ui
  RESOURCE_PREFIX /qt/qml NO_PLUGIN QML_FILES …)`; served from resources, not the filesystem.
- Load path: `pd_qml_module_prefix()` = `"qrc:/qt/qml/Porydaw/Ui/"` (`src/app/qml_engine_host.cpp:9-12`)
  exposed as `QmlEngineAccess.moduleResourcePrefix` (`src/swift/app/QmlEngineAccess.swift:8-10`);
  pages are loaded as prefix + repo-relative path (e.g. `AutomationPage.swift:45`), so QML file
  paths map 1:1 into the resource module.
- A text scanner can reliably check: instantiated type names ↔ `QML_FILES`/`QmlInstantiable`
  classes `[INFERENCE]`; `on<Signal>` handlers ↔ `@QtSignal` declarations `[INFERENCE]`.
- A text scanner cannot reliably resolve arbitrary property reads: delegate `model.<name>` reads
  need the model's element type, `required property var` obscures the type, and
  `[String: QVariantSettable]` keys are not statically enumerable. Any guard must scope itself to
  the reliable classes of check and treat the rest as explicitly out of contract.
- Harness registration surface: `src/checks/checkcatalog.cpp` → `checks::detail::catalog()`
  returning `CheckDefinition` (`src/checks/checkcatalog.h:23-37`: name, argv, handler, scratchKind,
  fixtureRootKind, fixtureFiles, environment, binary, startup, windowing, framework, optIn);
  exposed through `porydaw_checks --manifest` (`src/checks/checkregistry.cpp:118-125`). Standalone
  Swift lanes (`EditorQmlTests.swift:154`, `ShellQmlTests.swift:122`, `RollQmlTests.swift:77`) expose
  their own `--manifest` to `tools/run_checks.ts`.
