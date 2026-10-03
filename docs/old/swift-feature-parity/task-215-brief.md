# Task 215 brief — a catalog outage keeps the last valid catalog and reports on the status bar

# Context

**Released** under the user's 2026-09-28 ruling (2): the catalog outage ports the fork.
The status bar reports "sound directory is unavailable". The last valid catalog, the tab
binding and the voicegroup browser stay usable. A later refresh recovers cleanly
(sprint-3.md status header, lines 76–79).

Fork contract (oracle `fceecd88`):

- `projectio.cpp:659-689 scanCatalog`: the scan refuses with
  `"Project sound directory is unavailable."` (`:664`) when the project root or `<root>/sound`
  is not an existing directory. `refreshCatalog` (`:555-564`) turns that into a
  `CommandFailure`.
- `projectworkspace.cpp`: a successful scan replaces only `state.catalog` (`:144-149`). A
  `RefreshCatalogInput` failure (`:285-287`) publishes `CatalogMutationFailed` (`:347-350`)
  and leaves the state, snapshot and catalog unchanged. Project open resets the catalog to
  empty (`:86`), publishes Ready, then submits the refresh (`acceptSnapshot`, `:208-234`).
  An open therefore never fails because of the catalog.
- `workspaceui_project.cpp:388-390`: `CatalogMutationFailed` → `showStatus(message, 8000)`.
  This is a status-bar line, not a dialog. Browser loading follows only in-flight song
  loads (`workspaceui_voicegroup.cpp:201-206`), so a refresh never changes the browser's
  loading state or enablement.
- Other fork refresh triggers: sample commit (`workspaceui_samples.cpp:393`),
  voicegroup/song creation, and song deletion. The fork has no refresh after a save.
- Fork check: `savecore.cpp:76-110 catalogOutageRetainsLastValid`. The oracle hides
  `sound/` and submits `RefreshCatalogInput`, then asserts the status text, the unchanged
  `catalog.groupArgs`, the tab `voicegroupId`, `!isLoading`, and an enabled selector and
  release spin. It restores `sound/`, refreshes, and asserts the same groupArgs and
  `!isLoading` again.

Swift today:

- There is no refresh entry point.
- `ProjectService.voicegroupCatalog()` (`ProjectService+Bank.swift:23-59`) scans a missing
  `sound/` silently into an empty catalog.
- `ApplicationSession+ProjectOpening.swift` reads the catalog inside the atomic
  `ProjectRead.load` preflight and installs it field by field in `finishProjectSwitch`.
- `requestSaveImpl` (`ApplicationSession+Commands.swift:88-112`) rescans after a successful
  save, but only for the synth fields. It also runs the rescan inside the save's `do`. A
  rescan failure therefore sets `lastSaveError`, and `ShellPresenter.saveStateChanged`
  raises "Save Failed" although the save succeeded. This task fixes that misreport.
- The status route already exists (task 209): `ApplicationSession.statusMessage(message:)`
  → `ShellWindow.qml` `onStatusMessage` → `shell.statusText` → `ShellStatusBar.qml`
  `shellStatusText`.

Surface: the project voicegroup catalog lifecycle behind the voicegroup dock, settings
voicegroup list and pickers. It covers one public refresh API, its failure publication on
the shell status bar, and its triggers: project open, after Save, and later the P2/P4
flows.

Ledger spec: `src/checks/voicegroupsave/proof.savecore.txt` A016–A026 (11 GAP, fork
`VoicegroupSaveTest::catalogOutageRetainsLastValid`). All 11 rows are behavior; none is
representation or blocked. A016/A023 are the fork's fixture hide/restore guards, which the
Swift check reproduces fail-closed in its private scratch copy. The ledger's other 70 rows
are closed (52 MATCHED with zero strict-mapping debt, 18 RETIRED). The file therefore
closes and is deleted in the proving commit.

Verify lanes:

- `swiftcore-bankhistory`: session predicates.
- `shell-voicegroup-picker`: mounted status-bar, selector and release-spin predicates.
- Regressions: `swiftcore-projectsession`, the other `shell-voicegroup*` entries and
  `shell-tabs-bank-lifetime`.

Blocked rows left untouched:

- `project/proof.ioflow.txt` A014/A040 (worker FIFO and catalog preemption/requeue).
- `project/proof.iomutations.txt` A089 (closed-transport shutdown join).
- `project/proof.workspace.txt` A048/A051/A055 (ProjectWorkspace publication-log counts).

All six pin the fork's asynchronous command-envelope representation, which falls under
the project-store backend exclusion (sprint-3 §29 census). The Swift refresh is a direct
async read with no queue or event log.

The voicegroupbank write-failure family is the sibling task 218; the write sets do not
overlap.

Forward pointer: this task produces the one catalog-refresh API. P2 MIDI-import (tasks
230–239) calls it after creating a new voicegroup. P4 sample studio (tasks 240–269) calls
it after a sample commit. Both cite the Interface contract below verbatim.

# Exact write set

Production:

- `src/swift/app/ProjectService+Bank.swift` — `voicegroupCatalog()` only: the outage
  refusal (contract 1) and its doc comment.
- `src/swift/app/ApplicationSession+Catalog.swift` — NEW `@MainActor` extension:
  `refreshVoicegroupCatalog()` and `resetVoicegroupCatalog()` (contracts 2–3). This is a
  file of its own because it is a public cross-package seam (P2/P4). It has a separate
  reason to change from project switching.
- `src/swift/app/ApplicationSession.swift` **(shared hot file)** — two stored members
  beside `catalogService`: `@QtIgnored var catalogRefreshIssued: UInt64 = 0` and
  `@QtIgnored var catalogRefreshApplied: UInt64 = 0`. Nothing else.
- `src/swift/app/ApplicationSession+ProjectOpening.swift` **(shared hot file)**:
  - delete the `voicegroupCatalog` fields of `ProjectRead` and `ProjectSwitchCandidate`
    and the preflight `service.voicegroupCatalog()` read;
  - in `finishProjectSwitch`, replace the field-by-field catalog install with
    `resetVoicegroupCatalog()` followed by `await refreshVoicegroupCatalog()`, at the same
    position (after `projectRootChanged()`/`songDock.install`, before
    `projectOpen = true`);
  - keep `voiceList.projectService = candidate.service`.
- `src/swift/app/ApplicationSession+Commands.swift` **(shared hot file)** —
  `requestSaveImpl` only (contract 4).
- `src/swift/app/CMakeLists.txt` — register `ApplicationSession+Catalog.swift` after
  `ApplicationSession+Commands.swift`.

Checks:

- `src/checks/workspace/session_catalog.swift` — NEW:
  `@MainActor internal func sessionCatalogOutageRetainsLastValid(report: CheckReport, fixtureRoot: String)`
  (step 5).
- `src/checks/workspace/SessionChecks.swift` **(shared with task 216)** — one call line in
  `runBankHistorySuite`, after `bankMissingBasisAndApplied(...)`.
- `src/checks/CMakeLists.txt` **(shared hot file)** — `workspace/session_catalog.swift`
  after `workspace/bank_switching.swift` in the `swift_core_check` sources.
- `src/checks/editorqml/TabsDrawerProbe.swift` — three probe methods (contract 6).
- `src/checks/editorqml/tst_ShellVoicegroupPicker.qml` — one new function,
  `test_zzCatalogOutageRetainsLastValid` (step 6).

Ledger: `src/checks/voicegroupsave/proof.savecore.txt` — close A016–A026, then delete the
file (step 7).

Not touched:

- `ShellWindow.qml`, `ShellStatusBar.qml`, `ShellPresenter*.swift`, all production QML.
- `VoiceListController*.swift`. Task 209's `acceptNewVoicegroup` controller-local
  republish stays; its checks construct a bare controller.
