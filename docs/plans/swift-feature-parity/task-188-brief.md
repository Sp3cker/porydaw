# Task 188 brief — closing a tab must not teardown inside the `tabs` mutation

# Context

`SongTabsController+Close.swift:136` calls `tabs.remove(at:)` on the published
`QListModel<SongTabSession>`. `QListModel`'s row removal emits `rowsRemoved`
inside the element's storage access, so the QML strip destroys the closing
delegate synchronously while `tabs` is still under mutation. That destruction
runs `pageReleased(tabId:)` → `ApplicationSession.tabPageReleased` →
`retire(_:)` → `DocumentWorkspace.teardown()` → `VelocityPage.detach()`. Any
teardown that publishes a session change — the velocity selection clear this
task restores — runs `publishChange` → `PianoGrid.publishOutputs()` →
`commands.isAvailable` → `selectedWorkspace` → `tabIndex(of:)` → `tabs`, a
reentrant read that traps `SIGABRT` on the exclusivity violation.

Root fix: every path that removes a tab row (`closeTab`, `finishReload`'s
replacement, `dropAllTabs` if it has the same shape) must complete the row
mutation before any delegate destruction can run — mutate a copy, publish the
finished array, or restructure so no `tabs` access is active while the model
notifies. No deferral, no `Qt.callLater`, no swallowing the notification:
teardown stays synchronous, it just no longer interleaves with the mutation.

Surface: closing a tab whose velocity drawer holds a note selection — today a
reliable abort in the mounted lane.
Ledger spec: `src/checks/host/proof.tst_hostintegration.txt` A119 (PARTIAL —
the song-null and song-replacement conjuncts of `lifecycleTermination`), fork
`tst_hostintegration.cpp:523` at `c17d966f` (`clearsSelection` for
`song-null`/`song-replacement`). A119's voice-replace/voice-null conjuncts are
unreachable per A120's ruling and are not part of this row.
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose`,
`deno task verify:shell --filter shellwindow-velocity --verbose`, and
`deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: hostintegration A003/A004/A007 fixture tails,
A122 (closed by 181), A162/A174–A185 (real window-close harness), A087/A091
(WindowDeactivate, no mounted ingress), hostadapter A095's same-GUI-pass
residue.

# Exact write set

- `src/swift/app/SongTabsController+Close.swift` — `closeTab` (and
  `finishReload`'s row replacement if it shares the shape): finish the row
  mutation before teardown can reenter.
- `src/swift/app/SongTabsController.swift` — `dropAllTabs`/`select` helpers,
  conditional repair only where the same removal-under-teardown shape exists.
- `src/swift/app/ApplicationSession+Tabs.swift` — conditional repair only if
  the ordering fix needs the release/retire plumbing; prefer the controller.
- `src/swift/app/drawer/velocity/VelocityPage.swift` — restore the velocity
  selection clear in `detach()` (`session?.setSelectedNotes([])` before the
  session is dropped), so detach publishes an empty selection.
- `src/checks/host/HostBehaviorChecks.swift` — extend the S008/S009
  song-null/song-replacement lifecycle predicates with the
  `selectedNotes.isEmpty` conjunct after `detach()`.
- `src/checks/editorqml/tst_ShellTabsClose.qml` — one mounted journey: select
  a note through the real velocity plot input on the selected tab, click its
  close button, assert the tab leaves the strip without an abort (the crash
  repro) and the surviving selection/rows are correct.
- `src/checks/host/proof.tst_hostintegration.txt` — A119 only.

# Prerequisites

Tree is clean at `85a806f9` (task 181 landed; the gesture ledgers are deleted
and A122 is closed). The crash is reproducible before the fix: mount two songs,
give the selected tab a velocity selection, close it — the remove-time delegate
destruction reenters `tabs` inside the mutation. Reproduce first; then the fix
makes the same journey pass.

# Interface contract

The mounted predicate drives real pointer input (click a drawn velocity node,
then the tab's close button) and observes only published values: `tabCount`,
`tabOrderIds`, `pageOf`, `velocityPage().selectedCount`. The model-level
predicates live in `hostLifecycleTermination` beside S008/S009: after
`detach()` under song-null and song-replacement, the outgoing session's
`selectedNotes` is empty — the `clearsSelection` clause the fork asserts at
`tst_hostintegration.cpp:523`. One predicate per fork clause with its unique
literal message.

# Implementation steps

1. Reproduce the abort in `tst_ShellTabsClose` (selected tab, live velocity
   selection, close) — confirms the mutation/teardown interleave.
2. Restructure `closeTab` so the row mutation completes before any delegate
   destruction: build the post-removal contents, publish them, and let the
   resulting page destruction run after the mutation has returned. Mirror the
   shape in `finishReload`/`dropAllTabs` if they remove rows the same way.
3. Restore the selection clear in `VelocityPage.detach()`.
4. Extend S008/S009 with the selection-emptiness conjunct.
5. Re-run the mounted journey; close A119 in the same commit, compact form.

# Acceptance predicate

Closing a selected tab with a live velocity selection completes without an
abort; the song-null and song-replacement lifecycle predicates assert an empty
outgoing selection; all named lanes pass.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-velocity --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

No `Qt.callLater`, no deferred retire, no notification swallowing: the mutation
finishes before teardown, teardown itself stays synchronous. Sole wave-23
writer of the hostintegration ledger; do not touch its other open rows or any
velocity/gesture ledgers (181 closed them). `VelocityPage.swift` is free again
post-181; re-check `git status` at dispatch.
