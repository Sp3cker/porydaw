# AutomationCanvas Refactor — Performance, Grokability, and CCN

**Date:** 2026-08-27
**Scope:** `src/ui/editordrawer/automationcanvas_paint.cpp` (`paintContent`, CCN 50), `src/ui/editordrawer/automationcanvas_input.cpp` (`mousePressEvent`, CCN 49), private declarations in `automationcanvas.h`, and a focused automation-gesture routing domain plus its registration/support changes.

---

## 1. Origin: src/ui cyclomatic complexity audit

Ran `lizard` (McCabe CCN) over `src/ui` — 1,945 member functions analyzed. Distribution:

| CCN band | count |
|---|---|
| <10 | 1,786 |
| 10–14 | 82 |
| 15–19 | 72 |
| 20–29 | 54 |
| 30+ | 20 |

Concentration by directory (sum of file aggregate CCN): `songview` 524, `editordrawer` 326, `editordrawer/velocityarea` 192, `theme` 152, `editordrawer/nodelane` 133.

### Top offenders (pre-refactor)

| Function | CCN | LOC | File |
|---|---|---|---|
| `VoicegroupBrowser::commitEdit` | 62 | 213 | `voicegroupbrowser.cpp` |
| `eventlist::EventTableModel::data` | 50 | 84 | `eventtablemodel.cpp` |
| `AutomationCanvas::paintContent` | 50 | 275 | `automationcanvas_paint.cpp` |
| `AutomationCanvas::mousePressEvent` | 49 | 170 | `automationcanvas_input.cpp` |
| `checkThemeWorkflow` | 42 | 282 | `theme/themecheck.cpp` (harness — deprioritized) |
| `VoiceChangeLane::paint` | 41 | 169 | `voicechangelane.cpp` |
| `VoicegroupBrowser::populateEditor` | 35 | 133 | `voicegroupbrowser.cpp` |
| `EventListView::showContextMenu` | 32 | 61 | `eventlistviewactions.cpp` |
| `songview::PianoRoll::drawNotes` | 31 | 107 | `pianoroll_paint.cpp` |
| `AutomationCanvas::showLaneMenuFor` | 31 | 120 | `automationcanvas_menu.cpp` |

---

## 2. Completed work: VelocityArea::paintContent (calibration case)

**File:** `src/ui/editordrawer/velocityarea/velocityarea_paint.cpp` — single function, 153 LOC, CCN 25.

**Original structure:** 4 near-identical note loops (unselected stems → selected stems → unselected ellipses → selected rings+ellipses), each guarded by `if (selected(note)) continue;` / `if (!selected(note)) continue;`; a PSG level-band `while (sectionTick < lastTick)` loop with nested `for (level)`; antialiasing OFF for stems, ON for nodes.

**Review verdict (thermo-nuclear):** CONDITIONAL GO. Rejected the proposed single-loop collapse as **unsound**: it would interleave layers (stem of note N painting over node of note N−1 on crowded ticks), break the selected ring-then-fill two-ellipse order, and force per-note antialiasing toggles. Mandated **2 unified loops** (stems pass, nodes pass) + PSG extraction.

**Landed change:**
- Extracted `VelocityArea::paintPsgLevelBands(QPainter&, int origin, int width, uint64_t firstTick, uint64_t lastTick)` — private, same TU.
- Collapsed 4 note loops → 2 selection-aware loops (stems: per-note pen; nodes: ring+fill for selected, dimmed fill for unselected).
- Antialiasing toggle boundary and per-pass pen/brush state preserved.
- Later: marked `paintPsgLevelBands` `const` on declaration + definition (reviewer nit; no source-level cost change).

**Results:** `paintContent` CCN 25 → 18, NLOC 153 → 118; file NLOC 170 → 155; diff 2 files, +47/−53.
- `deno task build:app` — ok
- `deno task verify --filter rollcheck --verbose` — ok
- `deno task verify` — **56/56 PASS**
- `git diff --check` — clean

