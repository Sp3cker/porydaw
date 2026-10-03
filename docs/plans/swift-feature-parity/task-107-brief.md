# Task 107 brief — automation insertion prompts preserve the mounted drawer

# Context

Complete the fork-equivalent insertion value-prompt API and its mounted prompt, then preserve the automation plot geometry through resize, zoom and parameter switches. This is the dedicated follow-up to 104/106, not a new insertion gesture. Task 113 consumes its production insertion entrypoint for the exact Volume draft of 48.

Verified planning selection: **42 open rows (5 GAP + 37 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/automation/proof.automationcanvaslayout.txt` — A025, A026, A027, A029, A033, A035, A093, A094, A095, A096, A097, A098, A099, A100, A101, A102, A105, A109, A120, A121, A122, A124, A125, A126.
- `src/checks/drawerpresentation/proof.valueprompt.txt` — A014, A015, A020, A066, A069.
- `src/checks/selectionkey/proof.localinputtier_text.txt` — Original 332, Original 345, Original 357, Original 359, Original 361, Original 380, Original 385, Original 390, Original 397, Original 399, Original 402, Original 405, Original 574.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `f3069ef693542bdb63564b80a29773e2f5b2a360`, `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`, `f3069ef693542bdb63564b80a29773e2f5b2a360`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/drawer/automation/AutomationPage.swift`
- `src/swift/app/drawer/automation/AutomationModal.swift`
- `src/ui/songview/quick/drawer/AutomationPrompt.qml`
- `src/swift/app/drawer/EditorDrawerLayout.swift`
- `src/ui/songview/quick/drawer/EditorDrawer.qml`
- `src/checks/automation/automationcanvaslayout.swift`
- `src/checks/automation/AutomationPageChecks.swift`
- `src/checks/automation/automationpointmenus.swift`
- `src/checks/selectionkey/localinputtier_text.swift`
- `src/checks/editorqml/tst_ShellWindow.qml`
- `src/checks/editorqml/tst_EditorDrawer.qml`
- `src/checks/automation/proof.automationcanvaslayout.txt`
- `src/checks/drawerpresentation/proof.valueprompt.txt`
- `src/checks/selectionkey/proof.localinputtier_text.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 must land first. Rebase AutomationPage over 100 and the 104 automation cutover; rebase EditorDrawerLayout/EditorDrawer over 101, the drawer lane over 100/104, and the prompt/text/shell lane over 106 (and 99). The five valueprompt rows, twelve CC10 Original-labelled rows and velocity Original 574 are an explicit approved 106 residue handoff, not permission to reselect its closed work. Re-query them after 106; reconcile the brief/count before dispatch if any closes. No other 99–106 row is selected.

# Interface contract

- Add `public func openInsertionPrompt(tick: Int, value: Int) -> Bool` in the `AutomationPage` class body so QtBridge exposes the real presenter operation. Convert the tick at the domain boundary and reuse `AutomationPromptTransaction`, frozen facts, draft publication and the existing acceptance path. Its transaction is explicitly insertion (`forExistingNode: false`), not an existing-node prompt inferred from an occupant. Preserve `openPrompt(tick: Tick, value: Int)` and every existing-node caller. This is the production counterpart of fork `openValuePromptForInsertion`, not a check-only wrapper.
- The fork check calls that API directly; no empty-space double-click/right-click insertion-prompt gesture exists to port. Open the mounted production modal through the new presenter API, then drive its actual QML text field and real shell keys. Preserve 104's pointer/menu behavior and the existing double-click-no-insertion law. Do not add a menu row or gesture.
- Tempo insertion at tick 24 starts with exactly `140` selected and focused. Typing `90` and Enter inserts the exact event, advances revision/history once and returns focus to automation; retain the existing low/high clamp cases. CC10 insertion at tick 96 with stored value 64 displays exactly `0`; Escape cancels without song-byte/history/selection changes and returns focus. The existing CC10 node at tick 24 remains untouched. Close valueprompt A014/A015/A020/A066/A069 only on this insertion journey.
- For the twelve CC10 text residues use their own original fixture: CC10 nodes at ticks 48=32 and 96=64, insertion at tick 144 with stored value 64. Through the production insertion API prove literal `12`, actual text Copy/Paste, Up/Down, local S, Escape, unchanged full document bytes/history/selected notes and resumed window Solo. This is separate from the valueprompt tick-96 fixture; neither scenario supplies the other's missing conjunct. Preserve 106's completed Event List journey. A prompt over an already-written node cannot supply insertion evidence.
- Original 574 is the additional velocity Escape residue approved for this task. Add a Swift `VelocityPage` prompt transaction inside the existing registered numeric check, loading the same `mus_littleroot_test` project/song and parsed voice/program context used by `test_cWindowShortcutsAndNumericOwnership`. Target the same selected note semantics as its `selectDrawnVelocityNote` journey, capture non-optional serialized full-song bytes, edit the numeric draft and cancel through the production prompt API, then compare exact bytes/history/selection. Pair this predicate explicitly with 106's real right-click → Set Velocity → typed keys → Escape journey and unchanged mounted note/revision observations. The old synthetic CC10 fixture lacks the velocity prompt's parsed voice context; it cannot prove this row. No QML byte getter, saved-file fingerprint, private state probe or velocity-producer edit is authorized.
- Preserve `drawerAutomationHitGeometry` and `drawerAutomationViewStatePreservation`: minimum and maximum drawer extents are both positive and ordered; viewport height follows actual resize; roll/split geometry is re-read after resize; the tab stack retains content at both extremes. Preserve ticksAt(48), snapTicksAt(48), snap(30), snap spacing, positive grid/snap, unchanged 0.1/0.4 fractional snaps and changed 1.1 snap when an empty lane is activated. Activate the exact BendRange lane, not any other lane. Compare the full viewport-size pair and split before/after switches and zoom. Height changes must be real and equal the requested viewport height; velocity and voice section state and the active page remain unchanged.

# Implementation steps

1. Extend the existing AutomationPage/AutomationModal boundary with the explicit insertion entrypoint, retaining existing-node prompt callers and stale revision/parameter/track rejection. Use the existing AutomationPrompt QML modal; repair focus lifecycle there only if the new real ingress demonstrates a defect.
2. Extend the registered automation prompt/point-menu Swift checks and drawerOriginalNumericPromptTransaction with the exact Tempo/CC10 insertion transactions and the same-mounted-fixture velocity cancellation byte predicate. Reuse 106's completed local-key and velocity Escape predicates; add only the missing insertion and exact-byte conjuncts.
3. Extend tst_ShellWindow for production API-opened insertion followed by real text/clipboard/keys, and tst_EditorDrawer plus the existing canvaslayout checks for the exact resize/snap/BendRange/state-preservation clauses.
4. Update only the selected ledger identities with the new proving sources. After the 106 handoff is settled, delete each of the three ledgers only when its entire remaining scoped inventory closes.

# Acceptance predicate

The registered AutomationPage checks, canvaslayout checks and numeric transaction prove exact model/history/byte clauses; shellwindow proves actual insertion-modal keys/focus and velocity Escape, and verify:qml executes the mounted drawer geometry. None substitutes a written-node prompt for insertion or a CC10 transaction for velocity cancellation. All five valueprompt and thirteen text residues close on the approved handoff.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No AutomationInteraction.swift, AutomationPage.qml, ShellWindow.qml or registration writes. This deliberately corrects the earlier brief's nonexistent empty-space/menu ingress assumption; the authorized production presenter API mirrors the fork check. No new user gesture.
