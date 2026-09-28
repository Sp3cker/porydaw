# Task 209 brief — New Voicegroup creates a per-file group and assigns it undoably (VG03)

# Context

The voicegroup dock's "New..." button is already mounted and live:
`src/ui/songview/quick/docks/VoiceEditor.qml:320` calls
`VoiceListController.requestNewVoicegroup()` (`src/swift/app/voicelist/
VoiceListController.swift:388-390`), but `onNewVoicegroupRequested`
(`:148`) is assigned by nobody in `src/swift`, so the click is a dead end.
The fork's complete flow survives in the oracle: a guarded name/source
dialog (`workspaceui_project.cpp:597-654 runCreateVoicegroupFlow`), a
fail-closed project op (`projectio.cpp:389-406 createVoicegroup`) that
writes `sound/voicegroups/<name>.inc`
(`voicegroupsource.cpp:1797-1880`), appends the hub include
(`voicegroupsource.cpp:1882-1932`), rebuilds the voicegroup layout and
refreshes the catalog, then assigns `_<name>` to the selected song as a
plain undoable cfg edit that rebinds the bank through the dirty seam
(`workspaceui_project.cpp:206-216` pendingVoicegroupArg). Every Swift
piece the flow needs already exists except the file writer and the
prompt: `DocumentSession.selectVoicegroup` is the undoable -G +
rebind seam (`DocumentSession.swift:388-410`), `bankLease.sourcePath`/
`sectionLabel` carry the copy source (`ProjectService.swift:166-180`),
`RegistrationLines` gives byte-faithful hub editing
(`SongRegistration.swift:66-115`), `voicegroupArgs()` rescans the
directory (`SongRegistration+Store.swift:27-30`), and
`setVoicegroupChoices`/`refresh(from:)` republish the selector.

Surface: the voicegroup dock's New Voicegroup flow — "New..." button →
mounted name/source prompt → per-file creation → undoable -G assignment —
with collision refusal.
Ledger spec: `src/checks/voicegroup/proof.voicegroupsourceediting.txt`
A086–A092 (7 GAP; fork `VoicegroupSourceTest::editedFamiliesPreviewSaveReloadAndCreate`
tail `src/checks/voicegroup/voicegroupsourceediting.cpp:337,340,344,345,347,351,353`
at the ledger pin `fbe1015aaf056089f5d773f99d961ba906246cff`) and
`src/checks/voicegroupsave/proof.presentation.txt` A032–A037 (6 GAP; fork
`VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably`
`src/checks/voicegroupsave/presentation.cpp:239,240,244,251,253,255` at
pin `4346c26abdcab317ccf97e178c959a82301081c9`).
Verify lanes: `deno task verify --filter swiftcore-bankhistory --verbose`
(service/file/registry predicates),
`deno task verify --filter swiftcore-projectsession --verbose`
(controller prompt/accept/undo predicates), and
`deno task verify:shell --filter shell-voicegroup --verbose` (mounted
prompt journey on `tst_ShellVoicegroup.qml`).
Blocked rows left untouched: `voicegroupsave/proof.savecore.txt`
A016–A026 (catalog-outage status path — open user decision),
`voicegroup/proof.tst_voicegroupbank.txt` (all rows),
`voicegroup/proof.tst_voicegroupviewcache.txt` (A046 ruled deviation +
A069 owned by task 207), and `proof.savecore.txt` overall. The fork's
*other* New-Voicegroup ingress (`CreateSongInput.newVoicegroup` inside the
New Song flow, `projectworkspace.h:212`) is out: no open ledger row pins
it and task 171 deliberately left it unported.

# Exact write set

Production:

- `src/swift/project/VoicegroupSource+Create.swift` — NEW same-type
  extension: `VoicegroupSource.createVoicegroup(projectRoot:name:
  copyFromFile:copySectionLabel:)` + `appendIncludeLine(projectRoot:name:)`
  + the file-private copy-body/sibling-style helpers. New file because
  `VoicegroupSource.swift` is already 470L; the extension keeps it under
  the 600L cohesion line.
- `src/swift/project/CMakeLists.txt` — register the new file only.
- `src/swift/app/ProjectService+Bank.swift` — `createVoicegroup(name:
  copyFromFile:copySectionLabel:)`: the fail-closed op (store writer +
  include append), then `open()` rescan mirroring the fork's
  rebuild+refresh, wrapped in `projectFailure`.
- `src/swift/app/voicelist/VoiceListController.swift` — prompt state
  (`newVoicegroupPrompt`, `newVoicegroupName`, `newVoicegroupCopyLabel`),
  `presentNewVoicegroup`/`acceptNewVoicegroup`/`cancelNewVoicegroup`/
  `isValidVoicegroupName`, plus two outward seams: `onNewVoicegroupFailed`
  (refusal/failure messages) and `onStatusMessage` (the fork's showStatus
  line). `requestNewVoicegroup` keeps firing `onNewVoicegroupRequested`.
