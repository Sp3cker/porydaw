# Shared menu actions and fixed shortcuts

## Status and authority

Implementation plan only. Committing these documents does not start application implementation; builds, runtime checks and implementation require a separate execution request. The agreed behavior and resolved interfaces are in [spec.md](spec.md). No product questions remain open.

The controller obtained two independent plan-agent opinions on the major engineering decisions and two focused Qt-specialist reviews, resolved their challenges against the repository and official Qt source, and owns the decisions below.

## Global Constraints

1. The specification and this section govern every task. Implement on top of the existing `feature/time-editing` branch in the current checkout. Do not create another branch or worktree, switch checkouts, or move implementation to the main checkout. Preserve user work, including the existing reference files `Porydaw - Ableton` and `porydaw-shortcut-improvements.md`; do not edit AGENTS.md. Commit only when requested and synchronize authorized commits according to the repository's push requirement.
2. Follow `sdd-triage-gate` and, for SDD-track execution, `sdd-execution-loop`. Routes/seats are recorded below; Direct dispatches carry Target/Change/Acceptance inline, with the linked brief supplying their requirements. Global constraints are not repeated in briefs.
3. The write sets are closed. Use LSP references before exported-symbol changes; supplement demonstrably incomplete constructor/template references with scoped search. Preserve existing Qt ownership, selection observer, popup session and history conventions. Do not create a command bus, focus framework, implicit action fallback, compatibility alias, or second physical shortcut dispatcher.
4. Each ordinary task has at most three files, five steps and one acceptance predicate. Tasks 3, 6, 11 and 31 are explicit same-shape mechanical migrations/deletions with exact per-file lists. Time/note dismissal and action-row projection are combined where their union fits the cap; remaining splits follow real ownership/interface boundaries.
5. Dependencies name consumed interfaces/behavior. The numbered order is a valid serial order. Parallelize only ready tasks with disjoint write sets; shared-file edits are serialized even without a semantic dependency. Concurrent implementers perform the read-only, file-local inspection required by `sdd-execution-loop` on their owned files and report its evidence. They defer shared builds/tests and formatter/linter commands to the controller, who validates settled changes once per completed batch before the per-task review gate. Deferred verification is not a pass. Task acceptance does not require a commit; use the checkpoint cadence below.
6. Verification policy: command-based build/format/check verification uses only `deno task` entry points; read-only local inspection follows `sdd-execution-loop`. Run the named focused checks for each settled behavior change, batching the union for compatible completed tasks rather than rebuilding per micro-edit. Run the full `deno task verify --verbose` once at final integration. Final source formatting uses the project formatter on affected source files; do not restyle unrelated files. `--filter` is substring matching and repeated filters form a union; `rollcheck` also selects `rollcheck-static`. Avoid `--qt` unless exactly one harness is selected.
7. Native UI changes require the real shown application/Quick surfaces and a final visible walkthrough; use the native-window capture skill for screenshots when needed. Existing checks are preferred. Add a permanent regression only for a plausible target, lifetime, priority or exactly-once failure; delete obsolete wording/parent-layout/remapping/stale-menu pins rather than repinning them. Do not manually activate a closed menu to simulate a removed feature. Retain form-transaction guards.
8. Keep the current musical editing algorithms, lane/time/tempo scope, clipboard formats, undo granularity, scale-fold/audition behavior and transport distinctions unless the spec explicitly changes them. Window and Editor scope are not interchangeable. No disconnected automation node selection, modifier-hover scaffolding, drag redesign or unrelated menu reorganization.
9. Producers name their downstream consumers. Intermediate extraction stages preserve existing behavior; the keyboard/action-row cutovers then remove old execution paths, and Task 31 removes remaining unreachable storage. Do not leave stubs, no-op compatibility methods or obsolete paths in the completed implementation.

## Task sequence

Each line is one bounded task with its execution route, reason and implementation seat.

