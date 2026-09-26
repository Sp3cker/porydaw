# Context

VG05 shared-bank two-tab journey. Prove-first task: the Swift store is strong
and must not be rewritten; what is missing is the mounted two-tab UI journey
(next-sprint §3 "Shared bank (VG05)"; inventory.md VG05's inferred gap —
"siblings keep stale slots" — is already disproven at session level, because
`DocumentSession.bankSlots/bankDirty` read the shared state live, but no
mounted predicate observes it). Fork-main = `fceecd88`.

1. **Fork law — canonical bank, immutable views**
   (`git show fceecd88:src/project/decompproject.h:136-173`): the project
   worker keeps the one canonical bank per `VoicegroupId`; every publication
   is an immutable `LoadedBankView` copy; a hard error leaves the previous
   record (source, lease, file time) untouched.
2. **Fork fan-out** (`git show fceecd88:src/ui/workspaceui_voicegroup.cpp:
   93-107`, `WorkspaceUi::applyBankView`): install the canonical view first;
   every tab whose `voicegroupId()` matches swaps its lease atomically and
   hands the roll the new voicegroup (`songtab.cpp:197-202`); only the
   selected tab rebuilds the browser presentation and emits
   `selectedSongStateChanged`. Dock title stars on selected-tab bank dirty
   (`workspaceui_voicegroup.cpp:159-213`).
3. **Fork dirty surfaces** (`git show fceecd88:src/ui/workspaceui_tabs.cpp`):
   tab captions star on document dirty only (`:150-161` `refreshTabTitle`);
   the window title stars on document-or-bank dirty (`:198-202`
   `selectedSongDirty`); the per-tab close gate asks on document dirty only —
   the fork's own "Known limitation: users must save bank-only edits before
   closing the tab" (`:485-500` `requestCloseTab`, comment at :497);
   project-switch/close prompts ask per tab on document-or-bank dirty with
   "including voicegroup edits" wording (`:551-585` `maybeSaveTab`).
   Origin-aware gate: only the pending transition's tab refuses close
   (`voicegroupviewcache.cpp:88-95`).
