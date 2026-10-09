# Note grid adaptation — spec

Status: agreed behavior for implementation planning. Touches the roll grid geometry
(`PorydawDocument` view) and the piano-roll gesture layer (`PorydawApp` roll). Self-contained:
every requirement is expressed against existing Porydaw symbols only.

## 1. Goal

When the editing lattice changes while a gesture is held — the feel flips straight ↔ triplet,
the division narrows or widens, or the auto stride changes — the held preview re-anchors onto
the new lattice so the grabbed note always sits on a snap boundary. Committed notes never
move because the lattice changed: the grid is an entry and preview constraint, not a document
transform.

Headline scenario: hold a note drag, press `Ctrl+3` (triplet). The dragged note's preview
jumps to the nearest triplet boundary; the rest of the selection keeps its relative spacing;
nothing outside the gesture changes; releasing commits one undo step as usual.

## 2. Vocabulary

- **Lattice** — the set of snap boundaries in force: bar-anchored for musical selections
  (restarts each bar so bar lines always snap), absolute for clock; see
  `RollGrid.snapLattice` / `snapTicksAt`.
- **Feel** — `GridFeel`, `.straight` or `.triplet`; scales every musical spacing
  (`musicalTicks`) and swaps the adaptive ladder (`straightLadder` / `tripletLadder`).
- **Snap stride** — boundary spacing at a tick: fixed for `.musical`/`.clock`, zoom-derived
  for `.auto` (`adaptiveTicks`).
- **Held gesture** — an active `GridGesture` of `.draw`, `.move`, or `.resize`; these own a
  `latticePointer`. `.pendingDraw`, `.velocity`, `.pendingMenu`, `.band`, `.pan` have no
  lattice participation.
- **Grabbed note** — the note hit at press (the gesture's subject); for `.move` the note whose
  start anchors the re-snap, for `.resize` the note whose dragged edge anchors it.
- **Anchor bias** — a per-gesture tick offset, zero for the whole gesture unless a lattice
  change occurs, that shifts the `.move` projection onto the lattice.

## 3. Current facts

- `RollGrid` exposes `snapTickDown` / `snapTickUp` / `snapTick` (nearest of floor/ceil,
  ties to the lower boundary for bar-anchored lattices, to the upper for fine/clock),
  all clamped to `0...TimeDefaults.maxTick` and to the owning bar for musical lattices.
- `GridGesture.updated(x:y:metrics:grid:camera:scale:)` re-derives every snap quantity from
  the passed `grid`:
  - `.draw` recomputes its anchor from the raw `pressTick` each update — a lattice change
    already re-anchors the draw.
  - `.move` computes `dTick = round((pointerTick − pressTick) / stride) · stride` — the
    pointer *displacement* is quantized; the grabbed note's own position is never snapped.
    With the pointer unmoved, any lattice change leaves `dTick == 0`: the preview does not
    adapt.
  - `.resize` snaps the dragged edge to `snapTick(desired)` but gates it against the original
    grip (`abs(desired − gripTick) < abs(desired − snapped) → delta 0`): the edge holds while
    the original edge is nearer the pointer than any boundary. After a feel flip this gate
    keeps the old-lattice edge in place.
- `PianoGrid.gridLatticeDidChange()` (feel flip, narrow/widen, selection change) already runs
  `resnapHeldGesture()` → `updated(...)` at the held pointer, then refreshes the roll and
  lattice observers.
- `toggleFeel()` remaps a `.musical` selection to the nearest spacing in the other feel's
  ladder (toward finer when straight → triplet) and canonically demotes to `.clock` when no
  musical spacing exists; `selections` never offers a zero spacing.

## 4. Changes

### 4.1 Move: anchor bias on lattice change

- Extend `GridGesture.Move` with the grabbed note's original start tick (`grabbedStart`,
  captured at gesture start from the hit note) and an `anchorBias: Int` defaulting to `0`.
- `updated(...)` keeps its steady-state math unchanged and applies
  `dTick = quantizedDelta + anchorBias`. With `anchorBias == 0` (no lattice change yet)
  behavior is identical to today: offset-preserving drags, selection keeps relative spacing.
- `resnapHeldGesture()` on a `.move` recomputes the bias:
  `anchorBias = snapTick(grabbedStart + dTick) − (grabbedStart + dTick)` using the *new*
  lattice, then re-runs `updated(...)` at the held pointer. The grabbed note's projected
  start lands exactly on a boundary; every other selected note shifts by the same bias and
  keeps its offset (a straight-lattice chord dragged under a triplet grid stays internally
  coherent — only the grabbed note is grid-aligned).
