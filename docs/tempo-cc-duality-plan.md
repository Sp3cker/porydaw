# Kill the tempo-vs-CC duality — implementation plan

- **Worktree:** `/Users/spencer/dev/cProjects/porydaw-fork-tempo-cc`
- **Branch:** `fix/tempo-cc-duality` (base: `fork-main` @ `73b36e3`, "automationgesturecheck: deduplicate harness via private support header and table-driven scenarios")
- **Status:** SUPERSEDED — reviewed and synthesized into `docs/tempo-cc-duality-consensus.md` (v2). Kept for the full verified-site inventory.

---

## 1. Finding (verbatim, for reference)

> Finding #4: kill the tempo-vs-CC duality. The branch made tempo a first-class editable lane and "unified" it with CC lanes behind NodeLane contract adapters (2d4e29c → c4f76af). The unification is real in one place: body paint (`nodelane/paint.cpp` genuinely shares curve/node/hover/preview painting via `paintNodeLane`). But five things still exist twice, and every one encodes the same rule — "tempo is the singleton lane 0; CC are lanes 1..N":
>
> 1. Two selection stores (`EditorSelectionModel::TimeSelection` vs a `CCLanes::TimeSelection` cache) and two hit-tests (`TempoLane::selectionContains` vs `CCLanes::selectionContains`).
> 2. ~12 scattered `handle.index == 0` branches in canvas input/paint/publish.
> 3. Two commit back-ends (`CCLaneAdapter::movePoints/deletePoints` vs `nodelane::resolveCcMoves` + `resolveBatchDeletes`), plus an occupied==1 fast path that bypasses the canonical resolver.
> 4. Header chrome painted twice (CC in `automationcanvas_paint.cpp`, tempo in `tempolane.cpp`).
> 5. Tempo's implicit 120 BPM lead-in synthesized in the canvas and passed as an optional `leadIn` parameter into generic paint.
>
> The judo: Tempo is already `LaneHandle{0}`; push everything else behind it — one selection abstraction (`bool covers(LaneHandle)`, `bool hitTest(LaneHandle, x)`), a `NodeLane::leadIn()` virtual, a shared `paintLaneHeader(...)`, one commit path that always builds a `RangeEdit` through the resolvers, and a `BandGesture` that owns its lane range. After the move the canvas never knows tempo-vs-CC.

## 2. Verified inventory (all sites confirmed against worktree code)

| # | Duality | Sites |
|---|---------|-------|
| 1 | Two selection stores | Model `TimeSelection{startTick,endTick,scope,lanes,tempo}` `editorselectionmodel.h:18-28`; queries `timeSelectionCoversLane/Tempo` `editorselectionmodel.cpp:38-60`. Cache `CCLanes::TimeSelection` `cclanes.h:55-71`, `syncTimeSelection` `cclanes.cpp:102-124` (called from `invalidateContent` `automationcanvas.cpp:96` and `rebuildRows`), `selectionContains` `cclanes.cpp:159-172`. Tempo side `TempoLane::hasTimeSelection/selectionContains` `tempolane.cpp:71-88`. Consumers: `automationcanvas_paint.cpp:205-208, 245-248`; `automationcanvas_input.cpp:94-95, 98-102, 344-346, 358-364`; `automationcanvas.cpp:577-593`. |
| 2 | `index == 0` branches | `automationcanvas.cpp:364, 397, 500, 562`; `automationcanvas_input.cpp:77, 90, 143, 269, 286, 334, 353, 361, 395, 438, 485-489` (keyboard delete — **missed by the finding**); `automationcanvas_gesture.cpp:26, 84, 111, 149, 175`; `automationcanvas_paint.cpp:209, 238, 259-274, 280-285`. |
| 3 | Two commit back-ends | `CCLaneAdapter::deletePoints/movePoints` `cclanes.cpp:226-262` (group-collect, clamp, last-value-wins, **no collision planning**, `document.moveLanePoints`); `TempoLane::deletePoints/movePoints` `tempoadapter.cpp:55-84` (move already delegates to `resolveTempoMoves`; delete is bespoke); canonical resolvers `resolveTempoMoves/resolveCcMoves/resolveBatchDeletes` `batchcommit.cpp:50-167` (`resolveCcMoves` uses collision-aware `planLaneMoves`). Gesture fast paths `automationcanvas_gesture.cpp:103-109, 167-173`; menu `automationcanvas.cpp:507, 511`; keyboard delete `automationcanvas_input.cpp:485-489` (**third direct caller, missed by the finding**). `automationgesturecheck/contract.cpp` tests the adapter virtuals directly (269-276, 313-353, 419-441) — must be reworked. |
| 4 | Header chrome twice | CC: `automationcanvas_paint.cpp:151-211` (separator, two-line textLayout title+caption, summary cache). Tempo: `tempolane.cpp:169-225` (separator, collapse arrow, title, point-count caption). |
| 5 | leadIn | `nodelane/paint.h:36` field; consumed `nodelane/paint.cpp:76-84`; synthesized in canvas `automationcanvas_paint.cpp:266-268`; `{}` passed for CC at `:209`. |
| 6 | Band lane range | `BandGesture` is tick-only `gesture.h:154-171`; lane range is canvas state `m_bandStart/m_bandEnd` (`automationcanvas.h:179-180`) with the singleton clamp repeated at `input.cpp:269-272, 334-337`, range math at `paint.cpp:236-241, 280-283`, `bandPreviewContainsLane` `canvas.cpp:110-117`, and the publish encoder `publishBandSelection` `canvas.cpp:552-575`. |

