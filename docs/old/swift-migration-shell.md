# Swift migration: shell, keybindings, menu parity

Historical record condensing `docs/plans/swift-keybindings/**` (10 files),
`docs/plans/menu-items-handoff.md`, `docs/plans/swift-cpp-check-parity-handoff.md`,
and `docs/plans/swift-cpp-check-parity-audit.md` (all deleted 2026-09-24).
Exact deleted paths: `docs/plans/swift-keybindings/plan.md`,
`docs/plans/swift-keybindings/shell-contract.md`,
`docs/plans/swift-keybindings/registry-brief.md`,
`docs/plans/swift-keybindings/registry-checks-brief.md`,
`docs/plans/swift-keybindings/shell-surface-brief.md`,
`docs/plans/swift-keybindings/shell-logic-brief.md`,
`docs/plans/swift-keybindings/shell-proof-brief.md`,
`docs/plans/swift-keybindings/entry-build-brief.md`,
`docs/plans/swift-keybindings/menu-parity-brief.md`,
`docs/plans/swift-keybindings/settings-isolation-brief.md`,
`docs/plans/menu-items-handoff.md`,
`docs/plans/swift-cpp-check-parity-handoff.md`,
`docs/plans/swift-cpp-check-parity-audit.md`.
Active docs live under `docs/plans/swift-feature-parity/`; that tree is NOT covered here.
No old-plan assertion is promoted to a current fact; items below were proposals unless a completion milestone says otherwise.

## Provenance