1. [Retire remapping-only keymap checks](task-1-brief.md) — **SDD-track**: Qt Test contract retirement across the existing keyboard harness. Seat: `qt-cpp-reviewer`.
2. [Retire Keyboard settings-only checks](task-2-brief.md) — **SDD-track**: Settings test surgery must preserve independent Engine/Song behavior. Seat: `qt-cpp-reviewer`.
3. [Remove mutable keymap fixture dependencies](task-3-brief.md) — **Direct**: Same-shape removal of obsolete registry-restoration scaffolding. Seat: `qt-cpp-reviewer`.
4. [Remove the Keyboard Shortcuts application entry](task-4-brief.md) — **SDD-track**: Closes a user-facing menu/slot contract before Settings enum removal. Seat: `qt-cpp-reviewer`.
5. [Remove Keyboard settings and rollback state](task-5-brief.md) — **SDD-track**: User-facing Settings lifecycle and enum cutover. Seat: `qt-cpp-reviewer`.
6. [Delete unreachable shortcut editor sources](task-6-brief.md) — **Direct**: Same-shape source and build-list retirement after all consumers are removed. Seat: `sdd-implementer`.
7. [Make command bindings immutable and scope-explicit](task-7-brief.md) — **SDD-track**: Permanent fixed-key API, hot-path storage and activation metadata cutover. Seat: `qt-cpp-reviewer`.
8. [Separate semantic editing from key recognition](task-8-brief.md) — **SDD-track**: Target precedence and gesture invariants cross keyboard and QAction entry. Seat: `qt-cpp-reviewer`.
9. [Implement the concrete canonical edit action set](task-9-brief.md) — **SDD-track**: QObject ownership, target rebinding and shared availability are load-bearing. Seat: `qt-cpp-reviewer`.
10. [Bind actions at existing SongView lifecycle seams](task-10-brief.md) — **SDD-track**: Native ShortcutOverride and selection/menu lifetime must preserve local priority. Seat: `qt-cpp-reviewer`.
11. [Bind real actions in standalone fixture roots](task-11-brief.md) — **Direct**: Uniform construction-only dependency binding with an exact per-file list. Seat: `qt-cpp-reviewer`.
12. [Retire obsolete action ownership test pins](task-12-brief.md) — **Direct**: Remove implementation pins while preserving observable clipboard and activation proof. Seat: `qt-cpp-reviewer`.
13. [Make MainWindow project canonical edit actions](task-13-brief.md) — **SDD-track**: Stable per-window identity and active-tab/readiness retargeting change ownership. Seat: `qt-cpp-reviewer`.
14. [Remove Pencil’s duplicate action and keyboard interceptor](task-14-brief.md) — **SDD-track**: Pencil ownership and prompt deactivation behavior must be separated safely. Seat: `qt-cpp-reviewer`.
15. [Cut over editor keys to actual QAction activation](task-15-brief.md) — **SDD-track**: Removes the final duplicate physical/semantic delivery path. Seat: `qt-cpp-reviewer`.
16. [Route event movement through shared actions](task-16-brief.md) — **SDD-track**: Local row navigation must not compete with shared event edit activation. Seat: `qt-cpp-reviewer`.
17. [Attach remaining fixed window bindings consistently](task-17-brief.md) — **SDD-track**: A/V/P must remain window-wide across persistent Quick focus. Seat: `qt-cpp-reviewer`.
18. [Dismiss ruler menus on relevant state transitions](task-18-brief.md) — **SDD-track**: Cursor and document changes must retire positional menus without cancelling forms. Seat: `qt-cpp-reviewer`.
19. [Add guarded QAction-backed Quick menu rows](task-19-brief.md) — **SDD-track**: Close-before-trigger, checked state and QObject destruction are uncertain lifecycle edges. Seat: `qt-cpp-reviewer`.
20. [Dismiss and share the automation fallback Clear action](task-20-brief.md) — **SDD-track**: Automation menu lifetime must track lane/time identity, not focused drawer. Seat: `qt-cpp-reviewer`.
21. [Dismiss automation point menus without invalidating drafts](task-21-brief.md) — **SDD-track**: Point-menu retirement must not erase guarded numeric transactions. Seat: `qt-cpp-reviewer`.
22. [Expose the existing selected-note velocity form](task-22-brief.md) — **SDD-track**: New canonical entry must preserve the real guarded form transaction. Seat: `qt-cpp-reviewer`.
R1. Remediation — [Keymap catalogue collapse](task-R1-brief.md) —
    **SDD-track**: dead keymap plumbing deleted (K-B1); forwarding accessors
    consolidated with the allowShift carve-out and `singleStroke` helper
    (K-M5), matches overload split with `isModifierKey` kept public (K-M6);
    K-m7/K-m8 opportunistic. Seat: `qt-cpp-reviewer`.
R2. Remediation — [Make attach the single context writer](task-R2-brief.md)
    — **SDD-track**: five caller-side `setShortcutContext` pre-writes deleted
    (K-B2), including the automation-page live contradiction. Seat:
    `qt-cpp-reviewer`.
R3. Remediation — [Keymap override-immunity regression](task-R3-brief.md) —
    **SDD-track**: seeded registry keys provably ignored (K-B3). Seat:
    `qt-cpp-reviewer`.
R4. Remediation — [SettingsDialog bool cutover](task-R4-brief.md) —
    **SDD-track**: two-value Tab machine to a constructor bool (K-M4). Seat:
    `qt-cpp-reviewer`.
