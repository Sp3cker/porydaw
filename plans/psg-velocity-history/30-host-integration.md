# 30 — Host integration chain

**Wave:** serial `task` chain: 30C → `RENDERING_SHA` → 30A →
`ADAPTER_SHA` → 30B → `HOST_SHA`  
**Entry milestone:** `PRODUCT_SHA`, whose foundation ancestry is
`10A → parallel 10B/11 → DOCUMENT_SHA → 10C → CONTRACT_SHA`, followed by the
coordinator-recorded normal integration of packets 20–23 on
`feature/psg-velocity-history-upstream`.
**Output:** `HOST_SHA`, recorded only after 30B's approved ordinary merge from
`ADAPTER_SHA` and the coordinator's aggregate host proof on that exact merge.

## Shared entry and operating rule

Packet 05 already owns conditional production/check registration, matching
compile definitions, `CMakeLists.txt`, `src/main.cpp`, and
`src/editorcheckdispatch.h.in`.  It uses a conditional predicate only for a
genuinely new sentinel check source; it MUST NOT use the pre-existing 30B/30C
production or existing-harness sources as completion sentinels.  A task's
complete source/check set activates its individual registration on that task's
own branch; do not defer it until a later integration.  No task in this serial
chain may edit or claim CMake, main, dispatch, registration, or another task's
path.

`git-operations-runner` creates and verifies every host worktree and branch at
its exact serial base, including submodule initialization and verification.
Implementation task agents (`task`) author implementation code and focused checks
inside their prepared worktrees; no implementation task agent creates, resets, or
rebases a worktree.

The packet-05 host manifest has exactly these individual conditional commands:

| Task | New sentinel check source | Individual command |
| --- | --- | --- |
| 30C | `src/renderingplayheadcheck.cpp` | `<porydaw> --check-rendering-playhead <scratch-project> <song-label> [screenshot]` |
| 30A | `src/hostcheck.cpp` | `<porydaw> --check-host-adapter <scratch-project> <song-label>` |
| 30B | `src/mainwindowroutingcheck.cpp` | `<porydaw> --check-mainwindow-routing <scratch-project> <song-a> <song-b>` |

Each individual command activates from its own new sentinel and is independently
compilable and checkable on that task head.  The one aggregate command,
`<porydaw> --check-host-integration <scratch-project> <song-a> <song-b> [screenshot]`,
activates only when all three sentinel sources—`src/hostcheck.cpp`,
`src/mainwindowroutingcheck.cpp`, and `src/renderingplayheadcheck.cpp`—exist.
It is not an alias for any individual command.

`git-operations-runner` creates and verifies the `30c-host-rendering` worktree
and branch from exact `PRODUCT_SHA`, including submodule initialization and
verification. 30C's implementation `task` agent writes its focused checks and
commits without building, running checks, formatting, linting, or reviewing.
Before its ordinary merge, the coordinator verifies its manifest command and
builds/checks the committed 30C head from that base once; a reviewer inspects
the exact `PRODUCT_SHA..30C_HEAD` range and names that base and head in its
decision. Only an approved ordinary merge records `RENDERING_SHA`.

`git-operations-runner` then creates and verifies the `30a-host-songview`
worktree and branch from exact `RENDERING_SHA`, including submodule
verification. 30A's implementation `task` agent writes its focused checks and
commits without building, running checks, formatting, linting, or reviewing.
Before its ordinary merge, the coordinator verifies its manifest command and
builds/checks the committed 30A head from that base once; a reviewer inspects
the exact `RENDERING_SHA..30A_HEAD` range and names that base and head in its
decision. Only an approved ordinary merge records `ADAPTER_SHA`.

`git-operations-runner` then creates and verifies the `30b-host-mainwindow`
worktree and branch from exact `ADAPTER_SHA`, including submodule
verification. 30B's implementation `task` agent writes its focused checks and
commits without building, running checks, formatting, linting, or reviewing.
Before its ordinary merge, the coordinator verifies its manifest command and
builds/checks the committed 30B head from that base once; a reviewer inspects
the exact `ADAPTER_SHA..30B_HEAD` range and names that base and head in its
decision. Only an approved ordinary merge records `HOST_SHA`.

Only after that 30B integration does the coordinator run the aggregate focused
host proof on the exact `HOST_SHA`. No task head or reviewer runs the aggregate
command.

## 30A — SongView adapter and lifecycle

