# AutomationCanvas CCN Refactor — Plan & Audit Record

**Date:** 2026-08-27
**Scope:** `src/ui/editordrawer/automationcanvas_paint.cpp` (`paintContent`, CCN 50 → ~12) and `src/ui/editordrawer/automationcanvas_input.cpp` (`mousePressEvent`, CCN 49 → ~11), plus private declarations in `automationcanvas.h`.

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
- Later: marked `paintPsgLevelBands` `const` on declaration + definition (reviewer nit; zero performance impact — `const` only changes `this` pointer type, LTO inlines either way).

**Results:** `paintContent` CCN 25 → 18, NLOC 153 → 118; file NLOC 170 → 155; diff 2 files, +47/−53.
- `deno task build:app` — ok
- `deno task verify --filter rollcheck --verbose` — ok
- `deno task verify` — **56/56 PASS**
- `git diff --check` — clean

**Performance claim:** no regression. `CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON` (LTO) inlines private same-TU helpers in Release; the actual paint cost is `primaryTrackNotes()` (vector copy by value), `displayedVelocity()` → `previewVelocity()` per note, and QPainter draw calls — none affected by extraction.

---

## 3. AutomationCanvas plan (under review)

### paintContent — confirmed structure (275 LOC, CCN 50)

- setup: fill bg, early return if `!m_page || !ready() || !timeline()` (75–77), projection/dpr (78–79)
- `selectedTickRange` lambda: `m_band.active ? TickRange::orderedNonEmpty → pair` : `m_laneSelection.activeTickRange()` (80–88)
- `selectedRange` lambda (89–93), `laneSelected`/`nodeSelected` lambdas (94–99)
- `pointsBySlot` copy loop (100–105)
- `selectedCount` scan with `bandPreviewContainsLane` + tick-range filter + `multipleSelectedNodes` short-circuit (106–127)
- fonts + `m_voiceLane.paint(...)` (128–133), `selectedColor`/`dimmedColor` (133–134)
- gesture variant extraction via `std::get_if<NodeDrag|Phantom|Sweep|Pencil>` (135–144), `bandFirst`/`bandLast` (145–146)
- `paintLaneBody` lambda ~52 lines (147–199): plot calc, `save()`/`setClipRect(IntersectClip)`, `paintGrid`/fallback, phantom resolution (`originPhantom` → `OriginPhantomPaint`), `nodelane::paintNodeLane` with 14-field `NodeLanePaint`, second `save()`/clip for edit cursor
- `paintLaneReticle` lambda 2 lines (200–202)
- `paintTempoSlot` lambda ~56 lines (203–259): expanded flag, `if(document)` band = `slot.body` vs `headerRect`, clip/fill/separator, `!expanded` reticle, strip/arrow/textBounds/summaryBounds, `nodelane::paintLaneHeader`, `!expanded` early returns, save/clip delegate to `paintLaneBody` (tempo curve, `preparedPreview=true`), restore, reticle
- `paintCcSlot` lambda ~56 lines (260–316): `if (!slot.text) return`, `RowTextCache &rowText`, bounds/textBounds/textBoxes, `trackIdentityColor`, save/clip, **secondaryText cache-mutation block** (`points.empty()` ? `Points` : `EmptyControl`, with `pointCount`/`minimum`/`maximum` checks + `tr("%1 points · %2..%3")`), `paintLaneHeader`, `paintLaneBody` (`preparedPreview=false`), restore, reticle
- "+ Add CC lane" strip paint (317–325)
- reverse `for (index = m_nodeStack.size(); index-- > 0;)` (326–346) with `slot.visit(tempo/cc)` dispatching to the two lambdas

### mousePressEvent — confirmed structure (170 LOC, CCN 49)

