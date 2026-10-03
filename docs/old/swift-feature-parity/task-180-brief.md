# Task 180 brief — the automation drawer pan owns band focus, the input grab and shared commands

# Context

The fork's `automationPanLifecycle` staged a real middle-button pan on the
mounted automation plot and observed band focus, the window's mouse grabber,
and command arbitration through four interruption routes (page switch, ungrab,
focus loss, window deactivate). The Swift automation page exists and the
mounted lane already pans (`tst_EditorDrawerAutomationCamera.qml` middle-drag
predicates), but no predicate proves the focus/grab/shared-command contract:
the focused band, that pointer events keep reaching the grabbing item, grab
teardown on release/ungrab/page-switch, and that a live pan swallows Delete and
survives a first Escape while a second Escape clears the time selection.

Surface: the mounted automation drawer's pan lifecycle — band focus, input
grab ownership and shared-command arbitration while a middle-drag pan is live.
Ledger spec:
`src/checks/host/proof.tst_hostintegration.txt` A083, A085, A087, A089, A091,
A098 (6 GAP), fork `tst_hostintegration.cpp:377,391,397,400,407,418` at pinned
revision `c17d966f` (`automationPanLifecycle`);
`src/checks/selectionkey/proof.gesturecommands.txt` A016 and A017 (2 PARTIAL),
fork `gesturecommands.cpp:150,157` at pinned revision `c17d966f`
(`automationPanGuardsSharedCommands` — Delete is a no-op during the live pan,
first Escape cancels keeping the time selection, second Escape clears it).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose` (editorqml-drawer) and
`deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: hostintegration A162/A174–A185 (project
fingerprint, real window close/teardown), A119/A122 (task 181), and the
MouseHints source-token rows in the automationhover ledger (representation).

# Exact write set

- `src/checks/editorqml/tst_EditorDrawerAutomationCamera.qml` — mounted pan-lifecycle journey: focus request publishes the automation band as focused; a middle press keeps delivering moves to the plot input (grab behavior: positions outside the item still arrive); each interruption route (page switch, forced ungrab path, focus move, window deactivate where stageable) ends the pan without document mutation; release leaves no grab.
- `src/checks/editorqml/tst_EditorDrawerAutomationFocus.qml` — the gesturecommands A016/A017 key-arbitration predicates: real Delete during a live pan is consumed without document mutation, first Escape cancels the pan and keeps the staged time selection, second Escape clears it. One predicate per clause, each carrying its unique complete literal.
- `src/checks/selectionkey/localinputtier_window.swift` — conditional model-level predicates if the mounted lane cannot stage a route (window deactivate).
- `src/swift/app/drawer/automation/AutomationInteraction.swift` — conditional repair only if grab/focus arbitration diverges.
- `src/swift/app/drawer/automation/AutomationPointerDispatch.swift` — conditional repair only.
- `src/swift/app/drawer/EditorDrawer.swift` — conditional repair only if no focused-band publication exists.
- `src/checks/host/proof.tst_hostintegration.txt` — A083/A085/A087/A089/A091/A098 only.
- `src/checks/selectionkey/proof.gesturecommands.txt` — A016/A017 only.

`mouseGrabberItem` has no QML equivalent: prove the observable contract
(events still reach the input outside its bounds while held; nothing receives
them after release). If a clause is genuinely unobservable, close that row as
RETIRED-REPRESENTATION with an executed refusal predicate on the published
interaction state (`interactionActive`/`panning`), citing the ruling.

# Prerequisites

The performance wave is committed at `0504b68b`; all write-set files are clean.
Task 179 may land first — it only touches menu focus, not pan arbitration. Read
sprint-3 §22.

# Interface contract

Predicates run on the mounted production automation page through the existing
`AutomationTabsSupport` mount path. Band focus is observed through the
published drawer/presenter state or the item's `activeFocus`; grab behavior is
observed through event delivery and the published pan/interaction flag, never
through a test-only grab accessor. Delete/Escape are real key deliveries to the
window while the middle button is held. Each clause maps to one predicate whose
emitted message equals the fork literal.

# Implementation steps

1. Stage the mounted automation page; assert the focus request publishes the
   automation band as the focused band (A083) and the velocity band after the
   velocity focus request (A089).
2. Prove grab ownership behaviorally during the pan (A085/A091): real moves
   outside the item bounds keep reaching the pan; assert `isPanning`/
   `interactionActive` equivalents.
3. Prove release/ungrab/page-switch leave no grab and no mutation (A087/A098
   plus the existing matched S010 snapshot conjuncts).
4. Deliver real Delete and two Escapes around a live pan for A016/A017.
5. Close the eight rows in the same commit, compact form.

# Acceptance predicate

The mounted automation pan provably owns band focus and input delivery for its
duration, yields it on every interruption route, and arbitrates shared commands
exactly as the fork staged.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

No grab-identity test API (no `mouseGrabberItem` shim), no focus memory, no
`Qt.callLater`. Do not touch `AutomationPage.qml`/`AutomationScene.swift`/
`AutomationContentPublication.swift`/`AutomationOverlayPublication.swift` (task
183's conditional set) or `tst_ShellGridInput*.qml` (task 186's). Ledger
serialization: hostintegration and gesturecommands rows are applied by the
single ledger writer; task 181's rows in the same ledgers are disjoint.
