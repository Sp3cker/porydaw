# Sprint-4 plan: ruled residues, P3 WAV export, P2 MIDI import, P4 sample studio

Status: **complete** (controller: main session, 2026-09-29). Base `a77b8d01`, final gates green at `0aa5b5de`+ (checks 38/38, checks:shell 87/87, checks:qml 2/2, checks:qml-roll 1/1, bridge 0, proof --executed 0 not executed).
Landed: 214–218, 220–223 (P3), 230–235 (P2), 240–255 (P4), whole-branch review fixes (`3ecc2334`), async-catalog check readiness (`8f44537c`, `6d69e80b`, `a13d0667`). Decoder A081–A093 stay GAP (no external corpus); strict-mapping debt outside sprint scope: 137 sites.

Scope: every item the user released on 2026-09-28/29 (sprint-3.md status header rulings (1)–(10);
P3 rulings in `repairs/p3-wav-export-draft.md`). Standing exclusions from sprint-3 §29 are unchanged.
Global constraints: [plan.md](plan.md) § Global constraints. Verification policy: [verification.md](verification.md).

Execution rules for this sprint (controller-owned):
- Implementers run as SHARED_TREE writers: no builds, lanes, formatters. The controller runs each brief's
  commands once after writers settle, formats with plain `deno task format` (changed lines only), and
  gates on `deno task proof check --executed`.
- No `git stash`: `refs/stash` is shared by every linked worktree, and concurrent agents use it.
- Files shared between tasks are serialized; an accepted writer is checkpointed before the next writer
  edits the same file (conflict matrices below).
- The user's `e9e78068` PreferencesStore rewrite left 127 `swiftcore-projectsession` failures and two
  broken anchors (session S236/S237); repaired as a prerequisite fix, not a parity task.
- Every new window (export options/progress, Import MIDI wizard, Sample Studio, SF2 zone picker) uses
  `DialogWindow`, the Settings base (user direction, 2026-09-29).
- Modern Swift (user direction, 2026-09-29): spans, `InlineArray`, `OutputSpan` where they fit (plan.md
  Global constraints). Task 235 moves the SMF decoder onto `swift-binary-parsing`; P4's binary
  parsers (240 WAV/AIFF, 242 SF2) use the same `BinaryParsing` target.

Order (dependency waves):
1. 215 ∥ 218 → checkpoint → 217 (shares `TabsDrawerProbe.swift` with 215).
2. P3: 220 → 221 → 222 → 223 (serial; hot shell files).
3. P2: 235 ∥ 230 ∥ 231 → 232 → 233 (after 222) → 234.
4. P4: 240 (after 235) → {241, 242, 243} → 244 → {245, 246} → 247 → 248 → 249 → {250, 251, 252} → 253 → 254; 255 after 253.

Deferred decisions (defaults applied; ask the user before changing):
- Status-bar temporary-message expiry (fork `showMessage(…, 8000/10000)`): not ported in 215; shell-wide.
- File → New Song as the fork's blank-mode wizard: not adopted; visual dialogs A017–A021 and PJ03 stay GAP.

## Ruled proof closures (tasks 214, 216)

Task 214 uses ruling (1): its predicates already execute and the evidence file carries them. Task 216 uses ruling (3): atomic-reload retirement with task 176's refusal-predicate pattern. Both route SDD-track to `sdd-implementer`.