Cascade: hover invalidation + `!page` guard → MiddleButton pan start (accept+return) → `pointerLaneAt`/`inTempoHeader`/`inTempo` → voice lane contains → `voiceLane.mousePress` (accept+return) → Left/Right selection hit-test (`selectedNode`/`insideSelection`, clear time selection if outside) → `inTempoHeader`: Left toggle expand / Right band press (accept+return) → `ccRowBoundaryAt` resize start (bare return) → add-lane strip → `showAddLaneMenu` → resolve slot guard → label-gutter Right → `showLaneMenuFor` → body Right: band press + `nodePointHit → highlightHoveredPoint` → non-Left return → pencil mode: `nodeDragGestureAt` cell-hit → node drag, else `AutomationPencilGesture::start` → pencil → default: node/phantom/Sweep(Shift→Ramp) drag.

### Review2 verdict: CONDITIONAL GO — 10 mandatory modifications

1. **No flat-arg member functions.** Introduce intra-file `struct PaintFrame` bundling `proj, dpr, selectedTickRange/selectedRange, selectedColor/dimmedColor, bandFirst/Last, multipleSelectedNodes, nodeDrag/phantom/sweep/pencil, m_pencilMode, titleFont/captionFont/textLayout`. Helpers take `(QPainter&, const PaintFrame&, ...)`.
2. **Keep `paintTempoSlot` and `paintCcSlot` SEPARATE.** Reject `paintAnySlot<T>` collapse — divergent header payloads (tempo: collapsed `headerRect` vs expanded body, arrow/strip, `%n point(s)`; CC: `RowTextCache`, `trackIdentityColor`, `m_labelGutter`). Unified template re-introduces a switch in the hot loop.
3. **`updateCcSummaryText` must be non-const mutating** `(CCLanes::RowTextCache&, span, const NodeLane&) → QString`, preserve `AutomationCanvas::tr` context, never call `invalidateContent`/layout/theme. **Also fixes a latent bug:** `rowText.minimum/maximum` uninitialized when `summaryKind==None` but `points` non-empty.
4. **`paintLaneStack` owns the reverse loop AND per-iteration recomputation** (`bandPreviewContainsLane`, `laneSelected/nodeSelected`, `reticleBounds` at 332–336). Keep `slot.visit(...)` total dispatch; don't replace with `if (isTempo())`.
5. **QPainter self-balance contract:** each helper pairs its own `save()`/`restore()`. `paintLaneBody` saves twice; tempo's `!expanded` early returns (246–250) occur *before* any save — must stay before save.
6. **No unified `startBandGesture`.** Tempo-header-right and body-right are **not identical**: body-right adds `nodePointHit → highlightHoveredPoint` (load-bearing hover label sync) and uses `handle` after the `!laneSlot` guard; tempo uses `pointerLane` before it. Two helpers (`handleTempoHeaderRightBand` / `handleBodyRightBand`) or one with `bool highlightIfHit` + internal validity check.
7. **Event-accept contract:** helpers return `HandledWithAccept / HandledWithoutAccept / NotHandled`; skeleton calls `event->accept()` exactly once. Prevents fallthrough (e.g., tempo expand → spurious resize).
8. **Guard boundary invariant:** `!laneSlot return` (148–149) stays before lane/body/gutter/right-click branches.
9. **`clearTimeSelectionIfOutside` atomic:** capture the whole hit-test (96–115) — don't split into a separate hitTest helper (duplicates `nodePointHit` cost). Must not clear `m_band`.
10. **Intra-file only, no new compilation units.** Header gains ~20–30L private decls; paint cpp 346L → ~380L, input cpp 509L → ~560L — both under the 600L cohesion signal.

### Extractions vetoed by reviewer