4. **Swift core (strong)**: one `SharedBankState` per
   `BankBindingIdentity(owner, sourcePath, sectionLabel)` with weak-session
   subscribers (`SharedBankState.swift:16-57`); `ProjectBankViews` owns the
   identity map and the close-walk `dirtyBanks()` (:59-93). Sessions read the
   shared state live (`DocumentSession.swift:57-60`), attach at init (:130,
   :155 — a late opener adopts the current dirty view), re-attach on
   `adoptBank` (:507-515), and detach on `close()` (:487-497). A peer edit
   reaches every subscriber: `accept` → `sharedBankDidChange` →
   `publishChange([.bank, .dirty])` (:517-524). Workspaces keep
   `session.onChange` live while hidden (`DocumentWorkspace.swift:209-235`);
   only the active workspace rebinds audio on `.bank` (:345-351), and
   `activate()` binds the session's current lease (:133-141). Captions and
   the close gate read `SongTabSession.dirty = document.isDirty ||
   bankDirty` (`SongTabsController.swift:63-66`, strip `SongTabs.qml:
   185-187`); `tabStateChanged` refreshes every tab's dirty, then the
   selected document's window/dock state (`ApplicationSession.swift:
   871-885`); tab switch rebinds the dock through
   `voiceList.refresh(from:)` (`VoiceListController.swift:246-254`, panel
   star :302-312); mounted editor commits are origin-guarded
   (`VoiceEditorController.swift:73-107`; `applyVoiceEdit` routes through
   `DocumentSession.applyBankEdit`, `VoiceListController.swift:524-530`).
   Close walk: dirty tabs first, then each dirty bank once
   (`SongTabsController.swift:564-597`, `answeredCloseBanks`); tab-Save saves
   document+bank (`ApplicationSession.swift:768-796`), bank-Save
   (:802-828); retirement closes the session and detaches it (:890-898).
5. **Executing evidence today**: `bank_sharing.swift:10-56`
   (`twoOpenSessionsShareBankEdit`: peer sees edit + dirty, late subscriber
   catches up), `:351-446` (`bankBackgroundEditReachesSelectedAudio`: two
   real tabs, hidden-peer session edit, selected tab's native CGB telemetry
   switches Sq1→Noise) — both run in `swiftcore-bankhistory`
   (`SessionChecks.swift:94-103`). Single-tab mounted bank gates exist
   (`tst_ShellTabs.qml:1140-1309`, tests l/m/n). Grep-verified: no ledger
   S-row anywhere cites `twoOpenSessionsShareBankEdit` or
   `bankBackgroundEditReachesSelectedAudio`.
6. **Fixture readiness**: `mus_route101` and `mus_route102` both bind
   `-G fixture_rich` (`src/checks/fixtures/decompproject/sound/songs/midi/
   midi.cfg:3-4`); the `shell-tabs` entry already stages both plus
   `fixture_rich.inc` (`ShellQmlTests.swift:36-53, 86-87`). No new fixture
   files, no CMake or manifest change.
7. **Ledgers**: `proof.tst_voicegroupbank.txt` A019–A021 (lease reused across
   a shared voicegroup) MATCHED; its open rows are store/ingress tails
   (A001, A003, A014/A015, A017, A022, A044, A048–A050, A063/A064, A077,
   A086–A093) untouched by a mounted journey. `proof.tst_voicegroupviewcache.
   txt` = 57 GAP + 2 PARTIAL (A023/A036) with Swift index S001–S012.
   `proof.session.txt` carries the bank-sharing S-rows (S176–S178) and the
   mounted-lane precedent (S186–S188, shellwindow rows).
8. **Likely failures, from source** (the journey is expected to pass; these
   are the only seams with real risk, in order):
   - Peer caption/dock refresh — the whole chain
     (`accept`→`sharedBankDidChange`→`sessionStateChanged`→
     `tabStateChanged`→`refreshDirty`/`refreshVoicegroupDock`) is wired but
     never observed mounted with two tabs (single-tab tests only).
   - Close walk with two tabs over one bank — `settleCloseAll` must ask each
     dirty tab, then the bank exactly once; never proven with a shared bank.
   - Audio on peer activation — `activate()` rebinds `session.bankLease`
     (the edited shared lease); direction "mounted edit → switch → peer
     playback" is proven nowhere (the existing check proves the opposite
     direction, and through the session API, not the mounted editor).
   - Reopen while dirty — `DocumentSession.init` adopts the existing dirty
     state; proven at session level only, never through the mounted dock.
   Accepted divergences (NOT failures, NOT repair targets — register below):
   Swift stars peer captions on bank-dirty where the fork stars captions on
   document-dirty only; Swift's per-tab close gate asks on bank-only dirty
   where the fork's documented limitation does not; a queued editor commit
   is dropped when its origin tab loses selection
   (`VoiceEditorController.swift:79,99` guards) where the fork resolves it
   through the origin tab's history.

# Exact write set

- `src/checks/editorqml/tst_ShellTabs.qml` — new
  `test_uSharedBankTwoTabJourney` (name continues the a–t series).
- `src/checks/workspace/bank_sharing.swift` — new
  `mountedEditReachesPeerTabAudio(report:fixtureRoot:)`.
- `src/checks/workspace/SessionChecks.swift` — one dispatch line in
  `runBankHistorySuite`.
- Repair-only, touched iff a leg fails: `src/swift/app/SongTabsController.
  swift`, `src/swift/app/DocumentSession.swift`.

# Prerequisites

Task 36 landed and settled (shell composition collision; `tst_ShellTabs.qml`
seeds settings through task 36's `bootstrap.preferences`). No other
interface dependency; tasks 34a/34b's `SongTabsController` changes are
landed.

# Interface contract

No new production interface. The proven journey is the contract (and the
shared-bank policy P3/P4 will cite):

- **Shared view**: with `mus_route101` (tab A) and `mus_route102` (tab B)
  open, a voice edit committed through the mounted voicegroup dock on the
  selected tab A makes, without reopening anything: tab B's session
  `bankSlots` carry the edited voice; both tabs' strip captions star; the
  window dirty flag stays set; `voiceListController` rows/dirty/loadName
  still describe the selected tab's (shared) bank after switching to tab B.
- **Dirty/close gate**: closing tab B while only the shared bank is dirty
  raises tab B's gate (Save/Discard/Cancel). Discard closes tab B and leaves
  the bank dirty — tab A's caption stays starred, bank bytes unwritten.
  Cancel keeps the tab. The window close walk asks about each dirty tab,
  then about the shared bank exactly once
  (`pendingCloseBankTitle == "fixture_rich"`), then completes.
- **Save isolation**: closing tab B with Save writes the bank source once
  (fingerprint changes) and clears the dirty star on the still-open tab A
  through the shared publication.
- **Undo isolation**: the edit is undoable only from tab A (its history);
  tab B's `canUndo` stays false, and tab A's undo restores the voice and
  clears both captions.
- **Reopen**: after tab A is discarded with the bank still dirty, opening
  `mus_route101` again binds the same dirty shared bank — edited rows, dirty
  star, no disk write.
- **Audio**: editing the sounding voice through the mounted editor on tab A
  (slot-0 type change Sq1→Noise) and switching to tab B makes tab B's
  playback use the edited bank — native CGB telemetry reports the Noise
  channel for the program-0 note (channel 3 vs the original Sq1 channel 0),
  mirroring `bankBackgroundEditReachesSelectedAudio`'s discriminator.

## Preservation contract

- `SharedBankState.swift`, `ProjectService.swift`,
  `src/swift/project/ProjectStore+Bank.swift`, the bank apply/save pipeline,
  `VoiceListController`/`VoiceEditorController`, and all QML surfaces stay
  byte-identical unless a leg fails inside them; a failure rooted outside
  the repair surface is reported with evidence, not repaired.
- Existing predicates stay green and unedited: `tst_ShellVoicegroup.qml`
  (single-tab editor journey), `tst_ShellTabs.qml` tests a–t (incl. the
  single-tab bank gates l/m/n and cleanup's discard walk), all
  `bank_sharing.swift` checks, `bankleases`.
- Accepted divergences (Context 8) are preserved as-is; this task neither
  introduces nor removes them.
- No new fixture files; no CMake/checkcatalog/manifest edits.

# Implementation steps

1. Write the failing predicates first (RED record): `test_uSharedBankTwoTab
   Journey` in `tst_ShellTabs.qml` covering Context's journey legs — shared
   view, captions, peer close gate (Discard/Cancel), Save isolation, undo
   isolation, reopen — reusing the lane's existing helpers (`openShell`,
   `clickSelectTab`, `closeButton`, `dialogButton`, `awaitGateButtons`,
   `verifyBankGate`, `fileProbe.fileFingerprint`); and
   `mountedEditReachesPeerTabAudio` in `bank_sharing.swift` reusing the
   staging idiom of `bankBackgroundEditReachesSelectedAudio` (0xC0
   program-0 patch at tick 0, `stageTestProject`) but driving the edit
   through `app.voiceListController()` (`selectSlot(0)` + `editorModel().
   changeType(macro: 5, symbol: "")`) on the selected tab A, then
   `app.songTabs.selectTab(tabId: b)` before the telemetry assertion.
2. Run the two owning lanes; record per-leg RED/GREEN in the report
   (message + file:line). If every leg is green at first run, the task is a
   proof task: no production edit happens.
3. Repair only failing legs, at the narrowest point inside the repair
   surface: gate/walk/selection defects in `SongTabsController.swift`
   (requestClose/settleCloseAll/refreshDirty path), propagation/adoption
   defects in `DocumentSession.swift` (sharedBankDidChange/adoptBank/close).
   One bounded fix loop per leg; no speculative refactors, no second
   history or publication authority.
4. Re-run the acceptance lanes to GREEN; hand the controller the per-leg
   table plus the RED evidence for any repaired leg.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore-bankhistory --verbose`
