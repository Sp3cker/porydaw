#pragma once

#include <QObject>
#include <QString>
#include <QUndoStack>
#include <algorithm>
#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

#include "core/noteid.h"
#include "core/smf.h"
#include "core/songhistory.h"
#include "core/tempo.h"
#include "core/timedefaults.h"
#include "core/tracklimits.h"
#include "core/xcmd.h"
#include "project/decompproject.h"

class MidiTimeline;

// Pseudo-CC numbers for lanes that aren't controller-backed.
constexpr uint8_t DOC_CC_BEND = CoreTimeDefaults::kLaneCcBend;
constexpr uint8_t DOC_CC_VOICE = CoreTimeDefaults::kLaneCcVoice;
constexpr uint8_t DOC_CC_ECHO_VOLUME = xcmd::kEchoVolumeLane;
constexpr uint8_t DOC_CC_ECHO_LENGTH = xcmd::kEchoLengthLane;

// Loop markers as mid2agb reads them: a text-type meta (0x01-0x07) whose
// content, truncated to 32 bytes and whitespace-trimmed, is the single
// marker character. Matches MidiTimeline::build.
bool metaIsLoopMarker(const SmfEvent &ev, char marker);

// True for names mid2agb would read as a loop/label command instead of a
// name — it accepts ANY text-type meta (0x01-0x07, Track Name included)
// in the seq chunk whose whole text is one of these.
bool nameIsLoopMarker(const QString &name);

// Maps every pre-mutation SMF chunk and engine slot to its post-mutation
// owner. A value of -1 means the old owner was deleted or stopped being an
// engine track. The post-mutation counts identify inserted owners.
struct TrackRemap {
    std::vector<int> smfTrackMap;
    std::vector<int> engineTrackMap;
    int newSmfTrackCount = 0;
    int newEngineTrackCount = 0;

    bool isIdentity() const;
    TrackRemap inverse() const;
};

// A detached MIDI/config image and the monotonic state tokens that identify
// the document state from which it was captured. The tokens are checked only
// on the GUI thread after the worker has completed both disk stages.
struct SongSaveSnapshot {
    SmfFile smf;
    QString midPath;
    QString label;
    SongCfg cfg;
    bool flagsNeeded = false;
    uint64_t revision = 0;
    uint64_t saveStateToken = 0;
    DocumentStateIdentity documentState;
};

// A note located in the SMF model: the note-on event plus the event that ends
// it, paired exactly as mid2agb pairs them (first same-channel same-key
// note-off or velocity-0 note-on after the note-on).
struct DocNote {
    NoteId noteId;
    int engineTrack = -1;
    int smfTrack = -1;
    size_t onIndex = 0;
    size_t endIndex = SIZE_MAX; // SIZE_MAX = unterminated note-on
    uint64_t tick = 0;
    uint32_t duration = 0; // ticks (0 when unterminated)
    uint8_t key = 0;
    uint8_t velocity = 0;
    uint8_t channel = 0;

    bool unterminated() const { return endIndex == SIZE_MAX; }
};

// An automation point (CC, pitch bend, or voice change) located in the SMF
// model. Same staleness rule as DocNote.
struct DocLanePoint {
    int smfTrack = -1;
    size_t index = 0;
    uint64_t tick = 0;
    int value = 0; // CoreTimeDefaults::laneValueMinimum/Maximum
};

// Tempo-only mutation. Mixed time/range commands apply a typed Tempo payload
// through replaceTempoPoints inside their own redo; they must not call
// applyTempoEdit (that would push a second undo item).
struct TempoEdit {
    std::vector<TempoPoint> remove;
    std::vector<TempoPoint> add;

    bool empty() const { return remove.empty() && add.empty(); }
};

// A time-signature event (meta 0x58) located in the SMF model. Same
// staleness rule as DocNote.
struct DocTimeSig {
    int smfTrack = -1;
    size_t index = 0;
    uint64_t tick = 0;
    uint8_t numerator = 4;
    uint8_t denomPow2 = 2; // denominator = 1 << denomPow2
};