R5. Remediation — [Canonical command table + delivery-class recognizer](task-R5-brief.md)
    — **SDD-track**: one table, one recognizer (E-B1/E-B2) with the
    delivery-class parameter; preserves the window-delivered vs
    EditorRouted/manually-delivered split (cross-cutting gate 1). Seat:
    `qt-cpp-reviewer`.
R6. Remediation — [Availability/dispatch collapse](task-R6-brief.md) —
    **SDD-track**: shared predicates and per-command rows (E-M4/E-M5);
    focus/owner precedence resolved once (E-m7, E-m8 absorbed). Seat:
    `qt-cpp-reviewer`.
R7. Remediation — [Narrowed EditActions bind contract](task-R7-brief.md) —
    **SDD-track**: E-M3 option (b), bind/unbind without reassignment; the
    destroyed-refresh connection is kept under the borrow contract (E-m11);
    decided once per cross-cutting gate 2, before Q-F1's helper lands. Seat:
    `qt-cpp-reviewer`.
R8. Remediation — [EditActions refresh regimes](task-R8-brief.md) —
    **SDD-track**: clipboard cache kept; never-replaced-canvas machinery
    deleted; Copy folded into focus precedence (E-M6 amended). Seat:
    `qt-cpp-reviewer`.
R9. Remediation — [Fixture bind helper + per-site mechanical migration](task-R9-brief.md)
    — **Direct**: one `checks::support` helper replaces all identical
    `EditActions`/`rebind` fixture construction sites (29 sites / 23 files,
    Q-F1; explicit mechanical-migration exception). Seat: `qt-cpp-reviewer`.
R10. Remediation — [Quick-menu restructure](task-R10-brief.md) —
     **SDD-track**: Q-F2 header move + contract doc (Q-F3 rejected, folded as
     a doc sentence), Q-F4 per-level observation, Q-F5 trigger extraction
     keeping the post-trigger guard, Q-F6 shared predicate keeping the
     `isEditing` guard. Seat: `qt-cpp-reviewer`.
T22R. Mid-plan review gate — [Thermo-nuclear review after task 22](task-T22R-brief.md)
      — **Gate, not a task**: single `thermo-nuclear-reviewer` pass over tasks
      12–22 + R-fixes; gates 1/2 re-verified; fix loop bounded to one round.
      Seat: `thermo-nuclear-reviewer`.
23. [Expose cursor-based time signature form entry](task-23-brief.md) — **SDD-track**: Exact cursor/event identity must survive the existing modal transaction. Seat: `qt-cpp-reviewer`.
24. [Implement canonical velocity and positional commands](task-24-brief.md) — **SDD-track**: Current cursor/selection and multi-command undo define the new shared entries. Seat: `qt-cpp-reviewer`.
25. [Complete Edit menu with existing action objects](task-25-brief.md) — **SDD-track**: Transport ownership and native menu projection must remain identity-preserving. Seat: `qt-cpp-reviewer`.
26. [Dismiss and project canonical time selection menus](task-26-brief.md) — **SDD-track**: Replacing range ID dispatch must preserve clipboard and popup focus behavior. Seat: `qt-cpp-reviewer`.
27. [Dismiss and project canonical note context menus](task-27-brief.md) — **SDD-track**: Note selection and velocity form focus must not depend on a stale menu snapshot. Seat: `qt-cpp-reviewer`.
28. [Establish ruler context before canonical menu activation](task-28-brief.md) — **SDD-track**: Half-open hit classification, exact chip identity and transport seek are observable changes. Seat: `qt-cpp-reviewer`.
29. [Reuse canonical event actions in row menus](task-29-brief.md) — **SDD-track**: The equivalent event row menu must not retain a second mutation sink. Seat: `qt-cpp-reviewer`.
30. [Anchor unselected Insert Time at edit cursor](task-30-brief.md) — **SDD-track**: Playback and modal form timing currently select the wrong insertion anchor. Seat: `qt-cpp-reviewer`.
31. [Delete unreachable context menu target machinery](task-31-brief.md) — **Direct**: Same-shape removal of now-unreachable menu snapshots and dispatch sinks. Seat: `qt-cpp-reviewer`.
32. [Verify native priority and exactly-once integration](task-32-brief.md) — **SDD-track**: Native accelerators, foreign focus and active-tab lifetime need end-to-end proof. Seat: `qt-cpp-reviewer`.
33. [Document fixed commands and ruler cursor semantics](task-33-brief.md) — **Direct**: Bounded user documentation update after observed runtime behavior. Seat: `sdd-implementer`.