File sizes (all under 600L; review signal respected): `automationcanvas.cpp` 593, `input` 502, `paint` 287, `gesture` 395, `menu` 197, `tempolane.cpp` 225, `cclanes.cpp` 283, `nodelane/paint.cpp` 465, `batchcommit.cpp` 183, `editorselectionmodel.cpp` 401.

## 3. The moves

### M1 — One selection view (kills duality #1)

**Correction to the finding's wording:** the *data* already lives in `EditorSelectionModel::TimeSelection`; a LaneHandle-indexed store cannot live inside `EditorSelectionModel` because handle→(track, cc) mapping needs the canvas row table (LaneHandle is canvas layout, not model state). So: keep the model struct unchanged (it is consumed by piano-roll scope logic, sanitize/serialization, and `DrawerPageTimeSelectionMenuRequest`); **delete the cache and both hit-tests**, and add one small view over the model:

```cpp
// new: src/ui/editordrawer/laneselection.{h,cpp}  (~90L, real ownership boundary)
class LaneSelection {
  public:
    LaneSelection(const songview::EditorSelectionModel &model,
                  const std::vector<AutomationRow> &rows, uint32_t usedTrackMask) noexcept;
    bool active() const noexcept;                 // model.timeSelection().active()
    bool affectsCanvas() const noexcept;          // coversTempo(mask) || (scope==Lanes && any visible lane)
    bool covers(LaneHandle) const noexcept;       // 0 -> timeSelectionCoversTempo; else coversLane(rowIdentity)
    bool hitTest(LaneHandle, qreal x, const AutomationProjection &, qreal dpr) const noexcept;
    std::vector<std::pair<int, uint8_t>> visibleLanes() const noexcept; // selection.lanes filtered to rows
    std::pair<bool, std::vector<std::pair<int, uint8_t>>>  // {tempo, lanes} — the ONE publish encoder
    laneSet(LaneHandle first, LaneHandle last) const noexcept;
};
```

- `hitTest` unifies the two mappings: `projection.displayX(start/endTick, dpr)` (verified: `AutomationProjection::displayX` ≡ `page->displayX(tick, geometry.plotOrigin, dpr)`; the tempo path already used projection, the CC path used the page — same mapping).
- Canvas holds one `LaneSelection m_laneSelection;` rebuilt in `rebuildRows` (alongside `m_rowData`).
- **Delete:** `CCLanes::TimeSelection` + `syncTimeSelection` + `selectionContains` + `clearTimeSelection`; `TempoLane::selectionContains`; the `invalidateContent` sync call. (`TempoLane::hasTimeSelection` stays — it is a thin model query, used by `TempoLane::paint` for the collapsed reticle, not a store.)
- Consumers flip to live queries: paint `selectedLane`/reticle loop, input press/release selection checks, `showTimeSelectionMenu` (request built via `laneSet(contextLane)` + `visibleLanes`), and the two clear paths collapse to `if (m_laneSelection.affectsCanvas()) { model.clearTimeSelection(); invalidateContent(); }`.