**Performance assessment:** source-level paint costs were preserved: no additional note snapshot, note pass, antialiasing transition, or QPainter draw call. This calibration did not benchmark runtime and does not prove that later helper extractions will inline.

---

## 3. AutomationCanvas binding implementation contract

### 3.1 Optimization order and success definition

Make tradeoffs in this strict order:

1. **Runtime performance:** preserve algorithmic work, copies, allocations, paint operations, and hit-test counts; prove the paint refactor with a matched Release benchmark.
2. **Agent grokability:** keep paint ownership named and local; keep the complete mouse-routing precedence visible in `mousePressEvent`.
3. **Cyclomatic complexity:** reduce nesting and isolate cohesive decisions without creating thin wrappers, behavior flags, or metric-reset helpers.

The refactor succeeds only at the intersection of all three. A lower per-function CCN is not sufficient if it hides routing order or adds hot-path work.

### 3.2 Scope and non-goals

Production changes stay in:

- `src/ui/editordrawer/automationcanvas_paint.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- private declarations in `src/ui/editordrawer/automationcanvas.h`

Focused event-routing coverage must add `src/checks/automationgesturecheck/routing.cpp`, declare/register its domain in `domains.h` and `runner.cpp`, add only the minimal real-event dispatch support required in `rig.{h,cpp}`, and register the source in `CMakeLists.txt`. Do not redesign `NodeLane`, change `NodeLane::points()` ownership, redesign `BandGesture`, move caching out of `CCLanes`, introduce generic paint/input frameworks, or create new production compilation units. Keeping the production changes intra-file is a cohesion decision, not compliance with a line-count ceiling.

### 3.3 Current behavior map

#### `paintContent` (275 LOC, CCN 50)

- Fill background; return unless page, timeline, and page readiness are valid.
- Resolve projection, DPR, the half-open node-selection pair, and the `TickRange` used by reticles.
- Allocate `pointsBySlot` once and call each populated lane's `points()` once.
- Scan those snapshots once to derive `multipleSelectedNodes`, short-circuiting after the second selected point.
- Paint the voice lane, then the Add CC strip, then visit the node stack in reverse Z-order.
- Tempo and CC slots have different header, collapse, color, cache, and clipping behavior.
- Lane-body painting owns grid fallback, phantom resolution, `NodeLanePaint`, and the edit cursor.

#### `mousePressEvent` (170 LOC, CCN 49)

The precedence is load-bearing:

```text
hover invalidation and page guard
→ middle-button pan
→ pointer/tempo resolution
→ voice lane
→ atomic outside-selection clearing
→ tempo header
→ CC row resize
→ Add CC strip
→ lane-slot guard
→ gutter menu
→ body right-band
→ non-left rejection
→ pencil gesture
→ default node / phantom / sweep gesture
```

Do not reorder these stages.

### 3.4 Paint type ownership and dataflow

Use private nested implementation types:

```cpp
struct PaintFrame;
struct LanePaintItem;
using LanePointSnapshots = std::vector<std::vector<NodePoint>>;
```

Add a direct `#include <span>` to `automationcanvas.h`; the fixed declarations must not rely on a transitive include for `std::span`.

Forward-declare the structs and declare the member helpers in the private painting section of `automationcanvas.h`. Define `AutomationCanvas::PaintFrame` and `AutomationCanvas::LanePaintItem` only in `automationcanvas_paint.cpp`. This gives agents a navigable helper map without exposing paint fields or adding a dispatcher object.

`PaintFrame` is immutable after construction and contains only frame-wide state:

- `AutomationProjection projection` by value; never retain a reference to the temporary returned by `projection()`.
- `qreal devicePixelRatio`.
- `std::optional<std::pair<uint64_t, uint64_t>> selectedTickRange` for `NodeLanePaint`.
- `std::optional<TickRange> selectedRange` for selection reticles.
- selected and dimmed `QColor` values.
- ordered band endpoints.
- raw non-owning pointers to the active `NodeDragGesture`, `PhantomGesture`, `SweepGesture`, and `PencilGesture` alternatives.
- `bool pencilMode` and `bool multipleSelectedNodes`.
- non-owning references to the cached title font, caption font, and two-line text layout.

