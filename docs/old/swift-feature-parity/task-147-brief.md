# Task 147 brief — charmap-only registration repair and safe deletion of an open song

# Context

Complete the mounted Songs Register/Remove surface, whose current owner is `SongDockController`, not the deleted MainWindow action machinery. The action ledger's claim that dialogs are absent is stale: `SongConfirmDialog.qml` and `tst_ShellSongs.qml` already drive real confirmations. Extend those journeys with the fork's charmap-only partial registration, reopen enablement, deletion of a clean open tab and fallback-song refusal. Task 151 consumes the service-plan contract read-only; no new onboarding wizard is produced here.

Selected **49 open rows (40 GAP + 9 PARTIAL)**, all of `src/checks/onboardcheck/proof.action.txt`. Ordered A-ids correspond to assertion-start lines at `fceecd88:src/checks/onboardcheck/action.cpp`:

| Target A-ids | Fork lines / scenario |
|---|---|
| A001–A010 | 66,71,72,73,76,81,84,86,88,91 — complete registration then remove its charmap entry |
| A011–A019 | 95,96,101,102,103,104,107,109,111 — open, register enablement, missing-file list and confirmation |
| A020–A024 | 125,126,128,130,134 — exact restored charmap and disabled Register after reopen |
| A025–A034 | 150,153,157,159,162,167,171,173,179,189 — ordinary/fallback deletion fixture and byte baselines |
| A035–A041 | 220,223,225,226,228,229,231 — fallback refusal, retained tab/files/MIDI |
| A042–A049 | 235,237,240,241,247,248,249,250 — confirmed deletion closes tab, removes list row and trashes MIDI |

Setup-only rows: A001–A005, A007–A011, A013, A021–A023, A025–A034, A037, A040, A044. A006's applicability is a fixture precondition. Dialog/button-pointer representations A017/A018/A042/A043 retain their actual visible-and-activatable confirmation consumer, not QWidget identity. A036's empty error buffer is representation; the refusal must still identify the protected song.

# Exact write set

- `src/swift/app/songlist/SongDockController.swift` — `prepare`, `acceptConfirmation` and confirmation state only, conditional repair.
- `src/swift/app/songlist/SongListPresenter.swift` — `canRegister`/`requestRegister` only, conditional repair.
- `src/ui/songview/quick/docks/SongConfirmDialog.qml` — existing confirmation interaction only, conditional repair.
- `src/checks/editorqml/ShellQmlTests.swift` — isolated Songs fixture staging helpers only.
- `src/checks/editorqml/tst_ShellSongs.qml`
- `src/checks/onboardcheck/proof.action.txt` — selected surface; whole-ledger deletion eligible under §17.

# Prerequisites

Accepted/checkpointed 144 and 146 before reusing shell check support; preserve their tab-close and message-anchor changes. Accepted 127/128/131/145 registration/deletion/debug-list contracts. Read sprint-3 §17 for shared constraints and execution ownership.

# Interface contract

Keep `SongListPresenter.requestRegister(songId:)`, `canRegister(songId:)`, `requestDelete(songId:)`, `SongDockController.acceptConfirmation(alsoDeleteVoicegroup:)` and `cancelConfirmation()` signatures. Existing controller state remains the QtBridge-visible authority.

A registered song missing only its charmap entry stays listed and registered, exposes exactly `["charmap.txt"]`, and enables Register. Clicking the mounted confirmation repairs the exact independently seeded complete charmap bytes, refreshes the row to no gaps and disables Register; reopening the song keeps it disabled. Do not substitute the existing songs.h-only partial fixture for this case.

Deleting the registered clean song while its editor tab is open closes that tab after success, removes exactly one listed row, removes its original MIDI and leaves the original bytes at `.porydaw/trash/<label>.mid`. Deleting the song-table ID-0 fallback reports a refusal identifying that label, retains its open tab and original MIDI, and preserves the complete table/header/linker/charmap/midi.cfg/debug images. The existing dirty-tab guard, Cancel and optional-bank opt-in/out contracts stay intact.

# Implementation steps

1. Add isolated fixture branches beside the existing Songs bootstrap staging: literal charmap-complete/stripped images plus a registered deletable song and a playable ID-0 fallback. File creation/read failure fails setup; do not attach A-ids to bootstrap success.
2. Extend the existing mounted tests using row context-menu clicks and actual dialog buttons. Assert charmap-only gaps, full byte restoration, Register disabled after acceptance and after reopen.
3. Drive ordinary open-song deletion and fallback refusal. Observe tab/list identity and fixed file fingerprints derived from literal fixture bytes, not self-comparisons. Keep deletion opt-in/out/cancel coverage in the same lane.
4. Repair only the named controller/presenter/dialog boundary if these journeys diverge; close each selected portable clause with its executed consumer predicate and classify obsolete setup/QWidget representations alongside it.

# Acceptance predicate

The mounted Register/Remove actions implement all three fork journeys without replacing them with direct service calls. `ShellQmlEntries.swift` registers `shell-songs` with `tst_ShellSongs.qml`; this is the primary input/surface proof. No service-only test proves the click/enablement/tab-close clauses.

Named checks under §17 ownership (macOS Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
deno task proof check --executed
```

# Task-specific constraints

No `ShellWindow.qml`, `ShellPresenter.swift`, session fanout, host-ledger or Task146-owned QML changes. No new dialog/action dispatcher and no registration parser edits. Six files are one mounted confirmation surface, including its existing fixture host. Whole-ledger closure does not authorize production C++ deletion.
