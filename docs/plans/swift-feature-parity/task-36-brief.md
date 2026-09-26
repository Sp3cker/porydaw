# Context

One Swift settings store replaces every production QML `QtCore.Settings` writer/reader. Binding ruling (user, 2026-09-26): **Swift owns all settings**; the store is CFPreferences-backed with a configurable application ID; production keeps the on-disk domain `com.sp3cker.porydaw` and every key name/value so existing user preferences survive; check lanes point the store at an absolute plist path inside their private scratch directory (VERIFIED by the user: `CFPreferencesSetAppValue`/`CopyAppValue`/`AppSynchronize` with applicationID `/abs/path/x.plist` read/write exactly that file and write nothing to `~/Library/Preferences`). After this change no check writes to `~/Library/Preferences`. Observed leak: 1888 `com.sp3cker.porydaw-shell-checks-<uuid>.plist`, ~130 `com.sp3cker.workspace-codec-check-<uuid>.plist`, plus stale `com.sp3cker.shell_qml_tests` / `com.sp3cker.porydaw.porydaw` / `com.sp3cker.benchprobe`; `com.sp3cker.porydaw.plist` is the real production domain and must never be deleted.

1. **Production inventory** (every `Settings`/`import QtCore` in `src/ui`):
   - `ShellWindow.qml:62-77` `appearanceStore` (category `theme`): reads `mode`, `grid-line-contrast`; `shell.restoreAppearance(mode, contrast, Qt.application.name)`; writes both back canonically (:73-74); `shell.openStartup(...)` (:75).
   - `ShellWindow.qml:79-84` `dockSettings` (`swiftDock`): `columnWidth` int 280 (:536), `songsRatio` real 0.5 (:539); written only from the guarded handlers (:541-548).
   - `ShellWindow.qml:88-90` `displayModeSettings` (root): `velocityNoteColors`/`noteNames` bool; read in `Component.onCompleted` (:133-138, activate-if-differs); written + `sync()` from the session Connections (:176-185).
   - `ShellWindow.qml:91-114` `engineSettingsStore` (`engine`): `pcmMixer` "ipatix", `maxPcmChannels` 5, `pcmMixRate` 13379, `analogFilter` false; restore :95-101; written from `onRevisionChanged` :103-113.
   - `TransportBar.qml:57-66, 394-397` (root): `outputVolume` int 100; restored at mount; dial commit applies + assigns the property.
   - `EditorDrawer.qml:72-77` `drawerSettings` (`editorDrawer`, `location: drawerScope.preferenceLocation`; production `""`, tests feed INI URLs — `Settings.location` (Qt 6.5+) forces IniFormat, so those lanes never touched native domains). Keys `<section>Visible/Height` for velocity/automation/voiceChanges and `activePage`; read once at mount (:111-150, absent→-1/0); written + `sync()` from two presenter signals (:152-167, :597-603).
   - Swift writers: `EditorViewStateCodec` private `SettingsStore` (EditorViewStateCodec.swift:262-315) owns `lastProjectDir`, `lastOpenSongs` (empty→removed), `lastSongLabel`, `editorDrawer.automationLanes`; reached via `ApplicationSession.configurePersistence` (:649-652) and the save sites (:961-965, :1276-1278, :1292-1295). `ShellAppearance.removeLegacyCustomKeys` (ShellAppearance.swift:98-112) deletes `theme.primary`/`theme.accent` left by the old QML writer. Theme/engine/dock/volume/drawer/displayMode keys are QML-written today, tab/lane keys Swift-written — same domain, same dotted spelling.
   - `src/ui/shell/settings/*` persist nothing (draft + `store.apply()`). No other `Settings`/`QtCore`/`localStorage` exists in `src/ui`; legacy `workspaceui_samples.cpp` keys (`lastImportDir` etc.) have no current writer and must survive untouched.