### M2 — Lane-kind virtuals (kills duality #2 sites)

`nodelane.h` gains (forward-declared `AutomationCanvas`, `QWidget`, `QPoint`):

```cpp
virtual std::optional<NodePoint> leadIn() const { return std::nullopt; }      // M5
virtual bool promptValue(QWidget *parent, int currentValue, int *storedValue) = 0;  // was promptBpm / promptPointValue
virtual int neutralValue() const { return -1; }                                // was snapNeutralFor
virtual void showHeaderMenu(AutomationCanvas &area, const QPoint &globalPosition) = 0;
virtual bool showEmptyBodyMenu(AutomationCanvas &area, const QPoint &globalPosition) { return false; }
```

- **TempoLane:** `leadIn()` = `{0, CoreTimeDefaults::kTempoBpm}` iff first point tick > 0 (moved from canvas); `promptValue` = existing `promptBpm` body; `showHeaderMenu` = existing `showTempoMenu` (renamed); `showEmptyBodyMenu` = showTempoMenu, return true.
- **CCLaneAdapter:** `promptValue` = `AutomationCanvas::promptPointValue` body moved in (it has `m_controller` and `title()`); `neutralValue` = bend→0, pan(10/24)→64, else −1 (kills `snapNeutralFor`); `showHeaderMenu` = `showLaneMenu` body moved in (needs canvas internals: `friend class CCLaneAdapter;` alongside the existing `friend class TempoLane;`, plus the canvas `m_clipboard`); `showEmptyBodyMenu` = default false (canvas then clears selection — current CC behavior).
- **Canvas deletions:** `promptPointValue`, `snapNeutralFor`. Input sites 438-443 and canvas 500-505 become `lane->promptValue(this, value, &value)`.
- **Hover guards** (input 77-80, 286-297, 395-398): drop `inTempo` conditions — the voice lane rect (top inset) and the pinned tempo rect (viewport bottom) never overlap, so `m_voiceLane.contains(...)` is sufficient and the guard's `clearHover` is redundant with the unconditional clear immediately below. Pure geometry redundancy; verify via `rollcheckautomation*` harnesses.
- `ccRowIndexAt` (canvas 364) and `ccRowBoundaryAt` stay: they are row-layout bounds checks, not tempo semantics. `handle.index - 1` row arithmetic centralizes into a `CCLanes::rowIndexFor(LaneHandle)` helper (used by input 146/441, canvas 503, gesture 29, menu row→handle loop).

### M3 — One commit path (kills duality #3)

- `commitNodePointMoves` / `commitNodePointDeletes`: delete the `occupied == 1` fast paths (`gesture.cpp:103-109, 167-173`) and the `mutableLane` validation loops that only served them; always assemble `SongDocument::RangeEdit` via `resolveTempoMoves` (index 0) + `resolveCcMoves` / `resolveBatchDeletes` (indices 1..N) and `applyRangeEdit`. `edit.empty()` already covers the no-op cases.
- `showPointMenuNear` set-value / delete (`canvas.cpp:507, 511`) and keyboard delete (`input.cpp:485-489`): route through the same resolvers (single move / single `CcDeleteRequest` / single tempo tick).
- **Delete** `NodeLane::movePoints/deletePoints` virtuals and their four implementations (`CCLaneAdapter` cclanes.cpp:226-262, `TempoLane` tempoadapter.cpp:55-84). `replaceSpan` stays (sweep/pencil/double-click/paste commit).
- **Rework** `automationgesturecheck/contract.cpp` and any rig code calling those virtuals: the contract (group-collect, last-value-wins, unknown-tick no-op, empty no-op) moves onto `resolveCcMoves/resolveTempoMoves/resolveBatchDeletes`.
- **Pinned behavior changes (intentional, test them):** single-lane CC moves now go through collision-aware `planLaneMoves` (previously raw `moveLanePoints`); undo labels unify to `tr("edit automation points")` / `tr("delete automation point(s)")`.