- `deno task verify --filter bankleases --verbose`
- `deno task verify:shell --filter shell-tabs --verbose`
- `deno task verify:shell --filter shell-voicegroup --verbose`
- `deno task verify:bridge`
- Covers: swiftcore-bankhistory = both two-session predicates + the new
  mounted-edit→peer-audio check; bankleases = lease-reuse regression;
  shell-tabs = the mounted two-tab journey + tests a–t; shell-voicegroup =
  single-tab editor journey regression. Audio legs need a working native
  audio device (same prerequisite as the existing check; offscreen-safe).
- Controller-side after settle: `deno task proof check`, `deno task proof
  check --executed`, `deno task proof check --strict-mappings`, and the full
  `--filter swiftcore` + `verify:shell` sweep before treating VG05 closed.

# Task-specific constraints

- No store rewrite: the canonical-bank mechanism is the proven core; the
  repair budget is the two named files, and only for an observed failing leg.
- No new C++; no comments; delete stale comments in touched regions; no UI
  geometry, palette, or typography changes (behavioral task over existing
  surfaces — base-font-multiple and font rulings are untouched by
  construction).
- `tst_ShellTabs.qml`'s `cleanup()` must keep settling with a dirty shared
  bank (discard-walk) — a journey that strands the gate fails the lane.
