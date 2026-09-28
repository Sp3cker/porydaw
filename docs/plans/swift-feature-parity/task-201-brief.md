# Task 201 brief — the mounted roll retires the cursor-bitmap, view-state and undo-count representations

# Context

Four rollcheck ledgers carry PARTIAL tails whose residuals all name Qt
representations the Swift surface has no counterpart for — the standing
ruling the prompt re-applies: unreachable or native-representation states
close RETIRED-REPRESENTATION with executed refusal predicates on real
guards; genuinely un-synthesized runtime events stay PARTIAL.

Rows in scope (11 PARTIAL):

- `rollcheck/resize.cpp` A002–A004, A020, A027, A028 (reference `5f768e34`):
  DPI-matched `Qt::BitmapCursor` pixmaps for left/right edge drags and the
  `Qt::ArrowCursor` body shape. Swift publishes a *named* cursor shape
  through the roll surface; the pixmap identity is native representation.
  The mounted refusal predicate on `tst_SwiftRollSelection.qml`: the
  published cursor kind changes at the edge grip vs body and never reports a
  bitmap identity.
- `rollcheck/identity.cpp` A014 (reference `85b97239`): a `QFAIL` on Qt's
  `ViewState` capture/apply pair ("restore runtime state without changing
  cosmetics"). S008/S012–S021 already prove each runtime field survives
  reload; the residual conjunct is the Qt capture/apply value-type identity.
  Closes RR or MATCHED per clause against the mounted reload checks in
  `identity.swift`.
- `rollcheck/scale_editing.cpp` A017/A027/A030 (reference `a1244957`):
  three `QFAIL("gesture pass pushed an unexpected number of undo commands")`
  sites — Qt undo-stack command counts. The Swift gesture commits unwind
  through `undoDocument()` with no counted-commands representation; the
  closable law is "the gesture commits exactly the fork's byte delta and the
  undo restores the pre-gesture document". If a conjunct can pin "one
  history entry" on the real undo surface it goes MATCHED; otherwise RR
  with a refusal predicate on the executed undo guard.
- `rollcheck/selection.cpp` A009 (reference `a1244957`): the band-sweep
  audition's emitted sample duration ("zero-length note" QFAIL) — the Swift
  `onAudition` callback does not expose duration. Adjudicate per clause:
  MATCHED if the audition surface can publish the swept duration, else RR
  with an executed refusal on the mounted sweep (every auditioned note in
  the fixture is non-zero-length).

Surface: the mounted roll selection/resize lanes plus the existing
`identity.swift`/`scale_editing.swift` corecheck hosts.

Ledger spec: `proof.identity.txt` A014; `proof.resize.txt` A002–A004,
A020, A027, A028; `proof.scale_editing.txt` A017, A027, A030;
`proof.selection.txt` A009. On zero open rows the identity, resize and
scale_editing ledgers delete (their C++ sources are already gone, `Deleted
in:` `67544720`); `proof.selection.txt` deletes too if A009 closes — it is
the last open row.

Verify lanes: `deno task verify:qml-roll --filter swiftroll-window
--verbose` (selection/resize), `deno task verify --filter swiftcore
--verbose` (identity/scale_editing/selection corecheck rows).

Blocked rows left untouched: `rollcheck/presentation` A018–A024 (task 164's
QtBridge QML→Swift object passing) and every other ledger.

# Exact write set

- `src/checks/rollqml/tst_SwiftRollSelection.qml` — cursor-kind refusal
  predicates for A002–A004/A020/A027/A028 and the sweep refusal for A009.
- `src/checks/editorqml/tst_ShellNoteVisuals.qml` — only if a body-cursor
  predicate belongs on the mounted shell rather than the roll lane; keep it
  out of the set otherwise.
- `src/checks/rollcheck/scale_editing.swift` — executed refusal/undo
  predicates for A017/A027/A030.
- `src/checks/rollcheck/identity.swift` — executed predicate for A014's
  cosmetic-preserving reload law.
- `src/checks/rollcheck/proof.identity.txt`, `proof.resize.txt`,
  `proof.scale_editing.txt`, `proof.selection.txt` — the closed rows, and
  ledger deletion where open count reaches zero.

# Prerequisites

Read sprint-3 §25 and each fork section at the pinned reference. Confirm
Swift's published cursor surface (the named shape the roll publishes) before
writing RR rationale: if a mounted probe already distinguishes left/right
edge cursors, those clauses go MATCHED. Confirm `undoDocument`'s real guard
shape before pinning the undo law — no test-only count API.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a QFAIL conjunct is one predicate. Expectations are
independent literals; refusal predicates run against real mounted guards —
no test-only ingress, no cursor-image captures in Swift. Ledger deletions
happen only in the commit that closes the last open row.

# Implementation steps

1. Adjudicate each row per clause against the mounted surfaces.
2. Add the executed predicates (roll lane for cursor/audition, corecheck
   hosts for identity/scale_editing).
3. Close the eleven rows; delete ledgers at zero, same commit.

# Acceptance predicate

Mounted edge-hover/sweep predicates execute the refusal laws and the
remaining rollcheck tails close; ledgers that reach zero are deleted;
`proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --filter swiftroll-window --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-25 writer of the four rollcheck ledgers and the three check files.
Do not touch `presentation` rows (164-blocked), `tst_ShellGridInput*.qml`
(200's neighbours are untouched but the files belong to no other wave-25
write set — still prefer `tst_SwiftRollSelection.qml`), or any
`Shell*Support.qml`.
