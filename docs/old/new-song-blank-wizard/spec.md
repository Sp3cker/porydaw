# Spec — File → New Song blank-mode wizard

Frozen behavior contract for this surface. Oracle: fork revision `fceecd88`,
`src/ui/newsongwizard.{h,cpp}` (blank mode), `src/ui/workspaceui_samples.cpp`
(`runNewSongWizard`/`submitCreateSong`), `src/project/projectio.cpp:318-383`
(`createSong`), `src/mainwindow.cpp:289-300,960-961` (menu route/enablement).
Nothing in this spec is an implementer choice.

## 1. Decision: copy-from-current is replaced, not kept

The fork File menu has exactly one New Song command: `&New Song...` →
`WorkspaceUi::runNewSongWizard()` (`mainwindow.cpp:289-291`), which opens the
blank-mode wizard. No duplicate/copy-song command exists anywhere in the fork —
the only "Copy of %1" string is the New Voicegroup flow's copy-**source**
choice (`workspaceui_project.cpp:628`), which is about voicegroup sources, not
songs, and belongs to VG03.

The current Swift prompt (`SongConfirmDialog.qml` create mode →
`ProjectService.createSong(label:from:)` byte-copying the current song's
`.mid`) is a Swift-era substitute from tasks 171/210, not shipped C++
behavior. Adopting the fork therefore **removes** it; nothing fork-equivalent
is being deleted, and no replacement copy-song command is added elsewhere.

Removal set (owned by task 2):
- `SongDockController.requestNewSong()`, `@QtTracked newSongLabel`, and the
  create branch of `acceptConfirmation(alsoDeleteVoicegroup:)`
  (`src/swift/app/songlist/SongDockController.swift:135-140,152-173`).
- The create mode of `src/ui/songview/quick/docks/SongConfirmDialog.qml`
  (title/Create button text/name field/taken hint/create-focus). The register
  and delete modes stay.
- `ProjectService.createSong(label:from:)`
  (`src/swift/app/ProjectService+Songs.swift:49-82`) — its only caller is the
  create branch. `forkSongAs` (save-conflict fork) is untouched.
- `runSongCreationChecks` (`src/checks/songlist/SongRegistrationChecks.swift:344+`)
  and its call site: it pins "created MIDI copies the selected song bytes",
  which is the removed divergence, not parity.
- The five create-mode journeys in `src/checks/editorqml/tst_ShellSongs.qml`
  (`test_newSongShortcutCreatesFromSelectedSong`,
  `test_newSongEscapeCancelsWithoutMutation`,
  `test_newSongCollisionRefusesWithoutTouchingTabsOrBytes`,
  `test_newSongNameFieldFoldsFiltersAndRefusesLeadingDigit`,
  `test_newSongTakenNameDisablesCreateWithHint`). Their surviving name-law
  obligations re-land as wizard-lane predicates (§6).

Preserved despite the removal: `SongDockController.validNewSongLabel(label:)`
(consumed by the save-conflict flow, `ApplicationSession+Close.swift:209`) and
`SongListPresenter.acceptSongLabelEdit`/`normalizeSongLabel`/`songLabelTaken`
(shared name law).

## 2. Wizard surface (frozen)

- **Route**: `file.new_song` (Cmd+N, already registered) dispatches to
  `session.songDockController().newSongController().requestNewSong()`,
  mirroring `file.import_midi` (`ShellPresenter.swift:349-350`). Menu label
  and position unchanged ("New Song", first after Open Project).
- **Enablement**: `session.projectOpen` only — fork `updateChrome` gates
  `m_newSongAction->setEnabled(projectOpen)` (`mainwindow.cpp:960-961`). The
  current `projectOpen && songOpen` gate (`ShellPresenter.swift:274`) is wrong
  for blank mode: no current song is required. The wizard opens with zero
  tabs open.
- **Intake gate** (silent refusals, fork early-returns): project open, service
  installed, `!busy`, `!wizardOpen`, dock not busy, dock `confirmation`
  empty, `!session.saveInProgress` — identical to
  `MidiImportController.canIntake`.
- **Window**: `DialogWindow` base (Settings-window convention: native
  `Qt.Dialog`, platform open animation, focus return, Escape → close →
  `cancel()`), title **"New Song"** (`newsongwizard.cpp:553`), ClassicStyle
  chrome, `NoBackButtonOnStartPage`, minimum size `52 × 38` base-font units
  (`newsongwizard.cpp:585-587`, blank branch).
- **Page order (frozen)**: Identity (page 0) → Sound (page 1). Two pages, no
  Analysis. The GAP-row phrase "Sound page with player/voicegroup/config" is
  a summary of the wizard as a whole; the fork puts Player on Identity.

### 2.1 Identity page (fork `IdentityPage`)

- Title "Song identity"; subtitle "Names the .mid file, the song_table.inc
  entry, and the songs.h constant."
