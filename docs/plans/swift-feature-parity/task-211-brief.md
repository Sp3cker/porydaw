# Task 211 brief — File → Register Song restores the dead registry action on the selected tab

# Context

`file.register_song` is a registered keybinding
(`src/swift/app/commands/KeybindingRegistry.swift:111`, "Register Song")
with no entry in `ShellPresenter.actions` — the registry id has no menu row,
no shortcut and no handler. The fork's File menu carries "Re&gister Song"
between Save Song and Close Tab (`mainwindow.cpp:304-307` at `fceecd88`),
enabled exactly on `ready && selectedSongRegistrationPending()`
(`mainwindow.cpp:966,976-981`: selected tab ready and its song's
`registrationGaps` nonempty), and activating it registers the *selected
editor tab's* song through the register flow
(`workspaceui_project.cpp:420-428`: silent refuse when the tab isn't ready
or the song has no gaps, else `runRegisterFlow`).

Swift already owns the whole flow for the dock context-menu ingress
(`SongListPresenter.requestRegister` → `SongDockController.prepare`
→ `songRegistrationPlan` → mounted `songConfirmationDialog` →
`registerSong`), proven by `test_charmapOnlyRegisterAndReopen` in
`src/checks/editorqml/tst_ShellSongs.qml`. What is missing is the fork's
second ingress: the File-menu action on the current tab. The dock
`requestRegister` cannot be reused verbatim — it requires the song to be
*visible* under the dock's live filters, while the fork's menu action acts
on the selected tab regardless of dock filter state.

Surface: the File menu — "Register Song" row, its registration-pending
gate, and the selected-tab resolve into the mounted confirmation flow.
Ledger spec: none — the register-flow ledger is already deleted
(`test_charmapOnlyRegisterAndReopen`'s A-citing comments are matched
evidence); no open row pins the File-menu ingress. Feature port with zero
ledger edits.
Verify lanes: `deno task verify --filter swiftcore-projectsession
--verbose` (controller/presenter predicates via `session_io.swift`) and
`deno task verify:shell --filter shell-menus --verbose` (mounted menu
journey; `tst_ShellMenus.qml`, not `tst_ShellSongs.qml` which 210 owns).

# Exact write set

Production:

- `src/swift/app/songlist/SongDockController.swift` — selected-tab resolve
  only, appended beside `syncSelection` (private `prepare` is reused, never
  touched):
  - `selectedTabRegistrationPending() -> Bool` (`@QtIgnored`-free, public):
    selected tab exists, its title resolves to a `presenter.songListings`
    entry, and that entry's `registrationIncomplete` — the full snapshot
    listing, never the filtered `visible` list.
  - `requestRegisterSelectedTab()`: guards `!busy`, `confirmation.isEmpty`,
    `service != nil`, resolves the selected tab's `SongListing.id` through
    `songListings`, requires `registrationIncomplete`, then calls the
    existing `prepare(songId, deleting: false)`.
- `src/swift/app/shell/ShellPresenter.swift` — one `Action("file.register_song")`
  in the actions array (auto-joins `fileActionIds` and `windowIds`); an
  `actionEnabled` case returning `session.songOpen
  && session.songDockController().selectedTabRegistrationPending()`; an
  `activate` case calling `session.songDockController().requestRegisterSelectedTab()`.
  No `menuLabels` entry — the registry label is already "Register Song".

Checks:

- `src/checks/workspace/session_io.swift` — appended session-bound
  predicates only (own section, unique cppID): with a staged session,
  `selectedTabRegistrationPending` is false with no tab / with a fully
  registered selected song, true on the partial fixture song;
  `requestRegisterSelectedTab` on a pending song populates
  `confirmation == "register"` with the fork's plan detail after the async
  prepare settles, and on a clean song refuses silently (no confirmation,
  no failure message).
- `src/checks/editorqml/tst_ShellMenus.qml` — menu order/count update in
  `test_forkMenuTopologyAndLabels` (["file.open_project", "file.new_song",
  "file.save_song", "file.register_song", "file.close_tab", "file.quit"],
  count 6) plus a new function using
  `bootstrap.prepareSongActionFixture("charmap")`: File → Register Song is
  disabled while no song is selected or the selected song is clean, enabled
  on the charmap-gapped open tab; activating it mounts the real
  `songConfirmationDialog` with `confirmation === "register"` and the
  "charmap.txt" detail, and accepting completes the registration
  (`registrationGapText` clears on the dock row).

Ledgers: none.

# Prerequisites

None in-wave. Disjoint from 210/212: `ShellMenusSupport.qml` helpers are
shared read-only; `session_io.swift` extensions sit in a new section.
Read sprint-3 §28.

# Interface contract (fork clauses)

- Topology (`mainwindow.cpp:301-317`): Register Song sits after Save Song
  and before Close Tab in the File menu — the Swift File row order becomes
  open_project, new_song, save_song, register_song, close_tab, quit.
- Enablement (`mainwindow.cpp:966,976-981`): enabled iff a ready selected
  tab's song has nonempty registration gaps. Unregistered strays and
  partial registrations both enable it (`registrationIncomplete` =
  `!registered || !registrationGaps.isEmpty`, matching the dock's
  `canRegister` semantics and the fork's gap check).
- Activation (`workspaceui_project.cpp:420-428`): acts on the selected
  editor tab's song even when the dock's live filters hide it; a clean or
  absent selection refuses silently — no dialog, no failure message, no
  writes.
- Flow reuse: the mounted `songConfirmationDialog` register mode, the
  `songRegistrationPlan` → `registerSong` service path and the
  confirmation detail ("The following registration files need updates:…")
  are unchanged — only the resolve (menu id → selected tab → song id →
  `prepare`) is new.

# Implementation steps

1. `SongDockController`: `selectedTabRegistrationPending` +
   `requestRegisterSelectedTab` against `presenter.songListings`.
2. `ShellPresenter`: action entry, enabled gate, activate case.
3. `session_io.swift`: the gating/resolve predicates in a new section.
4. `tst_ShellMenus.qml`: topology update + the mounted charmap journey.
5. Run both lanes; no ledger edits (zero open rows claimed).

# Acceptance predicate

The mounted File menu shows Register Song in the fork's position, disabled
until the selected tab's song has a registration gap; activating it opens
the same confirmation the dock ingress mounts, for the selected tab's song
regardless of dock filters, and accepting repairs the registration — the
fork's `registerSelectedSong` contract on the Swift shell.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-menus --verbose
deno task proof check --executed
```

# Task-specific constraints

One predicate per fork clause; each literal unique to this task; the menu
row must be a real `ShellPresenter` action reached through
`actionEnabled`/`activate` — no direct controller calls from the menu
journey, no test-only properties, no `Qt.callLater` in production code,
fail-closed staging. The dock context-menu path (`requestRegister`,
`canRegister`, `SongsPanel` rows) stays byte-identical: the menu ingress
shares `prepare`, never wraps it. Existing menu-topology assertions are
updated to the fork's real order, not worked around. Swift 6.4, comments
≤2 lines. Workarounds or architectural changes: stop and report.
