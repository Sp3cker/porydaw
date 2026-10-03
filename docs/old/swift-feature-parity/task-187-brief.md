# Task 187 brief — the songs surface keeps its category list through close and reopen

# Context

`WorkspaceSessionTest::closeReopenPreservesSession` closes the browser and
reopens it after a state change. The one unproved conjunct is the category box
count (`session.cpp:192` `QVERIFY(categoryBox->count() > 1)`): the fork's songs
browser repopulates the song-library category combo on reopen, and nothing in
the Swift surface proves the category list is still populated after a
close/reopen cycle. Small surface, real user-visible seam: a reopened songs
browser that lost its categories would show an empty picker.

Surface: the mounted songs browser's category list across close/reopen.
Ledger spec: `src/checks/workspace/proof.session.txt` A017 (1 GAP), fork
`session.cpp:192` at the row's pinned revision (`closeReopenPreservesSession`).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose` and
`deno task verify:shell --filter shell-tabs --verbose`.
Blocked rows left untouched: session A024/A025 (sidecar path — `applySidebar`
has no Swift owner; the whole sidebar directory write path remains deferred),
A042's unmatched neighbors stay as recorded.

# Exact write set

- `src/checks/editorqml/tst_ShellSongs.qml` — extend `test_closeAndReopenPreservesSongBrowserState` (or a sibling journey in the same file): after the second open, the category model holds more than one entry and the selected category survives; real mounted lane, real close/reopen.
- `src/swift/app/` songs browser presenter file — conditional repair only if the category list actually drops on reopen.
- `src/checks/workspace/proof.session.txt` — A017 only.

# Prerequisites

All write-set files are clean at `0504b68b`. Read sprint-3 §22. The implementer
confirms the Swift category model's published surface (combo model or role)
before writing the predicate — observe the published count, not a private
list.

# Interface contract

The predicate observes the songs browser's published category model after a
real mounted close/reopen and compares the count and selection against
independent literals (`> 1` for count, the fork's staged category for
selection). One predicate for the fork clause with its literal message.

# Implementation steps

1. Read `session.cpp` around `:192` for the staged category and expected count
   shape.
2. Add the mounted close/reopen category predicate.
3. Repair the category publication only if it provably drops.
4. Close A017 in the same commit, compact form.

# Acceptance predicate

The mounted songs browser provably repopulates its category list through
close/reopen, with executed evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
deno task proof check --executed
```

# Task-specific constraints

No test-only model access — the published count/selection only. Sole wave-22
writer of the session ledger; do not touch its other open rows.