- **Name** field, placeholder `mus_my_song`; suggested label is **empty** in
  blank mode (no source file). Editing follows the shared whole-edit name law
  (`SongListPresenter.acceptSongLabelEdit` — lowercase folding, `[a-z_][a-z0-9_]*`).
- Name hint, shown while taken: "A song named %1 already exists."
- **Constant** field, auto-derived `SongCatalog.constantForLabel(label)` on
  name edits until the user edits the constant; then manual.
- **Player** combo: role display names over player data, tooltip "Select
  Background music for a song. Select Sound effect for a sound. Also select
  it for a fanfare."
- **Completeness (Next gate)**: incomplete while name or constant is empty or
  the name is taken; complete otherwise. `next()` refuses to leave page 0
  while incomplete; `back()` refuses at page 0 (no Back button shown).

### 2.2 Sound page (fork `SoundPage`)

- Title "Sound settings"; subtitle "The song's voicegroup and mid2agb flags —
  its entry in midi.cfg (or songs.mk). All of this can be changed later in
  Song Settings."
- **Voicegroup** editable combo: when the project has the per-file layout
  (`canCreateVoicegroup`), entry "(create a new voicegroup for this song)"
  listed first, then existing voicegroup display names; default selection is
  the **first existing voicegroup**, never the create entry. Tooltip: "The
  symbol is \"voicegroup_\" + this name (mid2agb -G)."
- Master volume (-V) 0–127 default **100**; Reverb (-R) 0–127 default
  `kDefaultReverb`; Priority (-P) 0–127 default **0**; Exact gate time (-E)
  default **checked**; 48 clocks per beat (-X) unchecked; Disable compression
  (-N) unchecked.
- **Finish refusal** (fork `validatePage`): choosing the create entry while
  `_<label>` already exists refuses Finish with warning title "New Voicegroup",
  message "A voicegroup named voicegroup_%1 already exists — pick it from the
  list instead."; the wizard stays open.

## 3. Creation transaction (frozen — reuse, do not re-implement)

The wizard does not write a second transaction. Finish composes
`SongImportRequest(label:constant:player:config:createVoicegroup:,
midi: MidiFile.blankSong())` and calls the existing
`ProjectService.importSong(_:)` (`src/swift/app/ProjectService+Import.swift`),
which already implements the fork order (`projectio.cpp:318-383`):

1. Invalid label → "Invalid song label: <label>." (before any write)
2. Existing `.mid` → "MIDI file already exists: <path>"
3. Taken label → "A song named <label> already exists."
4. Optional new voicegroup: `createVoicegroup(name: label, copyFromFile: "",
   copySectionLabel: "")` — new voicegroup named after the song
   (`sound/voicegroups/<label>.inc`, symbol `voicegroup_<label>`, `-G _<label>`);
   the store is re-acquired after its reopen.
5. Write the blank `.mid` (template below).
6. `MidiCfg.writeSongFlags` with `SongFlags.merge(config)`.
7. `registerSong(label:constant:player:)` → snapshot refresh.
8. Failure after the `.mid` write: no rollback; only
   `refreshSongCatalog()` so the partial state badges and File → Register
   Song retries.

**Blank MIDI**: `MidiFile.blankSong()` (`src/swift/core/MidiFile.swift:454`) —
format 1, division 24, conductor chunk (tempo 0x51 `[07 A1 20]` = 120 BPM,
time signature 0x58 `[04 02 18 08]` = 4/4) and one track chunk (program 0,
CC7 100), both one bar (96 ticks). **Not a copy of the current song.** The
template is already byte-proved against C++
`project/SongRegistry::blankSong` (`src/checks/midi/MidiSmfCodecChecks.swift:472-482`).

## 4. Post-commit behavior (frozen, fork `handleSongCreated` + `reconcileSnapshot`)

- Success: refresh the Songs dock listing; status message
  "Created and registered <label> (song ID <id>)".
- **New tab rule**: open the created song in a new tab **only when a new
  voicegroup was created**, preceded by `session.refreshVoicegroupCatalog()`.
  Without a voicegroup the song is listed in the dock and opened like any
  other song. (Mirrors `MidiImportController.finish` exactly.)
- Failure after Finish: the wizard is already closed; refresh the dock listing
  so the stray/partial badge shows, and surface the service error through the
  existing `session.operationFailed` channel ("Operation Failed") — not a
  second error channel.
- Warnings (voicegroup collision, §2.2) surface through the controller's
  warning signal → host `MessageDialog` titled per §2.2.

## 5. Ledger mapping (frozen)

`src/checks/visual/proof.dialogs.txt`, reference `4346c26`, original
`src/checks/visual/dialogs.cpp` (deleted in `67544720`):

