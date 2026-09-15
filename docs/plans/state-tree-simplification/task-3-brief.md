# Task 3 — `diffLiveState` and per-page pure refresh classification

## 1. Context

Three pages each compare seven `DrawerPageLiveState` fields by hand
(`automationpage.cpp:126-154`, `velocityarea.cpp:102-154`,
`voicechangearea.cpp:140-184`) plus `sameLiveState` (`automationpage.cpp:17`),
and interleave the comparison with state assignment and side effects. This task
extracts the same-shape comparison into one pure delta and moves each page's
branch selection into one pure classifier; every branch outcome is preserved
exactly — including automation playhead-only changes reaching `rebuildRows()`
when not panning. This is the behavior-preserving policy in spec.md, not a
playback optimization. Consumer: task 4's epoch continues to advance whenever
the refresh policy chooses `Rebuild`.

## 2. Exact write set

- `src/ui/editordrawer/drawerpage.h`
- `src/ui/editordrawer/automationpage.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`

The three page headers already declare `refreshLiveState`; classifiers are
file-local, so no header changes.

## 3. Prerequisites

Task 2 — consumes `AutomationCanvas::rebuildViewModel()` as the Selection
action's model publication. Its accepted publication contract must survive
this rewrite of the shared automationpage.cpp.

## 4. Interface contract

`drawerpage.h`, inline, `noexcept`:

```cpp
struct DrawerLiveDelta {
    bool revision = false, timeZoom = false, horizontalScroll = false,
         editCursor = false, trackColor = false, playhead = false, playing = false;
    bool any() const noexcept;
    bool onlyScroll() const noexcept;    // horizontalScroll set, no other field
    bool onlyPlayhead() const noexcept;  // playhead set, no other field
};
DrawerLiveDelta diffLiveState(const DrawerPageLiveState &before,
                              const DrawerPageLiveState &after) noexcept;
```

`diffLiveState` field mapping: `documentRevision`→`revision`,
`timeZoom`→`timeZoom`, `horizontalScroll`→`horizontalScroll`,
`editCursorTick`→`editCursor`, `trackColor`→`trackColor`,
`playback.playheadTick`→`playhead`, `playback.playing`→`playing`.

Per page, file-local `static`/free in the `.cpp`, no member access, pure:

```cpp
// automationpage.cpp — arms evaluated in the order declared
enum class AutomationRefreshAction { None, Selection, FullQuick, Rebuild };
AutomationRefreshAction classifyAutomationRefresh(const DrawerLiveDelta &delta,
                                                  bool viewStateChanged,
                                                  bool panning) noexcept;
// velocityarea.cpp — arms evaluated in the order declared
enum class VelocityRefreshAction { ScrollOnly, InteractionPreserve, PlayheadOnly,
                                   Rebuild };
VelocityRefreshAction classifyVelocityRefresh(const DrawerLiveDelta &delta,
                                              bool interactionActive,
                                              bool scrollRetainsPresentation) noexcept;
// voicechangearea.cpp — arms evaluated in the order declared
enum class VoiceRefreshAction { ScrollOnly, PanPreserve, PlayheadOnly, Rebuild };
VoiceRefreshAction classifyVoiceRefresh(const DrawerLiveDelta &delta,
                                        bool trackChanged, bool panning) noexcept;
```

`interactionActive` is `m_interaction != Interaction::None`; voice `panning` is
exactly `m_interaction == Interaction::Pan`; both are captured before any
`cancelInteraction()`. The classifier consults `scrollRetainsPresentation` only
when `delta.onlyScroll()`. Classification is value-only: it never reads page
members and never captures model-owned pointers (row titles).

### Exact outcome mapping (first match wins; assignment placement stated per arm)

**AutomationPage::refreshLiveState** — compute `viewStateChanged`
(`m_viewState != viewState`) and `panning = m_canvas->isPanning()` first; assign
`m_liveState`/`m_viewState` before the switch, as today:

| Condition | Action → switch arm |
|---|---|
| `!viewStateChanged && delta.onlyScroll()` | `None` → return (camera-tail comment stays) |
| `!delta.any() && !viewStateChanged` | `Selection` → task 2's `m_canvas->rebuildViewModel()` then `requestSelectionQuickUpdate()` |
| `panning && !delta.revision && !viewStateChanged` | `FullQuick` → `requestFullQuickUpdate()` |
| otherwise | `Rebuild` → `rebuildRows()` (playhead-only while not panning lands here — preserved) |

Order is load-bearing: `Selection` precedes `FullQuick` (panning with an empty
delta is `Selection` today); `None` precedes both. `FullQuick` fires for any
non-revision delta while panning, not only playhead.

**VelocityArea::refreshLiveState** — capture `interactionActive`.
`scrollRetainsPresentation` is false unless `delta.onlyScroll()`. Only in that
case, resolve the hover note when present and found; use `contextForNote(note)`
for that note, otherwise `currentContext()`. Compare the resolved VelocityMap
with `m_axis.map()` to obtain the boolean. This preserves the existing lazy
hover lookup. No state assignment before the switch:

| Condition | Action → switch arm |
|---|---|
| `delta.onlyScroll() && scrollRetainsPresentation` | `ScrollOnly` → assign `m_live`, `presentPlayhead`, return (camera-tail comment stays) |
| `interactionActive && !delta.revision` | `InteractionPreserve` → if `delta.playhead`, `presentPlayhead`; return; **no** `m_live` assignment (matches `velocityarea.cpp:129-134`) |
| `delta.onlyPlayhead()` | `PlayheadOnly` → assign `m_live`; if `currentContext() != m_axis.map()`, `rebuildVisualState()` (stays in-arm, lazy, `velocityarea.cpp:144`); `presentPlayhead`; return |
| otherwise | `Rebuild` → assign `m_live`; `cancelInteraction()`; if `!interactionActive`, `rebuildVisualState()`; `presentPlayhead` |

Consequences preserved: `ScrollOnly` outranks `InteractionPreserve` (scroll with
a matched hover context retains presentation even mid-gesture); `onlyScroll()`
with a hover-override context that differs from `m_axis.map()` falls through to
`InteractionPreserve`, else `Rebuild` (current code falls out of the
`scrollOnly` block the same way). An empty delta with an active interaction is
`InteractionPreserve` (no `presentPlayhead`: playhead unchanged). Playing-only
changes are never `PlayheadOnly`.

**VoiceChangeArea::refreshLiveState** — keep the opening statements verbatim:
`previousTrack`/`m_engineTrack = primaryTrack()`/`trackChanged` recapture and
its why-comment (`voicechangearea.cpp:142-147`). Assign `m_live` in the
`ScrollOnly`/`PlayheadOnly`/`Rebuild` arms only:

| Condition | Action → switch arm |
|---|---|
| `!trackChanged && delta.onlyScroll()` | `ScrollOnly` → assign `m_live`, `presentPlayhead`, return |
| `!trackChanged && panning && !delta.revision` | `PanPreserve` → if `delta.playhead`, `presentPlayhead`; return; **no** `m_live` assignment (matches `voicechangearea.cpp:162-167`) |
| `!trackChanged && delta.onlyPlayhead()` | `PlayheadOnly` → assign `m_live`, `presentPlayhead`, return |
| otherwise | `Rebuild` → assign `m_live`, `cancelInteraction()`, `rebuildVisualState()`, `presentPlayhead()` |

Note: voice `ScrollOnly` fires even while panning — it precedes `PanPreserve`
(`voicechangearea.cpp:148-161`); automation's `None` likewise outranks its pan
preserve.

## 5. Implementation steps

1. Add `DrawerLiveDelta`/`diffLiveState` to `drawerpage.h` (seven comparisons,
   inline). Delete `sameLiveState`.