2. **On-disk compatibility** (qtbase 6.8 = 6.9: `src/corelib/io/qsettings_mac.cpp` + `qsettings.cpp`; qtdeclarative `src/core/qqmlsettings.cpp`; URLs `https://code.qt.io/cgit/qt/qtbase.git/plain/src/corelib/io/qsettings_mac.cpp?h=6.8` and siblings, same tree for `qsettings.cpp`; `https://code.qt.io/cgit/qt/qtdeclarative.git/plain/src/core/qqmlsettings.cpp?h=6.8`):
   - QML Settings composes `<category>/<name>` (`beginGroup`); the mac backend rotates separators (`rotateSlashesDotsAndMiddots`, Macify): `/`→`.`, `.`→`·` (U+00B7), `·`→`/`. On-disk keys: `theme.mode`, `engine.pcmMixer`, `editorDrawer.velocityHeight`, root `outputVolume` — confirmed via `defaults read com.sp3cker.porydaw`.
   - Domain: `comify("sp3cker")`→`sp3cker.com`→reversed→`com.sp3cker` + application name.
   - `macValue`: Int/UInt/Double/LongLong→CFNumber, Bool→CFBoolean, QString→CFString (null bytes→CFData), lists→CFArray, QByteArray→CFData, QDateTime(LocalTime)→CFDate; anything else — including an invalid QVariant from `setValue(key, undefined)` — becomes the literal CFString `"@Invalid()"` (or `"@Variant(...)"`). `@ByteArray(...)` is never written on macOS. QSettings flushes asynchronously; QML declared-property writes are 500 ms-debounced, explicit `setValue` immediate.
   - Store reader rules: accept CFNumber/CFBoolean/CFString/CFArray/CFData; `"@Invalid()"` reads as absent (production sanitizers already coerce invalid values to defaults); empty string is a value, not absent (`keymap.*` seeds rely on `""`); never touch unowned keys.
3. **Check inventory**:
   - `ShellQmlTests.swift:220` `settingsApplicationName` = `"porydaw-shell-checks-" + uuid` → `Qt.application.name` in `initTestCase` of the shell entries (26 incl. 6 text-contrast) and `tst_ShellPolyphony.qml:38`; `clearSettings()` (:232-237, `UserDefaults.removePersistentDomain`) cannot stop cfprefsd re-materializing the file. Seeding/asserting `Settings` users: `tst_ShellWindow.qml` (keymap round-trip + theme repair :239-281), `tst_Theme.qml`, `tst_ShellSettings.qml` (engine), `tst_ShellSongs.qml` (swiftDock), `tst_ShellTransport.qml` (volume 87 relaunch + tab recipe), `tst_ShellTabs.qml` (lastOpenSongs/lastSongLabel), `tst_ShellMenus.qml` (displayMode toggle relaunch), `tst_ShellDrawerParity.qml`, `tst_ShellEventList.qml`, plus `lastProjectDir=""` seeding in clipboard/grid-input/grid-menu/pitch-bend/text-contrast. `tst_ShellOpenFailure.qml:32` clears per-test. `tst_Typography.qml:130` asserts organization `"sp3cker"` (identity, not storage).
   - Swift checks: `src/checks/workspace/editor_view_state_checks.swift:66-88` mints `com.sp3cker.workspace-codec-check-<uuid>` per run for `EditorViewStateCodec` round-trips; its `defer` nils keys but leaves the plist.
   - Roll lane touches the REAL domain: `RollQmlTests.swift:254-275` `captureSettings`/`restoreSettings` snapshot/restore 15 hardcoded `com.sp3cker.porydaw` keys; all 9 roll tst files set `Qt.application.name = "porydaw"` and redirect drawer prefs via `bootstrap.preferencesUrl("*.ini")` (`EditorQmlTests.swift:1142-1147`, `RollQmlTests.swift:345-350`).
   - Native C++ checks already isolate QSettings into a temp INI dir (`checkregistry.cpp:175-179`) — untouched.
4. **Scratch delivery**: `tools/run_checks.ts` gives each entry `<tempRoot>/<check.name>`, substituted only through argv (`expandArguments` :250-259; no env var exists). The QML harnesses take it as `arguments[1]` and stage it into the bootstrap (`ShellQmlTests.swift:132,149`; `EditorQmlTests.swift:161,176`; `RollQmlTests.swift:84,98`); child processes re-derive it from argv. The swiftcore entries already pass `{scratch}` (`checkcatalog.cpp:109`). The store is staged by each lane's Swift entry from argv — no runner, CLI, or C++ changes.

# Exact write set