| Row | Original predicate | Disposition | Evidence |
|---|---|---|---|
| A017 | `QVERIFY2(name, "identity name field not found")` | **MATCHED** | S008 — mounted wizard exposes the identity name field (placeholder `mus_my_song`) and the name-required Next gate |
| A018 | `QCOMPARE(wizard.currentId(), 0)` | **MATCHED** | S009 — route opens the wizard on page 0 (Identity, no Back) |
| A019 | `QVERIFY2(wizardRegions(...), "wizard chrome not found")` | **RETIRED-REPRESENTATION** | QWidget region lookup feeds only the frozen QWidget PNG (A001, visual-baseline exclusion); page content proved by S008–S010. Same precedent as A023/A025/A027 |
| A020 | `QCOMPARE(wizard.currentId(), 1)` after `next()` | **MATCHED** | S010 — a complete Identity page's Next advances to the Sound page |
| A021 | `QVERIFY2(wizardRegions(...), "wizard chrome not found")` on page 1 | **RETIRED-REPRESENTATION** | as A019 |

New S entries (appended to the ledger's `Swift assertion predicates` section;
S001–S007 exist, so these are S008–S010), anchored in
`src/checks/editorqml/tst_ShellNewSongWizard.qml`, lane `shell-new-song-wizard`:

- `S008 | test_newSongWizardPageFlow (shell-new-song-wizard lane)` —
  `Anchor: message "A017 identity name field found"`
- `S009 | test_newSongRouteGateAndOpen (shell-new-song-wizard lane)` —
  `Anchor: message "A018 wizard opens on identity page"`
- `S010 | test_newSongWizardPageFlow (shell-new-song-wizard lane)` —
  `Anchor: message "A020 next advances to sound page"`

Header updates in the same edit: the tally line and the closing sentence
"Fork File > New Song wizard feature obligations remain open." With A017–A021
closed the ledger reaches zero open rows (0 GAP, 7 MATCHED,
20 RETIRED-REPRESENTATION) and **task 3 deletes the file**; no unbuilt C++
production unit remains that only this ledger exercised (`src/ui/newsongwizard.*`
and `src/checks/visual/dialogs.cpp` are already deleted; the other dialog
families' C++ units belong to open ledgers in other tracks).

## 6. Check surfaces (frozen)

- `swiftcore-projectsession` (checks binary, `songlist_service` suite): pure
  `NewSongWizardState` laws + finish plan (task 1); still green after the
  `createSong` removal (task 3).
- `shell-new-song-wizard` (new shell QML lane): route gate, open-on-Identity,
  page flow with the name law (folding/filter/leading-digit, taken-name hint
  and disabled Next), Next → Sound, Sound fields/defaults, cancel/Escape
  (task 2).
- `shell-new-song-commit` (new shell QML lane): Finish writes
  `MidiFile.blankSong()` bytes + flags line, registers, dock row + status;
  new-voicegroup variant (voicegroup file, catalog refresh, new tab);
  voicegroup-collision warning refuses Finish; existing-`.mid` and taken-label
  refusals leave bytes untouched; partial registration badges with Register
  Song retry (task 3).
- `shell-songs` remains green after the five create-mode journeys are removed
  (register/delete journeys untouched). `shell-menus` File-order pin
  (`tst_ShellMenus.qml:99`) is unchanged by this plan.
- Contrast: both wizard pages join `tst_TextContrast.qml`'s audit (WCAG AA
  via the mounted window).

## 7. Doc cutover (task 3, frozen edits)

- `docs/old/swift-feature-parity/sprint-4.md:33` — drop the "not adopted"
  deferral line, replacing it with a pointer to this plan.
- `docs/old/swift-feature-parity/sprint-4.md:407` — dialogs A017–A021 and
  PJ03's conjuncts are no longer deferred-on-user-decision.
- `docs/old/swift-feature-parity/sprint-4.md:415` — the "Import mode only"
  planner decision is superseded for New Song; the wizard is adopted.
- `docs/plans/swift-feature-parity/inventory.md` PJ03 — no longer "Missing
  complete shell wizard/store transaction"; name the landed owners.
- `docs/plans/swift-feature-parity/plan.md:84` (PJ03 blocked row) and
  `plan.md:128` (J02 loses its PJ03 clause; VG03 remains its blocker).

## 8. Obligations already owned elsewhere (do not rebuild)

- **Blank template bytes**: `MidiSmfCodecChecks.swift:472-482` (C++ parity).
- **Transaction order/refusals/partial registration**:
  `SongImportChecks.swift` under `swiftcore-projectsession`.
- **Registration writes** (table/songs.h/ld/charmap/debug.c): the store's
  registration checks + File → Register Song (task 211 work), already landed.
- **Subsequent edit/play/save of the created song**: the song-tab path
  (`session.openSongFromDock` → `SongTabsController`, shell-tabs lane,
  workspace tabs proofs / PJ06) owns this for every open song; the wizard
  only decides whether a tab opens (§4).

## 9. Out of scope

MIDI import wizard (any rework), re-porting the integrated project
parser/registrar, VG03 dock New Voicegroup flow, save-conflict fork,
register/delete confirmations, themelayout settings and mainwindowrouting
ledgers, and any new copy-song command (§1).
