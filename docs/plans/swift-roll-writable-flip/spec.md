# spec.md — writable seam: behavior contract

Wave 4 of the Swift backend track ([plan.md](plan.md)). Fixes agreed
behavior; briefs cite it and never restate it.

## §1 Two command classes, one pipe

`sgc_` is a single submission entry. The C++ executor routes by enum,
Swift never chooses a path:

- **Document intents** — mutate the song; execute through the
  `SongDocument` command path onto `QUndoStack`. One intent = one
  undoable command. Resulting `documentChanged` → `sgd_` push.
- **Session intents** — `SongView` state: selection application
  (`EditorSelectionModel` setters), mute/solo masks
  (`SongView::setTrackMute`/`setTrackSolo`). No undo entries; state
  pushes via `sgs_`.

Submission is synchronous on the GUI thread and returns a result code:
`executed`, `rejectedInvalid` (malformed payload, stale `NoteId` token,
out-of-range fields), `rejectedUnavailable` (eligibility said no — the
policy-data answer, surfaced for arbitration). Rejection never mutates
anything.

## §2 Intent vocabulary (closed)

Document intents (undoable):

| Intent | Payload | Semantics |
| --- | --- | --- |
| `SGC_NOTE_ADD` | track, key, onTick, durationTicks, velocity | adds note; result carries the new `NoteId` token |
| `SGC_NOTE_MOVE` | `NoteId` token, deltaTicks (int64), deltaKeys (int32) | clamped per document rules (resize clamp, note-pair integrity — production semantics, C++-side) |
| `SGC_NOTE_MOVE_BATCH` | token list, deltaTicks (int64), deltaKeys (int32) | one gesture's uniform move: one `moveNotes` call, one undo entry (S-3) |
| `SGC_NOTE_RESIZE` | token, durationTicks | production clamp rules |
| `SGC_NOTE_RESIZE_BATCH` | token list, dDuration (int64, uniform) | one gesture's resize: one production batch call, one undo entry (S-3); `dDuration` is a duration DELTA, never an absolute duration — the payload mirrors production `resizeNotes` exactly |
| `SGC_NOTE_DELETE` | token list | one undo entry for the batch |
| `SGC_TRACK_ADD` / `SGC_TRACK_DUPLICATE` / `SGC_TRACK_DELETE` / `SGC_TRACK_REORDER` / `SGC_TRACK_RENAME` | track index / (index, newIndex) / (index, UTF-8 name, len) | production track-op semantics |

Session intents (no undo):

| Intent | Payload | Semantics |
| --- | --- | --- |
| `SGC_SELECTION_SET_NOTES` | token list (complete desired set) | Swift computes modifiers' effect from `sgs_` state; host applies wholesale |
| `SGC_SELECTION_CLEAR` | — | clears note selection |
| `SGC_TRACK_MUTE` / `SGC_TRACK_SOLO` | track, bool | routes to SongView setters |

Adding a verb requires amending this file first.

Amendment 2026-09-19 (controller, during Task 4): batch move/resize added
because single-note intents made multi-note gestures produce N undo entries,
violating S-3's one-gesture-one-entry rule.

## §3 `sgs_` session-state push (C++ → Swift)

Pushed on `EditorSelectionModel` observer transitions and mask-signal
changes. Payload: primary track, track scope mask, note-selection token
list, time selection (start/end/scope/lanes), mute mask, solo mask,
monotonic session revision. Reconciliation is host-owned: after undo,
redo, or track remap the pushed state reflects
`reconcileNoteSelection`/`applyRemap` results — Swift may hold tokens
that vanish; the next push is authoritative and Swift discards silently.
Stale-token intents are `rejectedInvalid`, never best-effort.

## §4 `sgk_` key delivery (C++ → Swift)

The host performs window-tier arbitration and registry matching exactly
as today (`keymap::Registry` + the `handleEditKey` successor path) and
delivers to the Swift band: command id (`SongView::EditCommand` value),
modifiers, autoRepeat flag, surface facts. Swift evaluates band-side
eligibility using `sgp_` policy data + `sgs_` state and returns
handled/not-handled; unhandled returns to the existing band fallback
order. No QKeyEvents, no QML shortcuts, no second dispatcher (INV-1/3).

## §5 Band graduation and flags

- `SwiftRollBand` — a C++ adapter implementing `TimelineBandInteraction`
  that forwards pointer/wheel/leave/key events into the Swift surface
  through the typed seams and owns gesture-active reporting. The Wave 3
  overlay's input absorption is replaced by this adapter when
  `PORYDAW_SWIFT_ROLL` is set; flags off keeps Wave 3 ship behavior.
- Gestures commit one intent (or one batch) at gesture end — live drag
  renders a preview Swift-side, the document mutates once. One gesture =
  one undo entry (S-3).
- Deviation (2026-09-19, Task 4 re-scope): the editing lane declines the
  left edge grip. A leading resize shifts every selected note's start by
  +d and its duration by −d, which the frozen §2 vocabulary carries only
  as per-note `noteMove`+`noteResize` pairs or as two batch intents — 2N
  or 2 undo entries against S-3. With no one-entry form and no
  executor-side coalescing (the C ABI is frozen for this milestone) the
  press is declined: no gesture opens, no intent crosses, and the
  flag-off C++ roll keeps its production leading resize
  (`resizeNotesLeft`) untouched. The trailing right-grip resize keeps its
  one-entry `SGC_NOTE_RESIZE_BATCH`. Closure: the deviation dies at the
  Swift-native transaction cutover, where one gesture is one transaction
  by construction.
- `PORYDAW_SWIFT_HEADERS` swaps the `TrackHeaderModel` presenter for the
  Swift presenter behind the same QML (`TrackHeaderBand.qml` unchanged;
  the Swift presenter mirrors the Q_PROPERTY surface). Rename drafting
  uses host-side text entry; commit is `SGC_TRACK_RENAME`.

## §6 Acceptance surfaces

- `swiftcommands`: every intent's validation matrix; undo granularity
  (one gesture = one entry); revision round-trip; session routing leaves
  the undo stack untouched.
- `swiftdocfeed` extension: transition payloads, mask pushes,
  post-undo reconciliation, stale-token rejection.
- `swiftbandkeys`: delivery + eligibility + gesture-active blocking +
  autoRepeat consumption + fallback order.
- `swiftrollgated` extension: flag-on edit → undo (production undo UI) →
  `sgd_` re-render; Escape arbiter rows through the real window.
- `swiftheadersgated`: presenter surface parity rows, mute/solo
  round-trip, rename commit, track ops undoable, revision guard holds.