Keeping both selected-range forms is deliberate: calculate each once before the lane loop rather than converting or branching per slot.

`LanePaintItem` is constructed inside `paintLaneStack` for one iteration and contains only:

- `LaneHandle`.
- a reference to the current `NodeLaneSlot`.
- `std::span<const NodePoint>`.
- `selectedLane`, `selectedNodesLane`, and `bandLane`.
- the lane's reticle bounds.

The hot-path dataflow is fixed:

```text
snapshotLanePoints()
        ↓
preparePaintFrame(dpr, pointsBySlot)
        ↓
paint voice lane and Add CC strip
        ↓
paintLaneStack(frame, pointsBySlot)
```

`snapshotLanePoints()` allocates the outer vector once and invokes `NodeLane::points()` at most once for each populated slot. `preparePaintFrame()` receives a read-only view of that snapshot to derive `multipleSelectedNodes`. `paintLaneStack()` receives the same snapshot. No later helper may call `NodeLane::points()` or reconstruct a lane snapshot.

### 3.5 Paint helper ownership

Declare one cohesive private helper group:

The private declarations are fixed:

```cpp
LanePointSnapshots snapshotLanePoints() const;
PaintFrame preparePaintFrame(
    qreal devicePixelRatio,
    std::span<const std::vector<NodePoint>> pointsBySlot) const;
void paintLaneStack(QPainter &painter, const PaintFrame &frame,
                    const LanePointSnapshots &pointsBySlot);
void paintTempoSlot(QPainter &painter, const PaintFrame &frame,
                    const LanePaintItem &item);
void paintCcSlot(QPainter &painter, const PaintFrame &frame,
                 const LanePaintItem &item);
void paintLaneBody(QPainter &painter, const PaintFrame &frame,
                   const LanePaintItem &item, const QColor &color,
                   bool preparedPreviewCurve);
const QString &refreshCcSummaryText(CCLanes::RowTextCache &cache,
                                    std::span<const NodePoint> points,
                                    const NodeLane &lane);
```

Returning `LanePointSnapshots` relies only on return-value elision/container move; it must not copy an inner point vector after `NodeLane::points()` produces it.

| Helper | Owns | Must not own |
|---|---|---|
| `snapshotLanePoints` | the single per-frame lane-point snapshot | selection or painting |
| `preparePaintFrame` | immutable frame-wide projection, selection, gesture, palette, and typography state | per-slot rectangles or flags |
| `paintLaneStack` | reverse traversal, `bandPreviewContainsLane`, lane/node selection flags, reticle bounds, and total `NodeLaneSlot::visit` dispatch | tempo/CC-specific rendering |
| `paintTempoSlot` | tempo collapsed/expanded header, tempo body clip, tempo color, body delegation, and reticle | CC cache/layout |
| `paintCcSlot` | `RowTextCache`, identity color, two-line header, body delegation, and reticle | tempo collapse behavior |
| `paintLaneBody` | plot calculation, both self-balanced QPainter save/clip/restore regions, grid fallback, phantom/origin-phantom resolution, `NodeLanePaint`, and edit cursor | slot-header rendering |
| `refreshCcSummaryText` | in-place lazy CC summary-cache refresh | invalidation, layout, theme mutation, or value-returning cache copies |

Do not extract the two-line reticle call, the five-line Add CC strip, the phantom branch inside `paintLaneBody`, or a generic `paintAnySlot` template.

The CC cache helper contract is fixed:

```cpp
const QString &refreshCcSummaryText(CCLanes::RowTextCache &cache,
                                    std::span<const NodePoint> points,
                                    const NodeLane &lane);
```

It is a non-const `AutomationCanvas` member so unqualified `tr(...)` preserves the current inherited `QWidget::tr` resolution. `AutomationCanvas` has no `Q_OBJECT`, so do not claim or introduce a new `AutomationCanvas` translation context during this refactor. The helper updates `cache` in place, returns `cache.secondary`, and never invalidates content or changes layout/theme state.