- Ledger work is controller-delegated to the ledger agent in this task's
  commit scope: `proof.session.txt` gains S-rows with message anchors for
  the executing two-session predicates that today have none
  (`twoOpenSessionsShareBankEdit` — "already-open peer sees the edited
  voice…", "already-open peer sees the dirty bank", "late subscriber catches
  up…"; `bankBackgroundEditReachesSelectedAudio` — "selected workspace
  sounds Sq1 then Noise…") plus the new mounted rows (test_u anchors: peer
  caption, dock rebind on switch, peer close gate, Discard-keeps-bank-dirty,
  peer Save clears both captions, reopen adopts dirty bank, walk asks once;
  `mountedEditReachesPeerTabAudio` — "mounted voicegroup edit reaches the
  peer tab's audio"), following the S186–S188 mounted-lane pattern.
  `proof.tst_voicegroupbank.txt` fixture/ingress rows (A001, A003, A014/
  A015, A017, A022) and the viewcache coordinator GAP rows (A040–A069) move
  only where an executing predicate establishes the row's full original
  expression — no preamble-only refresh, no closure by kinship.
- Open question for the controller (not decided here): the fork caption
  divergence (fork stars captions on document-dirty only; Swift's
  established `doc||bank` law stars peer captions on shared-bank edits).
  This brief preserves Swift's law; if the user rules fork parity instead,
  that is a separate one-line-surface task, not a VG05 repair.

# Controller verification

After the writer settles and `pgrep -fl 'porydaw|_qml_tests|swift_core_check'`
is empty:

1. Full lanes on the settled tree: `deno task build:checks`; `deno task
   verify --filter swiftcore --verbose`; `deno task verify:shell --verbose`;
   `deno task verify:bridge`; `deno task proof check --executed` and
   `--strict-mappings` after the ledger step.
2. Native smoke (desktop, production app on a real decomp project with two
   songs sharing a voicegroup): open both songs as tabs; edit a voice's
   envelope in the voicegroup dock on tab A; observe the peer tab's caption
   star and the dock's dirty star; click the peer tab and confirm the dock
   shows the edited value; play — the edited voice is audible; close the
   peer tab (gate asks; Save writes the bank and unstars tab A); reopen the
   first song and confirm the dirty edited bank returns.
