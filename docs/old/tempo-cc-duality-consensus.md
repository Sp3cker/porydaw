# Kill the tempo-vs-CC duality — consensus plan (v2)

- **Worktree:** `/Users/spencer/dev/cProjects/porydaw-fork-tempo-cc` · **Branch:** `fix/tempo-cc-duality` (base `fork-main` @ `73b36e3`)
- **Status:** SYNTHESIZED consensus — intersection of three viewpoints (the now-removed superseded v1 plan, `reviewer` agent, `evidence-plan-architect` agent). Only moves endorsed by all three are in scope; contested items are resolved or explicitly excluded below.

## 1. Verdict matrix

| Move | Main plan | Reviewer | Architect | Consensus |
|---|---|---|---|---|
| M1 one selection view | in | endorse + changes | endorse + changes | **IN** (pinned predicates) |
| M2 lane-kind surface | virtuals, guards out | 3 virtuals + 2 menu virtuals; **keep guards** | 3 virtuals + canvas kind switch; **keep guards** | **IN**: 3 data virtuals; menu = canvas kind switch (user: simplest/lowest code); hover guards **KEPT** |
| M3 one commit path | in | endorse + changes | endorse + changes | **IN** (corrected rationale, parity framing) |
| M4 shared header paint | in | endorse | endorse | **IN** |
| M5 leadIn virtual | in | endorse | endorse | **IN** (+ drop lambda param) |
| M6 BandGesture lane range | in | endorse + changes | endorse + changes | **IN** (public forwarder, validity guards, dead-code removal) |

## 2. Fact corrections (unanimous)

1. **The collision-planning divergence is FALSE.** `CCLaneAdapter::movePoints` → `SongDocument::moveLanePoints` (cclanes.cpp:261 → songdocument.cpp:1351), which runs the same `planLaneMoves` per lane (songdocument.cpp:1415) that `resolveCcMoves` uses (batchcommit.cpp:117). The single-lane path is *already* collision-aware. M3's genuine deltas: undo-label wording (singular "edit automation point" → plural "edit automation points") and op encoding (in-place `ModifyEvent` for same-tick rewrites vs `RangeEdit` remove+insert).
2. Keyboard delete (input.cpp:485-489) belongs to duality #3 (direct `deletePoints` caller), not duality #2.
3. Missed consumers (v1 inventory gaps): `AutomationCanvas::bandPreviewContainsLane` is public API called from `rollcheckautomation.cpp:570`, `automationgesturecheck/mapping.cpp:77`, `parity.cpp:391`; `rig.cpp:154-156` `MappingLane` **overrides** the virtuals M3 deletes; `TempoLane::showTimeSelectionMenu` (tempolane.cpp:146-158) is orphaned by M1 unless deleted; `contract.cpp:269-443` drives both adapters through `movePoints/deletePoints` at ~30 sites and already contains `checkMoveCollision` (411-443); `AutomationCanvas::bandPreviewContains(handle, tick)` has zero callers (dead); a sixth duality — two clipboards (canvas `vector<NodePoint>` vs `TempoLane::m_clipboard` of `TempoPoint`) — survives everything, acknowledged out of scope.
4. Hit-test equivalence verified: `AutomationProjection::displayX` delegates to `page->displayX(tick, geometry.plotOrigin, dpr)` (automationprojection.cpp:113-118), same mapping as `CCLanes::selectionContains`.

## 3. Final specs

### M1 — LaneSelection view (`src/ui/editordrawer/laneselection.{h,cpp}`, new file — unanimous)

```cpp
class LaneSelection {
  public:
    LaneSelection(const songview::EditorSelectionModel &model,
                  const std::vector<AutomationRow> &rows, uint32_t usedTrackMask) noexcept;
    bool active() const noexcept;   // model.timeSelection().active()
    // tempo handle 0 -> timeSelectionCoversTempo(mask);
    // CC handle    -> scope == Lanes && timeSelectionCoversLane(rowIdentity, mask) && row visible
    bool covers(LaneHandle) const noexcept;
    bool hitTest(LaneHandle, qreal x, const AutomationProjection &, qreal dpr) const noexcept;
    // covers && x in [min(startX,endX), max(...))  -- min/max explicit (sanitize does NOT reorder)
    std::vector<std::pair<int, uint8_t>> visibleLanes() const noexcept;  // selection.lanes filtered to rows, row order
    std::pair<bool, std::vector<std::pair<int, uint8_t>>> laneSet(LaneHandle first, LaneHandle last) const noexcept;
};
```