// The editable song document (SPEC.md §4): a full-fidelity SMF model plus the
// song's midi.cfg properties, with every mutation undoable. The .mid file is
// canonical storage; saving writes it plus (when changed) the song's midi.cfg
// line — nothing else in the project is ever touched.
class SongDocument : public QObject
{
    Q_OBJECT

  public:
    explicit SongDocument(QObject *parent = nullptr);

    bool load(const SongInfo &song, QString *error);
    bool adoptSmf(SmfFile smf, const SongInfo &song, QString *error);
    bool save(QString *error);
    SongSaveSnapshot captureSaveSnapshot() const;
    void didSave(const SongSaveSnapshot &snapshot, bool flagsWritten);

    const QString &midPath() const { return m_midPath; }
    const QString &label() const { return m_label; }
    const SmfFile &smf() const { return m_smf; }
    const std::vector<TempoPoint> &tempoPoints() const { return m_tempoPoints; }
    const SongCfg &cfg() const { return m_cfg; }
    QUndoStack *undoStack() { return &m_undoStack; }
    // The one SongHistory interface over this document's undo stack; tabs
    // re-export it unchanged and no second stack or identity space exists.
    SongHistory &history() { return m_history; }
    const SongHistory &history() const { return m_history; }
    bool isDirty() const
    {
        return m_history.currentDocumentIdentity() != m_history.savedDocumentIdentity();
    }
    uint64_t revision() const { return m_revision; }

    // The song's clock base for snapping: ticks per mid2agb clock. mid2agb
    // rescales everything to 24 (or 48 with -X) clocks/beat; finer positions
    // are quantized away by the build, so the editor snaps to this grid.
    // Always >= 1.
    uint32_t ticksPerClock() const;

    // Engine-track mapping (mirrors MidiTimeline::build).
    int engineTrackCount() const { return int(m_engineToSmf.size()); }
    int smfTrackFor(int engineTrack) const;
    uint8_t channelFor(int engineTrack) const;

    // Tracks this song's music player allocates in-game (DecompProject::
    // trackBudgetFor, set by the owner after load). MPlayStart never starts
    // tracks at or beyond this index, so the UI warns that they can be
    // incompatible in-game. Editing and Porydaw playback are never gated on
    // it. Defaults to track_limits::kHardwareCapacity.
    int trackBudget() const { return m_trackBudget; }
    void setTrackBudget(int budget)
    {
        m_trackBudget = std::clamp(budget, 0, track_limits::kHardwareCapacity);
    }

    // Lookups. NoteId is the stable identity for note selection and velocity
    // mutation; physical event locations remain document-owned details.
    std::vector<DocNote> notesForTrack(int engineTrack) const;
    // The ids of the track's current notes that were not in the before
    // snapshot — what an insert (draw commit or paste) added.
    std::vector<NoteId> insertedNoteIds(int engineTrack, const std::vector<DocNote> &before) const;
    bool findNote(int engineTrack, uint64_t tick, uint8_t key, DocNote *out) const;
    bool findNote(NoteId id, DocNote *out) const;
    uint64_t noteEndTick(const DocNote &note) const;
    bool containsNoteSpan(int engineTrack, const DocNote &snapshot, uint64_t expectedEndTick) const;
    std::vector<DocLanePoint> lanePoints(int engineTrack, uint8_t cc) const;
    bool findLanePoint(int engineTrack, uint8_t cc, uint64_t tick, DocLanePoint *out) const;
    // Loop markers ('[' / ']' text metas); UINT64_MAX when absent.
    uint64_t loopTick(bool endMarker) const;
    // Time signatures (meta 0x58), sorted by tick. When several share a tick
    // the last one is the one the bar grid honors.
    std::vector<DocTimeSig> timeSigs() const;

