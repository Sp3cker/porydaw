## 1. Context

All production routes are cut over. Existing input suites cover the majority of the contract; extend only genuinely uncertain native-priority/lifetime edges and preserve their existing scenario structure.

## 2. Exact write set

- `src/checks/mainwindowrouting/tst_mainwindowrouting_native.cpp`
- `src/checks/selectionkey/windowtier_keyboard.cpp`
- `src/checks/selectionkey/localinputtier_text.cpp`

## 3. Prerequisites

- [Task 15](task-15-brief.md).
- [Task 17](task-17-brief.md).
- [Task 25](task-25-brief.md).
- [Task 29](task-29-brief.md).
- [Task 31](task-31-brief.md).

## 4. Interface contract

Shown real-MainWindow checks prove native menu/Quick menu/key activation once, editor selection targeting despite other drawer/chrome focus, and protection of text/IME, numeric controls, popup/cell editing and foreign dialog input. Tests observe document/transport/undo effects and activation counts, not QAction parent layout or copied metadata fields.

## 5. Implementation steps

1. Exercise two distinct native/input cases with an enabled Editor action and the native Edit menu installed but closed: eligible timeline input activates once; a foreign non-modal window receives ordinary local keys with zero song edits/action activations. Protected text/navigation/popup input also stays local. A modal-only foreign case is vacuous because Cocoa disables menu items.
2. Retain Window A/V/P/Space and Copy/Solo observations, active-tab lifetime and paused Play-versus-Space behavior. Destroy the bound SongView without an external unbind; prove its early internal unbind prevents activation during child/popup teardown, not merely after destroyed is emitted. Preserve native QWidget text-copy availability with no musical selection and use real composition.
3. Run a visible native application walkthrough of Edit groups, note/range/automation targets, ruler inside/outside/chip flows, prompts and dismissal. Use real physical/OS-delivered keys for native-menu preemption and local-input checks: the existing sendShortcut/eventsynth helpers send QKeyEvent directly and do not exercise Cocoa key-equivalent dispatch. Record which observations are synthetic Qt protocol checks versus real native input.

## 6. Acceptance predicate

The final native application and focused suites demonstrate exactly-once action activation, correct targets, protected local input and cursor/menu lifetime with no duplicate owner. Named checks: `deno task verify --filter mainwindow-routing --filter selectionkey --filter rollcheck --filter automation --filter eventviews --filter transportcheck --filter selftest-transport --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Use existing scenario methods/data rows where possible; retain a new permanent regression only for a plausible native-priority or lifecycle failure. Do not assert source text or object ownership layout.