### 3.6 Paint performance invariants

The implementation must preserve:

- one outer `pointsBySlot` allocation and at most one `points()` result per populated lane;
- the same number of full lane and point passes;
- the selected-node scan's short-circuit after the second match;
- voice lane → Add CC strip → reverse node-stack paint order;
- tempo/CC `visit()` dispatch rather than a repeated kind test;
- every current QPainter `save()`/`restore()`, clip boundary, grid call, draw call, and antialiasing boundary;
- tempo's collapsed early returns before the body save;
- spans/references for point data, fonts, layout, lanes, slots, and cached strings.

Add no `std::function`, runtime polymorphism, heap dispatcher, extra `QString`/`QFont`/container copy, extra lane/point traversal, or forced-inline attribute.

### 3.7 Mouse input extraction boundary

`mousePressEvent` remains the visible orchestration method. An agent opening it must see the full precedence from §3.3, including which branches explicitly accept and which terminate with a bare return.

Extract only these cohesive leaf operations:

The private input declarations are fixed:

```cpp
void clearTimeSelectionIfOutsidePress(const QMouseEvent &event,
                                      const AutomationProjection &projection,
                                      LaneHandle lane,
                                      const NodeLaneSlot *slot);
void beginPencilPress(const QMouseEvent &event, LaneHandle handle,
                      const NodeLane &lane, const QRect &body,
                      const AutomationProjection &projection);
void beginDragOrSweep(const QMouseEvent &event, LaneHandle handle,
                      const AutomationProjection &projection);
```

`beginDragOrSweep` deliberately does not receive a lane or body: the preserved default path uses `mappedForLane`, `nodeDragGestureAt`, and `phantomDragGestureAt`, which already resolve the required lane state from `LaneHandle`. It must not re-resolve `NodeLaneSlot` merely because the code moved.

| Helper | Contract |
|---|---|
| `clearTimeSelectionIfOutsidePress` | Atomically performs the current selected-node hit, lane-selection hit test, and conditional time-selection clear. It performs no duplicate `nodePointHit` and never clears `m_band`. |
| `beginPencilPress` | Owns the complete pencil-mode terminal path, including cell-hit node drag, stroke creation, preview-label sync, and invalidation. It returns `void` and does not accept the event. |
| `beginDragOrSweep` | Owns mapping and the complete node/phantom/sweep terminal path, including gesture activation, preview-label sync, and invalidation. It returns `void` and does not accept the event. |

Keep middle-button pan, voice-lane dispatch, both tempo-header branches, resize initialization, Add CC menu routing, the lane-slot guard, gutter-menu routing, and the complete body-right band branch inline. In particular, keep the body `nodePointHit`/`highlightHoveredPoint` immediately adjacent to its band press. Do not add a three-line `beginBandGesture`, complete band-handler wrappers, a tri-state handled result, a broad `PressContext`, or behavior-selecting flags.

Event acceptance remains explicit in `mousePressEvent`:

- Middle-button pan, voice lane, and tempo header call `event->accept()` and return.
- Resize, Add CC menu, gutter menu, body band, pencil, and default gesture paths retain bare terminal returns.
- Helpers never call `accept()` and never decide whether a later routing stage runs.

### 3.8 Complexity acceptance

Use decision complexity, not raw summed CCN:

```text
aggregate decision complexity = Σ(function CCN - 1)
```

Acceptance:

- `paintContent` CCN ≤ 14.
- Every new paint helper CCN ≤ 9.
- Every extracted input leaf helper CCN ≤ 6.
- Aggregate decision complexity for `paintContent` plus its extracted helpers is ≤ 49, and for `mousePressEvent` plus its extracted helpers is ≤ 48.
- Maximum nesting decreases in both roots.
- Report the final `mousePressEvent` CCN. The former ≤13 estimate is best-effort, not binding; do not hide routing precedence to reach it.
- No helper exists only to reset CCN; no branch is hidden in a behavior flag or dense compound expression.

