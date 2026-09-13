# Task R10 — Quick-menu restructure: header hygiene, per-level observation, trigger extraction, shared move predicate

## 1. Context

`quickmenuhost.cpp` stays cohesive (one adapter, ~710L); file-splitting was
considered and explicitly rejected by the review. Four majors from the
QuickFixtures slice plus one folded documentation fix land here as one
coordinated behavior-preserving restructure:

- **Q-F2** (amended): `QuickMenuItem::fromAction` body leaves
  `quickmenumodel.h` for `quickmenumodel.cpp` beside `makeSeparator()`; the
  `&`-strip loop becomes a named `stripAccelerator(QStringView)` free function
  in that `.cpp`; the snapshot/live model is **not** redesigned. Q-F3 is
  **rejected as stated** (host triggers the callback, not `fromAction`), folded
  in as a contract-documentation sentence here — see step 4.
- **Q-F4** (sign-off, per-level remedy preferred): connect per level, not per
  root tree; drop `collectActionBackedRows` recursion, the root-only wiring,
  and the `actionBackedRoot` special-case in `handleLevelReset`; level-scoped
  cancel first (uniform with today's root semantics), re-projection optional
  polish. F7/F9 die with the recursion.
- **Q-F5** (amended): extract `triggerActionBackedRow(QAction*)`; the
  close-before-trigger order is load-bearing (trigger may reenter `open()`)
  and gets a one-line comment; delete only provably dead snapshots (`source`
  is dead after the guard); **keep the post-trigger `host && action` guard** —
  it protects the emit against reentrant destruction during `trigger()`.
- **Q-F6** (amended, one arm rejected): move `canMoveCurrentRow` body out of
  the header; make `rebuildRowMenu` enabled flags and `editCommandAvailable`
  consume the same predicate. **Rejected:** unconditional
  `m_events->moveCurrentRow(delta)` — it checks destination legality but not
  `isEditing()`, so unconditional dispatch is a behavior regression allowing a
  mid-edit move. Keep `if (m_events && m_events->canMoveCurrentRow(delta))`;
  the win is one definition, not unconditional dispatch. Double destination
  evaluation (predicate, then `moveCurrentRow`'s internal recompute with
  `why`) is acceptable.

Gate (1) is untouched: no QAction is ever added to a widget through these
remedies; window-delivered vs EditorRouted/manually-delivered delivery stays
exactly as-is.

Route: routes/seats recorded in plan.md; SDD-track. Seat: `qt-cpp-reviewer`.

## 2. Exact write set

- `src/ui/songview/quick/quickmenumodel.h`
- `src/ui/songview/quick/quickmenumodel.cpp`
- `src/ui/songview/quick/quickmenuhost.cpp`
- `src/ui/songview/quick/eventlistcontroller.h`
- `src/ui/songview/quick/eventlistcontroller.cpp`

Five files exceeds the ordinary three-file cap; this is the explicit
mechanical/cohesive-remedy exception recorded in plan.md (all five edits are
one restructure moving Q-F2/F4/F5 across the host/model seam plus Q-F6's
header/cpp pair; splitting it would strand Q-F4's recursion removal behind
Q-F2's header move for no ownership reason).

## 3. Prerequisites

- [Task 19](task-19-brief.md) — the lifecycle behavior being restructured is
  already reviewed/accepted there.
- [Task R9](task-R9-brief.md) — fixture scaffold fixed so the restructure's
  checks are not polluted by the pasted construction sites.
- E-M3 option (b) decision recorded in [R9](task-R9-brief.md)'s
  Context (recorded — not a re-decision here).

## 4. Contract per remedy and spec-amendment declarations

The spec text amends are minimal and explicit — each changing line is named
below so a later reader can audit the delta.

### a. Q-F2 + folded Q-F3 (header move, named helper, contract doc)

- Move `QuickMenuItem::fromAction` definition to `quickmenumodel.cpp` next to
  `makeSeparator()`; declare `static` in the header. Extract
  `stripAccelerator(QStringView)` as a named free function in that `.cpp`.
- Spec lines amended: **spec.md → the Submenu observation lifetime row /
  `fromAction`-projection paragraph(s)** (the lines claiming "without changing
  its scope, shortcut, callback, or ownership"). Replace the snapshot/live
  hybrid narrative with the adjudicated contract sentence:
  `fromAction` snapshots presentation text/enabled/checked at open time,
  retains a guarded non-owning identity the host triggers, requires the
  QAction to outlive the open menu, and retires the level on `changed()`.
- Do not redesign the projection model; no behavior change is implied.

### b. Q-F4 (per-level observation)

- Collect only the level's own model rows in `pushLevel`; store connections in
  the existing `Level::actionConnections` for every level; delete
  `collectActionBackedRows` recursion, the bool+out-param shape, the root-only
  wiring in `quickmenuhost.cpp`, and the `actionBackedRoot` special case in
  `handleLevelReset`. Q-F7 and Q-F9 fold in free.
- Spec lines amended: **spec.md → Submenu observation lifetime row** — the
  "Observe the full represented item tree on the existing root Level" decision
  line becomes "observe each open level on its own existing Level;
  detach each level's connections at its teardown; retirement on
  `changed()` is level-scoped". The plan.md engineering-decision row for
  submenu observation lifetime is correspondingly amended (see plan.md
  patch in this batch).
- Spec-context/category deletion: none (Q-F4 does not touch categories).

### c. Q-F5 (trigger extraction, ordering comment)

- Extract `triggerActionBackedRow(QAction *action)`; guards are pre-close
  liveness, post-close liveness, and the post-trigger `host && action` guard
  on the emit; one-line comment naming why `close()` precedes `trigger()`
  (reentrancy: the handler may open a new session). Delete only the provably
  dead `source` snapshot after the guard.

### d. Q-F6 (shared move predicate, `isEditing` guard kept)

- Move `canMoveCurrentRow` body out of `eventlistcontroller.h` into
  `eventlistcontroller.cpp`; make `editCommandAvailable`/`rebuildRowMenu`
  enabled flags consume the same predicate. **Rejected: unconditional
  `m_events->moveCurrentRow(delta)`** — keep the `isEditing()` guard as
  recorded above.

## 5. Implementation steps

1. Q-F2/a first (header hygiene + contract doc) — it is a prerequisite in
   spirit: once the model builds with the helper extracted, Q-F4's recursion
   removal touches only the host and cannot regress the header change.
2. Q-F4b (per-level observation, deleting `collectActionBackedRows` /
   `actionBackedRoot` / root-only wiring).
3. Q-F5c (trigger extraction + ordering comment).
4. Q-F6d (move `canMoveCurrentRow` to `.cpp`; single predicate across
   `editCommandAvailable` + `rebuildRowMenu`).
5. Spec.md text amendments per section 4b/4a lines — no prose beyond the named
   lines.

## 6. Acceptance predicate

For the experienced reviewer (execution phase): behavior-preserving — a
toggled-while-open deep level retires only its level, not the whole root menu;
`triggerActionBackedRow` exists with the reentrancy comment and the
post-trigger guard intact; `canMoveCurrentRow` is defined once (header has no
body); `fromAction` is absent from `quickmenumodel.h`'s definitions; the
observation-lifetime and projection lines of spec.md match section 4
verbatim.
Checks: existing quick-menu/model/event-view named checks are unchanged
(behavior is preserved; no new check is warranted by a plausible regression
target here — the retirement-scope, observation-lifetime edits are covered by
the existing checks per Q-F4's clearance). Named checks at execution:
`deno task verify --filter selectionkey --filter mainwindow-routing --verbose`
(quick-menu surface is exercised through these; the controller batches).

Also verify the documentation amendment exists in spec.md against Q-F3's
rejection fold — one contract sentence, no prose.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Global constraint 4's
three-file cap is exceeded per the recorded exception in Section 2; no other
exception is implied. Do not redesign `QuickMenuItem`'s snapshot semantics
(Q-F2's invariant half is downgraded to doc — Q-F3 is REJECTED as a code
change). Do not touch `src/ui/songview/editactions*` (E-slice is R5–R8's
write set); do not touch keymap (R1–R4); no QAction widget-association is
introduced in any of these steps (gate 1).