### M4 — Shared header paint (kills duality #4)

```cpp
// nodelane/paint.{h,cpp} — same module as paintNodeLane (~35L added, file stays < 600)
struct LaneHeaderPaint {
    QRect band;                       // row band incl. gutter
    QRect primary; QRect secondary;   // text boxes (caller computes via textLayout.align or strip math)
    std::optional<QRect> arrow;       // collapse arrow; tempo only
    bool expanded;
    QFont titleFont, captionFont;
    QString title; QString secondaryText;  // secondaryText empty -> caption omitted
};
void paintLaneHeader(QPainter &, const LaneHeaderPaint &);
```

- Renders: separator at band bottom, optional arrow polygon (expanded/collapsed triangles), title in title/caption font by `expanded`, caption in secondary color. Per-kind layout math (CC two-line center via `textLayout.align`; tempo strip+arrow offset) stays local to each caller; both call sites drop their bespoke pen/font/color/separator code.
- `TempoLane::paint` header section and the CC loop in `paintContent` become thin callers.

### M5 — leadIn virtual (kills duality #5)

- Remove `NodeLanePaint::leadIn`; `paintNodeLane` queries `paint.lane.leadIn()` (`paint.cpp:76-84` unchanged logic, new source).
- Delete the canvas synthesis (`automationcanvas_paint.cpp:266-268`) and the `{}` argument at `:209`; the tempo pass just calls `paintLaneBody` like the CC loop.

### M6 — BandGesture owns its lane range (kills duality #6)

```cpp
// gesture.h BandGesture gains:
LaneHandle laneStart, laneEnd;
void pressLane(LaneHandle);                 // sets both
void extendTo(LaneHandle candidate);        // THE singleton clamp: laneStart.index==0 -> laneEnd=0;
                                            // else candidate.index>0 -> laneEnd=candidate
std::pair<LaneHandle, LaneHandle> laneRange() const;
bool coversLane(LaneHandle) const;          // replaces canvas bandPreviewContainsLane
```

- Canvas drops `m_bandStart/m_bandEnd`; `input.cpp:269-272, 334-337` become `m_band.extendTo(candidate)`; press sites call `m_band.pressLane(handle)`; `publishBandSelection` consumes `m_band.laneRange()` + `LaneSelection::laneSet`; paint reticle loops (`paint.cpp:236-241, 280-285`) consume `laneRange()`.
- After M6, `publishBandSelection` shrinks to: read `laneRange()` → `m_laneSelection.laneSet(...)` → `publishTimeSelection` + announce.

### Where the rule lives afterwards (the "~15 lines")

1. `rebuildNodeStack` (`canvas.cpp:236`): tempo pushed at index 0 — the layout itself.
2. `LaneSelection::covers/laneSet` handle→identity mapping (~10 lines).
3. `BandGesture::extendTo` clamp (~5 lines).
Everything else is `handle.index` arithmetic inside `CCLanes::rowIndexFor` + stack bounds checks, which is row-layout knowledge, not tempo semantics.

## 4. Behavior-preservation table (review this)

| Behavior | Today | After | Status |
|---|---|---|---|
| Press outside selection clears it | tempo: if `coversTempo`; CC: if cache active | `affectsCanvas()` (same condition, one place) | identical |
| CC right-click on empty body | clears model selection if active | same | identical |
| Selection menu request | tempo → tempo-only; CC → all visible covered lanes | `laneSet(contextLane)` / `visibleLanes()` | identical |
| Band tempo+CC mix | tempo start forces tempo-only band | `extendTo` clamp | identical |
| Single-lane CC point move onto occupied tick | raw move (no collision plan) | `planLaneMoves` collision semantics | **changed (fix)** |
| Undo label, single-lane move/delete | adapter labels | batch labels | **changed** |
| Keyboard delete of hovered point | adapter direct | batch resolver | identical result |
| Hover guards `!inTempo &&` | present | removed (geometric redundancy) | identical |
| `syncTimeSelection` per invalidate | eager cache refresh | live query (no sync point) | identical results |

