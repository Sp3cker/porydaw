# Ordinary-edit note-pair integrity

## Invariant and vocabulary

A **span** is a half-open note interval `[start,end)` on one engine track and pitch. A **participant** is a note whose final geometry the current semantic edit computes, identified by its stable NoteId; every note an edit inserts, moves or resizes is a participant, including a per-pitch destination that equals the note's current pitch. A **stationary note** is any note outside the participant set. An **unmatched release** is a Note Off (including velocity-zero Note On) not claimed by a note in the document projection.

Starting with a clean, terminated, non-overlapping same-pitch note stream, semantic edits must not introduce unmatched releases, unterminated notes, zero-length notes, or shared release ownership. Each accepted note has a positive duration and one unique ending; same-track/same-pitch spans are disjoint. Different pitches/tracks may overlap. Adjacent spans are legal, with the existing end-before-start ordering at their shared tick.

`notesForTrack` pairs each Note On with the first subsequent same-channel/same-key release. Two overlapping intended spans therefore cannot be stored as independent notes under the existing interpretation. Keep this interpretation unchanged; it governs raw projection and import rendering, not what semantic edits must admit.

## Collision policy: uniform atomic refusal

There is exactly one rule. Every semantic edit — `addNote`, `addNotes`, `moveNotes`, `moveNotesToPitches`, `resizeNotes`, `resizeNotesLeft`, `applyRangeEdit`, `moveRange`, `TimeEditor::remove` — computes its final half-open participant spans first. Within each (engine track, pitch), those final spans must be pairwise disjoint among themselves and disjoint from every stationary span; participants are exempted from the stationary set by NoteId. Any violation — participant-participant overlap, participant-stationary overlap, or an identical duplicate span — refuses the entire edit before history/publication. On refusal nothing changes: no document bytes, tempo, track list, note identity, velocity, revision, save-state token, undo stack or redo availability; `moveNotesToPitches` returns false, existing void mutations simply return, no empty command is pushed, nothing is published.

The policy has no other clauses. No stationary note is ever trimmed, shortened, moved or removed by an edit it did not belong to. Grouped resizes are never capped. Identical duplicate spans are never admitted, which also removes the former plain-paste-versus-range-paste inconsistency. No winner is invented for equal starts.

Two mechanical rules already implemented remain: tick-overflow admission refuses edits whose computed ticks overflow, and zero-length final spans refuse (`addNote`/`addNotes` still normalize a requested zero duration to one tick before admission). Zero-delta commands produce no history.

## Stable identity

NoteIds survive every semantic edit, including per-pitch and scale-fold moves: a moved note's own on/end events are rewritten in place, never reminted through insert ops, so per-pitch and ordinary moves share one builder discipline. Unterminated selected notes move their patched note-on under per-pitch transpose instead of staying behind. Exempting participants from the stationary set by NoteId is valid only because identity is stable; nothing in this plan remints notes.

## Source-derived failure geometries

Each row is a code-derived corruption mode of the pre-change behavior; under the single rule, each must refuse atomically and each is a required runtime-proof case:

| Path | Minimal geometry / required outcome |
| --- | --- |
| Grouped right resize | Same-pitch `[0,10)`, `[20,30)`, duration delta +20 would emit `[0,30)`, `[20,50)`; both starts would claim release 30, leaving release 50 unmatched. Refuses; both notes keep `[0,10)` and `[20,30)`. |
| Grouped left resize | Same-pitch `[20,30)`, `[40,50)`, left delta −30 creates overlap after clamping. Refuses. A single-note resize that would reach a stationary note refuses equally. |
| Move/pitch collapse | Overlapping notes on pitches 1 and 2 with key delta −2 clamp onto pitch 0; tick-zero clamping can collapse two separated same-pitch notes; per-pitch destinations can converge. All refuse, including when one converging destination equals its note's current pitch. |
| Batch insertion / range replacement | Two incoming same-pitch spans overlap — within one batch, across separate TrackNotes groups for one destination, or into newly planned tracks of an empty original SMF. The combined eligible destination set refuses as one unit, together with track creation, removals, lane writes and tempo. |
| Delete Time | Same-pitch A `[0,100)`, B `[110,120)`; removing `[20,50)` would shift B to `[80,90)` onto A. Refuses; non-colliding ripple delete is unchanged. Both deleted and shifted notes are participants exempted by `NoteId`; only notes starting before the range are stationary, so a shifted note longer than the deleted span — its final span overlapping only its own old span — is accepted. |
| Range movement | Per-event tick clamping stays, but the exact clamped endpoints that will be emitted are planned and validated. A paired span collapsed to zero rejects with the mixed command untouched; surviving clamped spans must still satisfy the single rule. |

These examples are evidence from code inspection, not claims of measured trigger frequency. No imports or deliberately malformed raw editing are needed. Incoming malformed clipboard content is covered at the existing batch interface without extending this into import repair.

## Undo semantics

Planning is side-effect-free and produces op plans or refusal; commands are constructed from prebuilt ops, and admission happens before any command is pushed. Undo merging replans from gesture originals: candidate ops are computed before any revert of the already-applied state, so a failed or incompatible rebuild returns false with the document untouched by construction — no restore dance. Overflow guards in each `mergeWith` remain. Accumulated-delta compatibility loops for `moveNotes` and `resizeNotes` remain, and because clamping does not compose additively a merge commits only when the accumulated candidate geometry exactly equals the already-applied sequential final geometry per `NoteId`; any mismatch leaves the two accepted commands separate. Per-pitch merges match by `NoteId`, and incoming destinations stay bound to the incoming notes' `NoteId`s — a reordered second call realigns destinations to the original note order or refuses. Unterminated per-pitch participants obey the same start-tick overflow refusal as terminated ones. Clean-index barriers and true net-zero cancellation keep their existing behavior. There are no realized-duration stores hidden behind the visible geometry.

## User-visible outcomes

An edit that would make any same-pitch note overlap another is refused; nothing changes. During a resize drag the roll keeps showing the attempted geometry from the gesture delta — preview stays pure UI arithmetic, with no document preview API — and snaps back to unchanged document geometry when a refused commit leaves the revision unchanged. Single-note resize into free space and edits that create adjacency are unaffected.

Rejected plain or range paste does not clear selection, advance the edit cursor, scroll to a fictitious result, or emit a success announcement. Success-only view effects are gated on document revision change around the existing mutation, matching existing keyboard command practice; no new public result type, dialog or status channel.

For range nudging, the intentional rule that a selection band over empty content moves is preserved; a nonempty gathered edit refused by the document leaves the band unchanged. The same revision-based guard applies to time-selection transpose before result scrolling/announcement.

## Preservation and non-goals

Keep all existing public SongDocument mutation signatures; only private planning return types change, as specified in the briefs. Preserve event payloads, velocities, channel/track isolation and the `notesForTrack` interpretation. Raw Event List operations remain raw; pre-existing malformed/shared-end material is neither cleaned nor reinterpreted; unrelated raw bytes outside an accepted edit remain untouched. Do not assert the clean-song invariant globally over arbitrary imported data.

`insertBlankTime` and `duplicateTimeRange` are retained: their clean-note seam split and uniform shift preserve separation. Track duplication creates a separate track and needs no intra-track collision repair. Ordinary note deletion and nonzero velocity editing do not create geometric overlap.
