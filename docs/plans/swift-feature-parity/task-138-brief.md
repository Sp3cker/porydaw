# Task 138 brief — fresh and reloaded tabs publish only fully bound retained state

# Context

Complete the existing tab readiness surface, combining fresh bind and reload because both use the same production transaction and check lanes. Consume 118’s complete EditorViewState and 125’s remap/retained state, not the removed C++ three-stage injection harness.

Selected **21 open rows (20 GAP + 1 PARTIAL)** in `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A046, A047, A048, A049, A050, A051, A052, A053, A054 | `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:186,189,190,191,192,193,200,202,204` — `freshBind` |
| A060, A061, A062, A063, A064, A065, A066, A067, A068, A069, A070, A071 | `src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:237,250,251,252,253,255,256,257,258,260,261,262` — `stagedReload` |

# Exact write set

- `src/swift/app/ApplicationSession+Tabs.swift`
- `src/swift/app/SongTabsController.swift`
- `src/swift/app/DocumentSession.swift`
- `src/checks/workspace/session_view_state.swift`
- `src/checks/editorqml/tst_ShellTabsReload.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted/checkpointed 118, 125 and 132 before reusing DocumentSession/tab-reload files; accepted 135 startup recipe contract. No interface depends on the unselected native focus-ancestry row A041.

# Interface contract

Preserve ApplicationSession.openTab(label:at:restoring:), DocumentSession.open and in-place reload ownership. Before a successful fresh load completes, the tab is not command-ready; the first ready workspace has canonical fresh camera/selection/cursor and complete shared editor state, not chrome alone. A reload leaves the existing rendered timeline and full retained state usable while pending, but prevents commands against a partially replaced document. Its completed publication installs the new timeline with the retained camera, cursor, selection scope, lane cosmetics and drawer state together; consumers never observe a new timeline with old/missing owners. Readiness transitions occur once into pending and once into ready, without duplicate command rebinding. Swift atomically returns a fully loaded DocumentSession, so native applyMidiStage/applyBankView callback counts and intermediate timeline-pointer inequality are retired representation; prove the observable pending/ready boundary and semantic timeline change rather than inventing three stage APIs. Failed reload retains the prior complete workspace and permits a later successful reload.

# Implementation steps

1. Extend runSessionViewStateChecks and the mounted reload suite with complete seeded EditorViewState, exact timeline events and all pending/completed observations via existing signals/published state.
2. Exercise real reload input with changed copied MIDI and a missing-source failure/recovery; capture pending observations while pumping the actual event loop, never a mock stage injector.
3. Repair only atomic adoption/readiness publication in the listed owners; preserve task-125 remapping and task-135 recipe normalization.

# Acceptance predicate

Fresh and reload journeys never expose a partially ready document, preserve full retained state through replacement and recover after failure. projectsession proves state/publication consequences; shell-tabs-reload runs the mounted split reload suite through actual input.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-reload --verbose
```

# Task-specific constraints

No new asynchronous worker architecture, fake phase hooks, physical audio assertion, native focus ancestry or sidecar snapshot. No change to deliberate project-switch priority. If an intermediate C++ clause is inseparable from its retired protocol, retire only that clause and cite the proved atomic consumer contract; never claim the old pipeline executed. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
