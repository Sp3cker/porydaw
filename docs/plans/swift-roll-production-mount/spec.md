# spec.md — Swift roll production mount: behavior contract

Wave 3 of the Swift backend track ([plan.md](plan.md)). This file fixes
the agreed behavior and the shared vocabulary; briefs cite it and never
restate it.

## §1 Scope and non-goals

The Swift note grid renders a real `SongDocument` inside the production
window, read-only, behind `PORYDAW_SWIFT_ROLL=1`. Non-goals (this wave,
explicitly): key delivery to Swift, Swift-originated edits, undo crossing,
selection sharing, popup sessions, pitch editing surfaces, TimeCamera /
Grid / PitchBendKernel numeric work, any user-visible surface without the
flag. Flag off = zero behavior change, zero load-time cost beyond a linked
library.

## §2 The `sgd_` snapshot ABI

C ABI, declared in `src/ui/songview/quick/swiftgrid/document_feed.h`,
prefix `sgd_` (sibling of `sgm_`/`sgp_`/`sga_`/`sgw_`). Values only; no
Qt types, no pointers except the ABI context (charter S-2).

```c
typedef struct {
    int32_t trackIndex;
    int32_t key;            // MIDI note number
    int32_t onTick;         // document tick space
    int32_t durationTicks;
    int32_t velocity;       // 0..127
} SgdNote;

typedef struct {
    int32_t startTick;      // tick where the signature takes effect
    int32_t numerator;
    int32_t denominator;
} SgdTimeSignature;

typedef struct {
    uint64_t documentId;    // SongDocument::documentState identity value
    uint64_t revision;      // SongDocument::revision()
    int32_t ticksPerBeat;   // SongDocument clock base
    int32_t trackCount;
    int32_t noteCount;      // notes across ALL tracks
    int32_t timeSignatureCount;
} SgdDocumentHeader;

typedef void (*SgdDeliveryFn)(const SgdDocumentHeader *header,
                              const SgdNote *notes,
                              const SgdTimeSignature *signatures,
                              void *context);

void sgd_set_delivery(SgdDeliveryFn fn, void *context);   // Swift registers
void sgd_clear_delivery(void);
```

Delivery contract:

- **Push, host-initiated.** The C++ `SwiftGridDocumentFeed` connects
  `SongDocument::documentChanged()` and pushes one complete snapshot per
  emission (after every mutation, undo, redo — matching the signal's
  documented meaning). No polling, no pull.
- **Monotonic guard.** Swift applies a snapshot only when
  `documentId` matches the loaded document and `revision` is strictly
  greater than the applied one; otherwise it drops it silently. First
  delivery for a new `documentId` always applies. This mirrors the
  `PendingHeaderMenu` identity+revision pattern (charter S-2).
- **Ordering.** Deliveries arrive on the GUI thread
  (`Qt::QueuedConnection` is not required; `documentChanged` is emitted
  there). The struct arrays are valid only during the call — Swift copies
  before returning.

## §3 Read-only grid mode

`PianoGrid.readOnly: Bool` (default `false`). While `true`:

- Every mutation entry point is inert and returns without state change:
  note add/move/resize commit paths, controller edits, pitch editor
  opening, menu actions, `escapePressed` arbitration still resolves but
  its teardown branches are no-ops (nothing is open).
- Alive and unchanged: pan, zoom, hover highlighting, keyboard-gutter
  hover preview, palette/typography, raster geometry, note rendering.
- `GridUndo` never records; revision stays whatever the feed delivered.
- The existing fixture path and all prototype smoke rows must behave
  identically with `readOnly == false`.

## §4 Production mount

- Flag: `PORYDAW_SWIFT_ROLL` env var, read once at
  `TimelineQuickView` construction via `qEnvironmentVariableIsSet`.
- Mount: a `SwiftRollOverlay` QML item (qrc-embedded from the prototype
  dir by the Task 1 library target) loaded into the production window's
  `contentItem`, sized to the roll band geometry, opaque background,
  `focusPolicy: Qt.NoFocus`, absorbs pointer events without forwarding.
  It renders the notes of `SongView::selectedTrack` (ghosting other
  tracks is out of scope; other tracks' notes are not delivered to the
  scene layer).
- Track-follow: overlay listens to `SongView::selectedTrackChanged(int)`
  and re-filters the applied snapshot (all notes are in the snapshot;
  filtering is client-side by `trackIndex`).
- The overlay is created only when the flag is set AND the platform is
  APPLE; teardown follows `detachWindow()` idempotently with the existing
  window lifecycle.
- `SwiftGridDocumentFeed` is constructed at the mount point with the
  `SongDocument` the view renders, and destroyed with the mount.

## §5 Acceptance surfaces

- `swiftdocfeed` harness: fixture `.mid` → `SongDocument` → snapshot
  contents (note counts, values, time signatures), revision monotonicity
  (mutation, undo, redo each deliver revision+1), stale-drop (out-of-order
  delivery is dropped), first-delivery-for-new-document applies.
- `swiftrollgated` harness: `WorkspaceUi` boot with the flag, overlay
  present, rendered note count equals the fixture song's selected-track
  note count, track switch re-filters, C++-side mutation reaches the
  overlay (revision delivered), pointer press on the overlay changes no
  document state and no focus.
- Existing surfaces unchanged: prototype smoke row outcomes, selectionkey,
  rollcheck-static.