- Keybindings plan tree committed in `2f37f528` ("Port keybindings and application
  shell to Swift"); base `cdac8c53`, worktree `feature/swift-keybindings`,
  gitlink-only `60167ce4`; `build:app` passed on the aligned base.
- Parity audit pinned to integration `682095474e862b90227de941d9a0a5b29ad5926c`
  (registered suite green, Swift index green); further pinned in `eb5ff775`.
  Surface-first workflow recorded in `2ff9e2d0`; no standalone reconciliation.
- `menu-items-handoff.md` was **untracked/user-authored** (never committed).
  There is NO git recovery for it — this record is its only preservation.
  Related implementation landed as `1096534c` ("Restore missing menu items and
  roll display modes"); verify via source/proofs, not this doc.
- Tracked files recover via `git show <commit>:<path>`; deleted C++ oracles via
  `git show <pinned-ref>:<path>` (parity handoff used `f3069ef...`).
- Retained proof `src/checks/automation/proof.automationownership.txt` cites
  `docs/plans/swift-keybindings` as owner of the pencil-mode toggle shortcut;
  that prose was intentionally left unedited — historical reference, consult
  this record for provenance. Retained
  `src/checks/themelayout/proof.tst_themelayout_font.txt` cites the
  `feature/swift-keybindings` branch name, not a deleted file.

## Fixed-key registry decisions (source + proofs are the spec)

- Port behavior, not QWidget structure. No new C++ files/code, no shims or
  legacy-registry fallback; reuse existing visual QML (new shell/input/menu QML
  only where the old implementation was Widgets). Every check copies an old C++
  fixture/sequence/observable assertion; unmatched code must be justified
- `KeybindingRegistry` (Swift value, Qt-free public API): fixed catalogue + order
  verbatim from `keymap.cpp`. Keys/modifiers are Qt integer values — no new
  physical-key mapping. Platform `StandardKey`/alternate bindings resolve
  through existing Qt header APIs via Swift C++ interop, only after GUI startup.
- Native `RewriteWindow` key resolution ran before Swift — classified as a shim
  and removed. Swift `EditKeyArbiter` owns semantic routing; native editor-local
  and window delivery must never both execute one command. Production has exactly
  one Swift owner; native fixtures remain as oracles, not runtime fallback.
  Scope was every existing Swift-enabled production target (at the time: Apple
  only); non-Swift builds unchanged; Swift app has no native-shell fallback.
  Unknown-id lookups preserve empty/false where native has counterparts;
  sequences are immutable after first live-GUI resolution.

## Native vs QML routing (Cocoa arbitration)

- Old QMenu copied QAction's primary shortcut into `QCocoaMenuItem` while the
  registry installed its own Qt shortcut-map entry. Qt 6.11 `qcocoansmenu.mm`
  sends `ShortcutOverride` to the focus object: accept forwards the native event
  and suppresses the menu action; reject lets Cocoa activate the menu item
  without `keyDown` forwarding. Exclusive routes, never duplicate activation
  (`qcocoamenuitem.mm` accepts tab + `QKeySequence` NativeText as the key equivalent).
- Consequences kept: plain QML `MenuItem` with tab/NativeText caption registers
  NO shortcut-map entry — correct. Never use `QQuickAction.shortcut` for these
  (it would add a second entry). Physical Cocoa column/arbitration is
  **source-verified only**; offscreen runs cannot exercise it — never claim them.
- Context popup stays non-native/themed (original standalone QMenu was
  non-native): primary shortcut in a separate right-aligned label, menu roles
  from `presetcolors.h`. Song dialog (ex-`QInputDialog`, palette/QSS-painted)
  uses locally selected theme-capable Quick Controls; no global style change.
  Native menu bars, folder panels, message alerts stay system surfaces.
- `ShellPresenter.actionShortcut(id:)` exposes only the primary binding's Qt
  NativeText (empty for unbound Open Song/Stop), separate from portable delivery
  sequences.

## Shell contract (what the plans froze)

- `ShellPresenter` (`@MainActor @QtBridgeable`, QML-instantiated after QApp
  creates `QGuiApplication`): `session`, `actionIds` (+ `windowActionIds` /
  `contextActionIds` so QML never duplicates scope policy), `actionLabel`,
  portable `actionSequences`, `actionEnabled`, `activate`, single-execution
  `routeEditorKey`, close/lifecycle set, `openStartup`, `songLabels`, dialog
  requests. Empty-song text and error titles follow `RewriteWindow` exactly.
  QML-facing refs/ID arrays are stored `@QtTracked` vars assigned at init —
  the macro does not publish `let`/computed arrays (glue, not policy).
  `sceneDestroyed()` acknowledges Loader detachment, not synchronous QObject
  deletion.
- `ShellAppearance` owns native preset palette + settings canonicalization; QML
  supplies real `QtCore.Settings` values and applies Swift results.
  Velocity-zero fill consumes the active palette role. Positive resolved font is
  threaded through reused QML — the old global `Application.font.pixelSize`
  read is invalid under the QApp host.
- App identity is executable startup policy (`porydaw` / `sp3cker` / empty
  domain) set by the `PorydawApplication.qml` bootstrap before `ShellWindow`
  loads; Swift cannot import noncopyable `QCoreApplication` statics, so
  `Qt.application` is the access path. `FolderDialog.selectedFolder` is decoded
  via Foundation URL to a local path.
- Keybindings/shell port: controller gates passed — `build:app`, swiftcore
  registry checks, `verify:shell`, `verify:qml` (retained profiles, no
  rebaseline), formatter, Swift index. No C++ source/header added or modified.
  Registry proof mapped all native keymap assertion sites to expanded
  predicates; shell crosswalk kept named platform/identity gaps.
  Live-prototype evidence: Swift QApp shell loaded the original qrc SongTabs;
  a native menu shortcut activated once while text Copy/Space stayed local;
  drag input yielded Space to transport; clean process exit observed.
  Standard-key sequences resolved through Qt only after GUI startup.
- Settings isolation: the shared `com.sp3cker.porydaw` store proved an invalid
  fixture boundary (a seeded value came back polluted), and OS home overrides
  do not isolate modern macOS preferences. Fix: fresh test application name
  under the `sp3cker` organization plus bootstrap metadata before Settings;
  QML passes `Qt.application.name`; legacy-key removal follows the active name.
  Production preferences were verified untouched by the isolated lane.
- Adjudicated and kept: copied menu roles; File/Edit separator order; Swift
  owns the Apple entry while `main.cpp` stays the non-Swift entry.

## Menu-items handoff decisions (untracked — preserved here only)

IMPLEMENTED (landed `1096534c`; confirm via source/proofs):
- `file.close_tab` → `requestClose(selectedId)`; transport items
  (`go_to_start/play/play_pause/pause/stop/loop/follow_playhead`) via
  `session.transportBarPresenter()`; loop/follow checkable with `checked`
  bound to tracked state directly so drawer/shortcut changes propagate.
- View drawer items (velocity/voice-changes/automation, checkable) via
  `drawerPresenter().toggleSection(kind:drawerOwnsFocus:)`; checked from
  `*Section.visible`. `velocity_colors`/`note_names` (always enabled) persisted
  as QSettings root keys `velocityNoteColors`/`noteNames`.
- `help.about` → themed AboutDialog with the legacy Help text.
- Roll modes on `ApplicationSession` (app-wide including future tabs):
  velocity colors follow the legacy endpoint/quantized-HSV rule on non-ghost
  fills and preview; note names render on selected-track notes only when the
  key is tall enough and the name fits, in a contrasting ink.
- Explicitly out of scope (proposals, not decisions): Export WAV, View→Theme,
  New Song, Import MIDI, Register Song, Import Sample.
## Parity audit limits and source pointers (superseded as instructions)

- The parity handoff's build blocker, dirty-tree steps, and "immediate next
  steps" were superseded by integration `68209547` — do NOT execute them. Its
  Debug conformance investigation and pending-run `MATCHED`s are historical
  diagnostics only.
- Ledger limits kept: two proofs still used legacy (non-`A###`) records; some
  `MATCHED` entries lacked exact `S###` links and could not authorize C++
  retirement; two assertion-bearing support sources needed written exclusion
  rationale; evidence sections citing pending runs needed refresh.
- Area queue superseded by the surface-first workflow (ledger rows change only
  with the proving surface commit); native rendering needs an external
  production journey suite before retiring native coverage.
- Source pointers (recipes live in source/proofs): `keyboard/keymapregistry.cpp`;
  `themelayout` settings-repair test; `mainwindowrouting` fixture + native
  routing test; selectionkey numeric-prompt proof; automation menu tests;
  drawer voice-menu tests. Native pointer/rendering/focus/key-delivery sites
  stay NATIVE — presenter-state passes never prove them.
- Shell-proof evidence rules: no invented permanent scenarios; throwaway smokes
  stay throwaway and never enlarge the native assertion count; shell lane uses
  genuine `QtCore.Settings`, offscreen.

## Explicit unknowns

- Physical Cocoa menu-bar/key-equivalent integration never exercised offscreen;
  only source-traced — any future claim needs a real Aqua run. CLI remains
  lenient vs `QCommandLineParser` (reviewed non-blocking gap).
- `NATIVE` dispositions keep their native checks until an external
  production-app journey proves the same observation; suite-green alone never
  retires C++ coverage.