2. Rewrite each `refreshLiveState` as: compute delta → compute page-local facts
   (with the laziness notes above) → `switch (classify(...))`. Assignment
   placement per the mapping; move each why-comment (camera tail, hover-override
   match, primary-track recapture, pan preservation) beside the enum value or
   case it explains.
3. Keep classifiers file-local and preserve the existing page interfaces.

## 6. Acceptance predicate

- The three refresh bodies use `diffLiveState` rather than independently
  comparing its seven fields. Pure classifiers preserve the ordered tables.
- The Selection arm keeps task 2's publication before selection notification.
- The controller runs the named checks under plan.md's verification policy;
  * marks a desktop/native requirement.

```sh
deno task verify --filter automation-editing --verbose  # Selection action via the real path: setTimeSelection → drawer refresh with empty delta → selection-bound quick layers repaint (automationpainting.cpp:318-321, automationselection.cpp)
deno task verify --filter automation-raster --verbose   # * Automation None + Rebuild: fixture drives refreshLiveState with camera scroll and revision (rasterfixture.cpp:494-503)
deno task verify --filter host-adapter --verbose        # automation pan routing (isPanning lifecycle, revision stable during pan) + velocity playhead voice switching with contentBuildCount retained (tst_hostadapter.cpp:526-561,573-586)
deno task verify --filter velocity-page --verbose       # velocity ScrollOnly retention (contentBuildCount unchanged on scroll) + PlayheadOnly sweep retention (velocity.cpp:609-622)
deno task verify --filter editor-drawer --verbose       # voice surface: playhead within a span leaves band pixels stable, span change repaints, voice camera transactions
deno task verify --filter timelinepancheck --verbose    # * shared camera tail: scroll-only fan-out to the drawer bands during pan + playhead follow-scroll
```

- Coverage gaps (report-only throwaway rigs; no permanent tests; assert
  observable surfaces — quick-scene layers, pixels, `diagnostics()`,
  interaction state — never `m_live`-style implementation fields):
  1. Voice `PanPreserve`: real middle-drag pan on the voice band; advance the
     playhead within the same span via `view.setPlayheadSample(...)`; verify
     the voice markers continue following the active pan, the playhead overlay
     lands on the new tick, and the pan remains active through release.
     No recorded check directly covers this interleaving.
  2. Velocity scroll-with-hover fall-through: hover a note whose
     `contextForNote` differs from the axis map, then change the editor
     horizontal scroll → `diagnostics().contentBuildCount` increments
     (fall-through Rebuild); the unchanged half without hover is already
     velocity-page's scroll test.
  3. Automation `FullQuick` vs `Rebuild` while panning: no named check
     distinguishes the two (host-adapter asserts routing/panning only; the
     raster fixture never pans). Throwaway: start a real automation-band pan,
     drive `refreshLiveState` with a playhead-only delta, assert hover/grab
     state survives and no interaction cancellation fires.

## 7. Task-specific constraints

- No shared enum across pages: the three action sets differ (Automation has
  `Selection`, Velocity has `InteractionPreserve`, Voice has `PanPreserve`) and
  forcing one enum would reintroduce the "which branch applies to me" reasoning
  this task removes.
- Do not fold the classifier into `diffLiveState`; the delta is page-agnostic.
- Velocity laziness is part of the behaviour: the hover-override context lookup
  (`velocityarea.cpp:112-121`) and the `PlayheadOnly` `currentContext()`
  comparison (`velocityarea.cpp:144`) must stay lazily evaluated.
- Do not touch pending-target validity, `m_rowGeneration`, or the pending
  structs' `QPointer` fields (task 4); `Rebuild` must remain the only refresh
  action that reaches `rebuildRows()`.
- No new caching, snapshots, or repaint-scheduling changes; the rewrite is an
  extraction — branch outcomes, ordering, and assignment placement are
  preserved exactly.
