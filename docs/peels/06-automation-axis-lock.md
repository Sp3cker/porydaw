# Peel 06 — Shift axis-lock on automation point drags

Read `docs/peels/GROUND-RULES.md` first. Small peel, same size class as Pencil
Mode. Target: main's `AutomationArea` `Gesture::Point` path in `src/ui/songview.cpp`.
Source: branch `automationgesture.cpp:128-161` (drag update), `:191-214`
(`resolveAxisLock`/`applyAxisLock` — free functions, portable nearly verbatim);
harness `src/rollcheckautomation.cpp:1295-1392`.

## The feature

While dragging an existing point (main's Gesture::Point), holding **Shift** locks
the drag to one axis, chosen by the dominant direction of initial travel:

- After travel exceeds the activation distance, `|dx| >= |dy|` → **Time lock**
  (value frozen at the point's original value, tick follows the cursor), else
  **Value lock** (tick frozen at the original tick, value follows).
- The lock is sticky once resolved (wobbling past 45° later doesn't flip it);
  releasing Shift returns to a free drag; re-pressing re-resolves from current
  travel.
- Cursor feedback: `Qt::SizeHorCursor` for Time lock, `Qt::SizeVerCursor` for
  Value lock, restored on release (branch `automationarea.cpp:345-355`). Restore
  to the pencil cursor when pencil mode is on (use the existing `modeCursor()`
  helper) — never bake an arrow.

## Interaction with existing behavior — decide and document

- On main, Shift at PRESS time starts the Line-ramp gesture (checked before the
  point grab). Keep that: Shift+press on empty space or even on a point = ramp
  (main's documented "a ramp can start exactly on an existing point"). The axis
  lock therefore engages only when Shift is pressed AFTER a point drag has begun,
  OR you adopt the branch's rule (Shift+press on a point's dot = locked drag,
  ramp only off-dot). The branch's rule is more useful (a ramp rarely needs to
  start exactly on a dot; a constrained nudge of a dot is common) but it changes
  existing behavior — implement the branch rule, state it in SPEC.md and the
  summary so the user can veto.
- Pencil mode's stroke Shift-lock (already on main) is a different code path
  (Gesture::Sweep) — don't disturb it; extend the rollcheck pencil section's
  negative assertions if the two could interfere.

## Tests

- New rollcheck probes: drag a point right with Shift, wobble y → committed point
  keeps its exact value, tick moved (Time lock); drag down with Shift → tick
  frozen, value moved (Value lock); lock stickiness (cross 45° mid-drag → still
  locked to first axis); release Shift mid-drag → free; cursor shape asserts;
  Shift+press off-dot still commits a ramp (regression guard for main's Line).
- Adapt branch harness :1295-1392. Negative-test each probe (e.g. skip
  applyAxisLock → value-frozen probe fails). SF 1/1.5/2; ASAN sweep + ctest;
  SPEC.md + CHANGELOG.
