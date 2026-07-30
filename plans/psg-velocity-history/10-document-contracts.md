# 10 — Note identity, document mutation, and view projection

This packet is an ordered identity/document/projection chain: 10A first; 10B
and packet 11 then run independently from `NOTE_ID_SHA`; and 10C starts only
after approved 10B work yields `DOCUMENT_SHA`. Task agents write
implementation, focused coverage, and one commit, but do **not** run builds,
tests, formatters, or linters. The coordinator runs the named focused command
once per completed task; a `reviewer` agent then inspects the committed range.
All handoffs are ordinary merges into `feature/psg-velocity-history-upstream`,
never cherry-picks or staged-tree transport.

## 10A — Note identity transport

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/note-identity`  
**Worktree:** `10a-note-identity`  
**Base:** `INFRA_SHA`.

`git-operations-runner` creates/verifies the `10a-note-identity` worktree and `task/psg-velocity/note-identity` branch from the exact `INFRA_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

### Exclusive paths

1. `src/core/noteid.h` (new)
2. `src/core/smf.h`
3. `src/core/miditimeline.h`
4. `src/core/miditimeline.cpp`
5. `src/noteidcheck.cpp` (new)

This is the sole owner of identity transport. It must not edit `SongDocument`, any
UI path, registration, layout, model/axis, or host code.

### Contract

Define an opaque, transient `NoteId`. 10A adds the new `noteidcheck` harness
and only carries an unset identity slot from each SMF note-on through
`TimelineEvent`; it does not mint an ID. 10B is the sole minting owner.
Transport must not change MIDI serialization, SMF equality, or the value
meaning of pre-existing MIDI data. It must distinguish equal `(track, tick,
key)` note-ons once 10B assigns their IDs. `noteidcheck` establishes that an
unset/transient transport identity is never serialized or compared as MIDI
data.

### Edge cases and focused evidence

An unassigned identity must remain explicit rather than being confused with a valid
ID; repeated or duplicate note-ons must retain separate transport slots; and
serialization/equality must produce the same result with or without transport IDs.
The coordinator runs `porydaw --check-note-identity <scratch-project>` once
after the 10A commit.

A `reviewer` approves the exact committed range against `INFRA_SHA`. The coordinator
merges the approved head normally and records the resulting integration commit as
`NOTE_ID_SHA`. There is no `FOUNDATION_SHA` yet.

## 10B — Document mutation

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/document-contracts`  
**Worktree:** `10b-document-contracts`  
**Base:** `NOTE_ID_SHA`, after 10A is approved and merged.

`git-operations-runner` creates/verifies the `10b-document-contracts` worktree and `task/psg-velocity/document-contracts` branch from the exact `NOTE_ID_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

### Exclusive paths

1. `src/core/songdocument.h`
2. `src/core/songdocument.cpp`
3. `src/editcheck.cpp` — extend the existing upstream harness only with 10B's
   document-contract cases.

No UI path, registration file, layout/model source, or host source belongs here.

### Contract

10B is the sole owner of all production `SongDocument` identity, revision, velocity
batch, and `TrackRemap` semantics:

- Mint and preserve the opaque `NoteId` binding for an exact SMF track and note-on
  index; provide lookup by ID and revision-bound note address. Duplicate notes at one
  track/tick/key remain distinct.
- Provide a monotonic `SongDocument::revision()`. Successful mutation, load, Undo,
  and Redo increment it exactly once before remap and general document-change
  notification. Failed edits, no-ops, and view-only work do not increment it.
- Provide atomic `setNotesVelocities(expectedRevision, edits)`. Reject the whole
  batch before mutation for a stale revision or any stale/bad address; distinguish
  rejection from a successful no-op; deduplicate by SMF track/note-on index with last
  edit winning; clamp stored velocity to `1...127`; omit no-op writes; retain exact
  old values for one Undo command; and emit normal document/playback rebuild
  notifications only for a successful changing batch.
- Publish one complete `TrackRemap` after rebuilding the track map and before
  `documentChanged()`. It includes old-SMF-chunk-to-new and old-engine-slot-to-new
  mappings for move, insert, duplicate, delete, raw metadata-only↔engine-track
  transitions, Undo, and Redo. Use `-1` for deletion and suppress identity/no-op
  remaps.

A mutation, load, Undo, or Redo invalidates old revision-bound addresses. 10B does
not implement event-list anchoring, selection, mute/solo UI, follow-playhead, drawer,
automation, or velocity-page behavior.

### Edge cases and focused evidence

`editcheck` covers **CORE-01**, **CORE-02**, and the document half of
**CORE-03**: duplicate identity/edit/Undo; stale and bad-address all-or-nothing
rejection; last-write deduplication; clamping; no-op filtering; exact Undo;
revision timing; and every listed remap transition on apply/Undo/Redo, deletion
`-1`, suppression, and remap-before-document-change ordering. The coordinator
runs the existing `porydaw --editcheck <scratch-project>` command once after
the 10B commit.

A `reviewer` approves the exact committed range against `NOTE_ID_SHA`. The
coordinator normally merges the approved 10B head and records that integration
commit as `DOCUMENT_SHA`; only then may 10C start.

## 10C — View projection

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/note-projection`  
**Worktree:** `10c-note-projection`  
**Base:** `DOCUMENT_SHA`, after 10B is approved and merged. 10C therefore
runs after the real `SongDocument`-minted IDs are available, while packet 11
remains independently parallel with 10B from `NOTE_ID_SHA`.

`git-operations-runner` creates/verifies the `10c-note-projection` worktree and `task/psg-velocity/note-projection` branch from the exact `DOCUMENT_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

### Exclusive paths

1. `src/ui/songviewmodel.h`
2. `src/ui/songviewmodel.cpp`
3. `src/rollcheck.cpp`

10C must not edit `SongDocument`, the identity transport files, host seams,
registration, layout, model/axis, or concrete host components.

### Contract

Project the real `SongDocument`-minted `NoteId` into `ViewNote` without deriving
identity from track/tick/key. Characterize duplicate notes so
same-position/same-key notes preserve their distinct minted identities through
the view model. This is a projection only: it does not select notes, mutate a
document, assign IDs, supply Undo, create a timeline surface, or add a
drawer/page.

### Edge cases and focused evidence

`rollcheck` covers duplicate notes with equal visible MIDI fields, projection
of each separate minted identity, and ordinary notes with no assigned identity.
The coordinator runs the existing
`porydaw --rollcheck <scratch-project> <song-label> [screenshot]` command once
after the 10C commit.

## Review and integration handoff

10B and packet 11 are the only parallel tasks from `NOTE_ID_SHA`; their paths
are disjoint. The coordinator runs 10B's existing command and packet 11's
registered command once against their respective committed heads, then
independent `reviewer` agents inspect each exact range against `NOTE_ID_SHA`.
After 10B approval, its ordinary merge is `DOCUMENT_SHA`. Packet 11's approved
head is also merged normally, independently of that document handoff.

10C starts from `DOCUMENT_SHA`, so its `rollcheck` exercises IDs the document
actually minted rather than transport-only placeholders. After its command and
reviewer approval, the coordinator normally merges 10C. Once the approved 11
and 10C merges are both present with `DOCUMENT_SHA`, record that integration
result as `CONTRACT_SHA`.

The resulting contract guarantees that document-minted IDs and `ViewNote`
identities both exist, but it does not authorize host migration. Packets 14A
and 14B alone consume this contract from `CONTRACT_SHA` in parallel; foundation
integration is recorded only after 12A, 12B, 13, 14A, and 14B complete as
`FOUNDATION_SHA`.
