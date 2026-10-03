# Task 111 brief — automation tabs and ghost overlays paint the exact lane

# Context

Complete the mounted automation presentation: active lane ink, inclusion bars, tab badges, hover labels and left-axis ticks. Existing model predicates do not close missing raster colors, full rectangles, opacity transitions or negative-space clauses. Consume 107's stable drawer geometry; preserve 104's insertion/pencil transaction.

Verified planning selection: **55 open rows (20 GAP + 35 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/automation/presentation/proof.painting.txt` — A056, A057, A063, A066, A084, A087, A088, A098, A099, A102, A104, A105, A106, A107, A108, A109, A113, A126, A127, A129, A130, A131, A132, A135, A138, A139, A141, A143, A144, A147, A148, A149, A151, A152, A161, A171, A176, A183.
- `src/checks/automation/presentation/proof.tst_automationpresentation.txt` — A001, A008, A009, A011, A012, A013, A015, A016, A019, A020, A022, A024, A032, A033, A034, A037, A040.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `f3069ef693542bdb63564b80a29773e2f5b2a360`, `f3069ef693542bdb63564b80a29773e2f5b2a360`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/drawer/automation/AutomationPage.swift`
- `src/swift/app/drawer/automation/AutomationContentPublication.swift`
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift`
- `src/ui/songview/quick/drawer/AutomationPage.qml`
- `src/checks/automation/presentation/painting.swift`
- `src/checks/automation/presentation/tst_automationpresentation.swift`
- `src/checks/editorqml/tst_EditorDrawer.qml`
- `src/checks/automation/presentation/proof.painting.txt`
- `src/checks/automation/presentation/proof.tst_automationpresentation.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 and the accepted Group A checkpoint precede this task. Rebase automation publication/QML and painting checks over 100/104, then AutomationPage and tst_EditorDrawer over 107. No concurrent write to 113's EditorDrawer or shell lane is authorized.

# Interface contract

- Preserve `AutomationContentPublication`'s content/axis publication and `AutomationOverlayPublication`'s hover/ghost readout ownership. Repair only demonstrated selected presentation failures; no transaction, pointer or shortcut redesign.
- A056/A066 must paint active Tempo's curve with independently derived lane ink; A057 must exclude track-identity ink at the exact curve body. A063 compares the entire body rectangle including y across Volume/Tempo. After a real height increase (A084), both separator endpoints must follow the resized top/bottom (A087/A088).
- Pin exact active Pan/inactive LFO tab fills (A098/A099/A102), both LFO/Tempo inclusion-bar colors (A106/A107) and absence of leaked ghost outline at the exact two negative target positions (A108/A109). Expected colors come from the palette/oracle contract, never the item or primitive under test. Model colors and arbitrary changed pixels are insufficient.
- Ghost readouts remain inside the plot at the right half, follow their own curve y, show the exact hovered Tempo label, follow pointer x, sit above their own curve, disappear on unpin and avoid left-axis labels (A126/A127/A129/A130/A131/A135/A183). Badge presence, visible/inactive/empty opacity, bounds, name/count separation, stable tab height/name x and reactivation are distinct A139/A141/A143/A144/A147/A148/A149/A151/A152 conjuncts.
- Left-axis quarter labels, exactly three edge ticks at maximum/neutral/minimum and height alignment close A161/A171/A176. Use real pointer movement for the gutter arrow and Tempo pencil persistence (presentation A022/A024) and the selected move-consumption rows A034/A037/A040. These need no window keys in the editor-only lane.
- Retire painting A104/A105/A113's native capture prerequisites, A132's obsolete separate-native-model absence and A138's contentItem pointer only; keep the distinct hover-label/badge outcomes. Retire presentation A001/A008/A009/A011/A012/A013/A015/A016/A019/A020/A032/A033's deleted native fixture/pointer/window guards. Do not retire actual cursor or input-consumption behavior.

# Implementation steps

1. Extend the existing registered painting.swift and tst_automationpresentation.swift checks for the missing full rectangles, badge transitions, axis graduations and cursor consequences; retain existing domain predicates.
2. Extend the actual tab/ghost/hover journeys in tst_EditorDrawer with exact pixel targets and independently derived palette colors, including the negative outline targets and both resized separator endpoints.
3. Repair only selected publication or QML presentation divergence in the declared owners. Preserve all pointer transactions from 104 and insertion geometry/API from 107.
4. Close the 55 selected rows, account for the named native setup representations and delete both fully closed presentation ledgers.

# Acceptance predicate

The registered automation presentation checks prove model/layout consequences; verify:qml runs the actual EditorDrawer presentation/raster journeys. Every color, position, opacity, resize and cursor conjunct executes for its own selected row, and both full ledgers close.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No ShellWindow, EditorDrawer.qml, AutomationPrompt or transaction-owner writes. This editor-only lane may exercise pointer and presentation behavior, not window shortcut delivery.