- `ProjectStore*.swift`, `ApplicationSession+Close.swift`, `ApplicationSession+Audio.swift`.

# Prerequisites

None in-wave. The write set is disjoint from task 218 (`ProjectStoreSaveChecks.swift`,
`proof.tst_voicegroupbank.txt`).

Task 216 also edits `SessionChecks.swift` (its session_io suite). That is a different
function, but the same file: checkpoint one writer before the other edits it. Task 214 is
disjoint.

P2 (230–239) and P4 (240–269) consume contract 2 and must not edit
`ApplicationSession+Catalog.swift`.

Read sprint-3 §29 and the status-header rulings.

# Interface contract

1. **`ProjectService.voicegroupCatalog() async throws -> VoicegroupCatalog`**
   (fork `scanCatalog:659-665`).
   - After `requireStore()`: if `projectRoot` or `projectRoot + "/sound"` is not an
     existing directory, throw
     `ProjectServiceError.operationFailed("Project sound directory is unavailable.")`
     before any scan.
   - No new error case.
   - The success path is unchanged. `ProjectStore.voicegroupCatalog()` keeps its signature
     and its three check call sites.

2. **`ApplicationSession.refreshVoicegroupCatalog() async -> Bool`** — `public`,
   `@MainActor`, `@discardableResult`, declared in the extension. It is therefore
   Swift-only and not QML-registered. This is the only catalog-refresh entry point; P2/P4
   cite it verbatim.
   - No project (`catalogService == nil`): return `false`. Nothing is published.
   - Otherwise:
     - Take `generation = ++catalogRefreshIssued`.
     - Await `catalogService.voicegroupCatalog()`.
     - After the await, if `catalogService !== service` or `isDisposed` (project switched
       or closed): return `false`. Nothing is installed or published.
   - **Success** — the call returns `true`.
     - If `generation > catalogRefreshApplied`, install the catalog, set
       `catalogRefreshApplied = generation`, and bump `voiceList.catalogRevision` exactly
       once.
     - Otherwise drop the older result silently (a newer scan is already live).
     - Install:
       - Replace these fields: `settingsVoicegroups = groupArgs`,
         `voiceList.setVoicegroupChoices(groupArgs)`, `sampleChoices`, `waveSymbols`,
         `drumkitSymbols`, `keysplitTables`, `synthChoices`, `canMintSynths` and
         `adsrDefaults`.
       - Merge the minted-synth knowledge: `synthDefinitions.merge(catalog.synthDefinitions)`
         with disk winning, and `synthSymbols.formUnion(catalog.synths)`. Memory-only
         minted synths of unsaved banks must survive a refresh; this is today's after-save
         rule.
   - **Failure** — the call returns `false` and installs nothing.
     - The catalog, `catalogRevision`, the tab binding, the bank lease, and
       `isLoading`/`isBound`/`selectorEnabled` all stay untouched.
     - If `generation > catalogRefreshApplied`, publish the message through
       `statusMessage(message:)`. The message is the `operationFailed` payload, or
       `String(describing:)` for any other error.
     - Never write `lastSaveError`. Never emit `operationFailed`/`openFailed`. Never raise
       a dialog.
   - The call never throws and is safe to call concurrently.
   - `true` means the live catalog is at least as fresh as a scan taken after the call
     began.
   - `false` means the refresh failed or no longer applies. Any failure message is already
     on the status bar, so callers do not publish a second one.
   - It does NOT rebuild the `ProjectContext` loader, invalidate `ProjectStore.pickerSamples`,
     or touch banks. A P4 sample commit owns those steps, then calls the refresh.

3. **`resetVoicegroupCatalog()`** (internal) — project switch only. It clears every
   catalog field that contract 2 installs, including `synthDefinitions`, `synthSymbols`,
   `canMintSynths = false` and `adsrDefaults = VoiceListAdsrDefaults()`, then bumps
   `catalogRevision` once. It mirrors the fork's `loading.catalog = {}`, so the old
   project's catalog can never outlive the switch.