### 3.9 Focused behavioral verification

Run:

```bash
deno task format src/ui/editordrawer/automationcanvas.h \
  src/ui/editordrawer/automationcanvas_paint.cpp \
  src/ui/editordrawer/automationcanvas_input.cpp
deno task build:app
# Filters are substring matches: this runs automation, automation-gestures,
# and automation-popup-menus and must report each result.
deno task verify --filter automation --verbose
# This runs rollcheck and rollwindowingcheck and must report both.
deno task verify --filter rollcheck --verbose
deno task verify
/tmp/porydaw-lizard/bin/lizard -l cpp \
  src/ui/editordrawer/automationcanvas_paint.cpp \
  src/ui/editordrawer/automationcanvas_input.cpp
```

Record the lizard row for each touched root/new helper, calculate the two `Σ(CCN - 1)` totals from those rows, and record maximum nesting. Do not infer the aggregate gates from root CCN alone.

**Tool prerequisite recorded at handoff:** `lizard`, `uvx`, and `pipx` were not on this workstation's `PATH`. Before capturing the baseline, create an isolated temporary environment with `python3 -m venv /tmp/porydaw-lizard`, install the `lizard` package into that environment, record `/tmp/porydaw-lizard/bin/lizard --version`, and use that exact executable for baseline and candidate. Do not add a Python dependency or generated environment to the repository.

Add or extend focused automation-gesture routing coverage so representative events are initialized as not accepted and dispatched through the real widget:

- middle-button pan, voice-lane press, and tempo-header press finish accepted;
- resize, body-right band, pencil, and default body press preserve the non-explicitly-accepted terminal contract;
- every terminal route changes only its intended state and cannot fall through to a later route.

Keep the complete acceptance/fallthrough matrix in the dedicated `src/checks/automationgesturecheck/routing.cpp` domain; do not scatter it across lifecycle, mapping, or popup-menu checks.

### 3.10 Matched Release paint benchmark

Performance is priority one, so benchmark before and after even when source operation counts appear unchanged. Do not use assembly identity as a gate.

The implementation agent must read and follow the harness-managed `skill://benchmark-porydaw-playback` for matched builds, visibility/exposure proof, interleaved trials, and clean/instrumented result separation. The complete minimum protocol is also recorded below so the handoff does not depend on repository-local skill files. Adapt the methodology to a deterministic AutomationCanvas render workload rather than assuming ordinary playback exercises this surface.

1. Freeze the exact pre-refactor source state, then build baseline and candidate in separate matched worktrees, each using its own tool-managed `build/` directory and `deno task build:checks --release`. The tooling does not support alternate build-directory names within one worktree. Match compiler, fixture, submodule revision, window geometry, DPR, automation zoom, and scroll.
2. Exercise an exposed AutomationCanvas containing expanded tempo plus multiple dense CC lanes. Use a deterministic synchronous render loop over the same fixed viewport; do not time manual interaction.
3. Verify the window is visible and exposed. Warm the paint/font caches before measurement.
4. Run at least five interleaved baseline/candidate trials. Record raw per-trial paint/render duration and compare medians.
5. Treat a repeatable candidate regression greater than 5% as a failure requiring attribution. Re-run suspicious trials before diagnosing noise.
6. If regression is confirmed, use profiler/compiler diagnostics to locate it; do not prescribe `always_inline`, pass `PaintFrame` by value, or change code from instruction-count guesses.
7. Remove temporary benchmark hooks and instrumentation before final verification.

### 3.11 Implementation order

1. Capture the baseline complexity numbers, focused check results, and matched Release benchmark.
2. Add nested type forward declarations and the exact private helper declarations.
3. Extract the paint snapshot/frame/stack helpers while preserving operation counts and paint order.
4. Extract the three input leaf operations without changing the visible routing cascade or acceptance.
5. Add focused route-contract coverage.
6. Format, build, run focused checks, run the full suite, re-run complexity metrics, and run the matched candidate benchmark.
7. Review the landed diff against every invariant and remove all temporary benchmark code.