    // Edits that change document state each push one undoable command and emit documentChanged.
    void addNote(int engineTrack, uint64_t tick, uint8_t key, uint32_t duration, uint8_t velocity);
    // Batch insert (clipboard paste): all notes land in one undoable command.
    struct NewNote {
        uint64_t tick;
        uint8_t key;
        uint32_t duration;
        uint8_t velocity;
    };
    void addNotes(int engineTrack, const std::vector<NewNote> &notes);
    void deleteNotes(const std::vector<DocNote> &notes);
    // Move by a tick/key delta (note lengths preserved). mergeable marks a
    // keyboard transpose/nudge press: consecutive mergeable moves of the
    // same notes collapse into one undo command that re-lands from the
    // gesture's start, so a neighbor trimmed by a merely-passed-through
    // overlap comes back (only the final resting position trims). An inverse
    // merged press restores the start and removes that command, but still
    // publishes the current-state mutation. Mouse gestures stay one command
    // per drag.
    void moveNotes(const std::vector<DocNote> &notes, int64_t dTick, int dKey,
                   bool mergeable = false);
    // Batch move with per-note destination pitches. Each note moves from its
    // current key to the corresponding destKey (destPitches[i] for notes[i]).
    // dTick is the common time delta (0 for pitch-only moves). mergeable works
    // identically to moveNotes. All notes must belong to the same engine track.
    // Returns false and pushes nothing if any destKey is outside 0-127.
    bool moveNotesToPitches(const std::vector<DocNote> &notes,
                            const std::vector<uint8_t> &destPitches, int64_t dTick,
                            bool mergeable = false);
    void resizeNotes(const std::vector<DocNote> &notes, int64_t dDuration);
    // Left-edge resize: move the note-on by dTick with the note-off pinned
    // (tick and duration adjust together, at least 1 tick of note remains).
    void resizeNotesLeft(const std::vector<DocNote> &notes, int64_t dTick);
    void setNotesVelocity(const std::vector<DocNote> &notes, uint8_t velocity);
    std::optional<uint64_t> setNotesVelocities(uint64_t expectedRevision,
                                               const std::vector<NoteVelocity> &velocities);

    // Relative velocity change, clamped to 1-127 per note.
    void nudgeNotesVelocity(const std::vector<DocNote> &notes, int delta);

    void addLanePoint(int engineTrack, uint8_t cc, uint64_t tick, int value);
    // Gesture write (freehand sweep / line ramp): replaces every point of the
    // lane inside [tickBegin, tickEnd] with the given stream, as one undoable
    // command. Not for DOC_CC_VOICE (the voice row has no drag editing).
    struct LanePointValue {
        uint64_t tick;
        int value;
    };
    void writeLanePoints(int engineTrack, uint8_t cc, uint64_t tickBegin, uint64_t tickEnd,
                         const std::vector<LanePointValue> &points);
    struct LanePointMove {
        int engineTrack = -1;
        uint8_t cc = 0;
        DocLanePoint point;
        uint64_t newTick = 0;
        int newValue = 0;
    };
    // Descriptor-lane identities (point.index) are trusted: callers resolve
    // them fresh, and the canonical plan re-validates every identity — a
    // stale one rejects the whole command before anything is pushed.
    void moveLanePoints(const std::vector<LanePointMove> &moves);
    // Same identity-trust rule as moveLanePoints for descriptor lanes.
    void deleteLanePoints(int engineTrack, uint8_t cc, const std::vector<DocLanePoint> &points);
    void applyTempoEdit(const TempoEdit &edit);
    // Removes raw events and edits the global tempo stream as one undoable
    // mutation. Both payloads refer to the current document state.
    void removeRawEventsAndEditTempo(const QString &text, int smfTrack,
                                     std::vector<size_t> rawIndices, const TempoEdit &tempo);
    // Replaces one projected Tempo point with one raw event in one undoable
    // mutation. The point is addressed by tick in the current Tempo stream.
    void replaceTempoPointWithRawEvent(const QString &text, int smfTrack, const TempoPoint &point,
                                       SmfEvent event);
    // Multi-track range edit (time-selection delete/paste): removals and
    // insertions across any mix of tracks and lanes, applied as one undoable
    // command with a single documentChanged emission. Notes/points to remove
    // must be freshly resolved (their indices are read at push time). Tempo
    // uses removeTempo/addTempo, not a fake lane.
    struct RangeEdit {
        int minimumEngineTrackCount = 0;
        std::vector<DocNote> removeNotes;
        std::vector<DocLanePoint> removePoints;
        struct TrackNotes {
            int engineTrack;
            std::vector<NewNote> notes;
        };
        std::vector<TrackNotes> addNotes;
        struct LaneWrite {
            int engineTrack;
            uint8_t cc;
            std::vector<LanePointValue> points; // absolute ticks
        };
        std::vector<LaneWrite> addPoints;
        std::vector<TempoPoint> removeTempo;
        std::vector<TempoPoint> addTempo;

