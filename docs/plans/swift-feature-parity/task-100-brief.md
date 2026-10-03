# Task 100 brief — automation selection keeps its visible owner through tool changes

# Context

Own the mounted automation selection: half-open selected rings, a captured drag or pencil stroke surviving a tool-mode key, cancellation and ghost-pin rejection. Task 104 consumes the accepted publication and interaction seams for curve/pencil raster, without reopening these rows.

Verified selection: **47 open rows (19 GAP + 28 PARTIAL)**; all remaining open rows in both ledgers:

- `src/checks/automation/proof.automationownership.txt` — 37 (16 GAP + 21 PARTIAL): A001, A003–A008, A025, A026, A045, A047–A049, A051, A052, A055, A057–A062, A070–A072, A079–A083, A093, A096, A099, A103, A104, A113, A118.
- `src/checks/automation/proof.automationselection.txt` — 10 (3 GAP + 7 PARTIAL): A004, A005, A077, A124, A131–A133, A165, A169, A172.

Oracle source paths are the matching `.cpp` paths, at ownership pin `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac` and selection pin `f3069ef693542bdb63564b80a29773e2f5b2a360`; use `git show <pin>:<path>` alongside fork `fceecd88`. Current row clauses are at ownership ledger :92–170, :236–253, :326–497, :525–644, :681–824 and selection ledger :24–34, :312–316, :495–543, :666–699. These are assertion specifications, not stale preamble claims that the surface is absent.

# Exact write set

- `src/swift/app/drawer/automation/AutomationPage.swift` — conditional tool/ghost selection repair only.
- `src/swift/app/drawer/automation/AutomationInteraction.swift` — conditional captured gesture/cancel repair.
- `src/swift/app/drawer/automation/AutomationContentPublication.swift` — conditional selected-ring publication repair.
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift` — conditional transient clearing repair.
- `src/ui/songview/quick/drawer/AutomationPage.qml` — conditional actual selection/input paint repair.
- `src/checks/automation/automationselection.swift`
- `src/checks/automation/automationcanvasediting.swift`
- `src/checks/editorqml/tst_EditorDrawer.qml`
- `src/checks/automation/proof.automationownership.txt` — selected rows; delete after complete closure.
- `src/checks/automation/proof.automationselection.txt` — selected rows; delete after complete closure.

The original C++ sources were already deleted (`31ea635` recorded in both headers); do not recreate them. No registration, fixture, router, ShellWindow, document selection-domain or other automation-ledger edits.

# Prerequisites

All 91–98 must land first. Rebase interaction/selection checks over 92 and interaction/overlay/QML/editor-lane files over 96; preserve 92's exact raw-event transactions and 96's hover/hint ownership. Consume 95's accepted key authority read-only. Group A has no other automation-file writer. Task 104 waits for this group's accepted checkpoint before reusing files.

# Interface contract

- Preserve `AutomationPage.pointerPress/move/release`, `selectRange`, `activateParameter` and `toggleGhostParameter` signatures (`AutomationPage.swift:526–632`). `isPencilMode` remains the existing shared tool state (:109–121), not a second key dispatcher.
- The three included Pan nodes at ticks 48, 96 and 144 paint selected rings; the excluded tick-192 node does not. A track-scoped selection drag finishes at [48,216); the single-node range finishes at [168,192). Inspect start and end independently.
- A tool-key transition while a pencil stroke is held keeps that stroke and commits its end point with value 92. A transition while a selected node is held keeps the node drag, moves 72 to 168/value96 and removes the old source. Neither transition silently restarts or retargets the gesture. `pressPlot` and `updateGesture` remain the sole frozen gesture owners (`AutomationInteraction.swift:163–217,589–627`).
- A mixed-CC preview changes no document publication/revision/history before release. Release shifts its range, projects both moved Pan and LFO values into the real playback timeline, and preserves excluded lanes. Extend `drawerAutomationMultiCcDragExcludesOthers` and existing mixed-selection checks (`automationselection.swift:247–279,595–700`), not a parallel transaction.
- Actual plot focus receives Delete. During capture, moving outside the plot retains the captured target; cancellation ends capture, clears all visible transient primitives, and a new parameter accepts a fresh gesture. Prove this with real pointer/key delivery, not QQuickWindow grabber identity.
- Negative and upper-bound ghost indices leave pins empty; an eventless Modulation lane is explicitly empty and cannot replace the active Volume lane when its pin is rejected. Extend `drawerAutomationGhostViewOnlyAndSurvives` (:282–309).
- Retire exactly ownership A001/A008 (native row handles), A003/A093/A118 (native mesh revision counters), A070–A072/A079–A083 (harness probe arithmetic), A096/A099 (native grabber pointer identity), A113 (native row-activation prerequisite), and selection A004/A005 (native body prerequisites). All other selected rows are behavioral; visible rings/transients, key-mode retention, focus and timeline values must execute. This is **29 behavior rows and 18 representation rows**, not permission to retire painted outcomes.

# Implementation steps

1. Extend existing registered selection/ownership/cancellation functions with independent clause anchors and exact pre-press/held/release/cancel observations. Use real document builders and preserve existing literals.
2. Extend the production phase of `tst_EditorDrawer.qml`, beside `test_productionAutomationTabSwitchAndGhosts` (:5491) and its existing pencil input journey (:7770–7817), with actual tool-key changes while held and ring/transient image probes. Do not substitute direct model mode assignments for keyboard ingress proof.
3. Repair demonstrated mismatch only at the listed existing owners. `publishContent` (:107–132) and `nodeHandles` (:269 onward) own selection output; QML's existing node ring and plot input (`AutomationPage.qml:362–399,513–518`) own actual paint/input. RED may be absent if production already matches.
4. Record executed same-change mappings, retire only the 18 named representation clauses, then delete the two fully closed ledgers with the proving surface change. Preserve all unselected automation families and 91–98 evidence.

# Acceptance predicate

`runAutomationPageChecks` registers these existing functions (`AutomationPageChecks.swift:328–391`). `EditorQmlLane.entryName/inputFileName` (`EditorQmlTests.swift:18–23`) mounts the production drawer. Swift proves exact state/timeline transitions; the editor lane proves held input, focus and painted rings/transient disappearance.

Controller-run on the settled group under sprint-3 §11 verification policy:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json` and `editorqml-drawer.json` under `build/proof-evidence`. Full shell and full verify are mandatory, in addition to the mounted journey; each invoked process has a 175 s alarm and a 180 s ceiling after serialized lock acquisition.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
Offscreen capture proves mounted pixels/input, not physical macOS pointer capture. No shell/router or selection-domain repair may be hidden in this task.
