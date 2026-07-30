# 20 — EditorDrawer

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/drawer`  
**Worktree:** `20-drawer`  
**Base:** `FOUNDATION_SHA` — the coordinator-recorded, approved integration
commit after the 10A → 10B/11 → DOCUMENT_SHA → 10C and 12A/12B/13 → 14A/14B foundation DAG.
`git-operations-runner` creates/verifies the `20-drawer` worktree and `task/psg-velocity/drawer` branch at its exact `FOUNDATION_SHA` base and initializes/verifies submodules before the `task` agent begins. Product tasks (20, 21, 22, and 23) remain parallel only at `FOUNDATION_SHA`.
Start from that exact SHA; do not rebase or absorb packets 21, 22, or 23.

## Exact independent ownership

This packet owns exactly these three paths:

1. `src/ui/editordrawer.h`
2. `src/ui/editordrawer.cpp`
3. `src/rollcheckdrawer.cpp`

The third path is the drawer's cpp-only focused harness; do not add a harness
header. Packet 05 conditionally registers precisely this complete group with
`PORYDAW_HAS_DRAWER_CHECK` and `porydaw --check-editor-drawer [screenshot]`. Once all three
files exist on this branch, that command must compile and be runnable here; no
source/build/dispatch edit or later host integration is needed to enable it.

Consume, without editing, the generic Foundation contracts
`EditorPage`, `EditorPageContext`, `EditorPageHost`, and `EditorViewState`,
the layout contract, and the existing `TimelineSurface` supplied through the
page/context seam. `TimelineSurface` already exists; this packet neither
creates nor changes it. Packet 30 alone supplies concrete `SongView` and
`MainWindow` lifecycle/persistence wiring. Packet 05 alone owns central
registration and dispatch.

The module is an embeddable `EditorDrawer`: its generic host supplies bounds,
page widgets/canvas focus targets, resolved view state, and callbacks. It
reports local visible/page/height changes, status requests, focus requests, and
page-visibility/cancellation events through that seam. It must not reach into
`SongView` or `MainWindow`.

## Deliver

- Bottom-overlay geometry using foundation layout values: unchanged host/roll
  geometry, derived gutter/keyboard/plot origin, tab partition, resize handle,
  one-fifth default height, and minimum/maximum clamps. Below plot origin, plot
  width is zero and nothing paints through the gutter.
- Text-only, non-focusable `Automations` and `Velocity` tabs with exact
  tooltips. The visible-page tab closes; the other tab opens and switches.
  Expose local `A`/`V` actions and exact shown/hidden status requests for the
  host to route; do not install window-global shortcuts.
- Left-button resize only, named normal/hover splitter styling, retained local
  last-open height, and focus-facing transitions: a switch requests focus for
  the newly visible canvas; closing requests main-content focus if a drawer
  canvas owned focus.
- Local page-hide/close cancellation dispatch and host refresh requests.
  Preserve page and height across hide/switch; do not own page gestures.

## Non-goals

Do not edit `SongView`, `MainWindow`, `TimelineSurface`, `PlayheadOverlay`,
layout, foundation page/context/view-state contracts, page implementations,
sidecar code, `CMakeLists.txt`, `src/main.cpp`, or
`src/editorcheckdispatch.h.in`. Do not implement automation or velocity gestures,
status rendering, event-list policy, multi-tab routing, per-song save/load,
selection, playback, document/Undo state, or serialization.

## Edge cases

- First tab gets integer half of resolved header width; the second gets the
  remainder.
- Closing retains page and height; switching an already hidden page opens it.
- Resize clamps when the host is shorter than the minimum-open height and when
  retaining the minimum visible roll is possible.
- No tab, stack, or scroll container joins the focus chain; a missing/hidden
  canvas receives no focus request.
- A page/close notification cancels local capture exactly once and is harmless
  with no active gesture.

## Focused checks and acceptance

Write drawer-only cases in `src/rollcheckdrawer.cpp` for overlay/no-roll-resize
and narrow-width clipping; tab text, focus policy, toggles, tooltips, local
`A`/`V` action payloads, exact status payloads, resize bounds, and
page-switch/close focus and cancellation events. Exercise geometry and hit-test
behavior only through `porydaw --check-editor-drawer [screenshot]`; no repository-wide
geometry source audit belongs to this packet.

This packet owns **DRW-01** and the drawer-local portions of **DRW-02**,
**DRW-03**, **LIFE-01**, **UX-01**, and **UX-02**. Packet 30 proves global
shortcut routing, event-list blocking, and integrated behavior. No full native
suite, formatter, linter, or review gate belongs here.

## Downstream host integration

The four product heads merge normally only after their reviews, producing
`PRODUCT_SHA`. The host chain is serial: 30C alone starts from `PRODUCT_SHA`;
the coordinator builds/checks its focused command and a reviewer inspects
`PRODUCT_SHA..30C_HEAD` before its ordinary merge records `RENDERING_SHA`. 30A
then starts only from `RENDERING_SHA`; the coordinator builds/checks its
focused command and a reviewer inspects `RENDERING_SHA..30A_HEAD` before its
ordinary merge records `ADAPTER_SHA`. 30B then starts only from `ADAPTER_SHA`;
the coordinator builds/checks its focused command and a reviewer inspects
`ADAPTER_SHA..30B_HEAD` before its ordinary merge records `HOST_SHA`. 30A
constructs the drawer through the generic host and owns
SongView lifecycle, revisioned velocity forwarding, focus, sidecar state
routing, and dynamic-band requests; 30B owns public MainWindow A/V routing and
persistence; 30C owns the generic dynamic timeline-band API and overlay-only
playhead presentation. This packet does not edit or preempt any of those host
paths.

## Commit handoff

The assigned `task` agent implements the owned production paths and focused
harness, then makes one ordinary commit on `task/psg-velocity/drawer`; it does
not build, run checks, format, lint, or review. After the parallel product
commits, the coordinator runs `porydaw --check-editor-drawer [screenshot]` once on this
complete group before parallel review. Hand off the commit SHA, changed-file
list, exact host callbacks/events, and overlay/focus edge-case evidence. Do
not stage a transport tree or modify the integration branch.