        bool empty() const
        {
            return minimumEngineTrackCount == 0 && removeNotes.empty() && removePoints.empty() &&
                   addNotes.empty() && addPoints.empty() && removeTempo.empty() && addTempo.empty();
        }
    };
    void applyRangeEdit(const QString &text, const RangeEdit &edit);

    // Time-selection nudge: shift notes, lane points, and tempo points by a
    // tick delta as one undoable command. Events are re-inserted with their
    // exact bytes so unterminated notes stay unterminated. Tempo keeps its
    // stored microseconds-per-quarter-note.
    void moveRange(const std::vector<DocNote> &notes, const std::vector<DocLanePoint> &points,
                   int64_t dTick, const std::vector<TempoPoint> &tempo = {});

    // Remove a time range ("Remove contents"): erases the half-open range on
    // the scoped streams and closes the gap — everything at or after endTick
    // moves left by the span. Value streams (CC, bend, voice, tempo, time
    // signatures) keep the state the shifted content was authored under: the
    // last in-range point moves to startTick instead of vanishing (unless a
    // point shifts onto that seam from endTick anyway).
    // tracks close notes plus every non-note channel event of the track;
    // wholeSong — the all-tracks cut — ignores tracks/lanes and closes every
    // engine track plus the global rows: tempo, time signatures, loop markers
    // and other metas (moved to the seam, never deleted), and each chunk's
    // end-of-track tick, so the song itself gets shorter. One undoable command;
    // returns false when nothing would change.
    struct TimeRange {
        uint64_t startTick = 0;
        uint64_t endTick = 0;

        bool empty() const { return endTick <= startTick; }
        uint64_t span() const { return empty() ? 0 : endTick - startTick; }
        bool contains(uint64_t tick) const { return tick >= startTick && tick < endTick; }
        bool overlaps(uint64_t start, uint64_t end) const
        {
            return startTick < endTick && start < end && startTick < end && start < endTick;
        }
    };
    struct TimeScope {
        std::vector<int> tracks;                    // engine tracks (ignored when wholeSong)
        std::vector<std::pair<int, uint8_t>> lanes; // Voice/CC (engineTrack, cc)
        bool tempo = false;
        bool wholeSong = false;

        bool coversTrack(int engineTrack) const
        {
            return wholeSong ||
                   std::find(tracks.begin(), tracks.end(), engineTrack) != tracks.end();
        }
        bool coversTempo() const { return wholeSong || tempo; }
        bool coversLane(int engineTrack, uint8_t cc) const
        {
            if (wholeSong)
                return true;
            if (std::find(lanes.begin(), lanes.end(), std::pair{engineTrack, cc}) != lanes.end())
                return true;
            return engineTrack >= 0 &&
                   std::find(tracks.begin(), tracks.end(), engineTrack) != tracks.end();
        }
    };
    bool removeTimeRange(const TimeRange &range, const TimeScope &scope);
    // Insert a silent [startTick, endTick) gap on the scoped streams. Events
    // at or after startTick shift right; notes crossing the seam split so the
    // inserted interval remains silent. One undoable command.
    bool insertBlankTime(const TimeRange &range, const TimeScope &scope);
    // Duplicate [startTick, endTick) at endTick, shifting later scoped
    // content right by the span. Value streams seed their effective state at
    // the destination seam. One undoable command.
    bool duplicateTimeRange(const TimeRange &range, const TimeScope &scope);

