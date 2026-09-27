# Task 101 brief — velocity drawer painted context and stable chrome

# Context

Own the visible velocity drawer: wheel-anchored projection, ruler/context markers, detent chrome, selected/ordinary/dimmed ink, band/ramp preview and stable rows through refresh/hide/show. Preserve 94's instrument-family transactions and 95's overlap capture; this task completes the presentation laws, not another gesture engine.

Verified selection: **57 open rows (3 GAP + 54 PARTIAL)**, all open rows in `src/checks/drawerpresentation/proof.velocity.txt`:
A014–A016, A020–A024, A026, A027, A031–A033, A041, A054, A056, A057, A062–A075, A079, A082, A083, A085–A095, A097–A101, A113, A114, A116, A117, A120–A122.

Oracle: `f3069ef693542bdb63564b80a29773e2f5b2a360:src/checks/drawerpresentation/velocity.cpp`, with fork `fceecd88`. Selected clauses were read at ledger :71–180, :210–294, :312–553, :602–654. The header records the original's prior deletion in `67544720`; no C++ source is recreated.

# Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift` — conditional refresh/context repair.
- `src/swift/app/drawer/velocity/VelocityContext.swift` — conditional rounded context tick repair.
- `src/swift/app/drawer/velocity/VelocityPublication.swift` — conditional projected rows/transients repair.
- `src/swift/app/drawer/velocity/VelocityScene.swift` — conditional node/stem style repair.
- `src/swift/app/drawer/velocity/VelocitySceneValues.swift` — conditional axis/grid/ramp geometry repair.
- `src/swift/app/drawer/EditorDrawerLayout.swift` — conditional velocity chrome geometry/retained-height repair.
- `src/ui/songview/quick/drawer/VelocityPage.qml` — conditional actual wheel/paint repair.
- `src/ui/songview/quick/drawer/EditorDrawer.qml` — conditional detent/toggle paint repair.
- `src/checks/drawerpresentation/velocity.swift`
- `src/checks/velocity/tst_velocityediting.swift`
- `src/checks/editorqml/tst_ShellDrawerParity.qml`
- `src/checks/drawerpresentation/proof.velocity.txt` — selected rows, then delete after complete closure.

No velocity interaction/transactions, shared palette, camera-domain, fixture content, registration, automation page or editor-drawer check-file writes. This preserves Group A disjointness.

# Prerequisites

All 91–98 land before dispatch. Rebase the shell drawer lane over 94; consume 94's ruler/paint detents, 95's overlap cancellation, 97's roll modifier gestures and 98's toolbar key authority unchanged. Task 93's raster lessons and frame-safe sampling apply. No other Group A task owns these files; 105 later consumes wheel/camera behavior read-only.

# Interface contract

- Preserve `VelocityPage` pointer/refresh entry signatures, `VelocityScene.axisModel/axisRows` (`VelocitySceneValues.swift:91–188`) and `velocityContextTick` (`VelocityContext.swift:12–16`). No new public diagnostics.
- Real wheel input increases zoom and holds the tick under its pointer within one physical pixel, not merely after direct camera mutation. A displayed marker's y equals the axis mapping of its actual velocity; live raw-74 preview displays 74 and hover has exactly one active graduation. Existing projection checks are `drawerVelocityProjectionRefresh` (`drawerpresentation/velocity.swift:380–435`).
- Visible toggle geometry is contained in the bar, follows Automation by the base-font spacing, and retains the requested section height while hidden/re-shown. The detent control is visible for resolved PSG context, hidden for direct sound, lies left of the plot, aligns with the band's left/bottom edges and avoids the first graduation. Clicking it visibly repaints checked/unchecked ink; do not assert the deleted icon revision counter. Current owners are `EditorDrawerLayout.bodyHeight` (:67–78) and the actual detent item (`EditorDrawer.qml:429–495`).
- Sample actual past-end grid, ruler separator accent, outsider stem, selected ring, ordinary node base/track fill, dimmed-node mid ink without the ordinary border, selected stacked/right-pressed node highlight, right-band fill/edge/clear and Shift-ramp outline. Match fork vanilla color identities through the existing semantic palette; do not use the node's own model color as the sole expected value. QML draws these at `VelocityPage.qml:304–409`; style ownership is `VelocityScene.handleRows` (`VelocityScene.swift:227–303`).
- Moving the edit cursor visibly moves its guide. Clearing header selection empties note selection. Playing context rounds -1, 0.49, 0.5 and 0.51 to 0,0,1,1 and resolves the real program context at each resulting tick. `drawerVelocityPlayheadDiagnostics` (`drawerpresentation/velocity.swift:481–533`) is extended through real session state.
- Undo returns the exact pre-edit history index; redo returns the committed index. Undo and redo each advance revision exactly once. Refresh/song-change and horizontal scrolling do not churn stable text rows; hide/show retains their count. Extend `drawerVelocityGestureTransactions` (`tst_velocityediting.swift:9–72`) and existing publication checks; no new retained-state counters or idempotence guards.
- Retire only A014/A092–A094/A098–A100 (native fixture note/level prerequisites), A022/A070 (native interaction pointer identities), A027/A069 (duplicate native chrome visibility flags), A071 (native bounds-to-chrome-object identity), A079/A082 (native icon revision counters). Exactly **14 representation rows** accompany **43 behavior rows**. Painted color, geometry, marker, history and refresh outcomes cannot retire.

# Implementation steps

1. Extend the two existing Swift check files with distinct y/marker/context/history/row-lifecycle clauses through their real fixture builders. Retain existing messages and snapshots; do not copy a model value into its expected value.
2. Extend `tst_ShellDrawerParity.qml`'s real velocity journey (`dragMountedVelocity`, :490–619), using staged bank/program APIs and actual wheel/toggle/pointer input. Add image samples for each painted clause and hide/show geometry observations; do not borrow task 100's `tst_EditorDrawer.qml`.
3. Repair only an executed presentation divergence at the listed owners. Preserve the existing scroll-only publication path (`VelocityPublication.swift:44–61`) and axis/handle refresh (:63–75). RED may be absent if the runtime already matches.
4. Attach executed same-change evidence, retire only the 14 named native clauses and delete the fully closed presentation ledger. Leave all seven `velocity/` ledgers and their reserved rows untouched.

# Acceptance predicate

`runVelocityPageChecks` (`VelocityPageChecks.swift:148 onward`) runs the existing presentation/history functions in `swiftcore-projectsession`; `ShellQmlTests.swift:95–96` registers the actual mounted shell drawer lane. Both semantic state and actual wheel/paint/geometry journeys must pass.

Controller-run on the settled group under sprint-3 §11 verification policy:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-drawer-parity --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json` and `shell-drawer-parity.json` under `build/proof-evidence`. Full shell and full verify are mandatory, in addition to the mounted journey; each invoked process has a 175 s alarm and a 180 s ceiling after serialized lock acquisition.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
No physical-monitor DPR or audible-engine claim follows from the offscreen/null-backend lane. A real shared-camera defect outside the closed set requires an ownership revision, not a velocity-local workaround.