4. **Triggers.**
   - Project open (`finishProjectSwitch`: reset, then refresh). An outage at open is not
     an open failure.
   - After a successful `requestSaveImpl` save:
     - Run `await refreshVoicegroupCatalog()` after `session.save()` returns.
     - The call is outside the save's `do`/`catch`, and runs whichever tab is now
       selected, because the catalog is project-scoped.
     - `saveInProgress = false` only after the refresh returns, preserving today's
       ordering for save-then-catalog observers.
     - `lastSaveError` is set only by a thrown `session.save()`.
   - Future: the P2 import and the P4 sample commit. No other call sites.

5. **Status route (unchanged, reused).**
   - Path: `statusMessage(message:)` → `ShellWindow.qml` `onStatusMessage` →
     `ShellPresenter.statusText` → `ShellStatusBar.qml` `shellStatusText`.
   - The fork's 8000 ms timeout is not ported. The existing route has no expiry; task 209
     accepted the same for its 10 s line.

6. **Check probe (`TabsDrawerProbe`, check-side).**
   - `moveSoundAside(projectRoot: String) -> Bool` and `restoreSound(projectRoot: String) -> Bool`:
     - rename `<root>/sound` ↔ `<root>/sound.catalog-outage`;
     - use the `moveSongAside` guard (`projectRoot == ShellQmlBootstrap().projectRoot`);
     - refuse when the destination exists.
   - `requestShellCatalogRefresh() -> Bool`:
     - Select the unique `ShellPresenter` among `qmlChildren` whose `session.projectOpen`.
       This is the `liveLaneCosmetics` / `ShellQmlBootstrap.polyphonySession` pattern.
     - Start `Task { await session.refreshVoicegroupCatalog() }` and return `true`.
     - With no presenter or an ambiguous one, return `false`.
   - It is the Swift counterpart of the fork test's direct `submit(RefreshCatalogInput)`.
     It is not a production API.

# Implementation steps

1. `ProjectService+Bank.swift`: the contract-1 refusal and its doc comment.
2. `ApplicationSession.swift`: the two counters. `ApplicationSession+Catalog.swift`:
   contracts 2–3 with a shared private install helper. Register the file in
   `src/swift/app/CMakeLists.txt`.
3. `ApplicationSession+ProjectOpening.swift`: delete the preflight catalog read and both
   `voicegroupCatalog` fields. `finishProjectSwitch` calls reset + refresh as in the write
   set. Keep the remaining order: `projectOpen = true`, then tab restore/open.
4. `ApplicationSession+Commands.swift`: `requestSaveImpl` per contract 4. Delete the old
   synth-only merge block; the refresh install replaces it.