    // Raw SMF edits (the MIDI event list view): direct event-level operations
    // on one chunk, indices being current positions in its event vector.
    // Insert places the event at its tick's canonical position (setup events
    // ahead of same-tick notes and note ends ahead of same-tick note-ons,
    // like every other edit); a modify that changes
    // the tick re-inserts so event order stays non-decreasing — re-resolve
    // indices afterwards. No semantic validation happens here: an orphan
    // note-on or a bogus meta is the raw editor's prerogative (the SMF still
    // writes, and the playable projection is built defensively).
    void insertRawEvent(int smfTrack, const SmfEvent &event);
    void modifyRawEvent(int smfTrack, size_t index, const SmfEvent &event);
    void deleteRawEvents(int smfTrack, std::vector<size_t> indices);
    // Reorder within a tick: the event at index ends up at destIndex (its
    // position in the post-move vector). Same-tick order is significant —
    // the file keeps it and mid2agb stable-sorts — so this is the one raw
    // edit that picks position directly. The destination is clamped to
    // rawEventMoveBounds, so a move can never cross a tick boundary or
    // break the canonical intra-tick invariants insert maintains; a move
    // whose clamped destination is the current position is a no-op.
    void moveRawEvent(int smfTrack, size_t index, size_t destIndex);
    // The inclusive [first, last] range moveRawEvent would accept for the
    // event at index: its own tick group, minus positions that would put a
    // setup event after a same-tick note or a note-end after a same-tick
    // note-on (in either direction — the moved event may not cross an
    // event the canonical order pins it against). False when index is out
    // of range.
    bool rawEventMoveBounds(int smfTrack, size_t index, size_t *first, size_t *last) const;
    // Move the chunk's end-of-track marker; clamped so it never precedes the
    // chunk's last event.
    void setTrackEndTick(int smfTrack, uint64_t tick);

    // Move or create a loop marker; tick == -1 removes it.
    void setLoopTick(bool endMarker, int64_t tick);

    // Set the time signature at a tick: modifies the winning 0x58 meta
    // already there (keeping its chunk and metronome bytes), or inserts a
    // new one in the seq chunk, like tempo and loop markers. moveTimeSig
    // relocates every 0x58 at fromTick, overwriting any at toTick;
    // deleteTimeSig removes every 0x58 at the tick.
    void setTimeSig(uint64_t tick, int numerator, int denomPow2);
    void moveTimeSig(uint64_t fromTick, uint64_t toTick);
    void deleteTimeSig(uint64_t tick);

    // Track create/delete. A track needs a channel event to occupy an engine
    // slot (rebuildTrackMap), so a new track is seeded with a program change
    // at tick 0 carrying the given voicegroup entry, in a new MTrk chunk
    // appended on an unused MIDI channel. Returns the new engine track, -1
    // if none is free.
    bool canAddTrack() const;
    int addTrack(int voice);
    // Copy a track's owned channel events onto a fresh engine slot. The
    // end-of-track tick is preserved; metadata is never copied. Returns the
    // copy's engine track, -1 when no slot is free.
    int duplicateTrack(int engineTrack);
    // Removes the track's chunk — except chunk 0 (the seq chunk mid2agb
    // reads tempo/timesig/loop from), which only has its channel events
    // stripped; a winning loop marker inside a removed chunk is moved to
    // chunk 0 so the loop survives.
    void deleteTrack(int engineTrack);
    // Reorder: the track lands at the target track's engine slot. The
    // track's chunk moves, events untouched — AGB track order is chunk
    // order — and when the move displaces chunk 0, the seq globals (tempo,
    // time signatures, loop markers) migrate to the new first chunk, where
    // mid2agb and the tempo lane read them. Returns true when a command was
    // pushed (false: no-op or unmapped slot).
    bool moveTrack(int engineTrack, int targetEngine);

    // Track display name, exactly as MidiTimeline reads it: the chunk's
    // first unprefixed Track Name meta (0x03; one scoped to a channel by a
    // MIDI Channel Prefix meta 0x20 never counts). Rename modifies the 0x03
    // in place (keeping its tick and position) or inserts it at tick 0; an
    // empty name removes it. Names mid2agb would read as loop/label markers
    // (nameIsLoopMarker) are refused.
    QString trackName(int engineTrack) const;
    void renameTrack(int engineTrack, const QString &name);

    void setCfg(const SongCfg &cfg);

