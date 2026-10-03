# Task 178 brief — switching projects empties the tab set before the new project lands

# Context

The fork's project-switch journey asserted that requesting a different project
replaces the whole workspace: the tab set empties and the new project reaches ready.
The Swift app switches projects through `openProject` (the landed detached-snapshot
and failed-replacement contracts), but no mounted predicate observes the
tab-set-empty transition of a successful switch, and the fork family's two-song
session-open guard is undisposed.

Surface: opening a different project from the shell with two songs live (the File →
Open Project path on the mounted window).
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`
A092 and A093 (2 GAP), fork `projectSwitchAndQuitPreserveState`
(`src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:361-362` at pinned
revision `5f768e34`): `waitForProjectReady` after `requestProjectOpenAt`, and
`openTabCount() == 0` — the switch empties the tab set. The family's session-open
guard A091 (`:350`) rides the same journey as setup.
Verify lane: `deno task verify:shell --filter shellwindow --verbose`.
Blocked rows left untouched: A094/A095 (project-root snapshot, persisted project
view state — `swift-project-store`), A098/A099/A102–A103 (reopen readiness), and
every other foreign-file family.

# Exact write set

- `src/checks/editorqml/tst_ShellWindow.qml` — one project-switch journey: two songs open in the staged project, request the second staged project through the real open path, observe the tab set empty and the new project ready.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — A091, A092, A093 only.

Both files are clean in `git status`.

# Prerequisites

Tasks 134/139's project-open contracts are consumed unchanged. Disjoint from every
foreign file and sibling brief (175/176 own other workspace check files; 177 owns the
roll lane's header test). Read sprint-3 §21.

# Interface contract

The journey opens two songs in the first staged project (the existing shell staging),
then requests the second staged project through the production open path (the same
entry the File menu uses — real dialog/shortcut input where the journey pattern
requires it). Observations: the tab count reaches exactly zero as the switch lands,
the outgoing songs' documents are released (no zombie tabs), the new project reaches
its ready state with an empty tab set, and the first project's on-disk bytes are
untouched (independent fixture literals). The fork's quit-preserve half
(A094+) stays blocked.

# Implementation steps

1. Stage the two-project, two-song fixture using the existing shell staging helpers.
2. Drive the project switch through the real path; observe the emptied tab set and
   the ready project (A092/A093) with the retained-bytes guard.
3. Dispose A091 as the journey's setup guard in the same commit. Compact form:
   header + `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Switching projects visibly replaces the whole tab set — zero tabs until the new
project is ready — with the outgoing project's bytes preserved.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
deno task proof check --executed
```

# Task-specific constraints

No sidecar-snapshot claims (A094 stays blocked on `swift-project-store`), no
quit/relaunch journey, no `session_io.swift`/`session_edit_routing.swift` edits, no
foreign files. `tst_ShellWindow.qml` is the only check file.