- **Model struct untouched** — unanimous (Q3): consumed by piano-roll scope logic, sanitize/serialization, `rangeedit.cpp:170-191`, `rollcheck.cpp:606-651`, `hostcheck.cpp:435`; LaneHandle indexes `rebuildNodeStack` order, not stable identity.
- **Freshness:** live view over (model, rows) refs, rebuilt in `rebuildRows` after `m_rowData.rebuildRows()`. Sufficient because `AutomationPage::refreshLiveState` (automationpage.cpp:279-291) → `rebuildRows` fires on every TimeSelection change via `SongView::coordinateSelectionChange` (songview.cpp:465-467); the pan-preserve `invalidateContent()`-only branch is safe (selection cannot mutate during pan). The old `invalidateContent` → `syncTimeSelection` call dies.
- **Clear paths — there are FOUR, and the rule is uniform:** press outside selection (input 97-102), band-dismiss/fallback (input 343-346, 363-364), Escape (input 463-468), menu (canvas 589-592). Today `CCLanes::clearTimeSelection` clears **any active model selection** regardless of scope. Unified rule, all four sites: `if (!insideSelection && model.timeSelection().active()) { model.clearTimeSelection(); invalidateContent(); }` — preserves today's behavior exactly (v1's narrower `affectsCanvas()` is rejected).
- **Selection menu:** `if (!handled && hitTest(contextLane, x)) showTimeSelectionMenuFor(contextLane)`; tempo handle → `{tempo=true, lanes={}}`; CC handle → `{lanes=visibleLanes(), tempo=false}` (NOT `laneSet(ctx,ctx)` — today the CC menu sends all visible covered lanes).
- **Deletions:** `CCLanes::TimeSelection` + `syncTimeSelection` + `selectionContains` + `clearTimeSelection`; `TempoLane::selectionContains` **and** `TempoLane::showTimeSelectionMenu`; `AutomationCanvas::showTimeSelectionMenu` rebuilt on LaneSelection. `TempoLane::hasTimeSelection` stays (thin model query used by `TempoLane::paint`).
- Paint consumers (`selectedLane`, reticle loops) flip to `m_laneSelection.covers(handle)`; scope gate keeps Tracks-scope selections from highlighting CC lanes (today's cache was scope==Lanes-only).

### M2 — lane-kind surface

- **NodeLane gains exactly three virtuals:** `leadIn()` (M5), `promptValue(QWidget*, int, int*)`, `neutralValue()` (default −1).
  - `TempoLane::promptValue` = existing `promptBpm` body; `CCLaneAdapter::promptValue` = `promptPointValue` body moved in (its only row-derived input, `titleFor(row)` = `laneLabel(controller)` = `CCLaneAdapter::title()`, verified); `CCLaneAdapter::neutralValue` = bend→0, pan(10/24)→64, else −1 (absorbs `snapNeutralFor`).
  - `tr()` translation context shifts when prompt strings move classes — keep the same user-visible texts, check `.ts` files.
- **Menu dispatch — canvas kind switch (user decision: simplest/lowest code):** input.cpp call sites become `showLaneMenuFor(handle, globalPosition)`; the empty-body fallback uses `showEmptyBodyMenuFor(handle, globalPosition)`. Two `handle.index == 0` dispatch tests survive in `automationcanvas_menu.cpp` (one per helper) plus the selection-request tempo flag; the branch disappears from input/paint/publish. *Scope note vs the finding's literal "canvas never knows tempo-vs-CC" — see §8.*
- **Hover guards KEPT** (input 77-80, 286-297, 395-398): voice-lane rect and pinned-tempo rect are not provably disjoint (overlap whenever viewport height < voiceHeight + tempoTotal; `setMinimumHeight` applies to scroll content, not the viewport), and no harness exercises degenerate viewports. Removal requires first establishing the invariant (`tempoTop ≥ contentTopInset()` in `syncPinnedTempoLayout` + a viewport-shrink check case) — explicitly out of this branch.
- `CCLanes::rowIndexFor(LaneHandle)` centralizes `handle.index - 1` arithmetic (input 146/441, canvas 503, gesture 29, menu row→handle loop). `ccRowIndexAt`/`ccRowBoundaryAt` stay (row layout, not tempo semantics).

### M3 — one commit path

- Delete the `occupied == 1` fast paths (gesture.cpp:103-109, 167-173) and the counting loops (93-100, 157-164) + the pointer fetch that only served them. **Keep** the per-point validation loops (80-92, 145-156).
- Always assemble `SongDocument::RangeEdit` via `resolveTempoMoves` (index 0) + `resolveCcMoves` / `resolveBatchDeletes` (1..N) → `applyRangeEdit`.
- Menu set-value / delete (canvas 507, 511) and keyboard delete (input 486) route through the same resolvers.
- **Delete** `NodeLane::movePoints/deletePoints` virtuals + all four implementations (cclanes.cpp:226-262, tempoadapter.cpp:55-84) + `rig.cpp:154-156` MappingLane overrides. `replaceSpan` stays.
- **Tests frame parity, not "fix":** resolver path ≡ `moveLanePoints` path for occupied-destination, grouped-tick last-value-wins, unknown-tick no-op, empty no-op. Port `checkMoveCollision` (contract.cpp:411-443), don't add a new case. Compare **lane content**, not raw SMF bytes (`ModifyEvent` vs remove+insert may reorder same-tick events); assert undo **count**, not label text.
- Pinned deltas (the only real ones): undo labels unify to plural; same-tick rewrites commit as remove+insert instead of in-place modify.

### M4 — shared header paint (`nodelane/paint.{h,cpp}`, ~35L; file stays < 600)

- `struct LaneHeaderPaint { QRect band; QRect primary, secondary; std::optional<QRect> arrow; bool expanded; QFont titleFont, captionFont; QString title, secondaryText; }` + `paintLaneHeader(QPainter&, const LaneHeaderPaint&)`.
- Chrome only: separator at band bottom, optional arrow polygon, title/caption with correct fonts/colors; empty `secondaryText` = omit caption (covers collapsed-tempo case). Doc comment: **callers own background fill + clip rects** (tempo fills its band; CC header has no fill).
- Per-kind layout math stays local (CC `textLayout.align` two-line center; tempo strip + arrow offset). RowText summary caching stays in the CC caller.

### M5 — leadIn virtual

- `NodeLane::leadIn()` default `nullopt`; `TempoLane::leadIn()` = `{0, kTempoBpm}` iff first point tick > 0. Remove `NodeLanePaint::leadIn`; `paintNodeLane` queries `paint.lane.leadIn()`.
- **Also drop the `leadIn` parameter from the `paintLaneBody` lambda** (automationcanvas_paint.cpp:115-116) so the tempo pass calls it exactly like the CC loop — leaves no stragglers for the audit grep.
- Existing pin: `rollcheckautomation_paint.cpp:338-341` already tests lead-in painting. Residual out-of-scope flag: `preparedPreviewCurve=true` for tempo (paint.cpp:273) is a separate tempo-special, acknowledged.

### M6 — BandGesture owns lane range

- `BandGesture` gains: `LaneHandle laneStart, laneEnd;` `pressLane(LaneHandle)` (sets both — matches header press {0,0} and body press {h,h}); `extendTo(LaneHandle candidate)` (clamp: `laneStart.index == 0` → `laneEnd = 0`; else `candidate.index > 0` → `laneEnd = candidate`; else sticky); `laneRange()`; `coversLane(LaneHandle)` **with today's validity guards** (band active + both handles valid — parity.cpp:391 relies on false-when-idle).
- Canvas drops `m_bandStart/m_bandEnd`; input 269-272 / 334-337 → `m_band.extendTo(candidate)`; press sites → `pressLane`; `publishBandSelection` → `laneRange()` + `laneSet()`; paint reticle loops (236-241, 280-285) → `laneRange()`/`coversLane`.
- **Keep** public `bandPreviewContainsLane` as a one-line forwarder `return m_band.coversLane(handle);` (three harness consumers). **Delete** dead `bandPreviewContains(handle, tick)` (zero callers).
- Pins: `hostcheck.cpp:432-434` (tempo-only band → `scope==Lanes && tempo && lanes.empty()`), `rollcheck.cpp:3038-3060`.

## 4. Where the rule lives afterwards (honest list)

1. `rebuildNodeStack` (canvas.cpp:236) — tempo pushed at index 0 (the layout itself).
2. `LaneSelection::covers/laneSet` — handle→identity mapping.
3. `BandGesture::extendTo` — the singleton clamp.
4. `commitNodePointMoves/Deletes` — `movesByLane.front()`/`ticksByLane.front()` = tempo + the 1..N CC loop (gesture.cpp:111-128, 174-186); the resolver assembly encodes it structurally. Single-point menu set/delete and keyboard delete route through these same helpers via synthesized `NodeDrag`s, so this is the only commit-side encoding.
5. `automationcanvas_menu.cpp` — two `handle.index == 0` dispatch tests (`showLaneMenuFor` / `showEmptyBodyMenuFor`) plus the selection-request tempo flag in `showTimeSelectionMenuFor`.

Everything else is `CCLanes::rowIndexFor` + stack bounds checks.

## 5. Behavior table (corrected)

| Behavior | Today | After | Status |
|---|---|---|---|
| Press outside selection clears it | any active model selection cleared | same (`model.active()` rule, 4 sites) | identical |
| Tracks-scope selection vs CC lanes | cache empty → no CC highlight/hit | `covers()` gated on `scope==Lanes` | identical |
| CC selection menu request | all visible covered lanes | `visibleLanes()` | identical |
| Tempo selection menu request | tempo-only | `{tempo=true, lanes={}}` | identical |
| Band clamp incl. sticky laneEnd | tempo start → tempo-only; invalid candidate → sticky | `extendTo` same rule | identical |
| Single-lane undo label | singular "edit automation point" | plural | **changed (cosmetic)** |
| Same-tick rewrite op encoding | in-place ModifyEvent | RangeEdit remove+insert | **changed (content-equivalent)** |
| Hover routing guards | `!inTempo &&` guards | guards kept | identical |
| `syncTimeSelection` per invalidate | eager cache refresh | live query (no sync point) | identical results |

## 6. Waves (sequential — `automationcanvas*.cpp` + `nodelane.h` are the shared mutation boundary)

- **W0** baseline: `deno task build:checks` in the worktree (fresh build dir); `deno task verify` green.
- **W1** (`task` agent): M1 + M5. nodelane.h edit #1 = add `leadIn()`. Lands LaneSelection, deletions, consumer flip. Verify: `selectioncheck`, `rollcheckautomation`, `rollcheckautomation_tempo`, `automationgesturecheck`.
- **W2** (`task` agent): M3. nodelane.h edit #2 = remove `movePoints/deletePoints`. Fast paths, menu/keyboard reroute, contract.cpp port + parity rework. Verify: `automationgesturecheck`, `rollcheckautomation`.
- **W3** (`task` agent): M2 remainder + M4 + M6. nodelane.h edit #3 = add `promptValue`/`neutralValue`. Verify: `rollcheckautomation_paint`, `rollcheckautomation_tempo_paint`, `rollcheckautomation_popup`, `automationgesturecheck`, `selectioncheck`.
- **W4** (`sonic` + `task`): dead-code sweep, grep audits, full `deno task verify`, `deno task format --check`.
- **W5** (`reviewer`): branch review (Standards + Spec); manual smoke + screenshot via macOS capture skill (headers, band clamp, menus, prompts, collapse, lead-in).

## 7. Tests (consensus list)

- **LaneSelection table check** (new, `src/checks/`; the class is free-standing — no canvas instantiation): covers/hitTest/visibleLanes/laneSet, including Tracks-scope gating, hidden-lane filtering, min/max x-range, empty selection, laneSet over a range.
- **contract.cpp**: port `checkDelete`/`checkMove`/`checkMoveCollision` onto the resolvers via a thin per-adapter wrapper; keep `checkReplaceSpan`/`checkRangesTextSelection`; undo-count assertions; content-equality snapshots.
- **parity.cpp:186-272**: unified path end-to-end through real gestures — expected values unchanged.
- **hostcheck / rollcheck**: publish-encoder pins stay green (M1/M6).
- **rollcheckautomation_paint.cpp:338-341**: lead-in pin (M5); header text parity (M4).

## 8. Notes and out-of-scope items

- **Two kind-dispatch tests survive** in `automationcanvas_menu.cpp` (plus the selection-request tempo flag) — input/paint/publish are clean; the menu module keeps two mechanical tempo-vs-CC branches. Swapping them for menu virtuals later is a bounded change if the strict "canvas never knows" bar is enforced.
- Two clipboards (canvas `NodePoint` CC clipboard vs `TempoLane::m_clipboard` `TempoPoint`) remain — acknowledged sixth duality, out of scope.
- `preparedPreviewCurve` tempo flag remains in `NodeLanePaint` — out of scope, acknowledged.
- `tr()` context changes on moved prompt strings — verify `.ts` files in W3.
- File-size rule respected: no file grows past ~600L; most shrink; `laneselection.{h,cpp}` (~90L) is a real ownership boundary (module sibling of cclanes/tempolane/voicechangelane).