    // Playable projection for the audio engine (MidiTimeline::build).
    std::unique_ptr<MidiTimeline> buildTimeline(double sampleRate) const;

  signals:
    // Emitted after every mutation, undo, and redo.
    void documentChanged();
    // Emitted after the track map is rebuilt, but before documentChanged,
    // whenever a change alters chunk or engine-track ownership.
    void tracksRemapped(TrackRemap remap);

  private:
    friend class SongEditCommand;
    friend class TempoEditCommand;
    friend class SongCfgCommand;
    friend class MoveNotesCommand;
    friend class MixedEditCommand;
    friend class MoveNotesToPitchesCommand;

    struct EditOp {
        enum Type {
            InsertEvent,
            RemoveEvent,
            ModifyEvent,
            MoveEvent,   // reorder within a tick group: index -> indexTo
            InsertTrack, // insert trackData as chunk smfTrack
            RemoveTrack, // remove chunk smfTrack (contents recorded on apply)
            SetTrackEnd, // set chunk endTick to event.tick (old recorded on apply)
            MoveTrack    // move chunk smfTrack so it lands at index smfTrackTo
        } type;
        int smfTrack = 0;
        int smfTrackTo = 0;           // MoveTrack: the chunk's index after the move
        size_t index = 0;             // Remove/Modify/Move: target; Insert: recorded on apply
        size_t indexTo = 0;           // MoveEvent: the event's index after the move
        SmfEvent event;               // Insert: new event; Modify: new content (same tick)
        SmfEvent oldEvent;            // recorded on apply (Remove/Modify)
        uint64_t oldEndTick = 0;      // recorded on apply (Insert past track end)
        bool preservesNoteId = false; // true once this op owns a minted ID
        SmfTrack trackData;           // InsertTrack: content; RemoveTrack: recorded on apply
    };
    class TimeEditor;
    struct TrackMapState {
        int smfTrackCount = 0;
        std::vector<int> engineToSmf;
    };

    void applyOps(std::vector<EditOp> &ops);
    void revertOps(std::vector<EditOp> &ops);
    void pushEdit(const QString &text, std::vector<EditOp> ops);
    void pushEdit(const QString &text, std::vector<EditOp> ops, std::vector<TempoPoint> nextTempo);
    void rebuildTrackMap();
    TrackMapState trackMapState() const;
    TrackRemap currentTrackRemap() const;
    TrackRemap trackRemap(const TrackMapState &before, const std::vector<EditOp> &ops) const;
    void publishMutation(TrackRemap remap);
    static std::vector<TempoPoint> tempoPointsFromSmf(const SmfFile &smf);
    static std::vector<TempoPoint> normalizeTempoPoints(std::vector<TempoPoint> points);
    // The sole m_tempoPoints writer; its input must be normalized first.
    void replaceTempoPoints(std::vector<TempoPoint> normalized);
    void mintNoteId(SmfEvent *event);
    bool noteAt(int engineTrack, size_t onIndex, DocNote *out) const;
    void mintUnassignedNoteIds();

    int engineTrackForChunk(int chunk) const; // -1 = no engine slot
    // Lowest MIDI channel no existing engine track uses; -1 when all 16 are
    // taken.
    int freeChannel() const;