- `src/swift/app/shell/PreferencesStore.swift` — new (add to `src/swift/app/CMakeLists.txt` sources).
- `src/swift/app/shell/ShellPresenter.swift` — `configureSettings`, `restoreAppearance()` rewrite, `openStartup()` arg drop, dock members.
- `src/swift/app/shell/EngineSettingsStore.swift` — `restoreFromPreferences`, persist on apply.
- `src/swift/app/shell/ShellAppearance.swift` — delete private CF helpers; route `removeLegacyCustomKeys` through the store.
- `src/swift/app/ApplicationSession.swift` — `configurePersistence()` via shared store; display-mode persistence in the two setters.
- `src/swift/app/transport/TransportBarPresenter.swift` — `restoreOutputVolume`, `commitOutputVolume`.
- `src/swift/app/timeline/EditorViewStateCodec.swift` — store-parameterized load/save; delete private `SettingsStore`.
- `src/swift/app/drawer/EditorDrawer.swift` — `restoreStoredPreferences()` reads the store; persist at the existing emission region; delete `drawerActivePagePreferenceChanged`.
- `src/ui/shell/ShellWindow.qml`, `src/ui/shell/TransportBar.qml`, `src/ui/songview/quick/drawer/EditorDrawer.qml`, `src/ui/songview/quick/swiftroll/EditorSurface.qml` — Settings cutover; `import QtCore` removed.
- `src/checks/editorqml/ShellQmlTests.swift` — delete `settingsApplicationName`/`clearSettings`; add `preferences` + `resetPreferences`; stage scratch plist; register `PreferencesStore`.
- `src/checks/editorqml/EditorQmlTests.swift`, `src/checks/rollqml/RollQmlTests.swift` — same staging; delete `preferencesUrl`; delete roll `captureSettings`/`restoreSettings`.
- `src/checks/workspace/editor_view_state_checks.swift` + `src/checks/workspace/SessionChecks.swift` — scratch-plist store; drop the UUID domain.
- Shell lane tst batch: `tst_ShellWindow.qml`, `tst_Theme.qml`, `tst_ShellSettings.qml`, `tst_ShellSongs.qml`, `tst_ShellTransport.qml`, `tst_ShellTabs.qml`, `tst_ShellMenus.qml`, `tst_ShellDrawerParity.qml`, `tst_ShellEventList.qml`, `tst_ShellClipboard.qml`, `tst_ShellGridInput.qml`, `tst_ShellGridMenu.qml`, `tst_ShellPitchBend.qml`, `tst_TextContrast.qml`, `tst_ShellOpenFailure.qml`, `tst_ShellPolyphony.qml`, `tst_ShellChromeVisuals.qml`, `tst_ShellNoteVisuals.qml`, `tst_ShellReticleVisuals.qml`, `tst_Typography.qml`, `tst_EditorDrawer.qml`.
- Roll lane tst batch: `tst_SwiftRoll.qml`, `tst_SwiftRollAutomation.qml`, `tst_SwiftRollPlayhead.qml`, `tst_SwiftRollPlots.qml`, `tst_SwiftRollSelection.qml`, `tst_SwiftRollTrackHeaders.qml`, `tst_SwiftRollWindowing.qml`, `tst_TimelinePan.qml`, `tst_TimelineScrollbar.qml`.

# Prerequisites

None blocking. `ShellWindow.qml`, `EditorSurface.qml`, `ApplicationSession.swift`, `ShellPresenter.swift` are hot composition files — take the controller-sequenced slot after task 35's rollcheck work settles. One cutover, one verification surface over many files; the per-file test swaps are same-shape mechanical edits batched in one dispatch (sizing exception, named in dispatch).

# Interface contract

- `PreferencesStore` (`@QtBridgeable`, `QmlInstantiableStatus`, one file):
  ```
  static func stageShared(plistPath: String)
  static func configureShared(applicationName: String)
  func string(key: String, fallback: String) -> String
  func int(key: String, fallback: Int) -> Int
  func double(key: String, fallback: Double) -> Double
  func bool(key: String, fallback: Bool) -> Bool
  func hasValue(key: String) -> Bool
  func setString(key: String, value: String)
  func setInt(key: String, value: Int)
  func setDouble(key: String, value: Double)
  func setBool(key: String, value: Bool)
  func remove(key: String)
  func resetPreferences() -> Bool
  func synchronize()
  ```
  Internal (Swift-only): `strings(_:) -> [String]?`, `setStrings(_:_:)`, `data(_:) -> Data?`, `setData(_:_:)`. Instances are stateless views on one shared configured application ID (a CFString that is either `"com.sp3cker." + name` or an absolute plist path). `stageShared` removes any existing file at the path first (per-process clean slate) and wins; `configureShared` is a no-op once staged — that ordering keeps every check out of `~/Library/Preferences` even though QML still calls `configureSettings(Qt.application.name)`. Keys are verbatim on-disk identifiers (dotted); no separator rotation; unowned keys untouched. `resetPreferences` clears via key enumeration + `AppSynchronize`, never by deleting the file behind cfprefsd. Explicit `synchronize()` only where QML called `sync()` today (drawer, displayMode).