- `src/swift/app/ApplicationSession+Audio.swift` — assign
  `onNewVoicegroupRequested` (→ `voiceList.presentNewVoicegroup()`),
  `onNewVoicegroupFailed` (→ `lastSaveError`, the wired failure seam), and
  `onStatusMessage` (→ `statusMessage(message:)`).
- `src/swift/app/ApplicationSession.swift` — `@QtSignal statusMessage
  (message:)` next to `operationFailed`.
- `src/ui/songview/quick/docks/VoiceEditor.qml` — `objectName` on the
  existing "New..." button for the mounted lane (names a rendered
  surface; not a test-only API).
- `src/ui/songview/quick/docks/VoicegroupNewDialog.qml` — NEW Basic.Dialog
  in the SongConfirmDialog idiom: name TextField, source ComboBox
  ("Copy of <copyLabel>" / "Empty (dummy template)"), OK gated on
  `isValidVoicegroupName` + non-collision, Escape/close →
  `cancelNewVoicegroup`.
- `src/ui/songview/quick/docks/VoicegroupPanel.qml` — a top-level
  zero-height `Loader` (not a ColumnLayout-managed cell) that mounts the
  dialog while `controller.newVoicegroupPrompt`; parent `Overlay.overlay`
  as in SongConfirmDialog. Panel-mount so both the production
  SongsDockColumn path and the lane's bare-panel harness reach it.
- `src/ui/shell/ShellWindow.qml` — `onStatusMessage(message)` →
  `shell.statusText = message` in the existing session Connections.
- `CMakeLists.txt` (root) — register `VoicegroupNewDialog.qml` in the QML
  file list beside `SongConfirmDialog.qml`.

Checks:

- `src/checks/workspace/voicegroup_creation.swift` — NEW:
  `runVoicegroupCreationChecks` — service/file/registry predicates
  (swiftcore-bankhistory).
- `src/checks/workspace/SessionChecks.swift` — one call line inside
  `runBankHistorySuite`.
- `src/checks/CMakeLists.txt` — register the new check file.
- `src/checks/voicelist/voicelist_session.swift` — controller-level
  predicates: prompt open/gates, collision refusal, accept → cfg arg +
  dirty + bank rebind, undo → home arg + home lease (swiftcore-projectsession).
- `src/checks/editorqml/tst_ShellVoicegroup.qml` — mounted journey
  (shell-voicegroup): "New..." click → prompt → name + source → Create →
  bound `_name` + file on disk; undo → `bankLoadName` home restore; a
  pre-seeded colliding name leg refuses with the collision message and
  writes nothing.

Ledgers (edit only in the proving commit; every row of both ledgers is
open, so both files hit zero open rows and delete in that commit per the
closed-ledger rule — the C++ sources are already deleted, `Deleted in:`
headers stand):

- `src/checks/voicegroup/proof.voicegroupsourceediting.txt` — A086–A092 →
  MATCHED, compact form, then file deletion.
- `src/checks/voicegroupsave/proof.presentation.txt` — A032–A037 →
  MATCHED, compact form, then file deletion.

# Prerequisites

None in-wave. Disjoint from 206/207/208 (they own the themelayout,
viewcache and rollcheck-identity ledgers plus `EventListCell.qml`,
`tst_ShellEventListPresentation.qml`, `ThemeColorChecks.swift`,
`bank_undo_publication.swift`, `proof.identity.txt`); 207's
`SessionChecks.swift` row is a bank_undo_publication extension — the new
call line lands beside it without touching that function. Read
sprint-3 §26–§27.

# Interface contract (fork clauses)

- Prompt gates (fork `runCreateVoicegroupFlow:598-606`): refuse while no
  bound session, the bank/selector is loading, or a create prompt is
  already open — silent refuses, no dialog, no writes. The fork's
  `perFileVoicegroups` refusal and `m_dialogOps`/`projectBusy` map to the
  service-level `sound/voicegroups/` absence failure and the controller's
  own prompt/busy state; no prompt-side catalog-layout probe.
- Name validation: fork regex `[A-Za-z][A-Za-z0-9_]*` gates the dialog's
  Create button and the accept path (`:612-615, 643-644`). A catalog
  collision (`knownArgs`/`voicegroupArgs` contains `_` + name) refuses
  through the failure seam with a message naming the name
  (`:645-648 "A voicegroup named %1 already exists."`), changes nothing.
