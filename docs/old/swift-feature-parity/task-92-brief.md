# Task 92 brief — mixed automation range drag and Delete preserve raw events

# Context

Own the automation range-edit surface: its domain values, same-tick raw event
identity, fractional Tempo preservation and one-transaction mixed-lane drag /
Delete. Task 96 consumes the accepted interaction owner for hover recovery;
task 97 later consumes the mounted grid-input check file.

Verified selection: **45 open rows (2 GAP + 43 PARTIAL)**, all behavioral:

- `src/checks/automationgesturecheck/proof.contract.txt`: 27 rows — A001–A005,
  A008–A010, A012–A027, A031, A032, A044.
- `src/checks/automationgesturecheck/proof.crosslane.txt`: 18 rows — A001,
  A005, A007–A018, A021–A024.

These split native harness files are absent at `fceecd88`; use their ledger's
pinned **7430fb426d466be20dd3a5e816cb2081c0e9135f** versions of
`src/checks/automationgesturecheck/contract.cpp` and `crosslane.cpp`, not an
invented fork path. Read `checkRangesTextSelection`, `checkDelete`, `checkMove`,
`checkMoveCollision`, `checkLogicalXcmdOccurrences`, the common edit/undo
helpers, and the mixed/Pan+LFO range journeys.

Current seams already exist: `drawerAutomationGestureContractParity`, the
mixed-selection functions in `automationselection.swift`, the XCMD checks,
`AutomationNodeResolver`, `AutomationCommit.apply`, and
`AutomationSelectionCommands.consumeSelectionCommand`. The fixture already
contains Pan at 96:[10,20], collision destination 144:[70,80], LFO at 96:96,
Tempo at 96:499999 microseconds, and unrelated volume.

# Exact write set

- `src/swift/app/drawer/automation/AutomationEdits.swift` — conditional resolver/commit repair.
- `src/swift/app/drawer/automation/AutomationInteraction.swift` — conditional selected-range gesture repair.
- `src/swift/app/drawer/automation/AutomationSelectionCommands.swift` — conditional selected-range command repair.
- `src/checks/automation/domain/gestureNodeDrag.swift`
- `src/checks/automation/domain/xcmd.swift`
- `src/checks/automation/automationselection.swift`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/automationgesturecheck/proof.contract.txt` — selected 27 rows only.
- `src/checks/automationgesturecheck/proof.crosslane.txt` — selected 18 rows only.

Keep metadata/projection APIs, shared fixtures and registration files unchanged.
No checked-in fixture content changes. No router, hover-publication or shell
owner edits. Task 91 uses this range-command contract without writing it.

# Prerequisites

Start after accepted 84/86/87/89. Rebase reads of 84's
`ApplicationSession.swift`/`DocumentWorkspace.swift`, 86's `EditorSurface.qml`
focus ingress, 87's `localinputtier_text.swift` routed commands and 89's
`DocumentSession.swift`. Preserve task 85's settled node-drag work in
`AutomationInteraction.swift`; Group A has no second writer of that file.

# Interface contract

- Preserve `AutomationNodeResolver.moves/deletes`, `AutomationCommit.apply`
  overloads and the page pointer/command signatures. All range edits still
  resolve to one existing semantic document transaction; no alternate store.
- Domain observations retain Tempo min/max, fractional 398406-microsecond
  Tempo node value and full-precision text, CC values/text for 64 and 0,
  and bend min/max/text for 0 and 100. A cleared selection is inactive;
  covered and uncovered lanes report the same 50..150 interval with different
  coverage. Empty lanes expose no nodes.
- Empty/unknown-tick delete and move are byte/revision/history no-ops.
  Deleting or moving a CC node removes its complete same-tick raw group;
  a collision evicts the destination group without reordering survivors.
  Moving unchanged-value Tempo preserves 499999 microseconds, including
  collision; changing its value to 140 recomputes the microseconds.
  Moving one of two logical XCMD occurrences preserves the explicit selector /
  payload bytes, the untouched occurrence and exact source/destination groups.
- Each common fork helper law must execute at its meaningful caller contexts:
  exact effective points, one revision and undo-index increment, undo to the
  prior index/bytes/points, and redo to the committed index/points. A successful
  return or a changed history identity is not proof of exactly one edit.
- A Shift drag of Tempo+Pan+LFO [96,144) moves the interval to [144,192),
  retains Tempo precision, moves both raw Pan occupants, evicts its collision,
  moves LFO, leaves volume byte-exact and ends idle. A Pan+LFO-only range leaves
  Tempo untouched. Delete removes only the selected interval/lane contents.
  Preview and empty Delete change no bytes, revision or undo position;
  document rebuild cancels the stale preview and retains the original range.

# Implementation steps

1. Extend the existing domain and XCMD checks with separate literal anchors
   for every selected clause, including exact raw group order and each
   independent undo/redo result. Preserve all old messages.
2. Extend the mixed-selection fixture journeys rather than constructing a
   mock lane or hand-editing serialized fixture data. Use real document APIs
   and existing session/page bindings for drag, Delete and rebuild cancellation.
3. Add mounted pointer/Shift-drag/Delete/Undo journeys to `tst_ShellGridInput.qml`
   through the production automation drawer, using its real staged project.
   Check the rendered interval/points and visible recovery after release.
4. Repair only an executed divergence at the existing resolver, commit,
   interaction or command seam. **RED may be absent if production already
   matches; then the check is the deliverable.** Attach fresh evidence only to
   the 45 selected rows in the same surface change.

# Acceptance predicate

Controller-run after Group A settles. `swiftcore-projectsession` registers
`runAutomationPageChecks` and proves raw events/history; `shell-grid-input`
proves the mounted pointer/command journey. Each invocation is capped at
180 s with a 175 s alarm after serialized lock acquisition.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json` and `shell-grid-input.json` in
`build/proof-evidence`. Full shell runs all 26 lanes (~40 s warm), and full
verify (~10 s warm) is mandatory even if the narrow lanes pass. Leave native
host/setup rows and all unselected automation rows unchanged.

# Task-specific constraints

Carry sprint-3 §10: no new C++; Swift 6.4 on touched Swift; comments ≤2 lines;
base-font sizing and WCAG AA ahead of pixel parity. One keyboard authority;
no second dispatcher, synthetic forwarding, focus memory or bare-Space chrome
capture. Ban `Qt.callLater` coalescing and new idempotence guards. One literal
message anchor per fork clause, existing messages verbatim, real fixtures,
no test-only seams. Settings setup uses CFPreferences/UserDefaults, never
plist bytes. Fixture edits require every exact-content consumer in a revised
closed set; none is authorized here. Workarounds need user approval.
Parked areas, deferred menus and savecore A016–A026 are excluded.