- QML exposure: the three bootstraps gain `@QtTracked public var preferences: PreferencesStore` + `resetPreferences() -> Bool`; the three harness type lists register `PreferencesStore`. Production registers nothing — production QML never touches keys.
- Production configuration: `ShellWindow.Component.onCompleted` calls `shell.configureSettings(Qt.application.name)` right after the `establishApplicationIdentity` block — it must precede the displayMode reads at :133, which is why configuration cannot live only inside the (later) appearance/startup restore. Then `shell.restoreDisplayModes()` replaces :133-138; `transportBar.presenter.restoreOutputVolume()` replaces :139; `shell.settingsStore.restoreFromPreferences()` replaces :140; `shell.restoreAppearance()` + `shell.openStartup()` replace :141 and the deleted appearanceStore body, same order.
- `ShellPresenter.restoreAppearance()` reads `theme.mode`/`theme.grid-line-contrast` (fallback `""`), applies via the unchanged `ShellAppearance.mode/contrast/apply`, writes canonical values back (today's :73-74 write-back), and removes `theme.primary`/`theme.accent` through the store. `openStartup()` drops its argument; `ApplicationSession.configurePersistence()` uses the shared store.
- Dock: `@QtTracked dockColumnWidth: Int = 280`, `dockSongsRatio: Double = 0.5`, restored during `configureSettings` (published before the first frame); `setDockColumnWidth(_:)`/`setDockSongsRatio(_:)` persist write-on-change. QML keeps its guards (:541-548); bindings (:536/:539) swap to the presenter properties.
- Volume: `TransportBarPresenter.restoreOutputVolume()` reads `outputVolume` (fallback 100, existing 0...100 guard); `commitOutputVolume(percent:)` = `setOutputVolume` + persist; the dial commit calls only `commitOutputVolume`.
- Display modes: `ApplicationSession.setVelocityColorMode(enabled:)` (:1300) / `setNoteNameMode(enabled:)` (:1311) persist the root keys after their equality guards; the QML handlers keep only `++root.actionRevision`.
- Engine: `EngineSettingsStore.restoreFromPreferences()` reads the four `engine.*` keys with today's defaults; `apply()` persists them at the revision bump; the QML `Connections onRevisionChanged` writer is deleted.
- Drawer: `EditorDrawer.restoreStoredPreferences()` (no arguments) reads the seven `editorDrawer.*` keys with the existing absent→-1/0 semantics and never writes back; the preference-change region (EditorDrawer.swift:242-252) persists `<section>Visible/Height` and `activePage` exactly where it emitted for QML. Keep `drawerSectionPreferenceChanged` (ShellWindow.qml:203 listens); delete `drawerActivePagePreferenceChanged` (no remaining consumer). Delete `EditorDrawer.preferenceLocation` and `EditorSurface.drawerPreferenceLocation`.
- `EditorViewStateCodec.loadTabs/saveTabs/loadLanes/saveLanes` take `store: PreferencesStore`; `editor_view_state_checks` builds one from the `{scratch}` argv already delivered to `swiftcore-projectsession` (threaded through `SessionChecks.swift`).
- Preservation contract: unchanged domain, key spellings, categories, defaults, absent-until-changed writes, restore-at-mount order (:133→:141), theme canonical write-back, sync points, removeLegacyCustomKeys behavior. Accepted deviations: declared-property writes are no longer 500 ms-debounced; `"@Invalid()"` reads as absent; dock values publish at `configureSettings` instead of QML construction — all complete before the first frame.
- Tests seed/read through `bootstrap.preferences` (e.g. `setString(key: "theme.mode", value: "dark-neutral-high")`; `int(key: "outputVolume", fallback: 100)`), replacing every `settingsComponent`/`nativeSettings`/`storeComponent` helper; slash keys become dotted on-disk keys. Per-test isolation that used distinct INI locations becomes `bootstrap.resetPreferences()` or the automatic clean slate each staged child process gets. Ledger-cited messages stay verbatim, including "application output preference survives a fresh shell session" (S189) and "mounting writes nothing back" (S101); the tautological "genuine QtCore.Settings is available" checks are deleted. `tst_Typography.qml` keeps asserting organization `"sp3cker"`.

# Implementation steps

1. Add `PreferencesStore` + CMake source; register in the three harnesses.
2. Migrate Swift consumers: `EditorViewStateCodec` (delete private `SettingsStore`), `ShellAppearance`, `ApplicationSession`, `EngineSettingsStore`, `TransportBarPresenter`, drawer `EditorDrawer.swift`, `ShellPresenter` members above.
3. Cut over the four QML files; call sequence per the contract.
4. Harnesses: stage `<scratch>/settings.plist` in each lane entry (and in every child entry that re-stages); delete `settingsApplicationName`, `clearSettings`, `preferencesUrl`, roll `captureSettings`/`restoreSettings`; add `preferences`/`resetPreferences`.
5. Migrate `editor_view_state_checks` + `SessionChecks` threading.
6. Mechanical test batch per the write set: bootstrap-store seeding/reads, drop `Qt.application.name = bootstrap.settingsApplicationName` blocks (keep `tst_Typography.qml`'s literal org assertion), replace `clearSettings` with `resetPreferences` where a clean slate is needed.
7. Run the lanes below; prove the leak count and real-domain persistence.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --verbose` (all 26 entries)
- `deno task verify:qml --verbose`
- `deno task verify:qml-roll --verbose`
- `deno task verify:bridge`
- `deno task proof check`
- Leak proof (same shell, before and after the full verify:shell run): `ls ~/Library/Preferences | grep -c '^com\.sp3cker\.'` must not increase and the `porydaw-shell-checks|workspace-codec-check` count must stay at its before-value (zero after cleanup). Implementer-run.

# Task-specific constraints

- No new C++; no code comments; delete stale comments in touched regions.
- `com.sp3cker.porydaw.plist` and its unowned legacy keys (`windowState`, `windowGeometry`, `songFilter*`, `lastImportDir`, `lastWavExportDir`, `sampleLibraryFolders`, `dsp.resonanceSuppression`, `followPlayhead`, `keymap.*`) are never removed or rewritten by the store.
- `Qt.application.name`/organization establishment stays (window identity, About); it no longer selects storage anywhere.
- Ledger work is controller-delegated to the ledger agent in this task's commit scope: `proof.shell-theme.txt` (mechanism text :16/:38/:49 names genuine QtCore.Settings and the `bootstrap.settingsApplicationName` teardown), `proof.tst_themelayout_color.txt` A042-A046/A048-A050 and `proof.tst_themelayout_settings.txt` A011/A012/A039/A040 (reasons cite Settings seeding), `proof.tabs_transport.txt` A045/S189 (A055 GAP — "no Swift/QML owner exists for the outputVolume preference key" — gains an owner and may map to the extended relaunch predicate), `proof.selftest_workspace.txt` A006/A008/A009/A011/A014 (reasons cite the split QML/Swift stores; refresh wording, rows stay GAP), `proof.session.txt` notes :62/:119 (wording only), `proof.automationactions.txt` S035 (anchor kept or updated), `proof.drawer.txt` S101/S104 (messages preserved). No standalone reconciliation pass; no GAP row closes without a new executing predicate.
- The absolute-path applicationID is undocumented Apple behavior (user-verified). Keep it isolated inside `PreferencesStore`; the leak-count acceptance is the regression tripwire.

# Controller verification

After the writer settles and `pgrep -fl 'porydaw|_qml_tests|swift_core_check'` is empty:

1. One-time leak cleanup (never `com.sp3cker.porydaw`; ~2000 `defaults` calls, takes minutes):
   `cd ~/Library/Preferences`
   `for f in com.sp3cker.porydaw-shell-checks-*.plist com.sp3cker.workspace-codec-check-*.plist; do defaults delete "${f%.plist}"; done`
   `defaults delete com.sp3cker.shell_qml_tests; defaults delete com.sp3cker.porydaw.porydaw; defaults delete com.sp3cker.benchprobe`
   `rm -f com.sp3cker.porydaw-shell-checks-*.plist com.sp3cker.workspace-codec-check-*.plist com.sp3cker.shell_qml_tests.plist com.sp3cker.porydaw.porydaw.plist com.sp3cker.benchprobe.plist`
   Then `ls com.sp3cker.*` must show only `com.sp3cker.porydaw.plist`.
2. Full lanes on the settled tree: verify:shell (26 entries), verify:qml, verify:qml-roll, `verify --filter swiftcore`, verify:bridge; repeat the leak count before/after verify:shell.
3. Real-app smoke (native desktop): launch the built production app, set a non-default theme (dark-neutral-high), output volume, dock column width and a drawer height; quit normally; relaunch — all four restore, and `defaults read com.sp3cker.porydaw` shows the written keys with unchanged spelling.
4. `deno task proof check --executed` and `deno task proof check --strict-mappings` before treating the refreshed ledgers as consistent.
