# Task 119 brief — automation raster proves exact nodes, rings and half-open selections

# Context

Complete the actual automation/voice drawer framebuffer observations, not the deleted QSG layer representation. Consume 115’s stable pointer lifecycle and 118’s lane-state projection. Preserve 111’s active-tab/ghost presentation and 108’s velocity cases.

Verified planning selection: **58 open rows (58 GAP + 0 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/automation/raster/proof.interaction.txt` — A007, A009, A011, A012, A013, A014, A015, A017, A019, A020, A021, A022, A023, A024, A025, A026, A027, A028, A030, A031, A032, A033, A034, A037, A038, A043, A044, A046, A047, A057, A062, A070, A071.
- `src/checks/automation/raster/proof.painting.txt` — A010, A011, A012, A013, A014, A015, A016, A017, A018, A023, A024, A025, A026, A027, A029, A030, A034, A037, A038, A039, A040, A041, A042, A043, A044.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`, `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/drawer/automation/AutomationPage.swift`
- `src/swift/app/drawer/automation/AutomationContentPublication.swift`
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift`
- `src/ui/songview/quick/drawer/AutomationPage.qml`
- `src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift`
- `src/ui/songview/quick/drawer/VoiceChangesPage.qml`
- `src/checks/automation/presentation/painting.swift`
- `src/checks/automation/automationcanvasediting.swift`
- `src/checks/editorqml/tst_EditorDrawer.qml`
- `src/checks/editorqml/tst_ShellDrawerParity.qml`
- `src/checks/editorqml/ShellQmlTests.swift`
- `src/checks/automation/raster/proof.interaction.txt`
- `src/checks/automation/raster/proof.painting.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

Accepted Group A checkpoint, specifically 115 input and 118 state, precedes reuse of AutomationPage.swift, AutomationOverlayPublication.swift, AutomationPage.qml, automationcanvasediting.swift and tst_ShellDrawerParity.qml. Rebase presentation files and tst_EditorDrawer over 111. No dependency on another Group B implementation.

# Interface contract

- Use actual pointer hover/drag/release on the existing Pan/Tempo plot and voice-change lane. At the fork’s exact insertion center, written-node center and outer annulus, prove independently derived fill/ring colors and return to the exact idle target pixels on lane transition and leave. Repeated hover is pixel-identical and document bytes/revision/history are unchanged. Whole-frame “some pixels changed” is not a substitute for a node or annulus target.
- Scrolled held-value phantom hover has exactly one text row with the original lane value text; dragging paints the transient node at the actual drag target. Cancellation clears hover/transient state and retains the scrolled document snapshot. Commit edits the original source tick/value with no duplicate at the viewport edge. Pair bytes/points in registered Swift checks with mounted pointer and pixel evidence; do not expose a test-only byte getter.
- Painting A010–A029 retains normal held curve and node ink, selected ring ink, absence of the removed second node, correct inactive/away-lane node ink and complete time-selection retention (start/end/scope/tempo/lanes). Selected reticle publication must change after selection; obsolete QSG revision/triangles are not recreated, but visible curve/node/ring consequences remain mandatory.
- For both half-open selection variants, use the exact fork A/B/C node groups: A ring present, B ring present only when the end extends beyond B, C ring absent. Derive expected pixel coordinates from independent tick/value/radius equations and actual scene offsets; compare both layer-consumer geometry and final pixels. Do not hide the production selection reticle through a test mutation: sample the independently known outer annulus and include any reticle compositing in the independently calculated expected background. Expected colors come from palette/oracle constants, not tested items.
- Voice A057 verifies the exact cursor-derived value after the original gesture. A062 requires press-without-move pixel equality; A070/A071 requires identical frame size but the expected moved preview pixels before release, with no early commit. Preserve existing voice commit/cancel tests.
- In ShellQmlTests.swift add a DPR2 child for shell-drawer-parity following the existing note-visuals child convention, selecting a bounded dedicated raster test in tst_ShellDrawerParity.qml, guarded against recursion and with failures propagated. The child sets QT_SCALE_FACTOR=2 and captures physical pixels; assert observed DPR is 2. The ordinary lane and this real DPR2 child both execute selected raster clauses. Preserve note-visuals and polyphony registrations unchanged.
- Retire only the old capture-ready/helper success and QSG object forms: interaction A007/A009/A014/A017/A027/A028, painting A012/A016/A025/A030/A034/A040/A041, plus the obsolete layer-container portion of mixed rows. Capture errors still fail the actual pixel consumer; do not add frame-nonempty setup assertions as replacement evidence.

# Implementation steps

1. Extend registered Swift painting/canvas cases for exact points, selection and no-write snapshots accompanying the mounted scenarios.
2. Replace incomplete pixel-change-only evidence with precise curve/node/annulus and negative-target predicates in the existing drawer lanes.
3. Add the bounded actual DPR2 shell-drawer raster child and preserve all unrelated registration behavior.
4. Repair only demonstrated selected publication/QML defects, then have the separate ledger writer close/delete both raster inventories when every behavioral conjunct executes.

# Acceptance predicate

Both ordinary and actual DPR2 shell-drawer raster journeys prove node/ring/preview positions and colors, while registered Swift cases prove the corresponding transaction bytes. No raster row closes from model colors or a normal-DPR lane alone.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-drawer-parity --verbose
```

# Task-specific constraints

No velocity, shell command, ApplicationSession, EditorSurface or fixture-file writes. Window keys remain in shell-drawer-parity, never editorqml; the extra registration is only the declared DPR2 raster child.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