### 3.12 Execution ownership

Use these waves so the production and check changes remain independently owned:

1. A `task` subagent captures the immutable pre-refactor baseline: source snapshot identity, complexity metrics, focused check results, and matched Release benchmark inputs/results.
2. Dispatch two `task` subagents in parallel after the baseline:
   - one owns `automationcanvas.h`, `automationcanvas_paint.cpp`, and `automationcanvas_input.cpp`;
   - one owns only `src/checks/automationgesturecheck/routing.cpp`, its minimal `domains.h`/`runner.cpp`/`rig.{h,cpp}` support, and its `CMakeLists.txt` registration.
3. The integration owner formats once, builds once, runs the focused checks and full suite once, measures complexity, and runs the matched candidate benchmark.
4. Dispatch `qt-cpp-reviewer` and `cpp-smell-reviewer` in parallel on the integrated diff. They verify Qt event/QPainter correctness and the performance–grokability–CCN structure respectively; they do not edit or run validation.
5. The production owner applies accepted findings, removes temporary benchmark code, and the integration owner repeats the final focused/full verification and candidate benchmark when a finding changes a measured path.

The baseline snapshot must represent the exact pre-refactor tracked source state, including any relevant existing local source changes; the candidate may differ only by this contract's implementation and focused checks.

---

## 4. Final handoff acceptance checklist

- [ ] Scope remains limited to §3.2.
- [ ] `PaintFrame` and `LanePaintItem` are nested forward declarations in the header and definitions in the paint `.cpp`.
- [ ] `automationcanvas.h` directly includes `<span>`.
- [ ] Each lane's points are snapshotted at most once per paint.
- [ ] Frame and per-lane state are separated exactly as specified.
- [ ] Tempo and CC painters remain separate.
- [ ] QPainter state, clipping, draw order, and early returns are preserved.
- [ ] The entire mouse-routing precedence remains visible in `mousePressEvent`.
- [ ] Event acceptance remains explicit at the original branches.
- [ ] Body-right press retains node hover/highlight synchronization.
- [ ] Outside-selection clearing remains atomic and does not clear `m_band`.
- [ ] Complexity gates in §3.8 pass.
- [ ] The dedicated automation-gesture routing domain covers the acceptance/fallthrough matrix and is registered in the runner and build.
- [ ] Focused automation, gesture, popup-menu, and full verification pass.
- [ ] Matched Release benchmark shows no repeatable regression greater than 5%.
- [ ] No temporary benchmark hooks, compatibility shims, obsolete lambdas, or unused declarations remain.

---

## 5. Decision log

- **Optimization order fixed:** runtime performance → agent grokability → CCN reduction.
- **Nested member-helper design selected:** header exposes the private helper map; paint-only struct definitions remain in `automationcanvas_paint.cpp`.
- **Point snapshot dataflow fixed:** snapshot once → prepare frame from snapshot → paint from the same snapshot.
- **Dual range representation retained:** compute both node-paint and reticle forms once outside the lane loop.
- **Tempo and CC painters remain separate:** their header, cache, collapse, and color behavior genuinely diverge.
- **No band-handler extraction:** keep both three-line band starts inline; keep body hover/highlight adjacent and keep acceptance in the routing skeleton.
- **No tri-state event dispatcher:** explicit branch acceptance and return behavior is more grokkable.
- **Atomic selection clearing retained:** no split query/mutation helper and no duplicate point hit.
- **Decision complexity selected:** use `Σ(CCN - 1)` so extraction is not penalized by each helper's base CCN.
- **Runtime benchmark required:** source invariants are mandatory, and a deterministic matched Release comparison is the performance gate.
- **No new production compilation units:** the selected seams remain cohesive with AutomationCanvas paint and input ownership.
- **Routing coverage location fixed:** use a dedicated automation-gesture `routing.cpp` domain with minimal runner, rig, and CMake registration.
- **No open design choices remain:** implementation may change a contract only when current source or measured evidence disproves it, and must record that evidence in this plan before proceeding.