    // Builder helpers (operate on current state; see applyOps for index rules).
    SmfEvent makeChannelEvent(uint8_t typeNibble, uint8_t channel, uint64_t tick, uint8_t data0,
                              uint8_t data1) const;
    void appendNoteInsertOps(std::vector<EditOp> &ops, int smfTrack, uint8_t channel, uint64_t tick,
                             uint8_t key, uint32_t duration, uint8_t velocity) const;
    void appendRemoveOps(std::vector<EditOp> &ops, int smfTrack, std::vector<size_t> indices) const;
    // Same-key overlap resolution for edits that write notes. The pairing
    // rule (every note-on takes the first same-key end after it) cannot
    // represent two overlapping notes on one key — a written note landing
    // over a stationary one would silently re-pair the neighbor's end. So
    // the edited note wins: a stationary same-track same-key note
    // overlapping a written span keeps its head (end trimmed to the span
    // start), keeps its tail (start moved to the span end), or is removed
    // when fully covered — never split. written spans are the notes the
    // edit is inserting; editNotes are the notes it already rewrites
    // (excluded from trimming). Victim indices are appended to removals
    // (per SMF track, for the caller's appendRemoveOps pass) and the
    // trimmed events re-inserted with their exact bytes via trims (the
    // caller appends them after all its removals).
    struct PlannedNote {
        int engineTrack;
        uint8_t key;
        uint64_t tick;
        uint64_t endTick; // exclusive
    };
    void resolveNoteOverlaps(const std::vector<PlannedNote> &written,
                             const std::vector<DocNote> &editNotes,
                             std::vector<std::vector<size_t>> &removals,
                             std::vector<EditOp> &trims) const;
    // Note-move op builders, split out so their commands can rebuild the
    // move with an accumulated delta when merging keyboard presses.
    // moveNotes rewrites each note's own on/end events (note ids preserved;
    // unterminated notes keep their patched note-on); moveNotesToPitches
    // mints fresh events and drops unterminated or no-op pitches.
    std::vector<EditOp> buildMoveNotesOps(const std::vector<DocNote> &notes, int64_t dTick,
                                          int dKey) const;
    std::vector<EditOp> buildMoveNotesToPitchesOps(const std::vector<DocNote> &notes,
                                                   const std::vector<uint8_t> &destPitches,
                                                   int64_t dTick) const;
    // Replace one event: modify in place when the tick is unchanged (the
    // event keeps its position within its tick group — mid2agb stable-sorts,
    // so same-tick order is significant), else remove + re-insert so ticks
    // stay sorted.
    void appendEventEditOps(std::vector<EditOp> &ops, int smfTrack, size_t index,
                            const SmfEvent &event) const;
    bool laneEventMatches(const SmfEvent &ev, uint8_t cc) const;
    int laneValue(const SmfEvent &ev, uint8_t cc) const;
    SmfEvent makeLaneEvent(uint8_t cc, uint8_t channel, uint64_t tick, int value) const;
    void appendLaneInsertOps(std::vector<EditOp> &ops, int smfTrack, uint8_t channel, uint8_t cc,
                             uint64_t tick, int value) const;
    // The one XCMD adapter for an SMF track: one pass over the chunk's
    // channel events as a single decoder stream (the same slot playback
    // uses per engine track), rows carrying each event's chunk index as
    // identity. Callers project them or rewrite points and translate the
    // flat Patch via appendXcmdPatchOps; no protocol state is visible here.
    // TimeEditor and the lane TUs reuse this — no other adapter exists.
    std::vector<xcmd::Event> xcmdEvents(int smfTrack) const;
    // Translates one plan's Patch: raw removals land in removals[smfTrack],
    // and the ordered controller emissions become InsertEvents (canonical CC
    // events on emission.channel; verbatim re-insertions copy the named
    // event and only re-stamp its tick).
    void appendXcmdPatchOps(std::vector<std::vector<size_t>> &removals, std::vector<EditOp> &ops,
                            int smfTrack, const xcmd::Patch &patch) const;
    // Locates the loop marker event, mirroring MidiTimeline::build's rule
    // (first matching text meta in track/event order). Returns false if absent.
    bool findLoopMarkerEvent(bool endMarker, int *smfTrack, size_t *index) const;

    SmfFile m_smf;
    SongCfg m_cfg;
    SongCfg m_savedCfg; // as on disk, to detect midi.cfg write-back needs
    QString m_midPath;
    QString m_label;
    QString m_projectRoot;
    bool m_hadCfgLine = false;
    QUndoStack m_undoStack;
    SongHistory m_history{m_undoStack};
    uint64_t m_revision = 0;
    uint64_t m_saveStateToken = 0;
    uint64_t m_nextNoteId = 1;
    std::vector<TempoPoint> m_tempoPoints;

    std::vector<int> m_engineToSmf;       // engine track -> SMF track
    std::vector<uint8_t> m_engineChannel; // engine track -> MIDI channel
    int m_trackBudget = track_limits::kHardwareCapacity;
};
