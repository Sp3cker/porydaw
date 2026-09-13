## 1. Context

Remediation brief R6 fixes signed-off findings E-M4 (parallel availability/dispatch switches + transposeStepFor tail) and E-M5 (handleEditKey two-stage chain + SelectionTarget::None catch-all), plus opportunistic minors E-m7 (focus/owner precedence in two vocabularies) and E-m8 (objectName back-channel — dissolves with R5's table). All SIGN OFF by `QtSignoffFindings`. editkeyrouting.cpp:167-237 vs :239-350 run parallel availability and dispatch switches with repeated predicates at :176,180,211 and mirrored if/else bodies; PencilMode is the only arm re-checking availability inside execution (:331); transposeStepFor (:83-114) has seventeen dead arms returning 0; and handleEditKey (:381-428) chains per-command special cases before re-switching via resolveSelectionTarget (:430-448) with a DuplicateTime carve-out at :447.

## 2. Exact write set

- `src/ui/songview/editactions.h`
- `src/ui/songview/editactions.cpp`
- `src/ui/songview/editkeyrouting.cpp`

## 3. Prerequisites

- [Task R5](task-R5-brief.md) — the canonical table exists; this task adds the per-command policy columns to it. Same-file serialization, not an invented API dependency beyond that.

## 4. Interface contract

Per-command policy rows `{available, execute, ownerRule, originRule, autoRepeatRule, terminalWhenUnmatched}` in the R5 table preserve observable behavior and dissolve the availability/dispatch duplication; the shared availability predicates are single definitions, not locally re-derived ones; `PencilMode`'s mid-execution availability re-check becomes row data like every other arm. `transposeStepFor` becomes a 4-entry lookup with default 0 — the table form is deliberate: a switch default would suppress `-Wswitch` on an enum that gains values. The window-owner declines for **Copy/SoloTracks encode that window-scoped QAction delivery owns those keys when the window is the shortcut owner; they survive the table collapse as the delivery-class column's second reader — policy data, never inline ifs.** The focus/owner precedence duplication is folded into one `resolveCopyTarget`/`resolveSoloTarget` shared by `execute()` and the window-owner policy rows (E-m7). `SelectionTarget::None` stops being a catch-all: unknown targets are explicit rows, `DuplicateTime` becomes terminalWhenUnmatched data.

## 5. Implementation steps

1. Convert the parallel availability/dispatch switches (editkeyrouting.cpp:167-237, :239-350) to the row descriptors; delete the sixteen dead transposeStepFor arms and keep the table form with default 0.
2. Rewrite handleEditKey's per-command special cases (:381-428) and the resolveSelectionTarget re-switch (:430-448) as policy-row consumption; the DuplicateTime carve-out becomes `terminalWhenUnmatched` data, not an inline if.
3. Encode Copy/Solo window-owner declines as policy data read off the delivery-class column; no inline special case remains (E-m7 fold: shared targets via `resolveCopyTarget`/`resolveSoloTarget`, both consumed by execute() and keyboard policy).
4. Behavior guard: this task is restructuring; committed behavior including eligibility quantities, auto-repeat and the terminal outcome table are bit-identical.

## 6. Acceptance predicate

handleEditKey, availability and dispatch route through one per-command descriptor table; no availability predicate is stated twice; Copy/Solo declines exist as policy data only and the special-case if chain is gone; committed behavior is unchanged. Named checks: `deno task verify --filter selectionkey --filter rollcheck --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. **Spec amendments this brief lands:** spec.md#physical-activation-and-local-priority, the Editor-row "Keyboard-origin eligibility remains in `handleEditKey`; it is not stored on the action or in focus history" wording gains "as data rows in the canonical table, not per-command special cases"; the §"Keyboard-origin eligibility" phrasing "then applies existing origin/repeat/gesture rules to three terminal outcomes" gains "as per-command policy rows in the shared canonical table" and the phrase "Policy rows encode the window-owner declines for Copy/SoloTracks." Mechanical exception scope is as in R5: the reach into editactions.cpp/h is the descriptor landing; no fixture or widget files.