5. `session_catalog.swift`: `sessionCatalogOutageRetainsLastValid`. Follow
   `bank_sharing.swift`'s `ApplicationSession` harness: the `until` run-loop helper,
   `defer { app.hostClosing(); app.acknowledgeGridDetached() }`, and `runBlocking` for
   awaits.
   - Use cppID `"vgsavecheck/VoicegroupSaveTest::catalogOutageRetainsLastValid"`. Every
     message is a unique literal.
   - Setup (fail-closed through `report.fail`):
     - `stageTestProject(in: fixtureRoot, projectName: "swiftcore-catalog-outage")`;
     - `app.openProjectAndSong(path:label: "mus_session_test")` until `songOpen` and
       `settingsVoicegroupArgs()` is nonempty;
     - record `before = settingsVoicegroupArgs()`, `revision = voiceList.catalogRevision`,
       and the home `voicegroupArgument`, `bankLoadName` and `bankLease.sourcePath`;
     - open a second `ProjectService` on the root before hiding;
     - a `defer` restores `sound/` if it is still hidden.
   - Predicates:
     - "catalog outage hides the staged sound directory" (A016)
     - "the project service refuses the catalog scan with the fork outage message" — the
       second service throws exactly `.operationFailed("Project sound directory is unavailable.")`
     - "catalog outage refresh fails without a save error" — the refresh returns `false`
       and `lastSaveError` is empty
     - "catalog outage keeps the last valid voicegroup choices" — args equal to `before`
       and `catalogRevision` unchanged (A018)
     - "catalog outage keeps the song voicegroup binding" — argument, `bankLoadName` and
       `sourcePath` unchanged on the document and the voice list (A019)
     - "catalog outage leaves the voicegroup browser settled" — `!isLoading` (A020)
     - "catalog recovery restores the staged sound directory" (A023)
     - "catalog refresh settles after sound recovery" — the refresh returns `true` and
       `catalogRevision == revision + 1` (A024)
     - "recovered catalog republishes the same voicegroup choices" (A025)
     - "recovered catalog leaves the voicegroup browser settled" (A026)
   - Add the `SessionChecks.swift` call line and the check CMake registration.