| Task | Surface / brief | Rows closed | Depends on |
|---|---|---|---|
| 214 | [Project identity's value laws close on their already-executing predicates](task-214-brief.md) | project identity A001–A019 (19 PARTIAL → MATCHED on new S040–S058); the ledger is deleted at zero open rows | none |
| 216 | [A pending reload never drops the tab's view state](task-216-brief.md) | mainwindowrouting lifecycle A025 (1 PARTIAL → RETIRED-REPRESENTATION on new S335–S337) | 176 (landed `78af02d8`); serialize the lifecycle ledger with the close-harness task |

**Write-set conflict matrix**

| File | 214 | 216 | Other tracks |
|---|---|---|---|
| `src/checks/project/proof.identity.txt` (deleted) | W | – | none |
| `src/checks/workspace/session_io.swift` | – | W (new private scenario + one call line) | flag: serialize if any track edits it |
| `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` | – | W (A025, S335–S337) | **SHARED** with the close-harness task (A106–A108): one writer at a time; the later writer takes the next free S IDs |

Neither task touches the global hot files (ShellWindow.qml, ApplicationSession*, ShellPresenter*, command/menu registries, `src/checks/CMakeLists.txt`, the check catalog, Swift/QML source lists).

**Verification ownership.** The implementer runs each lane and the proof commands.
- 214:
  - `deno task checks --filter projectidentitycheck --verbose`
  - `deno task proof sites src/checks/project/proof.identity.txt --status PARTIAL` must return 0.
  - `deno task proof check --executed` must report 0 errors and no not-executed identity S entry.
  - `deno task proof check --strict-mappings` fails on pre-existing debt in other ledgers; its output must contain no line naming proof.identity.txt.
  - After `git rm`, `proof check --executed` again.
  - Controller check: rerun the lane, then confirm `projectidentitycheck.json` carries all 25 row literals, including the seven `A009/<row>` rows. The deleted ledger's edits don't survive in history, so the brief's table is the closure record.
- 216:
  - `deno task build:checks`
  - `deno task checks --filter swiftcore-projectsession --verbose`
  - `deno task proof check --executed`: no S335–S337 not-executed line.
  - `deno task proof show …lifecycle.txt A025`

**Deferred / blocked rows (untouched)**
- Visual chrome A007 stays GAP. It is `QVERIFY(SongName::create("mus_route101"))`, a fixture guard in `VisualChromeTest::shellLoaded`, which is the excluded loaded-shell baseline composite (A018). No executing predicate targets that site; citing `intro` acceptance would be a forbidden related-test closure. The chrome ledger stays open on excluded rows either way.
- Lifecycle rows stay as they are:
  - A004/A010/A031/A043–A045/A056–A059/A073–A075/A083/A087/A090/A096/A097/A100/A101/A104/A105 stay PARTIAL (project-store/sidecar and deleted-Qt residuals).
  - A042/A055/A072/A082 stay GAP (fixture guards).
  - A080/A085/A086/A088/A089/A094/A095/A098/A099/A102/A103/A109/A110 stay GAP (project-store).
  - A106–A108 stay GAP (close-harness task).
- Voicegroupbank label guards and other ledgers' `SongName::create` conjuncts are not in these tasks.

#### Planner decisions

- 214 closes all 19 rows. ProjectIdentityChecks.swift songName/voicegroupId repeat each fork assertion with the same literals (identity.cpp:76-136 at fceecd88), and each message names its A-ID. They run via CoreCheckSupport.swift:187 case 12 → catalog entry projectidentitycheck (checkcatalog.cpp:133), and build/debug/proof-evidence/projectidentitycheck.json carries all 25 row literals.
- A009 gets one S entry whose anchor is the interpolated literal `A009/\(row): path is rejected`. The resolver (proof_anchor.ts literalPattern) treats `\(...)` as `.*?`, and the lifecycle ledger already has this precedent at S-anchors with `\(target)`/`\(label)`. The controller then checks that all seven concrete rows are in the evidence file.
- S entries are appended by a direct text edit, following e24ceefc (S086/S087). proof:edit preserves entry IDs and cannot create them.
- The identity ledger is deleted in the same commit as the closures, following task 213. Nothing registers the ledger: git grep finds only historical prose in docs/old. The ProjectIdentityChecks.swift V-1 comment stays, since comments naming deleted ledgers are the repo's convention (for example MidiCfgChecks.swift:40 names proof.save.txt).
- src/project/projectidentity.{cpp,h} are out of scope. They are built production code (CMakeLists.txt:206-207, included by banklease.h) and still referenced by open ledgers.
- Chrome A007 stays GAP. Ruling (1) needs a predicate for that site to already be executing, and none exists; its only role is setup for the excluded visual baseline.
- 216's refusal predicate is new because nothing polls the view members on each pending turn. S322 polls MIDI, bank and selection; A063/A065 poll editorViewState and timeline; S223–S231 check after the reload. The Swift pending window really exists: page.isReady is false until finishReload.
- 216's scenario goes in session_io.swift right after sessionReloadAtomicBinding (the same reload-refusal family) rather than a new file. The keep-files-small rule says not to fragment for line count, and this avoids CMakeLists/SessionChecks hot-file edits.
- 216's fixture overwrites the staged mus_session_test.mid with a second used track, since the stock fixture has only track 0 and the fork needs an alternate used track. Seeding goes through the production mutators already used by session_view_state.swift:457-465.
- 216 uses `deno task checks` lanes, not the renamed `verify*`. `proof check` cannot be scoped to one ledger (proof_reader.ts:998), so the acceptance criteria filter its output by ledger path.

## Catalog outage and the voicegroupbank write-failure family (tasks 215, 218)

### Selection and dispatch

Released under ruling (2) of 2026-09-28. Ruling (2) makes the catalog outage port the fork. The status bar reports "sound directory is unavailable". The last valid catalog, the tab binding and the browser stay usable. A later refresh recovers cleanly. The ruling covers savecore A016–A026 plus the voicegroupbank write-failure family.

The work is two genuinely separate tasks. Their write sets and lanes are disjoint:
- 215 builds the Swift catalog-refresh surface (production and checks).
- 218 is check-only. It proves an existing store refusal branch.

Both route SDD-track to `sdd-implementer`. They are judgment work that closes proof rows. Task 215 exceeds the file cap (6 production + 5 check files) as one behavior with one verification surface. That exception is named here.

| Task | Surface / brief | Rows closed | Depends on |
|---|---|---|---|
| 215 | [A catalog outage keeps the last valid catalog and reports on the status bar](task-215-brief.md). One public refresh API: `ApplicationSession.refreshVoicegroupCatalog() async -> Bool`. | savecore A016–A026 (11 GAP → MATCHED). `proof.savecore.txt` is all-closed and is deleted in the proving commit. | none. P2 (230–239) and P4 (240–269) consume its API. |
| 218 | [A bank save refused by the synth-definition writer keeps the dirty record](task-218-brief.md) | voicegroupbank A089–A093 (5 PARTIAL → MATCHED). The ledger stays for A044 and its 38-row strict debt. | none |

### Write-set conflict matrix (**bold** = shared hot file)

| File | 215 | 218 | Other writers to serialize with |
|---|---|---|---|
| `src/swift/app/ProjectService+Bank.swift` (`voicegroupCatalog` guard only) | ✎ | | P4 sample ops, if they land here |
| `src/swift/app/ApplicationSession+Catalog.swift` (NEW; P2/P4 call it, never edit it) | ✎ | | |
| **`src/swift/app/ApplicationSession.swift`** (2 `@QtIgnored` counters) | ✎ | | P2/P4 wiring |
| **`src/swift/app/ApplicationSession+ProjectOpening.swift`** | ✎ | | P2 import / close harness, if touched |
| **`src/swift/app/ApplicationSession+Commands.swift`** (`requestSaveImpl`) | ✎ | | P3 WAV export, if touched |
| `src/swift/app/CMakeLists.txt` | ✎ | | any new app file |
| `src/checks/workspace/session_catalog.swift` (NEW) | ✎ | | |
| **`src/checks/workspace/SessionChecks.swift`** (1 line in `runBankHistorySuite`) | ✎ | | **216** (session_io suite; checkpoint one writer first) |
| **`src/checks/CMakeLists.txt`** | ✎ | | any new check file |
| `src/checks/editorqml/TabsDrawerProbe.swift` | ✎ | | |
| `src/checks/editorqml/tst_ShellVoicegroupPicker.qml` (new `test_zzCatalogOutageRetainsLastValid`) | ✎ | | |
| `src/checks/voicegroupsave/proof.savecore.txt` (close, then delete) | ✎ | | |
| `src/checks/projectstore/ProjectStoreSaveChecks.swift` | | ✎ | |
| `src/checks/voicegroup/proof.tst_voicegroupbank.txt` | | ✎ | |

Not touched by either task: `ShellWindow.qml`, `ShellStatusBar.qml`, `ShellPresenter*.swift`, all production QML, `VoiceListController*.swift`, `ProjectStore*.swift` and shell registration (`ShellQmlEntries.swift`).

### Verification ownership

Each implementer runs its brief's commands under `/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock`, with the 175-second alarm on the lanes.

215's commands:
- `deno task build:checks`
- `deno task checks --filter swiftcore-bankhistory --verbose`
- `deno task checks --filter swiftcore-projectsession --verbose`
- `deno task checks:shell --filter shell-voicegroup --verbose` (all four voicegroup entries)
- `deno task checks:shell --filter shell-tabs-bank-lifetime --verbose`
- `deno task checks:bridge`
- `deno task proof check --executed --strict-mappings`, before deleting the ledger
- `deno task proof check --executed`

218's commands:
- `deno task checks --filter projectstore-savebank --verbose`
- `deno task proof check --executed --strict-mappings`
- `deno task proof check --executed`

Each implementer is the only ledger writer for its file:
- `proof:edit` makes the row flips and header edits.
- New S entries are appended with `edit`, because `proof:edit` cannot add IDs.
- MATCHED needs executed message-anchor evidence.

The controller runs the project-wide gate once after both settle: `checks`, `checks:shell`, `checks:qml`, `checks:qml-roll`, `checks:bridge` and `proof check --executed`.

Named coverage gaps (215):
- The post-save refresh failure has no deterministic stimulus, because every save writes under `sound/`. It is fixed by construction. Review the shape of `requestSaveImpl`.
- An outage at project open is unreachable, because `SongCatalog.load` needs `sound/song_table.inc` first.
- No production QML changes, so there is no contrast lane and no visual capture.

### Untouched rows

- **voicegroupbank A044 (PARTIAL).** It needs unknown-`VoicegroupId` construction, and ghost-ID ingress is banned.
- **voicegroupbank's 38 strict-debt MATCHED rows.** Fixing them would be a standalone reconciliation, which is forbidden.
- **project ioflow A014/A040, iomutations A089, workspace A048/A051/A055 (GAP).** They pin the fork's ProjectIo FIFO, catalog preemption/requeue, closed-transport join and ProjectWorkspace publication-log counts. That is the project-store backend exclusion. Swift's refresh is a direct async read with no queue or event log.

#### Planner decisions

- **Refresh API (P2/P4-facing, frozen).** `public func refreshVoicegroupCatalog() async -> Bool` on `ApplicationSession`, `@MainActor` and `@discardableResult`. It is declared in the new extension file `src/swift/app/ApplicationSession+Catalog.swift`, so it is Swift-only and not QML-registered.
- With no project open it returns false and publishes nothing.
- On success it installs the whole catalog and returns true. `settingsVoicegroups`, `setVoicegroupChoices`, samples, waves, drumkits, keysplits, `synthChoices`, `canMintSynths` and `adsrDefaults` are replaced. Minted-synth knowledge is merged: `synthDefinitions` disk-wins, `synthSymbols` union. `catalogRevision` is bumped once.
- On scan failure it installs nothing and leaves binding, lease and loading/enablement untouched. It publishes the message through `statusMessage(message:)` and returns false. It never writes `lastSaveError`, emits `operationFailed`, or raises a dialog.
- If the project switched or closed during the await, it returns false silently.
- Generation counters let the newest scan win. Older successes are dropped but still return true. Stale failures are not published.
- It never throws. It does not rebuild the loader, the picker sample cache or banks; P4's commit op owns those.
- The API was sent verbatim to PlanSampleStudio2 and PlanMidiImport2.
- **Outage refusal location.** It lives in `ProjectService.voicegroupCatalog()`, the counterpart of the fork's ProjectIo worker `scanCatalog`. It throws `ProjectServiceError.operationFailed("Project sound directory is unavailable.")` when the root or `<root>/sound` is not a directory. There is no new error case. `ProjectStore.voicegroupCatalog()` and its three check call sites stay unchanged.
- **Project open follows the fork.** The fork resets the catalog to `{}`, reaches Ready, then refreshes. So the `ProjectRead` preflight catalog read and the `voicegroupCatalog` fields of `ProjectRead`/`ProjectSwitchCandidate` are deleted. `finishProjectSwitch` calls `resetVoicegroupCatalog()` and then awaits the refresh, at the old install position. A catalog outage at open is therefore never an open failure.
- **After-save refresh.** The Swift-specific post-save rescan stays, because saved synths must reach `synthChoices`. It is routed through the API outside the save's `do`/`catch`, which fixes the "Save Failed" misreport. It runs regardless of which tab is now selected, since the catalog is project-scoped. `saveInProgress` flips false only after the refresh, preserving the order existing save-then-catalog checks observe.
- **Status route reused unchanged.** The path is `statusMessage` → `ShellWindow` `onStatusMessage` → `ShellPresenter.statusText` → `shellStatusText`. The fork's 8000 ms timeout is not ported; task 209's 10 s line has the same accepted deviation. The ¼-width cap for non-failure status is neither changed nor pinned.
- **Task 209's New Voicegroup flow is not rerouted.** Its controller-local `voicegroupArgs`/`setVoicegroupChoices` republish stays, because its bare-controller checks have no owner hook. The settings voicegroup list catches up on the next refresh, which the after-save refresh now provides.
- **Proof split across lanes.**
- Session predicates are in the new `src/checks/workspace/session_catalog.swift`, lane `swiftcore-bankhistory`. They cover A016, A018–A020, A023–A026, and A017's service wording and no-save-error halves.
- The mounted leg in `tst_ShellVoicegroupPicker.qml`, lane `shell-voicegroup-picker`, asserts only what is observable there: the status bar (A017) and the enabled selector (A021) and release spin (A022).
- The fixture rename happens only in each lane's private scratch copy, with fail-closed guards and a guaranteed restore.
- A `TabsDrawerProbe` method calls the production API. This mirrors the fork test's direct `submit(RefreshCatalogInput)`.
- **Two tasks.** 218 has a disjoint write set, its own lane (`projectstore-savebank`) and no production change, so it is split from 215 rather than merged.
- **218's stimulus.** Mint a synth while `set_synth_*` macros exist, assign it, remove the macros in scratch, then save. This reaches the same writer refusal branch the fork hit ("doesn't define the set_synth_* macros"). The fork's unreferenced caller-supplied definition is dead in the Swift seam, so A089–A093 close MATCHED on five one-per-clause predicates instead of the immutable-flag substitution in S046.
- **Ledger closure.** `proof.savecore.txt` has 70 rows already closed and zero strict debt. It closes, is verified with `--executed --strict-mappings`, and is deleted in the proving commit. The commit message carries the A→S table for auditability. The voicegroupbank ledger stays.

## ShellWindow close harness (task 217, ruling 7)

Why one task: all ten claimed rows are proven by one new shell entry, so they share one verification surface. There is no production change: the close walk, the gate and the page-before-document retirement already exist. The task adds checks, a probe, one registration line and two ledger edits.

| Task | Surface / brief | Rows closed | Depends on |
|---|---|---|---|
| 217 | Application window close (title-bar close, File → Quit and `Window.close()` all use the same `onClosing`) — [task-217-brief.md](task-217-brief.md) | host A162, A174, A176, A177, A183–A185 → MATCHED (S068–S074); lifecycle A106, A108 → MATCHED (S338–S339); lifecycle A107 → RETIRED-REPRESENTATION | 216 must land first: they share the lifecycle ledger, and 216 owns S335–S337 |

Route: SDD-track, `sdd-implementer`.

Write-set conflicts:

| File | 217 | Also touched by | Handling |
|---|---|---|---|
| `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` | A106–A108, S338–S339, one header line | 216 (A025, S335–S337, header) | Serialize: 216 first. Agreed with PlanRuledProof2. |
| `src/checks/editorqml/ShellQmlEntries.swift` (**shared registration file**) | +1 entry `shell-tabs-window-close` | any track adding shell entries (P3/P4/catalog, if they add QML lanes) | One line, placed after `shell-tabs-reload`; serialize with other entry writers |
| `src/checks/editorqml/TabsDrawerProbe.swift` | +3 methods, +1 weak property | any task adding file/document probes here | Serialize if touched |
| `src/checks/editorqml/tst_ShellTabsWindowClose.qml` | new | — | — |
| `src/checks/host/proof.tst_hostintegration.txt` | A162/A174/A176/A177/A183–A185, S068–S074, header | none in current tracks | — |

Not touched: `ShellWindow.qml`, `ApplicationSession*.swift`, `ShellPresenter*.swift`, the command and menu registries, `src/checks/CMakeLists.txt` (shell QML inputs run unlisted, as `tst_ShellWindow`, `tst_ShellTabs` and `tst_ShellSongs` already do) and `ShellQmlTests.swift` (the probe is already registered).

Verification owner: the controller runs these after the writer settles.
- `deno task checks:shell --filter shell-tabs-window-close --verbose`
- `deno task proof check --executed`: no `not executed` line for host S068–S074 or lifecycle S338–S339.
- `deno task proof check --strict-mappings`: none of the edited sites may be listed. Both ledgers stay open.
- `proof show` of host A183 and lifecycle A107.

Deferred or blocked rows, left unchanged:
- Host A004 (PARTIAL): fixture-parity residue.
- Host A087/A091 (PARTIAL): WindowDeactivate, user exclusion.
- Host A175/A178/A179: already retired.
- Lifecycle A025: task 216.
- Lifecycle A042, A055, A072, A080, A082, A085, A086, A088, A089, A094, A095, A098, A099, A102, A103, A109, A110 (GAP): `swift-project-store` exclusion.
- Lifecycle A105 (PARTIAL).
- Neither ledger closes.

#### Planner decisions

- One task, not two: every row is proven by one new entry, `shell-tabs-window-close`. Test functions a/b/c share one verification surface (sdd-plan-writing sizing).
- No production change. The close is already a two-phase handshake: `ShellPresenter.beginClose` refuses the first close, walks the tabs and banks, then accepts on `closeReady` (ShellPresenter.swift:410-447, ShellWindow.qml:192-212). The fork's synchronous `QCloseEvent` accept is proven as the outcome: with no prompt and no cancellation, the window hides (`!shell.visible`).
- A174 (host) and A106 (lifecycle) are the same fork expression (`close.isAccepted()`) in near-identical scenarios. One predicate with the message "A174/A106 …" serves both, cited by S069 and S338, which avoids a duplicate assertion.
- A107 is `m_closeAccepted` and becomes RETIRED-REPRESENTATION. This matches host A175, which retired the same flag at be366b4a.
- A108 (fork: 30 s async wait after `window.close()`) maps to `waitForNative(closeReady && !visible, 30000)` after the real `shell.close()`.
- A183–A185 (quick window destroyed before the document) map to Swift's page-then-document retirement: `tabWillLeave` → `SongTab.qml` `Component.onDestruction` → `pageReleased` → `retire` → `DocumentSession.close()` (ApplicationSession+Tabs.swift:27-92). The test observes the page repeater's `itemRemoved` for the selected tab. The document side is read through a check-side probe holding a weak reference to `selectedDocument` and reading the production `isClosed` flag. Precedent for this kind of probe read: `liveLaneCosmetics`.
- A162 is proven as a fixture-readable guard. The `projectTreeFingerprint` probe mirrors the fork's `directoryFingerprint`: it returns empty on an unreadable file, and also empty on zero files. It excludes only the scratch's top-level `settings.plist`, which is the harness preference store staged at ShellQmlTests.swift:60, not project data.
- The switch-and-close journey also compares the whole project tree after close. This comparison is unmapped: it applies the verification.md filesystem-diff rule, and closed row A178 is not reopened.
- Test b (dirty tab: Cancel keeps the window open, Discard closes it) has no ledger row. It covers the ruling's "real prompt" requirement and the fork's `closeEvent` ignore/Cancel (mainwindow.cpp:1386-1400). Window-level Cancel was proven only for dirty banks (tst_ShellTabsBankLifetime test_m).
- The new test extends `ShellTabsSupport`, not `ShellWindowSupport`. It needs `pages()`, `drawNote`, `dialogButton`, `awaitGateButtons` and a cleanup that clears probe children.
- The project switch uses `session().openProject(root)`, the API behind the picker. The fork also calls `requestProjectOpenAt` directly, and the File → Open Project menu route is already proven by tst_ShellWindow test_x.
- A18x/A17x use independent pinned literals: 471:d31e7c4a0a32a53f and 425:c27d69bdefcd9207, from tst_ShellWindow.qml:157-160.
- S-ID allocation: host S068–S074 (current max S067); lifecycle S338–S339 after task 216's S335–S337, agreed with PlanRuledProof2.

## P3 — WAV export (tasks 220–223)

### Selection

User ruling (9) of 2026-09-28 and the P3 rulings of 2026-09-29 (`repairs/p3-wav-export-draft.md`) release the export port. It renders live unsaved state: the edit-buffer document, `DocumentSession.bankLease` and the applied settings. The whole app is modal while it runs, and Cancel is the only exit. The capture `precondition`s `!bankPersistenceInFlight && !document.history.bankTransitionInFlight`. There is no VG05 dependency.

The draft had five tasks. They become three SDD briefs and one Direct task:
- **220 = draft T1 + T2 + the ledger half of T5.** All three are proven by one run of `exportcheck-loop`/`-tail`, so they share one verification surface. Rows go in the commit that proves them (`proof-ledger-workflow`).
- **223 = the rest of T5** (retiring `wavexport.{h,cpp}`). It is a pure removal of fully replaced source, so it is Direct (plan.md "Dependency-ordered work packages") with no brief file.

| Task | Surface / brief | Rows closed | Depends on |
|---|---|---|---|
| 220 | [One Swift production owner renders and writes the export WAV](task-220-brief.md): `WavExport` in `PorydawAppAudio` (totals law, gain, preview, RIFF header, refusals, streamed private-engine render with suppression pre-roll/flush, cancel/cleanup). `ExportChecks.swift` rewritten over it. Over the 3-file default: one behavior, one verification surface. | midiexport: 23 MATCHED re-derived onto message-anchored production predicates. A003, A005, A006, A009, A024, A025, A027, A029, A032, A033, A035 go from PARTIAL to MATCHED (34 MATCHED). A001/A002 stay PARTIAL and untouched. | — |
| 221 | [The export captures the live unsaved session and holds its bank](task-221-brief.md): `WavExportCapture`, `DocumentSession.wavExportCapture` (hard precondition), `AudioSettings.applyingSong`/`NativeAudio.songSettings(for:)`, `@concurrent WavExportJob.run` with Task cancellation and an AsyncStream for progress. | none (the obligations come from `spec.md:40`, AU01/AU02 and the journey) | 220 (interface; re-edits `ExportChecks.swift` and `src/swift/app/CMakeLists.txt`) |
| 222 | [File → Export WAV: options dialog, save picker, app-modal render with progress and Cancel](task-222-brief.md): `WavExportPresenter`, `WavExportSurface.qml`, the File row between fork separators, the authority modal gate and close refusal, new lanes `shell-export-options`/`shell-export-render`, `WavFileProbe`, text-contrast audit, manual page. Over the file count: one mount plus its verification (mounting without the render would be a dead action). | none | 220, 221 |
| 223 | **Direct.** Target: delete `src/audio/wavexport.cpp`, `src/audio/wavexport.h` and their `CMakeLists.txt:201-202` lines. The replacement has passed; nothing else includes `wavexport.h`, and ledger text only quotes it historically. Keep `resonance_suppressor.*`, which `audioengine.h` still includes. Acceptance: `deno task build:app && deno task build:checks && deno task checks --filter exportcheck-loop && deno task checks --filter exportcheck-tail && deno task checks:shell --filter shell-export-render && deno task proof check`. | none | 222 accepted (complete replacement passes; shares root `CMakeLists.txt`) |

Run strictly serially: 220 → checkpoint → 221 → checkpoint → 222 → checkpoint → 223.

### Write-set conflict matrix

HOT = a hot file shared across tracks. Take the build lock and serialize with the named other-track writers.

| File | 220 | 221 | 222 | 223 | Other tracks |
|---|---|---|---|---|---|
| `src/swift/app/audio/WavExport.swift` (new) | W | read | read | | — |
| `src/swift/app/audio/AudioRenderEngine.swift` | W (`AudioSettings: Sendable`, static `applySettings`) | | | | possible P4 audition work |
| `src/swift/app/CMakeLists.txt` (**HOT**: module source lists) | W | W | W | | P4 sample studio |
| `src/checks/projectstore/ExportChecks.swift` | W | W (one call) | | | — |
| `src/checks/midi/proof.tst_midiexport.txt` | W | | | | — |
| `src/swift/app/export/WavExportJob.swift` (new) | | W | read | | — |
| `src/swift/app/NativeAudio.swift` | | W | | | possible P4 audition |
| `src/checks/projectstore/ExportCaptureChecks.swift` (new) | | W | | | — |
| `src/checks/CMakeLists.txt` (**HOT**) | | W | W | | P2, P4, close harness |
| `src/swift/app/export/WavExportPresenter.swift` (new) | | | W | | — |
| `src/swift/app/ApplicationSession.swift` (**HOT**) | | | W | | P2, P4, catalog outage |
| `src/swift/app/shell/ShellPresenter.swift` (**HOT**, command registry, 620 lines) | | | W | | P2 (`file.import_midi`), close harness (`beginClose`) |
| `src/ui/shell/ShellMenuBar.qml` (**HOT**, menu registry) | | | W (File groups + separators) | | P2 (the PlanMidiImport2 peer has the grouping: import_midi joins `fileActionIds`) |
| `src/ui/shell/ShellWindow.qml` (**HOT**) | | | W | | P2, P4, close harness |
| `src/ui/shell/WavExportSurface.qml` (new) | | | W | | — |
| `CMakeLists.txt` root (**HOT**: QML_FILES, porydaw_app sources) | | | W | W | P2, P4 |
| `src/checks/editorqml/ShellQmlEntries.swift`, `ShellQmlTests.swift` (**HOT** registration) | | | W | | P2, P4, close harness |
| `src/checks/editorqml/tst_ShellMenus.qml` | | | W (`:88-89` only) | | P2 |
| `src/checks/editorqml/tst_TextContrast.qml` | | | W (`auditWavExport`) | | P4 |
| `tst_ShellExport.qml`, `WavFileProbe.swift` (new) | | | W | | — |
| `docsrc/manual/export-audio.md` | | | W | | — |
| `src/audio/wavexport.{h,cpp}` | | | | D | — |

### Verification ownership

**Implementer** (under the build lock) runs each brief's named commands:
- 220: `deno task build:checks`; `deno task checks --filter exportcheck-loop|exportcheck-tail --verbose`; `deno task proof check --executed`; `deno task proof check --strict-mappings`; `deno task proof sites src/checks/midi/proof.tst_midiexport.txt --status PARTIAL`, which must list only A001/A002.
- 221: the two exportcheck entries plus `proof check --executed`.
- 222: `deno task build:app`; `deno task build:checks`; `deno task checks:shell --filter shell-export-options|shell-export-render|shell-menus --verbose`; `deno task checks:bridge`.

**Controller** runs:
- the 222 Controller verification: the three `shell-text-contrast-song-*` entries, `shellwindow` and `proof check --executed`;
- the native macOS visual comparison against the fork reference `build-asan/porydaw.app`, listing deviations;
- the project-wide gate once the track settles.

New lanes: `shell-export-options` and `shell-export-render` are registered in `ShellQmlEntries.swift` from one `tst_ShellExport.qml`. They are split to stay under `CHECK_TIMEOUT_MS = 90 s` (`tools/run_checks.ts:38`), and they stage their own fixtures (`mus_route101`, `mus_route102`). The `exportcheck` entries (`checkcatalog.cpp:311-314`) are unchanged.

### Deferred and blocked rows

- `midi/proof.tst_midiexport.txt` A001/A002 stay PARTIAL. They are QTest `initTestCase` run-once suite guards; the swiftcore runner has no suite guard, and the Swift guard runs per row. This is a deleted-harness structure residue (standing exclusion).
- `retained/proof.tst_nativeboundaries.txt` A015/A016 (export through the lease's native voices produces RIFF) stay untouched under the standing native-boundary exclusion for the retained harness. The export owner now exists, so the controller may raise them for a separate ruling.
- Not synthesizable (they stay as named gaps, with no rows):
  - mid-write and close I/O failure;
  - native save-panel delivery (offscreen uses the Quick FileDialog fallback);
  - 4 GB and empty-render refusals through the real UI (proven at the pure layer in 220);
  - physical audio output.
- The capture `precondition` is a deliberate crash and is never executed.
- Status-message timeouts (the fork cleared after 5/8 s) are not ported: the Swift status bar has no timed messages. This is a listed visual/behavior deviation.

#### Planner decisions

- Merged draft T1+T2 and T5's ledger re-map into 220. All three share one verification surface (the exportcheck entries), and `proof-ledger-workflow` requires row edits in the commit whose checks prove them.
- Draft T5's remainder (retiring `wavexport.{h,cpp}`) became Direct task 223 with no brief. plan.md treats pure removal of fully replaced source as Direct, and sdd-plan-writing gives Direct tasks no brief file. It waits for 222 because spec.md:45 retires the old owner only after the complete replacement passes.
- No new C ABI entry. `m4a_engine_create`/`free` and the setters already reach Swift through `PorydawPlaybackNative` (AudioRenderEngine.swift:46-69,175-181); `Sequencer.render` is public (Sequencer.swift:60-73); `ResonanceSuppression` is already a Swift port (latency 2047).
- The production owner is `src/swift/app/audio/WavExport.swift` in `PorydawAppAudio`: that module owns `AudioSettings` and `ResonanceSuppression` and links PorydawCore and PorydawPlayback, and `ExportChecks` already imports it. The capture, job and presenter go in a new `src/swift/app/export/` directory in `PorydawApp`, because `NativeBankLease`, `DocumentSession` and `ApplicationSession` live there (keep-files-small: one feature directory).
- The offline render uses a private M4AEngine plus `Sequencer`, not `AudioRenderEngine`. `AudioRenderEngine.render` applies live output gain, stops 3 s after the song ends and never pre-rolls the suppressor (AudioRenderEngine.swift:243-293). The fork renders through a private engine (wavexport.cpp:97-105,121-158).
- Concurrency: a synchronous core with the fork's `(Double) -> Bool` progress/cancel contract (wavexport.h:38-42) is wrapped by an `@concurrent` job, following the precedent at ApplicationSession+ProjectOpening.swift:64. Cancellation is cooperative Task cancellation at chunk boundaries; progress flows through `AsyncStream.makeStream` with `bufferingNewest(1)`. No GCD, no `Task.detached`, no locks.
- App-wide modality has three parts: the options, picker and progress windows are `Qt.ApplicationModal`; `ShellPresenter.actionEnabled` returns false for every id while an export is active, so the native menu bar and shortcuts are gated by the single authority; `beginClose()` refuses. Persistent chrome gets no key handler, and the modal prompts use AGENTS.md's local-Space exception.
- The QML reacts to presenter state through bindings plus item-local change handlers, never through presenter-targeted `Connections` or `@QtSignal`s. The r22 landed notes record that such `Connections` were undeliverable under QtBridge.
- The File menu gets the fork's two separators around Export WAV (mainwindow.cpp:312,316) as three published id groups. The `tst_ShellMenus.qml:88-89` pin is updated; no ledger anchors those messages (checked by grep). The P2 planner (PlanMidiImport2) was told where `file.import_midi` goes.
- The engine-settings law moves into a pure `AudioSettings.applyingSong`, which `NativeAudio.songSettings(for:)` uses, so the export and the live engine share one law (NativeAudio.swift:153-158 = fork mainwindow.cpp:899-910) and the exportcheck lane can test it without an audio device.
- The exportcheck fixture opens the runner's private staged root directly instead of a copy. That closes the 'copied scratch' residue on A003/A005/A024/A032; A001/A002 (the suite-guard structure) stay PARTIAL.
- PCM16 conversion clamps in Float before converting to an integer. Swift `Int32(_:)` traps on overflow or NaN (the check-local version at ExportChecks.swift:93-96 carries that risk); the fork casts via `int32_t` (wavexport.cpp:34-38).
- The fade and tail spin boxes are integer SpinBoxes in tenths with `stepSize` 10, matching QDoubleSpinBox's defaults: 1 decimal and a singleStep of 1.0 (mainwindow.cpp:1217-1229).
- Export errors show in their own MessageDialog titled "Export WAV", matching the fork's QMessageBox::warning (mainwindow.cpp:1315), instead of ShellPresenter's critical path, which is titled "Operation Failed". Success and cancel reuse `ApplicationSession.statusMessage`.
- The capture check lives in a new `ExportCaptureChecks.swift` rather than growing `ExportChecks.swift` past about 400 lines. It is a separate concern: capture and lease versus renderer.

## P2 — the Import MIDI wizard (tasks 230–234, ruling 10)

### Selection

The fork's Import MIDI flow is `NewSongWizard` in import mode (`fceecd88:src/ui/newsongwizard.cpp`, Analysis → Identity → Sound). It is driven by `WorkspaceUi::runMidiImport`/`submitCreateSong` (`workspaceui_samples.cpp:46-90`) and commits through `ProjectIo::createSong` (`projectio.cpp:318-383`).

The track ports import mode only. New Song keeps its task-171/210 prompt, and the fork's blank-mode wizard waits on a user decision (see Deferred).

The spec is `onboardcheck/proof.import.txt`: 33 GAP rows, A046–A078. They all close, and the ledger is deleted in task 234. The 12 NATIVE-SETUP rows are already closed. In `visual/proof.dialogs.txt`, the import-page rows A022–A027 close.

The tasks also close inventory PJ04 and journey J03. Window file-drop stays excluded (plan.md § Scope decisions).

Every task routes SDD-track with seat `sdd-implementer`: each has multi-file interfaces, persistence, async lifetimes or a mounted surface.

| Task | Surface / brief | Rows closed | Depends on |
|---|---|---|---|
| 230 | [Import pipeline + Analysis-page wording law](task-230-brief.md) (`MidiImport.prepareImportedSong`, `suggestedSongLabel`, `trackLimit`, public notice texts; `ImportAnalysisSummary`) | none (feature-port producer) | — |
| 231 | [Import transaction: fork write order, refusal taxonomy, partial success](task-231-brief.md) (`ProjectService.importProjectData`/`importSong`) | none (producer) | — (∥ 230) |
| 232 | [Wizard Swift owner: `MidiImportWizardState` + `MidiImportController` (owned by `SongDockController`) + the fork whole-edit song-name law for both name fields](task-232-brief.md). Over the file cap: one controller interface. | none (producer) | 230, 231, 215 |
| 233 | [File → Import MIDI mounted: picker at `lastImportDir`, warning, ClassicStyle wizard window and three pages; lane `shell-import-wizard`; contrast reach](task-233-brief.md). Over the file cap: one mounted surface. | onboard A053–A055 → NATIVE-SETUP; A056–A060, A063–A065, A069–A072, A078 → MATCHED. Dialogs A022/A024/A026 → MATCHED; A023/A025/A027 → RETIRED-REPRESENTATION | 232, 222 (checkpointed), 215 |
| 234 | [Commit variants on the mounted wizard: rescale off, dedup, overflow refusal, `-R50` vs unset Song Settings reverb, new voicegroup + catalog refresh + tab, collision warnings, partial registration + Register Song retry with a dirty tab; lane `shell-import-commit`](task-234-brief.md) (checks + ledger only) | onboard A046, A047, A073 → NATIVE-SETUP; A048–A052, A061, A062, A066–A068, A074–A077 → MATCHED; **`proof.import.txt` deleted** | 233 (checkpointed), 211, 215 |

### Write-set conflict matrix

⚠ marks a hot file shared across tracks.

| File | 230 | 231 | 232 | 233 | 234 | Other tracks |
|---|---|---|---|---|---|---|
| `src/swift/core/MidiImport.swift` | ✎ | | | | | |
| `src/swift/app/midiimport/*.swift` (new) | ✎ Summary | | ✎ State, Controller | | | |
| `src/swift/app/ProjectService+Import.swift` (new) | | ✎ | | | | |
| `src/swift/app/songlist/SongDockController.swift`, `SongListPresenter.swift`, `src/ui/songview/quick/docks/SongConfirmDialog.qml` | | | ✎ | | | |
| ⚠ `src/swift/app/CMakeLists.txt` | ✎ | ✎ | ✎ | | | 215 (uncommitted in tree) |
| ⚠ `src/checks/CMakeLists.txt` | ✎ | ✎ | ✎ | ✎ (`shell_qml_lane`) | | 215 (uncommitted), P3/P4 |
| `src/checks/songlist/songlist_service.swift` | | ✎ | ✎ | | | |
| `src/checks/editcheck/EventChecks.swift` | ✎ | | | | | |
| ⚠ `CMakeLists.txt` (root QML_FILES) | | | | ✎ | | P3/P4 |
| ⚠ `src/ui/shell/ShellWindow.qml` | | | | ✎ (one `MidiImportHost`) | | P3/P4, close harness |
| ⚠ `src/swift/app/shell/ShellPresenter.swift` | | | | ✎ (`file.import_midi` row) | | 222 (File groups), P4 |
| ⚠ `src/checks/editorqml/tst_ShellMenus.qml` | | | | ✎ (File pin +1) | | 222 |
| ⚠ `src/checks/editorqml/ShellQmlEntries.swift` | | | | ✎ | ✎ | P3/P4 |
| ⚠ `src/checks/editorqml/ShellQmlTests.swift` | | | | ✎ (+1 registration) | | P3/P4, close harness |
| ⚠ `src/checks/editorqml/tst_TextContrast.qml` | | | | ✎ | | P4 |
| `src/checks/editorqml/ImportWizardProbe.swift` (new) | | | | ✎ | ✎ | |
| `src/checks/onboardcheck/proof.import.txt` | | | | ✎ | ✎ + delete | |
| ⚠ `src/checks/visual/proof.dialogs.txt` | | | | ✎ A022–A027 + header | | P4 (A011–A016): one writer at a time |

Serialization:
- 230 ∥ 231: their only overlap is the two CMake source lists, so one controller applies those lines.
- 232 follows both of them and task 215.
- 233 follows 232, and follows a checkpoint of 222. It edits the same ShellPresenter File groups and the same `tst_ShellMenus` pin.
- 234 follows a checkpoint of 233, which it reuses for the probe, the entry list and the ledger.
- No task in this track touches `ApplicationSession*.swift` or `KeybindingRegistry.swift` (`file.import_midi` is already registered).

### Verification ownership

Writers run their brief's lane under the build lock/175-second alarm:
- 230: `deno task checks --filter swiftcore-midiimport --verbose`
- 231: `deno task checks --filter swiftcore-projectsession --verbose`
- 232: `deno task checks --filter swiftcore-projectsession --verbose`, `deno task checks:shell --filter shell-songs --verbose`, `deno task checks:bridge`
- 233: `deno task checks:shell --filter shell-import-wizard --verbose`, `deno task checks:shell --filter shell-menus --verbose`, `deno task checks:shell --filter shell-text-contrast`, `deno task checks:bridge`
- 234: `deno task checks:shell --filter shell-import-commit --verbose`, `deno task checks:shell --filter shell-import-wizard --verbose`

Every task also runs `deno task proof check --executed`. Tasks 233 and 234 add `--strict-mappings`. The lane names do not contain one another, so each `--filter` substring selects one entry.

The controller owns:
- the project-wide gate after the writers settle;
- task 233's Controller verification: a native macOS smoke run of File → Import MIDI with the real NSOpenPanel, and a `capture-macos-app-window` comparison of every wizard page against the fork reference build (`build-asan/porydaw.app`), with each deviation listed.

The proof edits belong to the implementer, in the same commit as the proving checks, through `deno task proof:edit`. There is no ledger-agent seat.

### Deferred / blocked rows

- **dialogs A017–A021** (New Song blank-mode wizard pages) and **PJ03**'s player/voicegroup/config/blank-MIDI conjuncts: left untouched until the user decides whether New Song adopts the wizard's blank mode (userDecision). The wizard component would host it with an Identity → Sound page set.
- **dialogs A001**: the shared frozen-PNG `compareShown` helper across five dialog families. It is a visual-baseline exclusion.
- **dialogs A003–A016**: the settings/theme dialogs (excluded) and the sample-editor/Sf2 rows (P4 track).
- **iomutations**: the task-171 creation rows are unchanged.
- **Native file-dialog delivery and the visual comparison**: not provable offscreen, so they go to Controller verification. On-device audio of the imported song is a physical-output exclusion.

#### Planner decisions

- Import mode only: New Song keeps its task-171/210 prompt (ruling 5, DONE). The blank-mode wizard is a user decision; the fork shares one `NewSongWizard` class for both modes (newsongwizard.h:13-20).
- Swift owner: a pure `MidiImportWizardState` (the laws, testable without Qt) plus a bridged `MidiImportController` owned by `SongDockController`. SongDockController already owns the create/register/delete lifecycle (install/detach, SongDockController.swift:38-56). This avoids edits to the hot `ApplicationSession*.swift`.
- Domain split: `prepareImportedSong`, `suggestedSongLabel` and `trackLimit` go in PorydawCore `MidiImport` (the fork keeps them in core/newsongwizard; `songFile`:637-654, `buildPages`:589-598, clamp:429-431). The Analysis wording goes in the app-layer `ImportAnalysisSummary` (`refresh`:423-525).
- Transaction freezes the fork order (projectio.cpp:318-383), with refusals before any write: invalid label; existing .mid ('MIDI file already exists: <path>', :326-328); taken label (task 171/210 stray parity); voicegroup name or collision. Then optional voicegroup → .mid → flags → registerSong → snapshot. No rollback. Earlier writes stay (:318-321). The existing `ProjectService.createVoicegroup` is reused, with the store re-acquired after its reopen.
- Partial success: after any Finish failure the controller refreshes the song list, so a stray or partial registration shows its retry badge at once (spec.md § Onboarding: retry badge). File → Register Song (task 211) completes it. The fork surfaced it only on the next refresh.
- Finish opens the song in a new tab only when a voicegroup was created, following fork `reconcileSnapshot` (workspaceui_project.cpp:195-204). Otherwise the status shows 'Created and registered %1 (song ID %2)' (:580-594).
- Catalog: the controller consumes task 215's `ApplicationSession.refreshVoicegroupCatalog() async -> Bool` after an import that created a voicegroup, including after a later-step failure. The contract was confirmed with PlanCatalogOutage2.
- Song-name law: the fork's `LowercaseNameValidator` whole-edit fold-then-accept-or-reject (:78-88) is adopted for both name fields through `SongListPresenter.acceptSongLabelEdit`. It closes A065 (a paste of 'mus 3!' is rejected). Task 210's keystroke journeys give identical results (tst_ShellSongs:277-311), so there is still one law.
- Warnings: titled 'Import MIDI' and 'New Voicegroup' MessageDialogs, as in the fork (workspaceui_samples.cpp:59,80; newsongwizard.cpp:241-251). Service failures use the existing `operationFailed` / 'Operation Failed' channel instead of the fork's 'Project Change' title, keeping one error channel (task 210 precedent).
- Window: `Qt.ApplicationModal` (fork `exec()`) with `QWizard::ClassicStyle` chrome (themeruntime.cpp:69; tst_themelayout_settings.cpp:52) and `NoBackButtonOnStartPage` (:585). Minimum size is baseFontPx×60 by ×44 (:586-587).
- Route: `file.import_midi` goes right after `file.new_song` and is enabled when projectOpen (mainwindow.cpp:294-300,960-961). Busy gates refuse silently in `requestImport`, like the fork's early returns. The remembered directory uses PreferencesStore key 'lastImportDir' (the fork's QSettings key) and is stored only after a successful read (workspaceui_samples.cpp:50-62).
- Visual rows: the currentId page-flow rows A022/A024/A026 are behavior and close MATCHED. The `wizardRegions` rows A023/A025/A027 retire as RETIRED-REPRESENTATION, since they only feed the frozen QWidget PNG (A001). A001 stays under the visual-baseline exclusion.
- Setup-guard rows (fixture copy, project open, fixture decode: A046/A047/A053/A054/A055/A073) close as NATIVE-SETUP. This follows the ledger's own precedent, A079/A092/A097/A099.
- A068 (SongSettingsWidget keeps an unset reverb) is proved on the mounted Song Settings page in task 234. It is required to delete the ledger, and the Swift owner is EngineSettingsStore (reverb -1 ↔ nil, EngineSettingsStore.swift:95,158).
- Lanes: new shell entries `shell-import-wizard` and `shell-import-commit`, whose names are not substrings of each other (the run_checks `--filter` is `includes`). Staged fixtures include test_midis/*.mid, music_player_table.inc, the voicegroup hub, dummy/fixture_alt and the registration files. The overflow source is synthesized by a check probe instead of a binary fixture. Swift predicates run in swiftcore-midiimport and swiftcore-projectsession.

## P4 — Sample Studio, sample picker, SoundFont zone picker (ruling 10): tasks 240–255

Selection: every open samplecheck row (decoder 93, soundfont 34, dsp 67, analysis 21 + 14 MATCHED-with-strict-debt, editor 130, integration 71, project 63), visual browsers sample-picker A013–A015/A017, themelayout color A039, plus the spec-only SA01–SA06 obligations (commit transaction, loader refresh, voice assignment, reopen). Pure domain first (module `PorydawSample`, Foundation-only + one C codec module), then store/provenance, then the editor objects, then the mounted surfaces. Oracle: `fceecd88` (decoder/dsp check revisions `5af4355`/`1f9f8a5` are byte-identical to it; `a7fcaa3` drops decoder A042–A046's f64 block, so `fceecd88` is the spec).

### Dispatch table (all SDD-track; seat `sdd-implementer` unless noted)

| Task | Surface / brief | Rows closed | Depends on |
|---|---|---|---|
| 240 | `PorydawSample` module, WAV/AIFF decoder, `samplecheck` lane — task-240-brief.md (over file count: lane registration is part of the single verification surface) | decoder A001–A056 (A030 retired) | — |
| 241 | Compressed MP3/FLAC/Ogg via restored dr_mp3/dr_flac/stb_vorbis behind `src/audio/sample_codec.{h,c}` — task-241-brief.md — **seat `qt-cpp-reviewer`** (native C) | decoder A057–A071, A074–A079 | 240 |
| 242 | SF2 reader, zone extraction, zone-picker model — task-242-brief.md | soundfont A001–A017, A019–A033 (A022/A023 retired) | 240 |
| 243 | DSP kernel (resampler, quantize/dither, markers, normalize, seam metrics) — task-243-brief.md | dsp A001–A025 (A025 retired) | 240 |
| 244 | Render pipeline `SampleDocument`, crossfade, 8-bit WAV writer, optional corpus plumbing — task-244-brief.md | dsp A026–A034, A052–A067; analysis A016–A021; decoder A072–A073, A080 (retired), A081–A093 only with a corpus run; soundfont A018 | 241, 242, 243 |
| 245 | YIN pitch hint, loop search/refine — task-245-brief.md | analysis A001–A015 | 243, 244 (ledger order) |
| 246 | `SampleRegistrar` probe/validate/register + loader/engine agreement — task-246-brief.md | project A001–A063 (A025–A039 retired: check-only inspector); dsp A035–A051 (NATIVE A046–A051 ported); integration A001–A012; project+dsp ledgers deleted | 244 |
| 247 | Provenance: SHA-256, sidecar, update, reopen resolution — task-247-brief.md | integration A013–A059, A065–A071 | 246, 244, 242 |
| 248 | Commit transaction + loader-context rebuild + bank republication (no ledger rows; spec SA05/SA06, VG05 coherence for new symbols) — task-248-brief.md | — (swiftcore-bankhistory predicates) | 247 |
| 249 | Editor presenter: params, dialog-local undo, rate commit, naming, readouts, commit bytes — task-249-brief.md | editor A001–A021, A025–A036, A089–A095, A106–A115; integration A060–A064; integration ledger deleted | 244, 246, 247 |
| 250 | Loop/pitch tools + seam badge — task-250-brief.md | editor A022–A024, A047–A077 | 249, 245 |
| 251 | Waveform display-list model, handles/zoom/fit/seam view, sample theme roles — task-251-brief.md | editor A078–A084; themelayout color A039 | 249, 250 |
| 252 | Audition strip on `AudioAudition` + analysis strict-debt repair — task-252-brief.md | editor A085–A088, A116–A119 (A118/A119 retired), A121–A125; analysis A022–A035 mappings; analysis ledger deleted | 249, 245 (code parallel with 250/251; editor-ledger edit after 251) |
| 253 | Mounted Tools → Import Sample → Sample Editor window → commit; lanes `shell-sample-studio(-refusal)` — task-253-brief.md (over file count: one mounted journey) | editor A037–A046, A096–A105, A120, A126–A130; editor ledger deleted | 215, 241, 248, 249, 250, 251, 252 |
| 254 | VoiceEditor “+”/“✎” routes, destination assignment, edit-from-provenance, SF2 zone picker window; lane `shell-sample-studio-voice` — task-254-brief.md | soundfont A034; soundfont ledger deleted | 253, 242, 247, 248 |
| 255 | Sample picker parity (per-row “∞” loop badge, fork detail line) — task-255-brief.md | browsers A013–A015, A017 | — |

Waves: W1 {240, 255} · W2 {241, 242, 243} · W3 {244} · W4 {245, 246} · W5 {247} · W6 {248, 249} · W7 {250, 252} · W8 {251} (252's ledger step after it) · W9 {253} · W10 {254}. 253 additionally waits for task 215 (catalog refresh API + shared ApplicationSession files).

### P4 shared constraints (briefs cite these; not repeated there)

- **Scaffolding rule.** A row whose original expression only asserts harness setup (`QTemporaryDir::isValid`, `createWav2AgbProject`/`writeFile` fixture writes, `QFAIL` data-row guards, `QSKIP`, `AudioEngineTestAccess`, forced-null-backend probes) → RETIRED-REPRESENTATION “harness scaffolding; the Swift predicate stages its own fixture”. A setup row that calls a production API (decode, register, voicegroup_load) → MATCHED via a precondition predicate on that call. Widget-lookup rows (`findChild`, objectName, `QDialogButtonBox` button, `QScrollArea` found) → RETIRED-REPRESENTATION “QWidget object lookup; QML binds presenter state”.
- **Predicates.** cppID `samplecheck/SampleProcessingTest::<method>` (ledger method names); one unique message literal per A-id; MATCHED only with message-anchored S entries and executed evidence; first closure in a ledger updates its header (`Swift counterpart:`, `Command: deno task checks --filter samplecheck --verbose`). Fork thresholds/goldens are expected values; never re-pin Swift output. Fixtures are synthesized by the check (`SampleFixtures.swift`) except the named staged binaries.
- **Ledger single-writer order** (proof edits in the proving commit via `deno task proof:edit`; never two writers of one ledger concurrently): decoder 240→241→244; soundfont 242→244→254; dsp 243→244→246; analysis 244→245→252; project 246; integration 246→247→249; editor 249→250→251→252→253; browsers 255; themelayout color 251. Each closing task deletes its fully closed ledger (C++ sources already deleted at `5b8dcc9e`) once `--strict-mappings` lists none of its sites.
- **Registration hunks** are append-only and serialized in task-number order within a wave (a later writer re-reads after the earlier writer's checkpoint): `src/swift/sample/CMakeLists.txt`, `src/checks/CMakeLists.txt`, `src/checks/samplecheck/SampleChecks.swift`, `SampleFixtures.swift`, `src/checks/checkcatalog.cpp`, `src/swift/app/CMakeLists.txt`, `src/swift/project/CMakeLists.txt`, root `CMakeLists.txt`, `tools/qtbridge_surface_baseline.json` (regenerated with `deno task bridge:baseline`, never hand-edited).
- `PorydawSample` imports only Foundation and `PorydawSampleCodec`; UI-facing models live in `src/swift/app/samplestudio/`; QML in `src/ui/shell/samplestudio/`. Colors only via GridPalette pairs; geometry from `baseFontPx`; Swift 6.4; comments ≤ 2 lines.

### Write-set conflict matrix (★ = cross-track hot file)

| File | P4 writers | Other tracks |
|---|---|---|
| ★ root `CMakeLists.txt` (porydaw_app sources, QML block, add_subdirectory) | 240, 241, 253, 254 | MIDI (QML block), WAV |
| ★ `src/swift/app/CMakeLists.txt` | 242, 248, 249, 250, 251, 252, 253, 254, 255 | 215, MIDI, WAV |
| ★ `src/checks/CMakeLists.txt` | 240–254 (not 255) | MIDI 230–233, WAV |
| ★ `src/checks/checkcatalog.cpp` + corecheck trio (`core_check.h`, `tst_swiftcore.*`, `CoreCheckSupport.swift`, `native_check.*`) | 240, 241, 244 | — |
| `src/swift/sample/CMakeLists.txt` | 240, 241, 242, 243, 244, 245, 247, 251 | — |
| `src/swift/project/CMakeLists.txt` | 246, 247, 248 | — |
| `src/checks/samplecheck/SampleChecks.swift` | 240–247, 249–252 | — |
| `src/checks/samplecheck/SampleFixtures.swift` | 240, 243, 244, 246 | — |
| `src/swift/sample/SampleImport.swift` | 240, 241 | — |
| `src/swift/project/VoicegroupStore.swift` | 248 | savecore/voicegroup work — flag |
| `src/swift/app/ProjectService+Samples.swift` | 248, 253 | — |
| `SampleStudioWorkflow.swift`, `SampleStudioHost.qml`, `ApplicationSession+Samples.swift` | 253, 254 | — |
| ★ `src/swift/app/ApplicationSession.swift`, `+ProjectOpening.swift`, `+Close.swift` | 253 | 215 (first), close harness |
| ★ `src/swift/app/ApplicationSession+Audio.swift`, `voicelist/VoiceListController.swift` | 255 | flag before dispatch |
| ★ `src/swift/app/shell/ShellPresenter.swift` (>600 lines), `src/ui/shell/ShellMenuBar.qml`, `src/ui/shell/ShellWindow.qml` | 253 | MIDI (file.import_midi, host), WAV (file.export_wav), close harness |
| ★ `src/checks/editorqml/ShellQmlEntries.swift`, `tst_TextContrast.qml` | 253, 254 | MIDI |
| ★ `src/checks/editorqml/tst_ShellMenus.qml` | 253 | MIDI, WAV |
| `src/checks/editorqml/tst_ShellVoicegroupPicker.qml` | 255 | — |
| ★ theme: `GridPalette.swift`, `ThemeColorTables.swift`, `ShellAppearance.swift`, `themecolor/ThemeColorPresets.swift` | 251 | any theme work — flag |
| `src/checks/audio/AudioAuditionChecks.swift` | 252 (one added expect) | — |
| `src/checks/fixtures/decompproject/{Makefile,audio_rules.mk,samplesources/*}` | 241, 253, 254 | — (declared only by P4 entries + contrast entries) |

### Verification ownership

The controller runs every build/lane after writers settle, serialized with `/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task …`; implementers do read-only local inspection only (no builds/lanes/formatters mid-flight). Lanes: `samplecheck` (240–247, 249–252), `swiftcore-bankhistory` (248), `swiftcore-themecolor` (251), `swiftcore-playback` (252), `checks:shell --filter shell-sample-studio` (253/254; covers -refusal/-voice), `shell-menus`, `shell-text-contrast`, `shell-voicegroup`, `shell-voicegroup-picker` (255), `checks:bridge` (249–255), `build:app` (241), then `deno task proof check --executed --strict-mappings`. Controller-only: optional corpus run `PORYDAW_SAMPLE_CORPUS=<built pret project> … checks --filter samplecheck` (244); visual captures vs the fork reference build `build-asan/porydaw.app` (253, 254); one manual verification.md Sample-Studio journey on a real project ending in `make` (254).

### Deferred / blocked rows (left untouched)

- decoder A081–A093 — need a built external corpus (`PORYDAW_SAMPLE_CORPUS`); stay GAP until the controller runs it (then 244's predicate closes them and deletes the decoder ledger).
- visual `proof.dialogs.txt` A011, A012, A014, A015 (sample-editor baselines) and A016 (Sf2ZonePicker baseline); `proof.browsers.txt` A018 (sample-picker baseline) and PARTIAL A007/A009/A011 (voicegroup-browser pixel/profile) — standing exclusion: frozen QWidget baseline PNGs.
- Physical audio-output conjuncts — excluded infrastructure (null backend); P4 PCM proofs render offline engines.
- Real wav2agb binary output — not vendored; agreement proven through the native loader (the engine's consumer) and the optional corpus.

#### Planner decisions

- Decoder strategy: Swift owns sniffing, WAV (incl. extensible, float64, lying data size), AIFF, SF2 RIFF, conversion laws, downmix and refusal taxonomy; only MP3/FLAC/Ogg decode in C via restored `external/dr_libs/{dr_mp3,dr_flac}.h` + `external/stb/stb_vorbis.c` (deleted at 5b8dcc9e with their sole consumer) behind one function `pd_sample_decode` in `src/audio/sample_codec.{h,c}` (inside the AGENTS.md native boundary); dr_wav is NOT restored — the fork's own registrar and the native loader already parse WAV in-house (samplereg.cpp inspectSampleWav, voicegroup_loader.c load_wav_from_path).
- C seam returns raw codec samples (f32 for MP3/Ogg, s32 for FLAC) so Swift reproduces the fork's exact clamp and /2147483648 conversions — required for the FLAC FNV golden 0x6c3d054141a6aae7 (decoder A065); allocation failure maps to the codec's 'too long to import' message (fork backstop semantics).
- VG05 is not a blocker: DocumentSession.applyBankEdit publishes through SharedBankState to all sessions sharing a bank (bank_sharing.swift twoOpenSessionsShareBankEdit / mountedEditReachesPeerTab; proof.session.txt task-37 VG05). Voice assignment after commit = VoiceListController.applyVoiceEdit (undoable bank edit); 248 proves new symbols resolve in peer sessions after the loader rebuild.
- Loader rebuild is P4's, not 215's: 215 (PlanCatalogOutage2, frozen) only rescans/republishes catalog lists via `ApplicationSession.refreshVoicegroupCatalog() async -> Bool`; the fork commitSample rebuilt the voicegroup loader context (decompproject.cpp 362–380). 248 swaps ProjectContext, rebinds VoicegroupStore (keeping unsaved edits/tokens), drops pickerSamples and republishes via the existing ProjectService.publish path; 253/254 then call 215's API — no second catalog-refresh path.
- NATIVE rows: editor 50 → 47 ported as behavior (presenter/QML predicates), A099 (QScrollArea lookup), A118 (forced null backend), A119 (AudioEngineTestAccess::parkDevice) retired; A037/A038/A096/A097 setup rows fall under the scaffolding rule (retired); soundfont 12 → A022 retired (widget lookup), A024–A034 ported (model + mounted accept); dsp 6 (A046–A051) ported — they are headless loader parity, the 'native dialog' boilerplate reason was wrong; integration 3 (A061/A062/A064) ported as edit-mode presenter predicates.
- project A025–A039 (projectInspect) retire: `SampleRegistrar::inspectSampleWav` had no production caller at fceecd88 (git grep: only checks); written-WAV fields are proven through voicegroup_load (project A047–A050) and a check-local RIFF reader (dsp A039–A043).
- Analysis A022–A035 are MATCHED but in strict-mapping debt (proof check --strict-mappings lists them); 252 adds message-anchored mappings (one new expect in AudioAuditionChecks) before deleting the analysis ledger.
- samplecheck lane: registered as swiftCore suite `PDC_SUITE_SAMPLE = 35` / slot `sampleCheck` / entry `samplecheck` (240), fixtures staged from `src/checks/fixtures/decompproject/samplesources/` (241: tone.mp3/.flac/.ogg/.opus restored byte-exact from fork `samplecheck_fixtures.h`; 253: hires_tone.wav; 254: zones.sf2); optional corpus via a dedicated `swiftSample` handler + `--pdc-sample-corpus=` (244), reusing the existing PORYDAW_SAMPLE_CORPUS allowance in deno.json/run_checks.ts.
- Source hash: pure-Swift SHA-256 (CryptoKit is Apple-only, Linux is a target, no Qt hash reachable without new C++), verified by FIPS vectors and fork-format sidecar decode.
- Reopen fallback follows the fork exactly: silent fallback to the committed WAV and sidecar removal on save (continueEditSampleFlow shows no extra warning) — no invented warning text.
- Seam badge: fork literal chip colors are not reproduced (text-contrast rule forbids literals; no theme role); badge text uses windowText/warningText/errorText by severity on the window surface.
- Sample theme roles ported from fork presetcolors.h (4 roles × 3 modes) with the fork's five legibility pairs mapped item_background→menuBackground, item_alternate_background→alternateBackground (ThemeColorPresets row assertions), closing themelayout A039.
- Editor window = separate ThemedWindow, Qt.Dialog + ApplicationModal (fork QDialog::exec), font-derived 75×53.33 baseFontPx initial size; waveform drawn through the existing DisplayList boundary (displayRevision + displayList(list:)), no native changes.
- Sample picker family (ruling 10) = parity of the existing SamplePicker.qml with fork samplepicker.cpp (per-row ∞ badge, 'Loops · N Hz · S s' detail, keysplit/typed detail) using the store's existing picker cache; closes browsers A013–A015/A017.
- Hosting follows PlanMidiImport2's pattern (own Host.qml with FileDialog/MessageDialog + window Loader); P4 owns its workflow on ApplicationSession because it needs voiceList, audio and 215's refresh.

## Following-sprint backlog (user, 2026-09-29)

- Separate song saving from voicegroup saving: add a "Save" button around the voicegroup editor so bank edits save on their own. Related defect: unified Save rewrites the song MIDI with canonicalized bytes even for flags/bank-only edits (`ProjectService+Bank.swift:179` via `SongDocument.captureSave`, `SongDocument.swift:393-409`); `shell-voicegroup-save`'s `test_zzzzzUnifiedSaveAndUndoRestorationReceipts` fails when run in isolation.