## 5. Waves (sequential — the canvas files are the shared mutation boundary)

- **Wave 0 — baseline:** `deno task build:checks` in the worktree (fresh build dir); capture the current harness list (`deno task verify` green).
- **Wave 1 — foundation (one `task` agent):** M1 (LaneSelection + deletions + consumer flip) + M5 (leadIn). Verify: `deno task verify --filter selectioncheck --filter rollcheckautomation --filter rollcheckautomation_tempo --filter automationgesturecheck`.
- **Wave 2 — commit path (one `task` agent):** M3 + `contract.cpp` rework. Verify: `deno task verify --filter automationgesturecheck --filter rollcheckautomation`.
- **Wave 3 — lane-kind surface (one `task` agent):** M2 virtuals + M4 header paint + M6 BandGesture. Verify: `rollcheckautomation_paint`, `rollcheckautomation_tempo_paint`, `rollcheckautomation_popup`, `automationgesturecheck`.
- **Wave 4 — sweep & cleanup (one `task` agent + `sonic` for mechanical greps):** kill remaining branches, delete dead helpers (`snapNeutralFor`, `promptPointValue`, old menu bodies), grep audits, full `deno task verify`, format.
- **Wave 5 — review:** `reviewer` subagent on the branch diff (Standards + Spec axes), then manual smoke + screenshot via the macOS capture skill (header unification, band clamp, menus, prompts, collapse, lead-in).

## 6. Tests (observable contracts)

- `automationgesturecheck`: rework contract tests onto the resolvers; add collision cases (CC move onto occupied tick, tempo move onto occupied tick, grouped ticks last-value-wins, unknown tick → no-op, empty → no-op); add single-lane RangeEdit parity with multi-lane.
- `selectioncheck.cpp` or `automationgesturecheck`: LaneSelection table tests — covers/hitTest/affectsCanvas/laneSet parity against the old two-store behavior (the table in §4 is the spec).
- `rollcheckautomation*`: band clamp (tempo start, CC start, release), selection menu requests, prompt value paths, header paint smoke (no crash, same texts).

## 7. Verification

- `deno task verify` (all harnesses) in the worktree; `deno task format --check`.
- Grep audits: no `index == 0` in `automationcanvas_input/paint/gesture.cpp`; no `TimeSelection` in `cclanes.h`; no `leadIn` in `nodelane/paint.h`; no `movePoints(`/`deletePoints(` on lanes outside `nodelane/`.
- Manual smoke: band-select tempo / CC / mixed, drag multi-lane selection, keyboard delete, both header menus, double-click prompt (BPM vs value), tempo collapse + lead-in line visible, paste CC lane, value-range menu.
- Screenshot of the canvas (capture skill) before/after for header paint parity.

## 8. Risks / open questions for reviewers

1. **LaneSelection home:** new `editordrawer/laneselection.{h,cpp}` vs nesting in `AutomationCanvas`. (File-size rule: new file is a real ownership boundary, not a fragment; nested alternative is also fine.)
2. **Virtual surface:** 5 new virtuals (leadIn, promptValue, neutralValue, showHeaderMenu, showEmptyBodyMenu) vs a centralized lane-kind switch for the two menu virtuals. Menus carry canvas state (clipboard, viewState) — pulling them into adapters via `friend` is a dependency inversion worth a second opinion.
3. **Model struct untouched** (deviation from the finding's "owned by EditorSelectionModel, indexed by LaneHandle"): justified in M1; reviewers should confirm.
4. **Hover-guard removal** relies on voice-lane/tempo rect disjointness — flagged for harness confirmation.
5. **`contract.cpp` rework scope** — the finding missed this harness dependency (and the keyboard-delete site).

## 9. Non-goals

- No changes to `EditorSelectionModel` storage, piano-roll selection, `SongDocument` move/delete APIs, or `replaceSpan` semantics.
- No new lane kinds (program-change lane etc.) — the seam just becomes cheap to extend.
- No file splits beyond the new `laneselection` unit; all touched files stay under 600L (most shrink).