- The bias is recomputed only when the lattice changes, not per pointer move: once set, the
  quantized delta keeps the note glued to the lattice (all further deltas are stride
  multiples). A second lattice change re-derives the bias from the then-current projection.
- Bias never un-clamps: the re-snapped target still honors `0...maxTick` and bar limits via
  `snapTick`.

### 4.2 Resize: one-shot re-anchor past the grip gate

- On a lattice change during `.resize`, `resnapHeldGesture()` computes the preview edge as
  `snapTick(desired)` directly — the grip-stickiness gate is bypassed for that single
  re-anchor, so the preview edge visibly jumps to the new lattice even with the pointer
  unmoved.
- Subsequent pointer moves re-apply today's sticky gate unchanged (`gripTick` stays the
  original edge; the edge releases only when a boundary is nearer the pointer than the
  original edge). The gesture remains one gesture: commit still records a single resize with
  its usual merge behavior.

### 4.3 Draw: no change

- `.draw` already re-anchors from the raw `pressTick` on every update (its anchor *is* a
  snap). This stays the reference behavior: raw press position retained, lattice applied at
  projection time.

### 4.4 Lattice-change path

- `gridLatticeDidChange()` ordering stays: re-anchor the held gesture first, then
  `refreshFromSession()` and `onGridLatticeChanged?()`, so observers see the adapted preview
  in the same update. No new notification kinds; the existing republish of
  `snapTicks` / `visibleGridTicks` covers the ruler and status readouts.
- Applies to every lattice-change trigger — feel flip, narrow, widen, division menu pick,
  and zoom-driven auto-stride changes that cross a ladder rung.

## 5. Invariants and edge cases

- Committed notes' ticks change only through recorded edits. A lattice change with no held
  gesture mutates no document state and records no history step.
- `anchorBias` and the bypassed grip gate exist only inside the gesture; nothing persists to
  the document or session.
- Flip during `.pendingDraw`: no lattice participation; when the drag later crosses the draw
  threshold, the anchor is derived from the *new* lattice (`snapTickDown(pressTick)` at
  crossing, as today).
- Flip during `.velocity`, `.band`, `.pan`, `.pendingMenu`: no-op for this spec
  (`latticePointer == nil`).
- Negative or over-range projections clamp through the existing `floor`/`ceil` bounds; the
  grabbed note re-snaps to the nearest in-range boundary.
- Feel flip with a `.musical` selection that has no spacing in the other feel still demotes
  to `.clock` (`toggleFeel` + `canonical`); the re-anchor then uses the absolute clock
  lattice.
- Multi-segment songs (time-signature changes): stride is derived at the grabbed position;
  dragging across a signature boundary keeps the gesture's stride, matching current
  behavior. Re-anchoring after a flip uses the lattice at the projected position
  (`snapLattice(at:)` picks the owning bar).
- `.auto` strides that change purely from zoom treat a rung crossing as a lattice change:
  held gestures re-anchor on zoom mid-drag exactly as on a menu flip.

## 6. Non-goals

- Moving or quantizing committed notes on grid changes (no document-side re-snap pass).
- Timed magnetism or pixel-threshold hysteresis: re-anchoring is geometric and instantaneous
  at lattice-change and pointer-update time; no timeouts, no preference thresholds.
- A gesture-time snap on/off modifier; grid keys already act mid-gesture here.
- Changing steady-state drag semantics — quantized-delta moves and the sticky resize gate
  are preserved verbatim outside lattice changes.
- Automation lane drawing, ruler markers, and the edit cursor: their snap behavior is
  unchanged by this spec (the cursor is not repositioned by lattice changes).
- Persisting or un-doing lattice state: feel/selection remain view state outside the undo
  history.

## 7. Verification

- Roll-lane check contracts (extend the existing grid-gesture checks): feel flip mid-move
  puts the grabbed note's projected start on a triplet boundary while selection offsets are
  preserved; flip mid-resize re-anchors the edge past the grip gate once, then the gate
  resumes; flip with pointer unmoved still adapts (bias ≠ 0 / edge ≠ original); no held
  gesture → flip mutates no notes and records no history entry; draw re-derives its anchor
  from the new lattice at threshold crossing; clamp behavior at `maxTick` and bar limits
  after re-anchor; zoom-driven rung crossing re-anchors like a menu flip.
- Commands: `deno task build:app`; `deno task checks --filter swiftcore` (roll lane);
  `deno task checks:qml-roll` (only if QML surface changes); `deno task format --check`.
- No proof-ledger rows: gesture-time view behavior with no retired native counterpart; no
  standalone ledger work.
