# Task 117 brief — polyphony event rows and responsive panel retain their exact behavior

# Context

Finish the mounted debugger’s tail-cut row, exactly-once navigation and short/wide layout. Existing production ownership is already present; do not create a second audio snapshot source or a synthetic debugger surface.

Verified planning selection: **16 open rows (8 GAP + 8 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/polyphony/proof.polyphonygate.txt` — A001, A005, A008, A013.
- `src/checks/polyphony/proof.polyphonypanel.txt` — A001, A005, A006, A012, A013, A023, A024, A026, A027, A029, A031, A032.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`, `3f830ceb349b6f5dd6e7fc76b035a83ec0cbd3d9`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/audio/PolyphonyPanelPresenter.swift`
- `src/ui/shell/PolyphonyPanel.qml`
- `src/checks/polyphony/PolyphonyPanelChecks.swift`
- `src/checks/editorqml/PolyphonyShellProbe.swift`
- `src/checks/editorqml/tst_ShellPolyphony.qml`
- `src/checks/polyphony/proof.polyphonygate.txt`
- `src/checks/polyphony/proof.polyphonypanel.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

Wait for 113/114 shell work and the previous accepted checkpoint. Keep the production audio/invert gate and existing PolyphonyShellProbe fixture interface; no Group A producer is required.

# Interface contract

- Preserve PolyphonyPanelPresenter.update, activateEvent(index:devicePixelRatio:), onJump, setVisible and setInvertChecked. Add the fork middle tail-cut event at tick 216 between the positioned steal and live drop in the existing fixture. It must display both literal 3:2.0 and tail cut; preserve newest-first order and the existing steal/live expectations by updating every exact fixture-count/index assertion.
- Count actual onJump invocations: the live sentinel emits none and activation of the positioned row emits exactly one tick/track/key/DPR tuple. Pair the Swift tuple law with a real pointer activation of the rendered existing panel delegate. Do not call activateEvent as the only mounted click witness.
- At the original tall/narrow, wide, short and expanded sizes, compare full actual usage/overflow rectangles: overflow top is at or below usage bottom in vertical layout; overflow left is at or beyond usage right in wide layout; every channel-grid cell stays in the viewport. After expanding, log vertical scroll range is exactly zero. An unrelated parent size or a positive content height does not close these clauses.
- Keep real initialized NativeAudio for the invert visibility gate; hidden checked state does not invert audio, reopening does, closing suspends invert without losing the checkbox, and unchecking disables it. Gate A001/A005/A008/A013, panel A001/A012 and A031 are deleted native fixture/spy/screenshot-file guards only; retire them alongside the executing audio, navigation and visible short-layout outcomes. Do not replace A031 with an assertion that a file can be saved.

# Implementation steps

1. Extend the existing three-event projection/fixture and update all checks that depend on its exact contents.
2. Complete the mounted responsive rectangle/grid/scroll and real row-click journeys without changing the panel’s public ownership.
3. Repair only selected formatting/layout/navigation defects; preserve the real audio visibility gate.
4. The separate ledger writer maps the sixteen rows and deletes the two ledgers only after all old native obligations are explicitly classified.

# Acceptance predicate

The registered themeColor suite actually calls runPolyphonyPanelChecks and the shell-polyphony lane observes mounted event text, pointer navigation and each requested layout transition. The audio device must initialize; an unavailable device is a reported prerequisite failure, not a skipped gate.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-themecolor --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-polyphony --verbose
```

# Task-specific constraints

No ApplicationSession, ShellPresenter, ShellWindow or audio-engine edits. Fixture changes here are confined to the existing check-owned snapshot producer, never shared on-disk project content.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