**Worktree Operator:** `git-operations-runner` (creates/verifies worktree at exact `RENDERING_SHA`, including submodules)  
**Agent:** `task`  
**Branch:** `task/psg-velocity/host-songview`  
**Worktree:** `30a-host-songview`  
**Base:** `RENDERING_SHA`

### Exclusive paths

- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/hostcheck.cpp`

### Deliver

Construct the accepted drawer and page modules in `SongView` and adapt them to
one shared host context/callback surface.  Pass through, rather than copy,
selected track, opaque shared `NoteId` selection, time zoom, horizontal scroll,
edit cursor, grid/snap, track colour, voice context, document attachment,
revision/remap/document-change notifications, Undo/Redo, and playback state.
Route page-local cosmetic state through `EditorViewState`/sidecar callbacks and
song edits through `SongDocument`; do not duplicate page drawing, selection,
gesture, sidecar, layout, or PSG logic.

Supply raw `double` playhead and voice-context inputs through the neutral
`EditorPageContext`; for every drawer lookup, consume and forward the result
of packet 11's sole static
`uint64_t EditorPageContext::drawerContextTick(double)` helper to hosted
pages. `SongView` must not round or truncate drawer ticks itself.

The velocity callback forwards the page's complete revisioned request—expected
document revision, exact `NoteId` bindings, and proposed values—to
`SongDocument`'s atomic batch mutation without reconstructing selection from
tick/key.  It handles three results precisely: an accepted mutation refreshes
from the resulting document state; a no-op leaves document revision, MIDI,
Undo, and shared selection unchanged; and a stale rejection applies none of
the batch, terminates the live page gesture through its established lifecycle
route, and refreshes only from current shared/document state.  This adapter is
the concrete host proof for **CORE-03**'s revision forwarding, no-op filtering,
stale rejection, selection continuity, and exact Undo; it does not redefine
document mutation semantics.

Route safe gesture termination to the visible hosted page on page switch/hide,
drawer close/hide, selected-track/song/document/voice replacement, every
document mutation including Undo/Redo/reload/replacement, mouse-grab loss,
window deactivation, and Escape.  The page alone restores staged document or
selection snapshots, clears preview/hover/cursor/grab state, and retains
already-applied pan/resize state.  `SongView` supplies no competing gesture
cancellation path.

Supply dynamic-band requests to 30C whenever roll/drawer visibility, page,
height, resize, scroll, or zoom changes.  Each request describes the current
roll and every visible page band from resolved gutter/plot origin and live
bounds; zero usable plot width produces no gutter-spanning band.  30A never
paints playhead content.

`hostcheck.cpp` supplies 30A's individual focused proof seam, including the
revisioned velocity cases above, full lifecycle routing, sidecar attach/save
boundaries, focus return, and the cross-agent band/overlay counters.  The
coordinator composes that public seam with the two other sentinel checks only
in the merged aggregate command.  It may use public page test
counters/adapters only; it does not own page-specific checks.

## 30B — MainWindow routing and persistence

**Worktree Operator:** `git-operations-runner` (creates/verifies worktree at exact `ADAPTER_SHA`, including submodules)  
**Agent:** `task`  
**Branch:** `task/psg-velocity/host-mainwindow`  
**Worktree:** `30b-host-mainwindow`  
**Base:** `ADAPTER_SHA`

### Exclusive paths

- `src/mainwindow.h`
- `src/mainwindow.cpp`
- `src/tabcheck.cpp`
- `src/sessioncheck.cpp`
- `src/mainwindowroutingcheck.cpp`

### Deliver

Own one `Qt::WindowShortcut` route for unmodified `A` and one for unmodified
`V` per top-level window.  Each acts and announces only through the active
`SongView`; inactive tabs do neither.  Disable both while that active tab shows
the raw MIDI event list, and preserve exact specification tooltips and
shown/hidden status text.

Route only through public `SongView` drawer/persistence methods: do not call
page, sidecar, rendering, or document internals.  Preserve the required focus
policy—tabs, drawer stack, and automation scroll container are non-focusable;
canvases use click focus; switching requests the newly visible canvas; and a
focus-owning drawer close returns focus to main content.  Keep selected page
and drawer height across tab switch/close/hide while requesting the public
scrollbar/overlay updates.

Call the public persistence route only at tab close, project switch, song
replacement, and application close.  It must decode only after song/document
attachment, merge-encode view state at those boundaries, preserve sidecar
behavior, and never save on drag, alter MIDI for view-only state, or create a
view-only Undo entry.

`mainwindowroutingcheck.cpp` is 30B's dedicated focused-check source and the
new sentinel for `--check-mainwindow-routing`.  It covers this task's public
MainWindow-to-`SongView` routing without replacing the named existing
`--tabcheck` or `--sessioncheck` routes.

## 30C — Rendering and playhead

**Worktree Operator:** `git-operations-runner` (creates/verifies worktree at exact `PRODUCT_SHA`, including submodules)  
**Agent:** `task`  
**Branch:** `task/psg-velocity/host-rendering`  
**Worktree:** `30c-host-rendering`  
**Base:** `PRODUCT_SHA`

### Exclusive paths

- `src/ui/timelinesurface.h`
- `src/ui/timelinesurface.cpp`
- `src/ui/playheadoverlay.h`
- `src/ui/playheadoverlay.cpp`
- `src/renderingplayheadcheck.cpp`

### Deliver

Expose a generic dynamic timeline-band update API for callers that own live
bounds.  Maintain the current set of bands and present routine playback through
`PlayheadOverlay` only.  Do not make `TimelineSurface` infer drawer geometry,
reach into pages, or add static bands.

A steady playhead tick updates overlay presentation only.  It must not build or
invalidate automation/velocity content.  Keep content diagnostics and
invalidation boundaries observable for the host proof: edits, selection,
zoom/scroll, resize, theme, document, and voice-context changes still reach
only their affected page through its established invalidation path.  Preserve
follow-scroll pause during a drawer gesture and resume on either commit or
cancellation without changing the frozen coordinate system.  Honor normal
widget update regions; do not restore broad paint culling.

`renderingplayheadcheck.cpp` is 30C's dedicated focused-check source and the
new sentinel for `--check-rendering-playhead`.  It proves this task's public
dynamic-band and overlay contract without adding a duplicate host alias.

## Non-negotiable cross-contracts

- **30C → 30A:** 30C exposes only the generic dynamic-band update API and the
  overlay/content diagnostic seams.  30A supplies current roll and
  visible-page bands; 30C does not calculate them from drawer/page internals.
- **30A → 30C:** 30A supplies current resolved bands and never paints playhead
  content or invalidates page content for a steady playback tick.
- **30B → 30A:** 30B calls only public `SongView` drawer/persistence methods.
  It neither accesses page/rendering internals nor duplicates lifecycle,
  selection, sidecar, or document behavior.
- **All agents:** use accepted product and foundation interfaces without
  editing their paths.  Packet 05 remains the sole registration owner.

## One coordinator-owned aggregate proof

Only on the normally merged host candidate, after all three sentinel checks
exist, run the packet-05 aggregate command exactly once:

```text
<porydaw> --check-host-integration <scratch-project> <song-a> <song-b> [screenshot]
```

Record that exact `HOST_SHA` candidate with its `PRODUCT_SHA`,
`RENDERING_SHA`, and `ADAPTER_SHA` predecessors, command/configuration,
fixture revision, isolated settings, and observed counters.  It must prove:

1. **CORE-03:** the exact revisioned `NoteId` batch reaches `SongDocument`;
   accepted values Undo exactly, a no-op has no revision/MIDI/Undo/selection
   effect, and stale input is rejected atomically with no partial mutation and
   no selection substitution.
2. **DRW-02**, **DRW-03**, **UX-01**, **UX-02:** a two-song active-tab
   exercise for `A`/`V`, event-list blocking, exact announcement routing, and
   focus return.
3. **LIFE-01:** every stated cross-module trigger reaches the visible page and
   switch/close preserves required view state without a second host gesture
   implementation.
4. **DRW-01**, **UX-11**, **PERF-01**, **UX-09:** open/closed/resized,
   zero-width, page-switch, scroll, and zoom bands; then 120 warmed-up
   playhead-only updates with no automation/velocity content-build increase
   and advancement to the requested final tick, followed by one edit,
   selection, zoom, and theme invalidation.
5. **DRW-04**, **DRW-05**, **UX-10:** attach and each save boundary route
   sidecar state without a MIDI diff or view-only Undo entry.

No task agent or reviewer reruns this aggregate proof or a full native matrix.
The final packet records this merged host-chain proof on the same `HOST_SHA`
rather than aliasing it. A failure routes to the exclusive owner—30C, 30A,
30B, or the owning earlier packet. For a repair, the coordinator runs only the
affected focused commands before all four final reviewers rerun; it reruns the
aggregate proof before that rereview only when the repair changes the aggregate
runner or cross-host behavior and that proof is affected. After all four approve
the replacement candidate, its post-approval final suite runs the aggregate
proof once on that same SHA.