6. `TabsDrawerProbe.swift`: the contract-6 methods. In `tst_ShellVoicegroupPicker.qml`,
   add `test_zzCatalogOutageRetainsLastValid`. It sorts last, after
   `test_zySelectorFailurePreservesBinding`.
   - Setup (follow `tst_ShellVoicegroupSave.qml`'s full-shell legs):
     - `fullShell = fullShellComponent.createObject(null)`, `requestActivate`, open
       `mus_route101`, wait for `songOpen` with an empty `lastSaveError`;
     - `voice.selectSlot(0)`;
     - locate `vgArgCombo` and, inside `voicegroupEditorSurface`, `vgReleaseSpin`,
       scrolling `voiceEditorScrollView` as `test_zzzzzzReleaseBoundaryEditsLeaveSongClean`
       does.
   - Guards (verify, unmapped): the probe hides `sound/` and the refresh request starts.
   - Predicates:
     - "catalog outage reaches the mounted shell status bar" — `waitForNative` until
       `findChild(shell, "shellStatusText")` is visible and its `text` contains
       "sound directory is unavailable" (A017)
     - "catalog outage leaves the mounted voicegroup selector enabled" —
       `vgArgCombo.enabled` (A021)
     - "catalog outage leaves the mounted release spin enabled" — `vgReleaseSpin.enabled`
       (A022)
   - A JS `try`/`finally` restores `sound/` through the probe on every path. The normal
     path verifies the restore ("mounted outage restores the staged sound directory",
     guard). The support's `cleanup()` destroys the shell.
7. Ledger (the implementer owns it; single writer):
   - Append S073–S085 after S072 with the `edit` tool. `proof:edit` preserves the entry-ID
     set and cannot add entries. Each entry is a header plus one `Anchor: message "…"`
     line:
     - S073–S082: the ten session literals in step-5 order;
     - S083–S085: the three mounted literals.
   - Flip each row with `deno task proof:edit` to compact MATCHED form: header +
     `Disposition: MATCHED` + one `Mapping:` line. Remove Source context and Original
     expression lines. Mappings:

     | Row | Mapping |
     |---|---|
     | A016 | S073 |
     | A017 | S083, S074, S075 |
     | A018 | S076 |
     | A019 | S077 |
     | A020 | S078 |
     | A021 | S084 |
     | A022 | S085 |
     | A023 | S079 |
     | A024 | S080 |
     | A025 | S081 |
     | A026 | S082 |

   - Run the step-8 lanes. Then run `proof check --executed --strict-mappings`: no savecore
     site may be in the strict list or not executed.
   - Delete `src/checks/voicegroupsave/proof.savecore.txt`. It has no build/runner
     registrations, and its C++ source is already deleted.
   - The commit message carries the A→S table (row → check function + literal) so the
     closed correspondence stays auditable in Git.
8. Run the acceptance commands.

# Acceptance predicate

With `sound/` hidden in a private scratch copy, a catalog refresh:

- puts "Project sound directory is unavailable." on the mounted shell status bar;
- keeps the last valid voicegroup choices, the song's voicegroup binding and bank lease;
- leaves the browser unloaded, with the selector and release spin enabled;
- reports no save error.

Restoring `sound/` and refreshing again reinstalls the same choices and settles. Project
open and Save route through the same API. A post-save refresh can no longer surface as
"Save Failed".

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock deno task build:checks
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-bankhistory --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-voicegroup --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-tabs-bank-lifetime --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
deno task proof check --executed
```

Coverage:

- **`swiftcore-bankhistory`**: the ten session predicates (A016, A018–A020, A023–A026,
  plus the service wording and no-save-error halves of A017).
- **`swiftcore-projectsession`**: open-path regression. It covers `session_io.swift`
  `settingsVoicegroupArgs() == ["_test_vg"]` after open, startup restore, failed project
  switch, and task 209's controller create flow in `voicelist_session.swift`.
- **`shell-voicegroup`** (substring: `shell-voicegroup`, `-editing`, `-picker`, `-save`):
  - the mounted A017/A021/A022 leg in `-picker`;
  - the after-save refresh regression in `-save` (`synthCatalogChoices()` gains the saved
    pulse; unified save leaves `lastSaveError` empty);
  - the New Voicegroup journey and dock catalog use at open.
- **`shell-tabs-bank-lifetime`**: project-switch gating on `catalogRevision` under the
  reset + refresh open.
- **`checks:bridge`**: the two new `@QtIgnored` stored members.
- **`proof check --executed --strict-mappings`**: run before deletion, it proves every new
  savecore anchor executed and is message-anchored. The final `--executed` run is on the
  post-deletion tree.

Named gaps:

1. **Post-save refresh failure (the misreport fix) has no deterministic stimulus.** Every
   save writes under `sound/`, so hiding it fails the save first. The fix holds by
   construction: the refresh is non-throwing and sits outside the save's `catch`. The
   reviewer inspects the `requestSaveImpl` shape. The outage predicate "catalog outage
   refresh fails without a save error" proves that the refresh itself never writes
   `lastSaveError`.
2. **Project-open outage is unreachable.** `SongCatalog.load` requires
   `sound/song_table.inc` first. The reset + refresh open path is exercised by every
   open in the regression lanes.
3. **No production QML changed**, so the brief requires no contrast lane and no
   visual-parity capture.

# Task-specific constraints

- **Predicates.** One predicate per fork clause. Each A-id maps to its step-7 S entries
  only. Unique complete literals; independent literals (recorded `before` values, never
  re-read for comparison).
- **Ingress.** Fixture manipulation happens only in the check's private scratch copy.
  Setup is fail-closed, and `sound/` is always restored (`defer` / `finally`). Real
  production ingress only: the refresh is the production API; the probe merely invokes
  it. No test-only reads, no `!("prop" in obj)`, no `Qt.callLater`, and Qt-only
  `wait`/`tryVerify` never stands in for `waitForNative` on Swift work.
- **Unchanged status bar.** Do not pin or change `ShellStatusBar` width or elision. A
  non-failure status keeps its existing ¼-width cap; the predicate reads `text`, as the
  fork reads `currentMessage()`.
- **No expiry.** Do not add a status timeout.
- **No queueing.** Do not add a refresh queue, cancellation, or event log (the fork's
  FIFO/preemption rows stay untouched).
- **No loader or picker-cache work.** Do not rebuild the loader or invalidate the picker
  sample cache.
- **Other flows.** Do not route task 209's New Voicegroup flow through the refresh.
- **Code style.** Swift 6.4; comments ≤2 lines; no hard-coded px.
- **Stop points.** Workarounds or architectural changes: stop and report.