## Dependency and ownership schedule

| Workstream | Interface order | Shared mutation boundary |
| --- | --- | --- |
| Fixed bindings/settings | 1/2/3 → 4/5/6 → 7 | Keymap, MainWindow and Settings source changes are serialized |
| Semantic/action ownership | 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15; then 16/17 | SongView header/routing and MainWindow are integration-owned |
| Popup lifetime/adapter | 10/11 → 18; 19 is independent; 10/11/19 → 20 → 21 | Separate ruler/automation owners; no parallel edits to a shared check file |
| Existing form entry points | 11 → 22; 18 → 23 | Roll/ruler commands are serialized against their menu migrations |
| Remaining canonical actions | 15/22/23 → 24 → 25 | SongView enum/dispatch and EditActions factory stay one ownership slice |
| Context-menu cutover | 19/25/20/21 → 26; 19/24 → 27; 18/19/24 → 28; 16/19 → 29 | Range, note, ruler and event rows migrate only after their contracts exist; Task 28 composes ruler rows independently of Task 26's range-menu producer |
| Cursor/final cutover | 28 → 30; 26/27/28/29/30 → 31 → 32 → 33 | Serialize Task 26 before Task 30 for their shared rangeedit.cpp writes, not as an interface prerequisite; final review and whole-suite validation are controller-owned |
| Remediation (keymap/settings) | R1 → R2 → R3; R4 independent | Keymap/settings writes serialized; SettingsDialog cutover may run parallel to R1 |
| Remediation (editactions core) | R5 → R6 → R7 → R8 | `editactions.h/.cpp` and `editkeyrouting.cpp` edits serialized; gate 1 (delivery split) and gate 2 (E-M3 option (b), decided in R7 before R9's helper) hold across all four |
| Remediation (fixtures + quick) | R5 → R9; R5 → R10 | R9 is Direct and independent once R7's contract is decided-but-not-required-to-land; R10 follows R5's final recognizer shape |
| Mid-plan review gate | R1–R10 in flight or landed → T22R → then tasks 23+ resume | T22R after task 22 and the R batch; single `thermo-nuclear-reviewer` pass, one bounded fix round; outcome recorded in progress.md |

The brief prerequisites are authoritative. A shared write set adds serialization, not an invented public API dependency.

## Checkpoint cadence

- Batch accepted work at coherent milestones: after Task 7 (fixed bindings),
  Task 17 (shared action/keyboard ownership), Task 31 (menu/cursor cutover
  and cleanup), and Task 33 plus final whole-branch review (verified behavior
  and documentation). These are checkpoint opportunities, not extra tasks
  or mandatory additional commits when an earlier checkpoint left no work
  pending.
- Before a later task re-edits any file in the accumulated uncommitted
  write sets of earlier tasks, finish the prior writer's review/fixes and
  checkpoint its accepted work with other ready work. This includes
  non-adjacent reuse such as Task 26 → Task 30 in rangeedit.cpp.
- Serial disjoint-file tasks do not need intervening commits. Retain their
  check/review gates and captured task-scoped review baselines; do not
  create commits just to generate a diff. Stage only accepted plan changes,
  not user reference files or in-flight work, and follow `sdd-execution-loop`
  and the existing authorization/push constraint.

## Engineering decisions and second opinions

| Decision | Final choice | Challenge and disposition |
| --- | --- | --- |
| Fixed catalogue | Retain immutable metadata/read/match/attach, remove override machinery and planned dynamic eligibility metadata | A cold scout invented target restrictions from the mixed routing descriptions. Registry only supplies bindings/scope; Copy delegates to its existing time-first operation and event actions consume a controller-owned bool predicate |
| Canonical identity and registration | One MainWindow-owned EditActions; installWindowShortcuts is its sole QWidget-association operation and excludes EditorRouted actions | A cold scout mistook reusing the same QAction for safe widget registration. The owner now hides registration selection; native menus only project pointers, and widgets never call addAction for borrowed song actions |
| Native Editor shortcuts | Scope::Window uses Qt matching; Scope::EditorRouted uses one editorCommandForKey recognizer shared by the existing two stages | Name the delivery mechanism rather than implying a widget-local shortcut. Remove SongView's duplicate command map/matcher and caller-side association choices; retain decline/consume-no-op/trigger-once exits |
| Target binding and destruction | EditActions::rebind is the only writable binding interface; SongView exposes a getter and privately grants the owner access | Cold scouts split view-side pointer clearing from action teardown. Removed the public setter and caller-managed retirement; internal unbind precedes popup/child teardown, with defensive null-QPointer refresh retained |
| Window scope | Preserve existing Window commands, plus fixed A/V/P; no Window fallback in SongView | A/V/P/Space are examples, not a whitelist. The one isolated Copy fixture stimulus becomes real QAction activation; real MainWindow checks retain physical Window-key proof |
| Selection and availability | Existing semantic operations own targets; the action set only projects their eligibility | Copy has one time-before-notes implementation. EventListController hides destination legality behind canMoveCurrentRow, so unrelated note/time selections and raw index sentinels cannot leak into event-action policy |
| Ruler targeting | Selection path finishes before the cursor path can snap; menu opening takes only scene position, not a pre-snapped tick | A cold scout classified after snapping despite quoting the opposite rule. Removed the pre-snapped argument/left-drag-anchor reuse; exact chip or raw press coordinates decide the path, and only the outside background path snaps |
| Menu metadata/lifetime | Action-derived open-time projection; dismiss on relevant context or represented action metadata changes | Rejected local mutation switches and a second live metadata model. Paste empty↔valid can retire a menu; valid↔valid reads fresh payload at execution. Disabled Paste remains genuinely disabled |
| Checked-state synchronization | Canonical semantics use triggered only; plain setChecked preserves changed notifications; borrowed toggle owners stay unchanged | Qt review found that QSignalBlocker would suppress the menu-retirement signal. The obsolete Pencil toggled sink is explicitly removed; no metadata replay or custom signal is added |
| Submenu observation lifetime | Observe each open level on its own existing Level; detach each level's connections at its teardown; retirement on `changed()` is level-scoped | Q-F4 sign-off amended the remedy: the root tree walk also observed popped/unopened submenu snapshots and forced whole-session cancels; per-level observation retires only the affected level's stack (root retirement remains the session cancel) and the `actionBackedRoot` reset special case dies with the recursion |
| Shared popup hosts | Require session ownership plus the relevant root model or typed fallback row | Review found that host-only cancellation also closes unrelated grid/lane menus. Ruler root identity and the stable automation Clear row distinguish existing menu kinds without new state; the inactive Clear row also explicitly borrows its canonical action |
| Menu activation and focus | Scope-agnostic fromAction borrowing; one terminal host branch closes, rechecks guards and triggers, then reports focus-only completion | Cold scouts inferred menu-side scope and uncertainty after close callbacks. Callers now have no shortcut/lifetime decisions; failed guards return with no retry or completion, and a new form keeps focus |
| Forms and positional edits | Keep existing guarded forms; loop/signature/velocity actions use current cursor/selection | Stale menus disappear, not numeric transaction guards. Loop set/remove remains two undo commands. Static Set Velocity label replaces the context-only suffix |
| Transport and history | Borrow existing transport/search/history actions and handlers | Play resumes a paused transport; Space restarts at edit cursor. Undo/Redo retain WorkspaceUi request routing, not a newly invented history integration |
| Task size/proof | Closed bounded slices; combine same-surface menu dismissal/projection; mechanical fixture binding and dead-path deletion are explicit exceptions | Final plan validation checks links, dependency order, caps, paths and registered filters. Existing synthetic QKeyEvent helpers are not Cocoa key-equivalent proof; execution includes actual native input, a non-modal foreign-window protocol case, and removal of obsolete native metadata pins |

Plan-agent second opinions: `ActionArchitectureReview` (action ownership, fixed bindings, native priority, composition) and `MenuCursorDesignReview` (ruler/cursor, popup/model ownership, clipboard/focus, task cuts). Focused `qt-cpp-reviewer` opinions: `NativeQtScope` (native arbitration, associations and target destruction) and `QuickActionLifetime` (projection, checked signals, close/trigger ordering and root-tree observers). Required corrections are integrated. Blanket signal blocking and retained conflicts machinery were rejected; the former breaks Quick metadata retirement, the latter contradicts the fixed-catalogue cutover. Qt primary-source links are in [the activation contract](spec.md#physical-activation-and-local-priority).

## Completion evidence required during execution

- Fixed defaults ignore old override settings; Keyboard tab/menu and replacement-browser concepts are absent.
- Native Edit, keyboard and equivalent Quick/context/transport presentations use the same action objects with one semantic execution.
- Window priority, local text/IME/control/popup/gesture priority, selection authority and foreign-dialog isolation hold in the shown application.
- Ruler inside/outside/end/chip behavior, no note-grid seek, selected versus cursor Insert Time and advancing-playback form acceptance match the spec.
- Context changes dismiss menus without later stale activation; commands close before opening a form; form guards and two-step loop undo remain.
- All named checks and final full suite pass, actual visual walkthrough evidence is recorded, and existing manual/changelog text matches the final behavior.