- File creation (`voicegroupsource.cpp:1797-1880`): refuse if
  `sound/voicegroups/` is missing or `<name>.inc` already exists —
  collision refusal reads before any write and preserves the existing
  bytes exactly, mirroring task 171's stray-bytes contract. Detect the
  header style from the first sibling (`voicegroup\w+::` label style with
  optional `\t.align 2`, else `voice_group <name>`) and CRLF vs LF. Body
  is `copiedVoicegroupLines` semantics (declaration start,
  section-label `::`/`.align` boundary for labelled copies, trimmed
  trailing blanks) or the 128-line `voice_square_1 60, 0, 0, 2, 0, 0, 15, 0`
  dummy when `copyFromFile` is empty.
- Include append (`:1882-1932`): insert `.include "sound/voicegroups/
  <name>.inc"` after the last `.include` (file end if none) preserving
  the hub's indent/CRLF/trailing-newline; a missing
  `sound/voice_groups.inc` is a success no-op. The hub gains exactly one
  line (A092).
- Post-create (`projectio.cpp:389-406`): rescan and republish so
  `voicegroupArgs`/`voicegroupCatalog().groupArgs`/`argChoices` contain
  `_<name>` (A091) — then the flow assigns `_<name>` through
  `session.selectVoicegroup`, the undoable cfg edit + bank rebind
  (`workspaceui_project.cpp:206-216`; presentation A034/A035).
- Copy fidelity (A088–A090): `voicegroup_load` resolves
  `_voicegroup_qtest_copy`-style names, the edited slot's parsed voice
  name survives the copy, and resolved subgroup tones equal the source
  bank's (check-side: `PorydawCoreCheckNative` `voicegroup_load` /
  `ToneData` like `VoicegroupEditingChecks.swift:149-230`, helpers
  file-private in the new check file).
- Undo (A036/A037): one undo of the assignment restores the home
  `-G` and the home bank lease/`bankLoadName`; the created file and hub
  line remain (creation is a project op, not a document edit).
- Status/failure: success publishes the fork's
  "Created sound/voicegroups/<name>.inc and assigned it to <song>."
  through the new status seam; every refusal publishes a nonempty
  message through the failure seam — no silent failure anywhere.

# Implementation steps

1. `VoicegroupSource+Create.swift`: byte-faithful create + include append
   using `ProjectFileStore`/`RegistrationLines` helpers; refusal paths
   write nothing.
2. `ProjectService+Bank.swift`: `createVoicegroup` op — guarded writes,
   `open()` rescan, `projectFailure` envelope.
3. `VoiceListController`: prompt state + present/accept/cancel +
   `isValidVoicegroupName`; accept runs the service op, then
   `session.selectVoicegroup("_" + name)`, `setVoicegroupChoices` from a
   fresh `voicegroupArgs`, and `refresh(from:)`; failures route to
   `onNewVoicegroupFailed`, success to `onStatusMessage`.
4. `ApplicationSession+Audio.swift` + `ApplicationSession.swift`: the
   three callback assignments and the status signal; `ShellWindow.qml`
   routes it to the status bar.
5. QML: `VoicegroupNewDialog.qml` (SongConfirmDialog idiom: modal,
   `CloseOnEscape`, OK bound to validity + `!knownArgs.contains` via a
   controller predicate — never `!("prop" in obj)`; real rendered
   surfaces only), the `VoicegroupPanel` Loader, the `VoiceEditor`
   `objectName`, CMake registration.
6. Checks: `voicegroup_creation.swift` (file bytes, hub line count,
   `voicegroup_load` loadability + name + resolved tone, `voicegroupArgs`
   membership, collision refusal with independently seeded stray bytes);
   `voicelist_session.swift` (prompt gates, accept → `_<name>` cfg +
   dirty + rebind, undo → home arg + lease); `tst_ShellVoicegroup.qml`
   (mounted journey + collision leg).
7. Close the 13 rows in the proving commit, compact form; delete both
   zeroed ledgers. Run `deno task proof check --executed`.

# Acceptance predicate

The mounted "New..." button opens the prompt, accepting creates
`sound/voicegroups/<name>.inc` (+ one hub include) and binds `_<name>`
undoably — one undo restores the home binding — while a colliding name
refuses with a nonempty message and preserves existing bytes. The fork's
creation contract on the Swift surface.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-voicegroup --verbose
deno task proof check --executed
```

# Task-specific constraints

Task 205's VG03-retirement analysis is superseded: the ingress is wired
and stays, so the rows close MATCHED — never RETIRED. One predicate per
fork clause, each with a unique complete literal; each A-id on exactly
one predicate; independent literals (fixture byte strings written by the
check, never read back); real production ingress only — the prompt opens
via `requestNewVoicegroup`, the accept runs `session.selectVoicegroup`,
no test-only properties or `Qt.callLater`; setup is fail-closed (a failed
stage/seed fails the row). Swift 6.4, comments ≤2 lines, no hard-coded
px (geometry via `baseFontPx`/`layoutSpaces` like SongConfirmDialog).
The `createSong`-time `newVoicegroup` variant stays out (no row pins
it). Workarounds or architectural changes: stop and report.