- `paintLaneReticle` (2-line wrapper — thin-wrapper violation; keep inline).
- `paintTempoSlot + paintCcSlot` collapse (see #2).
- `"+ Add CC lane"` strip (5-line `drawText`).
- `startPan` as mockable helper (QScrollBar coupling, not a seam).
- Merging add-lane + gutter menu handlers (guard scattering → null deref).
- Splitting the phantom/originPhantom branch inside `paintLaneBody` (fragments save/clip contract).

### Expected CCN delta

- `paintContent`: **50 → 11–14** (−36 to −39); max helper CCN ≤ 9.
- `mousePressEvent`: **49 → 10–13** (−36 to −39); max helper CCN 5–6.

### Top risks

- QPainter clip-stack leakage on early return.
- Parameter transposition bugs without `PaintFrame`.
- Accept-swallowing helpers causing fallthrough.
- `RowTextCache` mutation during paint (const-correctness temptation; `size_t`/`int` mixing in `tr` arg).
- Band-press dedup breaking hover feedback.
- Caching `selectedTickRange` before `m_band.press` desyncing paint vs input.

---

## 4. Assembly-equivalence proof plan

**Claim to prove:** extraction produces the same or better assembly (LTO inlines private helpers; no new prologue/spill cost).

**Step 0 — calibrate on the landed velocityarea refactor** (already in repo, before/after pair exists):
- Build Release with LTO.
- `llvm-nm build/porydaw.app/Contents/MacOS/porydaw | grep paintPsgLevelBands` → expect **no external call sites** if inlined.
- If inlined here, the pipeline is proven for automationcanvas.

**Step 1 — build both, diff objects:**
```bash
# baseline (pre-refactor) vs refactored, both CMAKE_BUILD_TYPE=Release, IPO on
llvm-size -t baseline.o refactored.o
llvm-objdump -d --no-show-raw-insn baseline.o > b.txt
llvm-objdump -d --no-show-raw-insn refactored.o > r.txt
```

**Step 2 — confirm inlining in the final binary:**
```bash
llvm-nm build/porydaw.app/Contents/MacOS/porydaw | grep -iE 'paintLaneBody|paintTempoSlot|paintCcSlot|paintLaneStack|startPencilOrNodeDrag|startDefaultDragOrSweep|handleBodyRightBand'
llvm-objdump -d build/porydaw.app/Contents/MacOS/porydaw | grep -c 'bl.*paintLaneBody'  # expect 0
```

**Step 3 — per-function accounting** (find ranges via `llvm-nm --print-size`, then `objdump -d -start-address -stop-address`):
- instruction count, `bl` count (→ 0 if inlined), branch count
- prologue stack frame size (`sub sp, sp, #...`) — larger frame = register pressure from `PaintFrame`
- `grep -c 'ldr.*sp'` — stack loads in `paintContent`/`mousePressEvent` (spill check)

**Step 4 — runtime proof:** `xctrace` CPU Profiler on a dense song, same scroll/zoom/interaction; compare self time in `paintContent`/`mousePressEvent` and total frame time.

**Fallback if worse:** `[[gnu::always_inline]]` on hot helpers, or pass `PaintFrame` by value (if SROA fails). The diff decides; no guessing.

---

## 5. Verification bar (before yielding)

- `deno task build:app` — ok
- `deno task verify --filter rollcheck --verbose` — ok
- `deno task verify` — 56/56 (current baseline)
- `git diff --check` — clean
- lizard re-run: `paintContent` ≤ 14, `mousePressEvent` ≤ 13
- Review2 re-inspection of landed diff against all 10 conditions
- Assembly proof artifacts (nm + objdump counts + xctrace) — §4

---

## 6. Decision log

- **velocityarea single-loop collapse rejected** — Z-order/AA state leakage; mandated 2-loop + PSG extraction. Landed and verified.
- **`paintPsgLevelBands const` applied** — correctness/interface nit; zero performance impact (`const` only changes `this` pointer type; LTO inlines either way).
- **automationcanvas `startBandGesture` unification rejected** — tempo-header-right vs body-right semantics diverge (hover highlight, guard boundary).
- **automationcanvas `paintAnySlot<T>` collapse rejected** — re-introduces switch in hot paint path; keeps `visit()` total dispatch.
- **Intra-file extraction only** — per `keep-files-small.md` cohesion rule; `editordrawer/` is the model module; no new files.
