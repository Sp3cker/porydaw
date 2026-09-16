# Ordinary-edit note-pair integrity

## Invariant and vocabulary

A **span** is a half-open note interval `[start,end)` on one engine track and pitch. A **participant** is a note whose final geometry belongs to the current selected edit, including an unchanged selected note in a per-pitch move. A **stationary note** is outside that participant set. An **unmatched release** is a Note Off (including velocity-zero Note On) not claimed by a note in the document projection.

Starting with a clean, terminated, non-overlapping same-pitch note stream, semantic edits must not introduce unmatched releases, unterminated notes, zero-length notes, or shared release ownership. Each accepted note has a positive duration and one unique ending; same-track/same-pitch spans are disjoint. Different pitches/tracks may overlap. Adjacent spans are legal, with the existing end-before-start ordering at their shared tick.

`notesForTrack` pairs each Note On with the first subsequent same-channel/same-key release. Two overlapping intended spans therefore cannot be stored as independent notes under the existing interpretation. Keep this interpretation unchanged.

## Source-derived failures requiring runtime proof

| Path | Minimal geometry / failure |
| --- | --- |
| Grouped right resize | Same-pitch `[0,10)`, `[20,30)`, duration delta +20 emits `[0,30)`, `[20,50)`; both starts claim release 30, leaving release 50. |
| Grouped left resize | Same-pitch `[20,30)`, `[40,50)`, left delta -30 creates overlapping intervals after clamping. |
| Move/pitch collapse | Overlapping notes on pitches 1 and 2, key delta -2, both clamp to pitch 0; tick-zero clamping can likewise collapse two separated same-pitch notes. Per-pitch destinations can converge too. |
| Per-pitch unchanged participant | Selected overlapping-time notes on different pitches; one destination stays unchanged while the other moves onto it. `shouldSkip` omits the unchanged span, but `notes` exempts it from stationary trimming. It must participate in admission. |
| Batch insertion/range replacement | Two incoming same-pitch spans overlap. Existing overlap planning only checks incoming versus stationary, not incoming versus incoming. Validate the combined destination set, including separate TrackNotes groups for the same destination. |
| Delete Time | Same-pitch A `[0,100)`, B `[110,120)`; remove `[20,50)`. A currently stays unchanged while B becomes `[80,90)`, leaving A's release unmatched. |
| Range move at tick zero | Each raw endpoint clamps independently, but the planner uses shifted start plus original duration. Endpoints can both become zero; nonempty clamped spans can also cause excessive stationary trimming because the planned end is wrong. |

These examples are evidence from code inspection, not claims of measured trigger frequency. No imports or deliberately malformed raw editing are needed for the resize and ripple examples. Incoming malformed clipboard content is covered at the existing batch interface without extending this into import repair.

## Collision policy

1. **Grouped right-edge extension:** cap each earlier selected same-track/same-pitch note's requested end at the next selected note's start. Compute each cap independently; do not reduce the whole group's delta. Keep starts, IDs and velocities unchanged, and let the final note extend normally. For `[0,10)`, `[20,30)` with duration delta +20, accept `[0,20)`, `[20,50)`. The capped spans, not the attempted spans, drive event emission and stationary overlap resolution. Input order must not matter. This user-specified rule replaces whole-batch rejection for right-edge extension; other operations still reject unrepresentable participant collisions (including equal-start collisions), rather than invent a winner. Adjacency accepts.
2. **Participants versus stationary:** preserve existing edited-note-wins behavior. A stationary note keeps its head, keeps its tail, or is removed if covered; never split it. Gate participant representability before planning any stationary mutation.
3. **Atomic refusal:** no document bytes, tempo, tracks, note identities, revision, save-state token, undo stack or redo availability change. `moveNotesToPitches` returns false. Existing void mutations simply return. Do not push an empty command or publish a mutation on rejection.
4. **Delete Time:** shifted paired notes are participants; notes removed by the range are excluded from stationary victims. Notes starting before the range are stationary. Reconcile collisions with the same edited-note-wins rule. The example becomes A `[0,80)`, B `[80,90)`, in one undo command. Noncolliding earlier notes stay unchanged; this is not a general time-cropping redesign.
5. **Range movement:** keep the existing per-event tick clamping, but plan exactly the endpoints that will be emitted. Reject a paired span collapsed to zero. Do not silently switch range movement to duration-preserving clamping. Mixed notes, automation and tempo remain one atomic operation.
6. **Limits/no-ops:** retain existing tick-overflow admission and zero-delta guards. `addNote`/`addNotes` still normalize requested zero duration to one tick before admission. No new arithmetic overflow, silent wrapping or spurious history on unchanged commands.
7. **Undo:** store realized resize durations, not just original duration plus requested delta. Subsequent presses operate on the visible capped result; there is no hidden extension debt when the user shortens again. Merge only when replanning from gesture originals produces exactly the already-applied two-command participant geometry. If admission fails or candidate geometry differs, restore the already-applied state and refuse the merge without changing either command's stored fields. Compatible capped presses still merge, clean-index barriers remain, and an inverse sequence that truly restores original geometry removes the net-zero command and restores intermediate stationary trims. Do not assume clamping composes additively.

## User-visible outcomes

Grouped extension succeeds with earlier selected notes stopping at the next selected start; later notes continue extending normally. A fully capped resize that changes nothing produces no history/publication. Other unrepresentable participant edits remain no-ops, with a rejected drag returning to unchanged document geometry on release. No new collision popup/status system is introduced.

Rejected plain or range paste must not clear selection, advance the edit cursor, scroll to a fictitious result, or emit a success announcement. Use the document revision around the existing mutation, matching existing keyboard command practice; no new public result type is necessary.

For range nudging, preserve the intentional rule that a selection over empty content moves. A nonempty gathered edit rejected by the document must not move its selection band. A successful edit keeps existing view behavior. Apply the same revision-based success guard to time-selection transpose before result scrolling/announcement.

## Preservation and non-goals

Keep all existing public SongDocument mutation signatures, except private planning return types specified in the brief. Preserve event payloads, velocities, existing identity rules and channel/track isolation. Raw Event List operations remain raw; pre-existing malformed/shared-end material is neither cleaned nor assigned a new interpretation. Unrelated raw bytes outside an accepted edit remain untouched. Do not assert the clean-song invariant globally over arbitrary imported data.

`insertBlankTime` and `duplicateTimeRange` are retained: their clean-note seam split and uniform shift preserve separation. Add targeted regression coverage rather than another normalization pass. Track duplication creates a separate track and does not require intra-track collision repair. Ordinary note deletion and nonzero velocity editing do not create geometric overlap.
