#include "songdocument.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <algorithm>
#include <tuple>

#include "core/miditimeline.h"
#include "core/velocitymodel.h"
#include "project/songregistry.h"

namespace song_document_tempo {
void removeTempoMetas(SmfFile &smf);
void writeTempoMetas(SmfFile &smf, const std::vector<TempoPoint> &points);
} // namespace song_document_tempo

// Declared in songdocument.h: the event list's summary column shares it.
bool metaIsLoopMarker(const SmfEvent &ev, char marker)
{
    if (!ev.isMeta() || ev.metaType < 0x01 || ev.metaType > 0x07)
        return false;
    const int len = std::min<int>(ev.blob.size(), 32);
    const QString text = QString::fromLatin1(ev.blob.constData(), len).trimmed();
    return text.size() == 1 && text[0] == QLatin1Char(marker);
}

bool TrackRemap::isIdentity() const
{
    const int smfCount = track_limits::checkedTrackInt(smfTrackMap.size());
    const int engineCount = track_limits::checkedTrackInt(engineTrackMap.size());
    if (smfCount != newSmfTrackCount || engineCount != newEngineTrackCount)
        return false;
    for (int i = 0; i < smfCount; i++) {
        if (smfTrackMap[i] != i)
            return false;
    }
    for (int i = 0; i < engineCount; i++) {
        if (engineTrackMap[i] != i)
            return false;
    }
    return true;
}

TrackRemap TrackRemap::inverse() const
{
    TrackRemap inverse;
    inverse.smfTrackMap.assign(static_cast<std::size_t>(newSmfTrackCount),
                               -1); // vector API wants size_t
    inverse.engineTrackMap.assign(static_cast<std::size_t>(newEngineTrackCount),
                                  -1); // vector API wants size_t
    inverse.newSmfTrackCount = track_limits::checkedTrackInt(smfTrackMap.size());
    inverse.newEngineTrackCount = track_limits::checkedTrackInt(engineTrackMap.size());
    const int smfSize = inverse.newSmfTrackCount;
    const int engineSize = inverse.newEngineTrackCount;
    for (int old = 0; old < smfSize; old++) {
        const int current = smfTrackMap[old];
        if (current >= 0)
            inverse.smfTrackMap[current] = old;
    }
    for (int old = 0; old < engineSize; old++) {
        const int current = engineTrackMap[old];
        if (current >= 0)
            inverse.engineTrackMap[current] = old;
    }
    return inverse;
}

namespace {

// Time-signature metas as MidiTimeline::build reads them: numerator and
// denominator exponent must both be present.
bool metaIsTimeSig(const SmfEvent &ev)
{
    return ev.isMeta() && ev.metaType == 0x58 && ev.blob.size() >= 2;
}
// The pinning relation, exactly the pair rules InsertEvent's canonical
// placement enforces and raw-event reorder bounds preserve: a setup event
// (CC, program, channel aftertouch, bend) stays ahead of a same-tick note,
// a note-end ahead of a same-tick note-on. Metas and sysex are pinned
// against nothing — their position within the tick group is freely the
// user's.
bool pinnedBefore(const SmfEvent &a, const SmfEvent &b)
{
    if (a.isChannel() && a.typeNibble() >= 0xB && b.isChannel() && b.typeNibble() <= 0x9)
        return true;
    return a.isChannel() && a.isNoteEnd() && b.isNoteOn();
}

// Move the chunk at `from` to index `to`, the chunks between shifting by one
// toward the vacated slot. applyOps and revertOps share it with the endpoints
// swapped — the mirror lives here, not in two hand-maintained rotates.
void moveChunk(std::vector<SmfTrack> &tracks, int from, int to)
{
    const auto begin = tracks.begin();
    if (from < to)
        std::rotate(begin + from, begin + from + 1, begin + to + 1);
    else
        std::rotate(begin + to, begin + from, begin + from + 1);
}

bool cfgSemanticEqual(const SongCfg &a, const SongCfg &b)
{
    return a.voicegroupArg == b.voicegroupArg && a.masterVolume == b.masterVolume &&
           a.reverb == b.reverb && a.priority == b.priority && a.exactGate == b.exactGate &&
           a.extendedClocks == b.extendedClocks && a.noCompression == b.noCompression;
}

} // namespace

// Applies a prebuilt op list; undo reverts it. Op index rules: removals and
// modifications carry indices valid against the document state at apply time,
// so builders order all removals first (descending index per track) and let
// insertions resolve their position when applied.
class SongEditCommand : public QUndoCommand
{
  public:
    SongEditCommand(SongDocument *doc, const QString &text, std::vector<SongDocument::EditOp> ops)
        : QUndoCommand(text)
        , m_doc(doc)
        , m_ops(std::move(ops))
    {}

    void redo() override
    {
        const auto before = m_doc->trackMapState();
        m_doc->applyOps(m_ops);
        m_doc->rebuildTrackMap();
        m_remap = m_doc->trackRemap(before, m_ops);
        m_doc->publishMutation(m_remap);
    }

    void undo() override
    {
        m_doc->revertOps(m_ops);
        m_doc->rebuildTrackMap();
        m_doc->publishMutation(m_remap.inverse());
    }

  private:
    SongDocument *m_doc;
    std::vector<SongDocument::EditOp> m_ops;
    TrackRemap m_remap;
};

class SongCfgCommand : public QUndoCommand
{
  public:
    SongCfgCommand(SongDocument *doc, const SongCfg &newCfg)
        : QUndoCommand(QObject::tr("song settings"))
        , m_doc(doc)
        , m_new(newCfg)
        , m_old(doc->m_cfg)
    {}

    void redo() override
    {
        m_doc->m_cfg = m_new;
        m_doc->rebuildTrackMap();
        m_doc->publishMutation(m_doc->currentTrackRemap());
    }

    void undo() override
    {
        m_doc->m_cfg = m_old;
        m_doc->rebuildTrackMap();
        m_doc->publishMutation(m_doc->currentTrackRemap());
    }

  private:
    SongDocument *m_doc;
    SongCfg m_new;
    SongCfg m_old;
};

// A note move that may merge with the next one (keyboard transpose/nudge —
// rapid presses form one gesture). Merging replans the accumulated delta
// from the gesture's ORIGINAL notes with the pure admission predicate
// before any revert: a refused candidate returns false with the document
// untouched by construction. When admitted, the accumulated move re-lands
// in one hop from the pre-gesture state. QUndoStack refuses to merge
// across its clean index, so a save between presses keeps its own command.
class MoveNotesCommand : public QUndoCommand
{
  public:
    MoveNotesCommand(SongDocument *doc, std::vector<DocNote> notes, int64_t dTick, int dKey,
                     bool mergeable, std::vector<SongDocument::EditOp> ops)
        : QUndoCommand(SongDocument::tr("move %n note(s)", nullptr, int(notes.size())))
        , m_doc(doc)
        , m_notes(std::move(notes))
        , m_dTick(dTick)
        , m_dKey(dKey)
        , m_mergeable(mergeable)
        , m_ops(std::move(ops))
    {}

    int id() const override { return m_mergeable ? 0x4d76 : -1; } // 'Mv'

    void redo() override
    {
        const auto before = m_doc->trackMapState();
        m_doc->applyOps(m_ops);
        m_doc->rebuildTrackMap();
        m_remap = m_doc->trackRemap(before, m_ops);
        if (m_initialRedo) {
            m_initialRedo = false;
            return;
        }
        m_doc->publishMutation(m_remap);
    }

    void undo() override
    {
        m_doc->revertOps(m_ops);
        m_doc->rebuildTrackMap();
        m_doc->publishMutation(m_remap.inverse());
    }

    bool mergeWith(const QUndoCommand *command) override
    {
        // id() matched, so the cast is safe; on success the stack deletes
        // the other command, so mutating it is fine.
        auto *other =
            const_cast<MoveNotesCommand *>(static_cast<const MoveNotesCommand *>(command));
        if (!other->m_mergeable || !movesMyOutputs(other->m_notes))
            return false;
        // Plan first from the pre-gesture state: overflow guards precede
        // the predicate, and a refused candidate leaves both commands
        // applied (the stack keeps them separate). Nothing was reverted,
        // so the document is untouched by construction.
        if (other->m_dTick > int64_t(CoreTimeDefaults::kMaxTick) ||
            other->m_dTick < -int64_t(CoreTimeDefaults::kMaxTick))
            return false;
        const int64_t newDTick = m_dTick + other->m_dTick;
        if (newDTick > int64_t(CoreTimeDefaults::kMaxTick) ||
            newDTick < -int64_t(CoreTimeDefaults::kMaxTick))
            return false;
        const int newDKey = m_dKey + other->m_dKey;
        for (const DocNote &note : m_notes) {
            if (newDTick > int64_t(CoreTimeDefaults::kMaxTick) - int64_t(note.tick))
                return false;
            const Tick newTick = CoreTimeDefaults::shiftTickClamped(note.tick, newDTick);
            if (!note.unterminated() &&
                uint64_t(newTick) + note.duration > CoreTimeDefaults::kMaxTick)
                return false;
            const auto incoming =
                std::find_if(other->m_notes.begin(), other->m_notes.end(),
                             [&](const DocNote &next) { return next.noteId == note.noteId; });
            if (incoming == other->m_notes.end() ||
                newTick != CoreTimeDefaults::shiftTickClamped(incoming->tick, other->m_dTick) ||
                std::clamp(int64_t(note.key) + newDKey, int64_t(0), int64_t(127)) !=
                    std::clamp(int64_t(incoming->key) + other->m_dKey, int64_t(0), int64_t(127)) ||
                note.duration != incoming->duration)
                return false; // Clamping must compose to the already-applied result.
        }
        auto candidate = m_doc->buildMoveNotesOps(m_notes, newDTick, newDKey);
        if (!candidate || candidate->empty())
            return false;
        // Admission succeeded: rewind both applied commands, rebuild the
        // candidate against the pre-gesture state (op indices are state
        // owned), and land the accumulated move in one hop.
        m_dTick = newDTick;
        m_dKey = newDKey;
        m_doc->revertOps(other->m_ops);
        m_doc->revertOps(m_ops);
        m_ops = *m_doc->buildMoveNotesOps(m_notes, m_dTick, m_dKey);
        if (movesMyOutputs(m_notes)) {
            setObsolete(true);
            return true;
        }
        m_doc->applyOps(m_ops);
        m_doc->rebuildTrackMap();
        m_remap = m_doc->currentTrackRemap();
        return true;
    }

  private:
    // The next press must edit the notes exactly where this command left
    // them; anything else (new selection, another note landing on the same
    // spot) is a separate gesture.
    bool movesMyOutputs(const std::vector<DocNote> &next) const
    {
        if (next.size() != m_notes.size())
            return false;
        for (const DocNote &note : m_notes) {
            const Tick outputTick = CoreTimeDefaults::shiftTickClamped(note.tick, m_dTick);
            const uint8_t outputKey = uint8_t(std::clamp(int(note.key) + m_dKey, 0, 127));
            const auto output =
                std::find_if(next.begin(), next.end(), [&](const DocNote &candidate) {
                    return candidate.noteId == note.noteId &&
                           candidate.engineTrack == note.engineTrack &&
                           candidate.tick == outputTick && candidate.key == outputKey &&
                           candidate.duration == note.duration &&
                           candidate.velocity == note.velocity && candidate.channel == note.channel;
                });
            if (output == next.end())
                return false;
        }
        return true;
    }

    SongDocument *m_doc;
    std::vector<DocNote> m_notes; // resolved against the pre-gesture state
    int64_t m_dTick;
    int m_dKey;
    bool m_mergeable;
    bool m_initialRedo = true;
    std::vector<SongDocument::EditOp> m_ops;
    TrackRemap m_remap;
};

class MoveNotesToPitchesCommand : public QUndoCommand
{
  public:
    MoveNotesToPitchesCommand(SongDocument *doc, std::vector<DocNote> notes,
                              std::vector<uint8_t> destPitches, int64_t dTick, bool mergeable,
                              std::vector<SongDocument::EditOp> ops)
        : QUndoCommand(SongDocument::tr("move %n note(s)", nullptr, int(notes.size())))
        , m_doc(doc)
        , m_notes(std::move(notes))
        , m_destPitches(std::move(destPitches))
        , m_dTick(dTick)
        , m_mergeable(mergeable)
        , m_ops(std::move(ops))
    {}

    int id() const override { return m_mergeable ? 0x4d50 : -1; } // 'MP'

    void redo() override
    {
        m_doc->applyOps(m_ops);
        emit m_doc->documentChanged();
    }

    void undo() override
    {
        m_doc->revertOps(m_ops);
        emit m_doc->documentChanged();
    }

    bool mergeWith(const QUndoCommand *command) override
    {
        auto *other = const_cast<MoveNotesToPitchesCommand *>(
            static_cast<const MoveNotesToPitchesCommand *>(command));
        if (!other->m_mergeable || !movesMyOutputs(other->m_notes))
            return false;
        // Plan first from the pre-gesture state: overflow guards precede
        // the predicate, and a refused candidate leaves both commands
        // applied (the stack keeps them separate). Nothing was reverted,
        // so the document is untouched by construction.
        if (other->m_dTick < -int64_t(CoreTimeDefaults::kMaxTick) ||
            other->m_dTick > int64_t(CoreTimeDefaults::kMaxTick))
            return false;
        const int64_t newDTick = m_dTick + other->m_dTick;
        if (newDTick < -int64_t(CoreTimeDefaults::kMaxTick) ||
            newDTick > int64_t(CoreTimeDefaults::kMaxTick))
            return false;
        std::vector<uint8_t> alignedPitches;
        alignedPitches.reserve(m_notes.size());
        for (size_t i = 0; i < m_notes.size(); i++) {
            const DocNote &note = m_notes[i];
            const auto incoming =
                std::find_if(other->m_notes.begin(), other->m_notes.end(),
                             [&](const DocNote &next) { return next.noteId == note.noteId; });
            if (incoming == other->m_notes.end() ||
                CoreTimeDefaults::shiftTickClamped(note.tick, newDTick) !=
                    CoreTimeDefaults::shiftTickClamped(incoming->tick, other->m_dTick) ||
                note.duration != incoming->duration)
                return false;
            // Each destination belongs to the incoming note's identity,
            // not its position in the original gesture's selection.
            alignedPitches.push_back(
                other->m_destPitches[size_t(incoming - other->m_notes.begin())]);
            if (note.smfTrack < 0 || note.smfTrack >= int(m_doc->m_smf.tracks.size()) ||
                (alignedPitches[i] == note.key && newDTick == 0))
                continue; // key no-op: the builder emits nothing to overflow
            if (newDTick > int64_t(CoreTimeDefaults::kMaxTick) - int64_t(note.tick))
                return false;
            const Tick newTick = CoreTimeDefaults::shiftTickClamped(note.tick, newDTick);
            if (!note.unterminated() &&
                uint64_t(newTick) + note.duration > CoreTimeDefaults::kMaxTick)
                return false;
        }
        // The candidate here is only the admission gate: refusal leaves the
        // document untouched (the stack keeps the two separate commands).
        auto candidate = m_doc->buildMoveNotesToPitchesOps(m_notes, alignedPitches, newDTick);
        if (!candidate)
            return false;
        if (candidate->empty()) {
            // Zero accumulated delta: the merged result is a pure no-op —
            // rewind both applied commands to the pre-gesture state and
            // obsolete this command, so the inverse press produces no
            // history entry and the bytes are already back at the start.
            // Both reverts land exactly where each command's redo began,
            // but each of those redos published a change; publish the
            // restored state too so observers see a balanced notification
            // even though the bytes round-trip to the gesture start.
            m_destPitches = std::move(alignedPitches);
            m_dTick = newDTick;
            m_doc->revertOps(other->m_ops);
            m_doc->revertOps(m_ops);
            setObsolete(true);
            emit m_doc->documentChanged();
            return true;
        }
        m_destPitches = std::move(alignedPitches);
        m_dTick = newDTick;
        // Admission succeeded: rewind both applied commands, rebuild the
        // candidate against the pre-gesture state (op indices are state
        // owned), and land the accumulated move in one hop.
        m_doc->revertOps(other->m_ops);
        m_doc->revertOps(m_ops);
        m_ops = *m_doc->buildMoveNotesToPitchesOps(m_notes, m_destPitches, m_dTick);
        m_doc->applyOps(m_ops);
        emit m_doc->documentChanged();
        return true;
    }

  private:
    static bool allOnSameEngineTrack(const std::vector<DocNote> &notes)
    {
        const int engineTrack = notes.front().engineTrack;
        return std::all_of(notes.begin(), notes.end(), [engineTrack](const DocNote &note) {
            return note.engineTrack == engineTrack;
        });
    }

    bool movesMyOutputs(const std::vector<DocNote> &next) const
    {
        // The next press must edit the notes exactly where this command
        // left them — matched per note by its stable NoteId against the
        // planned output geometry. The builder's plan lands every note
        // (unterminated participants included, via their note-on) at the
        // shifted tick and m_destPitches[i], so the matcher copies it.
        if (next.size() != m_notes.size() || !allOnSameEngineTrack(m_notes) ||
            !allOnSameEngineTrack(next) || m_notes.front().engineTrack != next.front().engineTrack)
            return false;
        for (size_t i = 0; i < m_notes.size(); i++) {
            const DocNote &note = m_notes[i];
            const Tick outputTick = CoreTimeDefaults::shiftTickClamped(note.tick, m_dTick);
            const uint8_t outputKey = uint8_t(m_destPitches[i]);
            const auto output =
                std::find_if(next.begin(), next.end(), [&](const DocNote &candidate) {
                    return candidate.noteId == note.noteId &&
                           candidate.engineTrack == note.engineTrack &&
                           candidate.tick == outputTick && candidate.key == outputKey &&
                           candidate.duration == note.duration &&
                           candidate.velocity == note.velocity && candidate.channel == note.channel;
                });
            if (output == next.end())
                return false;
        }
        return true;
    }

    SongDocument *m_doc;
    std::vector<DocNote> m_notes;
    std::vector<uint8_t> m_destPitches;
    int64_t m_dTick;
    bool m_mergeable;
    std::vector<SongDocument::EditOp> m_ops;
};

// A note resize that may merge with the next one (keyboard lengthen/shorten —
// rapid presses form one gesture). Merging replans the accumulated delta
// from the gesture's ORIGINAL notes with the pure admission predicate
// before any revert: a refused candidate returns false with the document
// untouched by construction. QUndoStack refuses to merge across its clean
// index, so a save between presses keeps its own command.
class ResizeNotesCommand : public QUndoCommand
{
  public:
    ResizeNotesCommand(SongDocument *doc, std::vector<DocNote> notes, int64_t dDuration,
                       bool mergeable, std::vector<SongDocument::EditOp> ops)
        : QUndoCommand(SongDocument::tr("resize %n note(s)", nullptr, int(notes.size())))
        , m_doc(doc)
        , m_notes(std::move(notes))
        , m_dDuration(dDuration)
        , m_mergeable(mergeable)
        , m_ops(std::move(ops))
    {}

    int id() const override { return m_mergeable ? 0x5273 : -1; } // 'Rs'

    void redo() override
    {
        const auto before = m_doc->trackMapState();
        m_doc->applyOps(m_ops);
        m_doc->rebuildTrackMap();
        m_remap = m_doc->trackRemap(before, m_ops);
        if (m_initialRedo) {
            m_initialRedo = false;
            return;
        }
        m_doc->publishMutation(m_remap);
    }

    void undo() override
    {
        m_doc->revertOps(m_ops);
        m_doc->rebuildTrackMap();
        m_doc->publishMutation(m_remap.inverse());
    }

    bool mergeWith(const QUndoCommand *command) override
    {
        // id() matched, so the cast is safe; on success the stack deletes
        // the other command, so mutating it is fine.
        auto *other =
            const_cast<ResizeNotesCommand *>(static_cast<const ResizeNotesCommand *>(command));
        if (!other->m_mergeable || !resizesMyOutputs(other->m_notes))
            return false;
        // Plan first from the pre-gesture state: overflow guards precede
        // the predicate, and a refused candidate leaves both commands
        // applied (the stack keeps them separate). Nothing was reverted,
        // so the document is untouched by construction.
        const int64_t newDDuration = m_dDuration + other->m_dDuration;
        if (newDDuration > int64_t(CoreTimeDefaults::kMaxTick) ||
            newDDuration < -int64_t(CoreTimeDefaults::kMaxTick))
            return false;
        for (const DocNote &note : m_notes) {
            if (newDDuration >
                int64_t(CoreTimeDefaults::kMaxTick) - int64_t(note.tick) - int64_t(note.duration))
                return false;
            const auto incoming =
                std::find_if(other->m_notes.begin(), other->m_notes.end(),
                             [&](const DocNote &next) { return next.noteId == note.noteId; });
            if (incoming == other->m_notes.end() ||
                std::max<int64_t>(1, int64_t(note.duration) + newDDuration) !=
                    std::max<int64_t>(1, int64_t(incoming->duration) + other->m_dDuration) ||
                note.tick != incoming->tick || note.key != incoming->key)
                return false;
        }
        auto candidate = m_doc->buildResizeNotesOps(m_notes, newDDuration);
        if (!candidate || candidate->empty())
            return false;
        m_dDuration = newDDuration;
        // Admission succeeded: rewind both applied commands, rebuild the
        // candidate against the pre-gesture state (op indices are state
        // owned), and land the accumulated resize in one hop.
        m_doc->revertOps(other->m_ops);
        m_doc->revertOps(m_ops);
        m_ops = *m_doc->buildResizeNotesOps(m_notes, m_dDuration);
        if (resizesMyOutputs(m_notes)) {
            setObsolete(true);
            return true;
        }
        m_doc->applyOps(m_ops);
        m_doc->rebuildTrackMap();
        m_remap = m_doc->currentTrackRemap();
        return true;
    }

  private:
    // The next press must edit the notes exactly where this command left
    // them; anything else (new selection, another note landing on the same
    // spot) is a separate gesture.
    bool resizesMyOutputs(const std::vector<DocNote> &next) const
    {
        if (next.size() != m_notes.size())
            return false;
        for (const DocNote &note : m_notes) {
            const uint32_t outputDuration =
                uint32_t(std::max<int64_t>(1, int64_t(note.duration) + m_dDuration));
            const auto output =
                std::find_if(next.begin(), next.end(), [&](const DocNote &candidate) {
                    return candidate.noteId == note.noteId &&
                           candidate.engineTrack == note.engineTrack &&
                           candidate.tick == note.tick && candidate.key == note.key &&
                           candidate.duration == outputDuration &&
                           candidate.velocity == note.velocity && candidate.channel == note.channel;
                });
            if (output == next.end())
                return false;
        }
        return true;
    }

    SongDocument *m_doc;
    std::vector<DocNote> m_notes; // resolved against the pre-gesture state
    int64_t m_dDuration;
    bool m_mergeable;
    bool m_initialRedo = true;
    std::vector<SongDocument::EditOp> m_ops;
    TrackRemap m_remap;
};

SongDocument::SongDocument(QObject *parent) : QObject(parent)
{
    // Only a published document mutation moves the save-state token; raw
    // stack index or clean-flag churn never fakes one.
    connect(this, &SongDocument::documentChanged, this, [this] { ++m_saveStateToken; });
}

bool SongDocument::load(const SongInfo &song, QString *error)
{
    SmfFile smf;
    // readFile coerces format 0 to format 1 at the parse layer, so every
    // edit path below deals in one shape: chunks are tracks. Deterministic,
    // so an untouched file re-converts identically next open; the disk copy
    // flips to format 1 on the first real edit + save.
    if (!SmfFile::readFile(song.midPath, &smf, error))
        return false;

    return adoptSmf(std::move(smf), song, error);
}

bool SongDocument::adoptSmf(SmfFile smf, const SongInfo &song, QString *error)
{
    Q_UNUSED(error);
    const auto before = trackMapState();
    m_smf = std::move(smf);
    // NoteId tokens belong to one SongDocument. An in-memory SmfFile can
    // arrive from another document with stamped IDs, but adopting it is a
    // document boundary: remint every note-on from this document's
    // monotonically advancing token stream.
    for (SmfTrack &track : m_smf.tracks) {
        for (SmfEvent &event : track.events)
            event.noteId = NoteId{};
    }
    replaceTempoPoints(normalizeTempoPoints(tempoPointsFromSmf(m_smf)));
    song_document_tempo::removeTempoMetas(m_smf);
    m_cfg = song.cfg;
    m_savedCfg = song.cfg;
    m_midPath = song.midPath;
    m_label = song.label;
    m_hadCfgLine = song.hasCfg;
    m_history.clear();
    mintUnassignedNoteIds();
    rebuildTrackMap();
    TrackRemap remap;
    remap.smfTrackMap.assign(static_cast<std::size_t>(before.smfTrackCount),
                             -1); // vector API wants size_t
    remap.engineTrackMap.assign(before.engineToSmf.size(), -1);
    remap.newSmfTrackCount = track_limits::checkedTrackInt(m_smf.tracks.size());
    remap.newEngineTrackCount = engineTrackCount();
    publishMutation(remap);
    return true;
}

SongSaveSnapshot SongDocument::captureSaveSnapshot() const
{
    SongSaveSnapshot snapshot;
    snapshot.smf = canonicalizedForExport();
    song_document_tempo::writeTempoMetas(snapshot.smf, m_tempoPoints);
    snapshot.midPath = m_midPath;
    snapshot.label = m_label;
    snapshot.cfg = m_cfg;
    snapshot.flagsNeeded = !cfgSemanticEqual(m_cfg, m_savedCfg) || !m_hadCfgLine;
    snapshot.revision = m_revision;
    snapshot.saveStateToken = m_saveStateToken;
    snapshot.documentState = m_history.currentDocumentIdentity();
    return snapshot;
}

void SongDocument::didSave(const SongSaveSnapshot &snapshot, bool flagsWritten)
{
    if (snapshot.flagsNeeded && !flagsWritten)
        return;
    m_savedCfg = snapshot.cfg;
    if (snapshot.flagsNeeded) {
        m_savedCfg.rawFlags = SongRegistry::mergeCfgFlags(snapshot.cfg);
        m_hadCfgLine = true;
    }
    if (snapshot.revision != m_revision || snapshot.saveStateToken != m_saveStateToken)
        return;
    if (m_history.currentDocumentIdentity() != snapshot.documentState)
        return;
    if (snapshot.flagsNeeded)
        m_cfg.rawFlags = m_savedCfg.rawFlags;
    m_history.markDocumentSaved(snapshot.documentState);
}

bool SongDocument::save(QString *error)
{
    auto snapshot = captureSaveSnapshot();
    if (!snapshot.smf.writeFile(snapshot.midPath, error))
        return false;
    auto flagsWritten = false;
    if (snapshot.flagsNeeded) {
        const QStringList flags = SongRegistry::mergeCfgFlags(snapshot.cfg);
        if (!SongRegistry::writeSongFlags(QFileInfo(snapshot.midPath).path(), snapshot.label, flags,
                                          error))
            return false;
        flagsWritten = true;
    }
    didSave(snapshot, flagsWritten);
    return true;
}

uint32_t SongDocument::ticksPerClock() const
{
    const uint32_t clocksPerBeat = 24 * (m_cfg.extendedClocks ? 2 : 1);
    return std::max<uint32_t>(1, m_smf.division / clocksPerBeat);
}

void SongDocument::rebuildTrackMap()
{
    const SmfEngineTrackMapping mapping = mapSmfEngineTracks(m_smf);
    m_engineToSmf.clear();
    m_engineChannel.clear();
    m_engineToSmf.reserve(size_t(mapping.usedTrackCount));
    m_engineChannel.reserve(size_t(mapping.usedTrackCount));
    for (int i = 0; i < mapping.usedTrackCount; i++) {
        m_engineToSmf.push_back(mapping.tracks[size_t(i)].smfTrack);
        m_engineChannel.push_back(mapping.tracks[size_t(i)].channel);
    }
}

SongDocument::TrackMapState SongDocument::trackMapState() const
{
    return {track_limits::checkedTrackInt(m_smf.tracks.size()), m_engineToSmf};
}

TrackRemap SongDocument::currentTrackRemap() const
{
    TrackRemap remap;
    remap.smfTrackMap.resize(m_smf.tracks.size());
    remap.engineTrackMap.resize(
        static_cast<std::size_t>(engineTrackCount())); // vector API wants size_t
    std::iota(remap.smfTrackMap.begin(), remap.smfTrackMap.end(), 0);
    std::iota(remap.engineTrackMap.begin(), remap.engineTrackMap.end(), 0);
    remap.newSmfTrackCount = track_limits::checkedTrackInt(m_smf.tracks.size());
    remap.newEngineTrackCount = engineTrackCount();
    return remap;
}

TrackRemap SongDocument::trackRemap(const TrackMapState &before,
                                    const std::vector<EditOp> &ops) const
{
    std::vector<int> chunkOrigins(
        static_cast<std::size_t>(before.smfTrackCount)); // vector API wants size_t
    std::iota(chunkOrigins.begin(), chunkOrigins.end(), 0);
    for (const EditOp &op : ops) {
        if (op.type == EditOp::InsertTrack) {
            chunkOrigins.insert(chunkOrigins.begin() + op.smfTrack, -1);
        } else if (op.type == EditOp::RemoveTrack) {
            chunkOrigins.erase(chunkOrigins.begin() + op.smfTrack);
        } else if (op.type == EditOp::MoveTrack) {
            if (op.smfTrack < op.smfTrackTo) {
                std::rotate(chunkOrigins.begin() + op.smfTrack,
                            chunkOrigins.begin() + op.smfTrack + 1,
                            chunkOrigins.begin() + op.smfTrackTo + 1);
            } else {
                std::rotate(chunkOrigins.begin() + op.smfTrackTo,
                            chunkOrigins.begin() + op.smfTrack,
                            chunkOrigins.begin() + op.smfTrack + 1);
            }
        }
    }
    TrackRemap remap;
    remap.smfTrackMap.assign(static_cast<std::size_t>(before.smfTrackCount),
                             -1); // vector API wants size_t
    remap.engineTrackMap.assign(before.engineToSmf.size(), -1);
    remap.newSmfTrackCount = track_limits::checkedTrackInt(m_smf.tracks.size());
    remap.newEngineTrackCount = engineTrackCount();
    const int chunkCount = track_limits::checkedTrackInt(chunkOrigins.size());
    const int engineBefore = track_limits::checkedTrackInt(before.engineToSmf.size());
    for (int current = 0; current < chunkCount; current++) {
        const int old = chunkOrigins[size_t(current)];
        if (old >= 0)
            remap.smfTrackMap[old] = current;
    }
    for (int oldEngine = 0; oldEngine < engineBefore; oldEngine++) {
        const int oldChunk = before.engineToSmf[size_t(oldEngine)];
        const int newChunk = remap.smfTrackMap[oldChunk];
        for (int newEngine = 0; newEngine < engineTrackCount(); newEngine++) {
            if (m_engineToSmf[size_t(newEngine)] == newChunk) {
                remap.engineTrackMap[oldEngine] = newEngine;
                break;
            }
        }
    }
    return remap;
}

void SongDocument::publishMutation(TrackRemap remap)
{
    m_revision++;
    if (!remap.isIdentity())
        emit tracksRemapped(std::move(remap));
    emit documentChanged();
}

void SongDocument::mintNoteId(SmfEvent *event)
{
    if (!event->isNoteOn() || event->noteId.isAssigned())
        return;
    event->noteId = NoteId{m_nextNoteId++};
    if (m_nextNoteId == 0)
        m_nextNoteId++;
}

void SongDocument::mintUnassignedNoteIds()
{
    for (SmfTrack &track : m_smf.tracks) {
        for (SmfEvent &event : track.events)
            mintNoteId(&event);
    }
}

int SongDocument::smfTrackFor(int engineTrack) const
{
    if (engineTrack < 0 || engineTrack >= int(m_engineToSmf.size()))
        return -1;
    return m_engineToSmf[engineTrack];
}

uint8_t SongDocument::channelFor(int engineTrack) const
{
    if (engineTrack < 0 || engineTrack >= int(m_engineChannel.size()))
        return 0;
    return m_engineChannel[engineTrack];
}

int SongDocument::engineTrackForChunk(int chunk) const
{
    for (int t = 0; t < int(m_engineToSmf.size()); t++) {
        if (m_engineToSmf[t] == chunk)
            return t;
    }
    return -1;
}

bool SongDocument::noteAt(int engineTrack, size_t onIndex, DocNote *out) const
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return false;
    const auto &events = m_smf.tracks[size_t(smfTrack)].events;
    const uint8_t channel = channelFor(engineTrack);
    if (onIndex >= events.size() || !events[onIndex].isNoteOn() ||
        events[onIndex].channel() != channel)
        return false;
    const SmfEvent &on = events[onIndex];
    DocNote note;
    note.noteId = on.noteId;
    note.engineTrack = engineTrack;
    note.smfTrack = smfTrack;
    note.onIndex = onIndex;
    note.tick = on.tick;
    note.key = on.data0;
    note.velocity = on.data1;
    note.channel = on.channel();
    for (size_t index = onIndex + 1; index < events.size(); index++) {
        const SmfEvent &end = events[index];
        if (end.isChannel() && end.isNoteEnd() && end.channel() == channel &&
            end.data0 == on.data0) {
            note.endIndex = index;
            note.duration = uint32_t(end.tick - on.tick);
            break;
        }
    }
    *out = note;
    return true;
}

std::vector<DocNote> SongDocument::notesForTrack(int engineTrack) const
{
    std::vector<DocNote> notes;
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return notes;
    const auto &events = m_smf.tracks[size_t(smfTrack)].events;
    const uint8_t channel = channelFor(engineTrack);

    // Pair as mid2agb does: the first same-channel same-key note end after
    // the note-on (several note-ons may legitimately share one end). One
    // backward pass keeps that exact rule in linear time: when the walk
    // reaches a note-on, endAt holds the smallest later end index for its
    // (channel, key) slot.
    // 256 key slots, not 128: the parse layer preserves out-of-range data
    // bytes (mid2agb parity), and pairing compares the raw key byte, so key
    // 0x83 must never pair with key 0x03.
    std::vector<size_t> endAt(16 * 256, SIZE_MAX);
    for (size_t index = events.size(); index-- > 0;) {
        const SmfEvent &event = events[index];
        if (!event.isChannel())
            continue;
        const size_t slot = size_t(event.channel()) * 256 + event.data0;
        if (event.isNoteEnd()) {
            endAt[slot] = index;
        } else if (event.isNoteOn() && event.channel() == channel) {
            DocNote note;
            note.noteId = event.noteId;
            note.engineTrack = engineTrack;
            note.smfTrack = smfTrack;
            note.onIndex = index;
            note.tick = event.tick;
            note.key = event.data0;
            note.velocity = event.data1;
            note.channel = event.channel();
            if (endAt[slot] != SIZE_MAX) {
                note.endIndex = endAt[slot];
                note.duration = uint32_t(events[endAt[slot]].tick - event.tick);
            }
            notes.push_back(note);
        }
    }
    std::reverse(notes.begin(), notes.end()); // restore note-on order
    return notes;
}
std::vector<NoteId> SongDocument::insertedNoteIds(int engineTrack,
                                                  const std::vector<DocNote> &before) const
{
    std::vector<NoteId> ids;
    for (const DocNote &candidate : notesForTrack(engineTrack)) {
        const bool existed =
            std::any_of(before.begin(), before.end(), [&](const DocNote &previous) {
                return previous.noteId == candidate.noteId;
            });
        if (!existed)
            ids.push_back(candidate.noteId);
    }
    return ids;
}
uint64_t SongDocument::noteEndTick(const DocNote &note) const
{
    if (!note.unterminated())
        return uint64_t(note.tick) + note.duration;
    if (note.smfTrack < 0 || note.smfTrack >= int(m_smf.tracks.size()))
        return note.tick;
    return m_smf.tracks[size_t(note.smfTrack)].endTick;
}

bool SongDocument::containsNoteSpan(int engineTrack, const DocNote &snapshot,
                                    uint64_t expectedEndTick) const
{
    DocNote current;
    if (!snapshot.noteId.isAssigned() || !findNote(snapshot.noteId, &current))
        return false;
    return current.engineTrack == engineTrack &&
           current.unterminated() == snapshot.unterminated() &&
           noteEndTick(current) == expectedEndTick;
}

bool SongDocument::findNote(int engineTrack, Tick tick, uint8_t key, DocNote *out) const
{
    for (const DocNote &note : notesForTrack(engineTrack)) {
        if (note.tick == tick && note.key == key) {
            *out = note;
            return true;
        }
    }
    return false;
}

bool SongDocument::findNote(NoteId id, DocNote *out) const
{
    if (!id.isAssigned())
        return false;
    for (int smfTrack = 0; smfTrack < int(m_smf.tracks.size()); smfTrack++) {
        const int engineTrack = engineTrackForChunk(smfTrack);
        if (engineTrack < 0)
            continue;
        const auto &events = m_smf.tracks[size_t(smfTrack)].events;
        for (size_t index = 0; index < events.size(); index++) {
            if (events[index].isNoteOn() && events[index].noteId == id)
                return noteAt(engineTrack, index, out);
        }
    }
    return false;
}

bool SongDocument::laneEventMatches(const SmfEvent &ev, uint8_t cc) const
{
    if (!ev.isChannel())
        return false;
    if (cc == DOC_CC_BEND)
        return ev.typeNibble() == 0xE;
    if (cc == DOC_CC_VOICE)
        return ev.typeNibble() == 0xC;
    return ev.typeNibble() == 0xB && ev.data0 == cc;
}

int SongDocument::laneValue(const SmfEvent &ev, uint8_t cc) const
{
    if (cc == DOC_CC_BEND)
        return ((int(ev.data1) << 7) | ev.data0) - 8192;
    if (cc == DOC_CC_VOICE)
        return ev.data0;
    return ev.data1;
}

std::vector<DocLanePoint> SongDocument::lanePoints(int engineTrack, uint8_t cc) const
{
    std::vector<DocLanePoint> points;
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return points;
    const auto &events = m_smf.tracks[size_t(smfTrack)].events;
    if (const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(cc)) {
        // Known points surface through the neutral projection; each row's
        // index is the payload event's raw chunk position (Point identity).
        const xcmd::Projection projection = xcmd::projectEvents(xcmdEvents(smfTrack));
        for (const xcmd::Point &point : projection.points) {
            if (point.lane == descriptor->laneController)
                points.push_back({smfTrack, size_t(point.index), point.tick, int(point.value)});
        }
        return points;
    }
    for (size_t index = 0; index < events.size(); ++index) {
        if (laneEventMatches(events[index], cc))
            points.push_back({smfTrack, index, events[index].tick, laneValue(events[index], cc)});
    }
    return points;
}

bool SongDocument::findLanePoint(int engineTrack, uint8_t cc, Tick tick, DocLanePoint *out) const
{
    // The LAST point at the tick, mirroring setTimeSig: playback applies a
    // tick's events in order, so among same-tick duplicates the last is the
    // audible one — edits must target it, not a shadowed earlier value.
    bool found = false;
    for (const DocLanePoint &pt : lanePoints(engineTrack, cc)) {
        if (pt.tick > tick)
            break;
        if (pt.tick == tick) {
            if (out)
                *out = pt;
            found = true;
        }
    }
    return found;
}

bool SongDocument::findLoopMarkerEvent(bool endMarker, int *smfTrack, size_t *index) const
{
    const char marker = endMarker ? ']' : '[';
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        // Mirror MidiTimeline::build: name metas — the chunk's name (first
        // unprefixed 0x03, marker text included) and channel-scoped
        // (prefixed) non-marker 0x03s — are never checked as loop markers;
        // a prefixed 0x03 carrying marker text has no name position, so it
        // IS one (mid2agb's reading).
        bool nameSeen = false;
        SmfChannelPrefix prefix;
        const auto &evs = m_smf.tracks[t].events;
        for (size_t i = 0; i < evs.size(); i++) {
            const SmfEvent &ev = evs[i];
            prefix.observe(ev);
            if (!ev.isMeta())
                continue;
            if (ev.metaType == 0x03) {
                if (prefix.channel >= 0) {
                    if (!smfMetaIsMarker(ev))
                        continue; // channel-scoped name, not this chunk's
                } else if (!nameSeen) {
                    nameSeen = true;
                    continue;
                }
            }
            if (metaIsLoopMarker(ev, marker)) {
                *smfTrack = int(t);
                *index = i;
                return true;
            }
        }
    }
    return false;
}

Tick SongDocument::loopTick(bool endMarker) const
{
    int track;
    size_t index;
    if (!findLoopMarkerEvent(endMarker, &track, &index))
        return CoreTimeDefaults::kNoTick;
    return m_smf.tracks[track].events[index].tick;
}

std::vector<DocTimeSig> SongDocument::timeSigs() const
{
    std::vector<DocTimeSig> sigs;
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        const auto &evs = m_smf.tracks[t].events;
        for (size_t i = 0; i < evs.size(); i++) {
            if (metaIsTimeSig(evs[i]))
                sigs.push_back(
                    {int(t), i, evs[i].tick, uint8_t(evs[i].blob[0]), uint8_t(evs[i].blob[1])});
        }
    }
    std::stable_sort(sigs.begin(), sigs.end(),
                     [](const DocTimeSig &a, const DocTimeSig &b) { return a.tick < b.tick; });
    return sigs;
}

SmfEvent SongDocument::makeChannelEvent(uint8_t typeNibble, uint8_t channel, Tick tick,
                                        uint8_t data0, uint8_t data1) const
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = uint8_t((typeNibble << 4) | (channel & 0x0F));
    ev.data0 = data0;
    ev.data1 = data1;
    return ev;
}

void SongDocument::appendNoteInsertOps(std::vector<EditOp> &ops, int smfTrack, uint8_t channel,
                                       Tick tick, uint8_t key, uint32_t duration,
                                       uint8_t velocity) const
{
    EditOp on;
    on.type = EditOp::InsertEvent;
    on.smfTrack = smfTrack;
    on.event = makeChannelEvent(0x9, channel, tick, key, velocity);
    ops.push_back(on);

    // Note ends are written as velocity-0 note-ons: the form mid2agb's own
    // ecosystem uses, and the one that keeps running status unbroken.
    EditOp end;
    end.type = EditOp::InsertEvent;
    end.smfTrack = smfTrack;
    const uint64_t endTick = uint64_t(tick) + std::max<uint32_t>(1, duration);
    Q_ASSERT(endTick <= CoreTimeDefaults::kMaxTick);
    end.event = makeChannelEvent(0x9, channel, Tick(endTick), key, 0);
    ops.push_back(end);
}

void SongDocument::appendRemoveOps(std::vector<EditOp> &ops, int smfTrack,
                                   std::vector<size_t> indices) const
{
    std::sort(indices.begin(), indices.end(), [](size_t a, size_t b) { return a > b; });
    indices.erase(std::unique(indices.begin(), indices.end()), indices.end());
    for (size_t index : indices) {
        EditOp op;
        op.type = EditOp::RemoveEvent;
        op.smfTrack = smfTrack;
        op.index = index;
        ops.push_back(op);
    }
}

void SongDocument::appendEventEditOps(std::vector<EditOp> &ops, int smfTrack, size_t index,
                                      const SmfEvent &event) const
{
    const SmfEvent &old = m_smf.tracks[smfTrack].events[index];
    SmfEvent replacement = event;
    if (old.isNoteOn() && replacement.isNoteOn())
        replacement.noteId = old.noteId;
    if (replacement.tick == old.tick) {
        EditOp op;
        op.type = EditOp::ModifyEvent;
        op.smfTrack = smfTrack;
        op.index = index;
        op.event = std::move(replacement);
        ops.push_back(std::move(op));
        return;
    }
    EditOp remove;
    remove.type = EditOp::RemoveEvent;
    remove.smfTrack = smfTrack;
    remove.index = index;
    ops.push_back(remove);

    EditOp insert;
    insert.type = EditOp::InsertEvent;
    insert.smfTrack = smfTrack;
    insert.event = std::move(replacement);
    insert.preservesNoteId = insert.event.isNoteOn() && old.isNoteOn();
    ops.push_back(std::move(insert));
}

// The single collision rule; see the declaration for the contract. Overlap
// between two written spans (duplicates included) or against a stationary
// note refuses the whole edit — no trim, no removal, no winner for equal
// starts. Stationary membership is exempted by NoteId because every
// participant's identity is stable through the planned edit.
bool SongDocument::noteEditAdmissible(const std::vector<PlannedNote> &written,
                                      const std::vector<DocNote> &editNotes) const
{
    if (written.empty())
        return true;
    for (const PlannedNote &note : written) {
        if (note.endTick <= note.tick)
            return false;
    }
    auto sorted = written;
    std::sort(sorted.begin(), sorted.end(), [](const PlannedNote &a, const PlannedNote &b) {
        return std::tie(a.engineTrack, a.key, a.tick, a.endTick) <
               std::tie(b.engineTrack, b.key, b.tick, b.endTick);
    });
    for (size_t i = 1; i < sorted.size(); ++i) {
        const PlannedNote &previous = sorted[i - 1];
        const PlannedNote &note = sorted[i];
        if (previous.engineTrack == note.engineTrack && previous.key == note.key &&
            note.tick < previous.endTick)
            return false;
    }
    std::vector<NoteId> participantIds;
    participantIds.reserve(editNotes.size());
    for (const DocNote &note : editNotes)
        participantIds.push_back(note.noteId);
    std::sort(participantIds.begin(), participantIds.end());

    // One projection per touched track. Within each pitch, admitted spans
    // have increasing ends, so the first end past a stationary start is
    // the only candidate needed to decide whether that stationary note overlaps.
    for (auto trackBegin = sorted.cbegin(); trackBegin != sorted.cend();) {
        const int engineTrack = trackBegin->engineTrack;
        const auto trackEnd = std::upper_bound(
            trackBegin, sorted.cend(), engineTrack,
            [](int track, const PlannedNote &note) { return track < note.engineTrack; });
        for (const DocNote &stationary : notesForTrack(engineTrack)) {
            if (stationary.unterminated() ||
                std::binary_search(participantIds.begin(), participantIds.end(), stationary.noteId))
                continue;
            const auto groupBegin = std::lower_bound(
                trackBegin, trackEnd, stationary.key,
                [](const PlannedNote &note, uint8_t key) { return note.key < key; });
            const auto groupEnd = std::upper_bound(
                groupBegin, trackEnd, stationary.key,
                [](uint8_t key, const PlannedNote &note) { return key < note.key; });
            const auto overlap = std::upper_bound(
                groupBegin, groupEnd, uint64_t(stationary.tick),
                [](uint64_t tick, const PlannedNote &note) { return tick < note.endTick; });
            if (overlap != groupEnd &&
                uint64_t(overlap->tick) < uint64_t(stationary.tick) + stationary.duration)
                return false;
        }
        trackBegin = trackEnd;
    }
    return true;
}

void SongDocument::addNote(int engineTrack, Tick tick, uint8_t key, uint32_t duration,
                           uint8_t velocity)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return;
    // A persisted note end must stay at or below kMaxTick; a zero duration
    // normalizes to one tick before the checks. The single collision rule
    // refuses an overlapping span before anything is pushed.
    if (uint64_t(tick) + std::max<uint32_t>(1, duration) > CoreTimeDefaults::kMaxTick)
        return;
    if (!noteEditAdmissible(
            {{engineTrack, key, tick, uint64_t(tick) + std::max<uint32_t>(1, duration)}}, {}))
        return;
    std::vector<EditOp> ops;
    appendNoteInsertOps(ops, smfTrack, channelFor(engineTrack), tick, key, duration, velocity);
    pushEdit(tr("add note"), std::move(ops));
}

void SongDocument::addNotes(int engineTrack, const std::vector<NewNote> &notes)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0 || notes.empty())
        return;
    // One invalid end or an overlap inside the batch or against stationary
    // notes rejects the whole batch before anything is pushed.
    for (const NewNote &note : notes) {
        if (uint64_t(note.tick) + std::max<uint32_t>(1, note.duration) > CoreTimeDefaults::kMaxTick)
            return;
    }
    std::vector<PlannedNote> written;
    written.reserve(notes.size());
    for (const NewNote &note : notes)
        written.push_back({engineTrack, note.key, note.tick,
                           uint64_t(note.tick) + std::max<uint32_t>(1, note.duration)});
    if (!noteEditAdmissible(written, {}))
        return;
    const uint8_t channel = channelFor(engineTrack);
    std::vector<EditOp> ops;
    for (const NewNote &note : notes)
        appendNoteInsertOps(ops, smfTrack, channel, note.tick, note.key, note.duration,
                            note.velocity);
    pushEdit(tr("add %n note(s)", nullptr, int(notes.size())), std::move(ops));
}

void SongDocument::deleteNotes(const std::vector<DocNote> &notes)
{
    if (notes.empty())
        return;
    // Group removal indices per SMF track so each track's removals apply in
    // descending order.
    std::vector<EditOp> ops;
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        std::vector<size_t> indices;
        for (const DocNote &note : notes) {
            if (note.smfTrack != int(t))
                continue;
            indices.push_back(note.onIndex);
            if (!note.unterminated())
                indices.push_back(note.endIndex);
        }
        appendRemoveOps(ops, int(t), std::move(indices));
    }
    pushEdit(tr("delete %n note(s)", nullptr, int(notes.size())), std::move(ops));
}

void SongDocument::moveNotes(const std::vector<DocNote> &notes, int64_t dTick, int dKey,
                             bool mergeable)
{
    if (notes.empty() || (dTick == 0 && dKey == 0) ||
        dTick < -int64_t(CoreTimeDefaults::kMaxTick) || dTick > int64_t(CoreTimeDefaults::kMaxTick))
        return;
    // Every participating note must keep its stored start and, when
    // terminated, its end at or below kMaxTick; one invalid upper
    // destination rejects the whole batch before anything is planned.
    for (const DocNote &note : notes) {
        if (note.smfTrack < 0 || note.smfTrack >= int(m_smf.tracks.size()))
            continue;
        if (dTick > int64_t(CoreTimeDefaults::kMaxTick) - int64_t(note.tick))
            return;
        const Tick newTick = CoreTimeDefaults::shiftTickClamped(note.tick, dTick);
        if (!note.unterminated() && uint64_t(newTick) + note.duration > CoreTimeDefaults::kMaxTick)
            return;
    }
    const bool changes =
        std::any_of(notes.begin(), notes.end(), [dTick, dKey](const DocNote &note) {
            return CoreTimeDefaults::shiftTickClamped(note.tick, dTick) != note.tick ||
                   uint8_t(std::clamp(int(note.key) + dKey, 0, 127)) != note.key;
        });
    if (!changes)
        return;
    // Plan (and refuse) before anything enters the undo stack: nullopt
    // leaves revision, bytes, IDs and undo state untouched.
    auto ops = buildMoveNotesOps(notes, dTick, dKey);
    if (!ops || ops->empty())
        return;
    m_history.pushDocument(
        std::make_unique<MoveNotesCommand>(this, notes, dTick, dKey, mergeable, std::move(*ops)));
    // The command suppresses publication from its initial redo because a
    // merge can replace that provisional state. Publish the public move
    // call after the stack settles: an inverse merge may remove the
    // command but has still restored live state.
    publishMutation(currentTrackRemap());
}

bool SongDocument::moveNotesToPitches(const std::vector<DocNote> &notes,
                                      const std::vector<uint8_t> &destPitches, int64_t dTick,
                                      bool mergeable)
{
    if (notes.empty() || notes.size() != destPitches.size() ||
        dTick < -int64_t(CoreTimeDefaults::kMaxTick) || dTick > int64_t(CoreTimeDefaults::kMaxTick))
        return false;
    for (uint8_t destKey : destPitches) {
        if (destKey > 127)
            return false;
    }
    bool anyMove = false;
    for (size_t i = 0; i < notes.size(); i++) {
        if (notes[i].key != destPitches[i] || dTick != 0) {
            anyMove = true;
            break;
        }
    }
    if (!anyMove)
        return true;
    // Notes that stay put never move; every rewritten note must keep its
    // stored start and end at or below kMaxTick or the whole batch is
    // refused. Plan (and refuse) before anything enters the undo stack.
    for (size_t i = 0; i < notes.size(); i++) {
        const DocNote &note = notes[i];
        if (note.smfTrack < 0 || note.smfTrack >= int(m_smf.tracks.size()) ||
            (destPitches[i] == note.key && dTick == 0))
            continue;
        if (dTick > int64_t(CoreTimeDefaults::kMaxTick) - int64_t(note.tick))
            return false;
        const Tick newTick = CoreTimeDefaults::shiftTickClamped(note.tick, dTick);
        if (!note.unterminated() && uint64_t(newTick) + note.duration > CoreTimeDefaults::kMaxTick)
            return false;
    }
    auto ops = buildMoveNotesToPitchesOps(notes, destPitches, dTick);
    if (!ops || ops->empty())
        return false;
    m_history.pushDocument(std::make_unique<MoveNotesToPitchesCommand>(
        this, notes, destPitches, dTick, mergeable, std::move(*ops)));
    return true;
}

// Shared move planning for both move builders. Each note's own on/end
// events are rewritten (preservesNoteId keeps the minted identity, velocity
// stays in the copied note-on) with the planned destination tick and key —
// `destKeys[i]` is note i's destination pitch. Notes with an invalid SMF
// track plan nothing; an unterminated participant moves its patched note-on
// to the destination key and contributes no span. A no-op (same key, zero
// tick delta) still contributes its current span to the admission set but
// emits no ops, so a converging sibling refuses against it. Pure: builds op
// plans or reports refusal, touches nothing.
//
// Index discipline: applyOps erases at the op's stored index sequentially,
// so all index-bearing ops (RemoveEvent/ModifyEvent) must be emitted first
// in descending index order per SMF track, and inserts follow — otherwise a
// later note's removal index points across an already-shifted track. The
// builder stages the per-note remove/modify records and inserts separately,
// sorts the index-bearing records without changing their type or payload,
// and appends the inserts afterwards.
std::optional<std::vector<SongDocument::EditOp>>
SongDocument::buildMoveOps(const std::vector<DocNote> &notes, std::vector<uint8_t> destKeys,
                           int64_t dTick, bool skipUnchanged) const
{
    std::vector<PlannedNote> written;
    written.reserve(notes.size());
    std::vector<std::vector<EditOp>> removals(m_smf.tracks.size());
    std::vector<std::vector<EditOp>> inserts(m_smf.tracks.size());
    for (size_t i = 0; i < notes.size(); i++) {
        const DocNote &note = notes[i];
        const uint8_t destKey = destKeys[i];
        if (note.smfTrack < 0 || note.smfTrack >= int(m_smf.tracks.size()))
            continue;
        const bool moved = destKey != note.key || dTick != 0;
        const Tick newTick = CoreTimeDefaults::shiftTickClamped(note.tick, dTick);
        if (!moved && skipUnchanged) {
            // Stays exactly where it is, but its current span still
            // participates in admission so a converging sibling refuses.
            if (!note.unterminated())
                written.push_back(
                    {note.engineTrack, destKey, newTick, uint64_t(newTick) + note.duration});
            continue;
        }
        if (!note.unterminated())
            written.push_back(
                {note.engineTrack, destKey, newTick, uint64_t(newTick) + note.duration});
        std::vector<EditOp> &trackRemovals = removals[size_t(note.smfTrack)];
        std::vector<EditOp> &trackInserts = inserts[size_t(note.smfTrack)];
        SmfEvent on = m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex];
        on.tick = newTick;
        on.data0 = destKey;
        if (!note.unterminated()) {
            SmfEvent end = m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex];
            end.tick = Tick(uint64_t(newTick) + note.duration);
            end.data0 = destKey;
            EditOp op;
            op.smfTrack = note.smfTrack;
            if (end.tick == m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick) {
                op.type = EditOp::ModifyEvent;
                op.index = note.endIndex;
                op.event = std::move(end);
                trackRemovals.push_back(std::move(op)); // ModifyEvent is index-bearing too
            } else {
                op.type = EditOp::RemoveEvent;
                op.index = note.endIndex;
                trackRemovals.push_back(std::move(op));
                EditOp insert;
                insert.type = EditOp::InsertEvent;
                insert.smfTrack = note.smfTrack;
                insert.event = std::move(end);
                trackInserts.push_back(std::move(insert));
            }
        }
        EditOp op;
        op.smfTrack = note.smfTrack;
        if (on.tick == m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex].tick) {
            op.type = EditOp::ModifyEvent;
            op.index = note.onIndex;
            op.event = std::move(on);
            trackRemovals.push_back(std::move(op)); // ModifyEvent is index-bearing too
        } else {
            op.type = EditOp::RemoveEvent;
            op.index = note.onIndex;
            trackRemovals.push_back(std::move(op));
            EditOp insert;
            insert.type = EditOp::InsertEvent;
            insert.smfTrack = note.smfTrack;
            insert.event = std::move(on);
            insert.preservesNoteId = true;
            trackInserts.push_back(std::move(insert));
        }
    }
    if (!noteEditAdmissible(written, notes))
        return std::nullopt;
    std::vector<EditOp> ops;
    ops.reserve(written.size() * 3);
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        std::sort(removals[t].begin(), removals[t].end(),
                  [](const EditOp &a, const EditOp &b) { return a.index > b.index; });
        for (EditOp &op : removals[t])
            ops.push_back(std::move(op));
        for (EditOp &op : inserts[t])
            ops.push_back(std::move(op));
    }
    return ops;
}

std::optional<std::vector<SongDocument::EditOp>>
SongDocument::buildMoveNotesOps(const std::vector<DocNote> &notes, int64_t dTick, int dKey) const
{
    // Every note moves by the common delta; keys clamp to 0-127.
    std::vector<uint8_t> destKeys(notes.size());
    for (size_t i = 0; i < notes.size(); i++)
        destKeys[i] = uint8_t(std::clamp(int(notes[i].key) + dKey, 0, 127));
    return buildMoveOps(notes, std::move(destKeys), dTick, false);
}

std::optional<std::vector<SongDocument::EditOp>> SongDocument::buildMoveNotesToPitchesOps(
    const std::vector<DocNote> &notes, const std::vector<uint8_t> &destPitches, int64_t dTick) const
{
    return buildMoveOps(notes, destPitches, dTick, true);
}

std::optional<std::vector<SongDocument::EditOp>>
SongDocument::buildResizeNotesOps(const std::vector<DocNote> &notes, int64_t dDuration) const
{
    // Index discipline mirrors buildMoveOps: all index-bearing ops first
    // (per track, descending), then the inserts.
    std::vector<PlannedNote> written;
    std::vector<std::vector<EditOp>> removals(m_smf.tracks.size());
    std::vector<std::vector<EditOp>> inserts(m_smf.tracks.size());
    for (const DocNote &note : notes) {
        if (note.unterminated() || note.smfTrack < 0 || note.smfTrack >= int(m_smf.tracks.size()))
            continue;
        // Per-note max(1, duration + d), then the kMaxTick headroom guard:
        // never capped, one out-of-range resize refuses the batch.
        const uint32_t newDuration =
            uint32_t(std::max<int64_t>(1, int64_t(note.duration) + dDuration));
        const uint64_t endTick = uint64_t(note.tick) + newDuration;
        if (endTick > CoreTimeDefaults::kMaxTick)
            return std::nullopt;
        written.push_back({note.engineTrack, note.key, note.tick, endTick});
        // Consume and re-land (not duplicate) the note's own end event.
        std::vector<EditOp> &trackRemovals = removals[size_t(note.smfTrack)];
        EditOp op;
        op.smfTrack = note.smfTrack;
        if (Tick(endTick) == m_smf.tracks[size_t(note.smfTrack)].events[note.endIndex].tick) {
            op.type = EditOp::ModifyEvent;
            op.index = note.endIndex;
            op.event = makeChannelEvent(0x9, note.channel, Tick(endTick), note.key, 0);
            trackRemovals.push_back(std::move(op)); // ModifyEvent is index-bearing too
        } else {
            op.type = EditOp::RemoveEvent;
            op.index = note.endIndex;
            trackRemovals.push_back(std::move(op));
            EditOp insert;
            insert.type = EditOp::InsertEvent;
            insert.smfTrack = note.smfTrack;
            insert.event = makeChannelEvent(0x9, note.channel, Tick(endTick), note.key, 0);
            inserts[size_t(note.smfTrack)].push_back(std::move(insert));
        }
    }
    if (!noteEditAdmissible(written, notes))
        return std::nullopt;
    std::vector<EditOp> ops;
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        std::sort(removals[t].begin(), removals[t].end(),
                  [](const EditOp &a, const EditOp &b) { return a.index > b.index; });
        for (EditOp &op : removals[t])
            ops.push_back(std::move(op));
        for (EditOp &op : inserts[t])
            ops.push_back(std::move(op));
    }
    return ops;
}

void SongDocument::resizeNotes(const std::vector<DocNote> &notes, int64_t dDuration, bool mergeable)
{
    if (notes.empty() || dDuration == 0)
        return;
    // The resized end of every note this writes must stay at or below
    // kMaxTick. Classify the delta against the remaining headroom before
    // any addition so an out-of-range resize is rejected rather than
    // overflowing the int64_t sum; one overflow rejects the batch.
    for (const DocNote &note : notes) {
        if (dDuration >
            int64_t(CoreTimeDefaults::kMaxTick) - int64_t(note.tick) - int64_t(note.duration))
            return;
        const int64_t newDuration = std::max<int64_t>(1, int64_t(note.duration) + dDuration);
        if (uint64_t(note.tick) + uint64_t(newDuration) > CoreTimeDefaults::kMaxTick)
            return;
    }
    const bool changes = std::any_of(notes.begin(), notes.end(), [dDuration](const DocNote &note) {
        return note.unterminated() ||
               uint32_t(std::max<int64_t>(1, int64_t(note.duration) + dDuration)) != note.duration;
    });
    if (!changes)
        return;
    // Plan (and refuse) before anything enters the undo stack: nullopt
    // leaves revision, bytes, IDs and undo state untouched.
    auto ops = buildResizeNotesOps(notes, dDuration);
    if (!ops || ops->empty())
        return;
    m_history.pushDocument(
        std::make_unique<ResizeNotesCommand>(this, notes, dDuration, mergeable, std::move(*ops)));
    // The command suppresses publication from its initial redo because a
    // merge can replace that provisional state. Publish the public resize
    // call after the stack settles: an inverse merge may remove the
    // command but has still restored live state.
    publishMutation(currentTrackRemap());
}

void SongDocument::resizeNotesLeft(const std::vector<DocNote> &notes, int64_t dTick)
{
    if (notes.empty() || dTick == 0)
        return;
    const bool changes = std::any_of(notes.begin(), notes.end(), [dTick](const DocNote &note) {
        const int64_t maxTick =
            note.unterminated() ? INT64_MAX : int64_t(note.tick) + note.duration - 1;
        return Tick(std::clamp<int64_t>(int64_t(note.tick) + dTick, 0, maxTick)) != note.tick;
    });
    if (!changes)
        return;
    // Index discipline mirrors buildMoveOps, and the empty-ops guard below
    // keeps an all-invalid-track batch from pushing an empty command.
    std::vector<PlannedNote> written;
    std::vector<std::vector<EditOp>> removals(m_smf.tracks.size());
    std::vector<std::vector<EditOp>> inserts(m_smf.tracks.size());
    for (const DocNote &note : notes) {
        if (note.smfTrack < 0 || note.smfTrack >= int(m_smf.tracks.size()))
            continue;
        // An unterminated note has no note-off to pin; its note-on just
        // moves and contributes no span.
        const int64_t maxTick =
            note.unterminated() ? INT64_MAX : int64_t(note.tick) + int64_t(note.duration) - 1;
        const Tick newTick = Tick(std::clamp<int64_t>(int64_t(note.tick) + dTick, 0, maxTick));
        SmfEvent on = m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex];
        on.tick = newTick;
        std::vector<EditOp> &trackRemovals = removals[size_t(note.smfTrack)];
        EditOp op;
        op.smfTrack = note.smfTrack;
        if (on.tick == m_smf.tracks[size_t(note.smfTrack)].events[note.onIndex].tick) {
            op.type = EditOp::ModifyEvent;
            op.index = note.onIndex;
            op.event = std::move(on);
            trackRemovals.push_back(std::move(op)); // ModifyEvent is index-bearing too
        } else {
            op.type = EditOp::RemoveEvent;
            op.index = note.onIndex;
            trackRemovals.push_back(std::move(op));
            EditOp insert;
            insert.type = EditOp::InsertEvent;
            insert.smfTrack = note.smfTrack;
            insert.event = std::move(on);
            insert.preservesNoteId = true;
            inserts[size_t(note.smfTrack)].push_back(std::move(insert));
        }
        if (note.unterminated())
            continue;
        const uint64_t endTick = uint64_t(note.tick) + uint64_t(note.duration);
        written.push_back({note.engineTrack, note.key, newTick, endTick});
    }
    // A left edge that would cross a same-key neighbor refuses atomically;
    // the stationary note keeps its span.
    if (!noteEditAdmissible(written, notes))
        return;
    std::vector<EditOp> ops;
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        std::sort(removals[t].begin(), removals[t].end(),
                  [](const EditOp &a, const EditOp &b) { return a.index > b.index; });
        for (EditOp &op : removals[t])
            ops.push_back(std::move(op));
        for (EditOp &op : inserts[t])
            ops.push_back(std::move(op));
    }
    if (ops.empty())
        return;
    pushEdit(tr("resize %n note(s)", nullptr, int(notes.size())), std::move(ops));
}

void SongDocument::setNotesVelocity(const std::vector<DocNote> &notes, uint8_t velocity)
{
    if (notes.empty())
        return;
    const uint8_t target = clampVelocity(velocity);
    std::vector<EditOp> ops;
    for (const DocNote &note : notes) {
        if (note.velocity == target)
            continue;
        EditOp op;
        op.type = EditOp::ModifyEvent;
        op.smfTrack = note.smfTrack;
        op.index = note.onIndex;
        op.event = makeChannelEvent(0x9, note.channel, note.tick, note.key, target);
        ops.push_back(op);
    }
    pushEdit(tr("set velocity"), std::move(ops));
}

std::optional<uint64_t>
SongDocument::setNotesVelocities(uint64_t expectedRevision,
                                 const std::vector<NoteVelocity> &velocities)
{
    if (expectedRevision != m_revision)
        return std::nullopt;
    struct ResolvedVelocity {
        DocNote note;
        int velocity = 1;
    };
    std::vector<ResolvedVelocity> resolved;
    resolved.reserve(velocities.size());
    for (const NoteVelocity &velocity : velocities) {
        DocNote note;
        if (!findNote(velocity.noteId, &note))
            return std::nullopt;
        const auto it = std::find_if(resolved.begin(), resolved.end(),
                                     [&note](const ResolvedVelocity &candidate) {
                                         return candidate.note.noteId == note.noteId;
                                     });
        if (it == resolved.end())
            resolved.push_back({note, velocity.velocity});
        else
            it->velocity = velocity.velocity;
    }
    std::vector<EditOp> ops;
    for (const ResolvedVelocity &item : resolved) {
        const uint8_t target = clampVelocity(item.velocity);
        if (item.note.velocity == target)
            continue;
        SmfEvent event = m_smf.tracks[size_t(item.note.smfTrack)].events[item.note.onIndex];
        event.data1 = target;
        EditOp op;
        op.type = EditOp::ModifyEvent;
        op.smfTrack = item.note.smfTrack;
        op.index = item.note.onIndex;
        op.event = std::move(event);
        ops.push_back(std::move(op));
    }
    if (ops.empty())
        return expectedRevision;
    pushEdit(tr("paint note velocities"), std::move(ops));
    return m_revision;
}

void SongDocument::nudgeNotesVelocity(const std::vector<DocNote> &notes, int delta)
{
    if (notes.empty() || delta == 0)
        return;
    const auto velocityFor = [delta](const DocNote &note) {
        return clampVelocity(int(note.velocity) + delta);
    };
    std::vector<EditOp> ops;
    for (const DocNote &note : notes) {
        if (velocityFor(note) == note.velocity)
            continue;
        EditOp op;
        op.type = EditOp::ModifyEvent;
        op.smfTrack = note.smfTrack;
        op.index = note.onIndex;
        op.event = makeChannelEvent(0x9, note.channel, note.tick, note.key, velocityFor(note));
        ops.push_back(op);
    }
    pushEdit(tr("adjust velocity"), std::move(ops));
}

void SongDocument::insertRawEvent(int smfTrack, const SmfEvent &event)
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()) ||
        // Raw FF 51 is rejected because Tempo lives in tempoPoints.
        isTempoMeta(event))
        return;
    std::vector<EditOp> ops;
    EditOp op;
    op.type = EditOp::InsertEvent;
    op.smfTrack = smfTrack;
    op.event = event;
    ops.push_back(op);
    pushEdit(tr("insert event"), std::move(ops));
}

void SongDocument::modifyRawEvent(int smfTrack, size_t index, const SmfEvent &event)
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()) ||
        index >= m_smf.tracks[smfTrack].events.size() ||
        // Raw FF 51 is rejected because Tempo lives in tempoPoints.
        isTempoMeta(event))
        return;
    if (m_smf.tracks[smfTrack].events[index] == event)
        return;
    std::vector<EditOp> ops;
    appendEventEditOps(ops, smfTrack, index, event);
    pushEdit(tr("edit event"), std::move(ops));
}

void SongDocument::deleteRawEvents(int smfTrack, std::vector<size_t> indices)
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()))
        return;
    const size_t count = m_smf.tracks[smfTrack].events.size();
    std::erase_if(indices, [count](size_t i) { return i >= count; });
    if (indices.empty())
        return;
    std::vector<EditOp> ops;
    appendRemoveOps(ops, smfTrack, std::move(indices));
    pushEdit(tr("delete %n event(s)", nullptr, int(ops.size())), std::move(ops));
}

bool SongDocument::rawEventMoveBounds(int smfTrack, size_t index, size_t *first, size_t *last) const
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()))
        return false;
    const auto &evs = m_smf.tracks[smfTrack].events;
    if (index >= evs.size())
        return false;
    const SmfEvent &moved = evs[index];
    size_t lo = index;
    while (lo > 0 && evs[lo - 1].tick == moved.tick && !pinnedBefore(evs[lo - 1], moved))
        lo--;
    size_t hi = index;
    while (hi + 1 < evs.size() && evs[hi + 1].tick == moved.tick &&
           !pinnedBefore(moved, evs[hi + 1]))
        hi++;
    *first = lo;
    *last = hi;
    return true;
}

void SongDocument::moveRawEvent(int smfTrack, size_t index, size_t destIndex)
{
    size_t first, last;
    if (!rawEventMoveBounds(smfTrack, index, &first, &last))
        return;
    destIndex = std::clamp(destIndex, first, last);
    if (destIndex == index)
        return;
    std::vector<EditOp> ops;
    EditOp op;
    op.type = EditOp::MoveEvent;
    op.smfTrack = smfTrack;
    op.index = index;
    op.indexTo = destIndex;
    ops.push_back(op);
    pushEdit(tr("reorder event"), std::move(ops));
}

void SongDocument::setTrackEndTick(int smfTrack, Tick tick)
{
    if (smfTrack < 0 || smfTrack >= int(m_smf.tracks.size()))
        return;
    const SmfTrack &track = m_smf.tracks[smfTrack];
    // Ticks are non-decreasing, so the last event is the latest.
    const Tick minTick = track.events.empty() ? 0 : track.events.back().tick;
    tick = std::max(tick, minTick);
    if (tick == track.endTick)
        return;
    std::vector<EditOp> ops;
    EditOp op;
    op.type = EditOp::SetTrackEnd;
    op.smfTrack = smfTrack;
    op.event.tick = tick;
    ops.push_back(op);
    pushEdit(tr("move end of track"), std::move(ops));
}

void SongDocument::setLoopTick(bool endMarker, int64_t tick)
{
    if (m_smf.tracks.empty())
        return;
    std::vector<EditOp> ops;
    int smfTrack;
    size_t index;
    const bool exists = findLoopMarkerEvent(endMarker, &smfTrack, &index);
    if (!exists && tick < 0)
        return;

    SmfEvent markerEvent;
    if (exists) {
        markerEvent = m_smf.tracks[smfTrack].events[index];
        EditOp remove;
        remove.type = EditOp::RemoveEvent;
        remove.smfTrack = smfTrack;
        remove.index = index;
        ops.push_back(remove);
    } else {
        // New markers go in the first chunk — the only place mid2agb reads
        // seq events from — as a Marker meta.
        markerEvent.status = 0xFF;
        markerEvent.metaType = 0x06;
        markerEvent.blob = QByteArray(1, endMarker ? ']' : '[');
        smfTrack = 0;
    }
    if (tick >= 0) {
        markerEvent.tick = Tick(tick);
        EditOp insert;
        insert.type = EditOp::InsertEvent;
        insert.smfTrack = smfTrack;
        insert.event = markerEvent;
        ops.push_back(insert);
    }
    pushEdit(endMarker ? tr("set loop end") : tr("set loop start"), std::move(ops));
}

void SongDocument::setTimeSig(Tick tick, int numerator, int denomPow2)
{
    if (m_smf.tracks.empty())
        return;
    const char nn = char(std::clamp(numerator, 1, 64));
    const char dd = char(std::clamp(denomPow2, 0, 6));
    // The bar grid honors the last 0x58 at a tick; modify that one in place
    // so it keeps its chunk, its position within the tick group, and its
    // metronome/32nds bytes.
    DocTimeSig target;
    bool exists = false;
    for (const DocTimeSig &sig : timeSigs()) {
        if (sig.tick == tick) {
            target = sig;
            exists = true;
        }
    }
    std::vector<EditOp> ops;
    EditOp op;
    if (exists) {
        if (char(target.numerator) == nn && char(target.denomPow2) == dd)
            return;
        op.type = EditOp::ModifyEvent;
        op.smfTrack = target.smfTrack;
        op.index = target.index;
        op.event = m_smf.tracks[target.smfTrack].events[target.index];
    } else {
        // New signatures go in the first chunk — the seq chunk, where tempo
        // and new loop markers live — with mid2agb's usual metronome bytes.
        op.type = EditOp::InsertEvent;
        op.smfTrack = 0;
        op.event.tick = tick;
        op.event.status = 0xFF;
        op.event.metaType = 0x58;
        op.event.blob = QByteArray("\x00\x00\x18\x08", 4);
    }
    op.event.blob[0] = nn;
    op.event.blob[1] = dd;
    ops.push_back(op);
    pushEdit(tr("set time signature"), std::move(ops));
}

void SongDocument::moveTimeSig(Tick fromTick, Tick toTick)
{
    if (fromTick == toTick)
        return;
    const std::vector<DocTimeSig> sigs = timeSigs();
    std::vector<EditOp> ops;
    std::vector<EditOp> inserts;
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        std::vector<size_t> indices;
        for (const DocTimeSig &sig : sigs) {
            // A signature already at the destination is overwritten.
            if (sig.smfTrack != int(t) || (sig.tick != fromTick && sig.tick != toTick))
                continue;
            indices.push_back(sig.index);
            if (sig.tick == fromTick) {
                EditOp insert;
                insert.type = EditOp::InsertEvent;
                insert.smfTrack = int(t);
                insert.event = m_smf.tracks[t].events[sig.index];
                insert.event.tick = toTick;
                inserts.push_back(insert);
            }
        }
        appendRemoveOps(ops, int(t), std::move(indices));
    }
    if (inserts.empty())
        return;
    ops.insert(ops.end(), inserts.begin(), inserts.end());
    pushEdit(tr("move time signature"), std::move(ops));
}

void SongDocument::deleteTimeSig(Tick tick)
{
    std::vector<EditOp> ops;
    for (size_t t = 0; t < m_smf.tracks.size(); t++) {
        std::vector<size_t> indices;
        for (const DocTimeSig &sig : timeSigs()) {
            if (sig.smfTrack == int(t) && sig.tick == tick)
                indices.push_back(sig.index);
        }
        appendRemoveOps(ops, int(t), std::move(indices));
    }
    if (ops.empty())
        return;
    pushEdit(tr("delete time signature"), std::move(ops));
}

int SongDocument::freeChannel() const
{
    bool used[16] = {};
    for (uint8_t c : m_engineChannel)
        used[c] = true;
    for (int c = 0; c < 16; c++) {
        if (!used[c])
            return c;
    }
    return -1;
}

bool SongDocument::canAddTrack() const
{
    if (m_smf.tracks.empty())
        return false;
    if (engineTrackCount() >= track_limits::kHardwareCapacity)
        return false;
    return freeChannel() >= 0;
}

int SongDocument::addTrack(int voice)
{
    if (!canAddTrack())
        return -1;
    const int channel = freeChannel();
    std::vector<EditOp> ops;
    const int smfTrack = int(m_smf.tracks.size());
    EditOp insert;
    insert.type = EditOp::InsertTrack;
    insert.smfTrack = smfTrack;
    ops.push_back(insert);
    EditOp seed;
    seed.type = EditOp::InsertEvent;
    seed.smfTrack = smfTrack;
    seed.event = makeChannelEvent(0xC, uint8_t(channel), 0, uint8_t(std::clamp(voice, 0, 127)), 0);
    ops.push_back(seed);
    pushEdit(tr("add track"), std::move(ops));

    for (int t = 0; t < engineTrackCount(); t++) {
        if (m_engineToSmf[t] == smfTrack)
            return t;
    }
    return -1;
}

int SongDocument::duplicateTrack(int engineTrack)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0 || !canAddTrack())
        return -1;
    const int channel = freeChannel();
    const uint8_t sourceChannel = channelFor(engineTrack);
    const SmfTrack &src = m_smf.tracks[smfTrack];
    std::vector<EditOp> ops;
    const int newSmfTrack = int(m_smf.tracks.size());
    EditOp insert;
    insert.type = EditOp::InsertTrack;
    insert.smfTrack = newSmfTrack;
    insert.trackData.endTick = src.endTick;
    for (const SmfEvent &ev : src.events) {
        if (ev.isChannel()) {
            if (ev.channel() != sourceChannel)
                continue;
            SmfEvent copy = ev;
            copy.status = uint8_t((ev.status & 0xF0) | channel);
            insert.trackData.events.push_back(copy);
        }
    }
    if (insert.trackData.events.empty())
        return -1;
    ops.push_back(std::move(insert));
    pushEdit(tr("duplicate track"), std::move(ops));

    for (int t = 0; t < engineTrackCount(); t++) {
        if (m_engineToSmf[t] == newSmfTrack)
            return t;
    }
    return -1;
}

void SongDocument::deleteTrack(int engineTrack)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return;
    std::vector<EditOp> ops;
    const auto &evs = m_smf.tracks[smfTrack].events;
    if (smfTrack == 0) {
        // Chunk 0 stays (it is the seq chunk): strip the track's channel
        // events, keep everything else.
        std::vector<size_t> indices;
        for (size_t i = 0; i < evs.size(); i++) {
            if (evs[i].isChannel())
                indices.push_back(i);
        }
        appendRemoveOps(ops, smfTrack, std::move(indices));
    } else {
        // Time signatures in the doomed chunk shape the whole song's bar
        // grid; move them to chunk 0 so the grid survives.
        for (const SmfEvent &ev : evs) {
            if (metaIsTimeSig(ev)) {
                EditOp rescue;
                rescue.type = EditOp::InsertEvent;
                rescue.smfTrack = 0;
                rescue.event = ev;
                ops.push_back(rescue);
            }
        }
        // If the winning loop marker lives in the doomed chunk, move it to
        // chunk 0 (where setLoopTick puts new ones) so the loop survives.
        for (int endMarker = 0; endMarker <= 1; endMarker++) {
            int markerTrack;
            size_t markerIndex;
            if (findLoopMarkerEvent(endMarker != 0, &markerTrack, &markerIndex) &&
                markerTrack == smfTrack) {
                EditOp rescue;
                rescue.type = EditOp::InsertEvent;
                rescue.smfTrack = 0;
                rescue.event = evs[markerIndex];
                ops.push_back(rescue);
            }
        }
        EditOp remove;
        remove.type = EditOp::RemoveTrack;
        remove.smfTrack = smfTrack;
        ops.push_back(remove);
    }
    pushEdit(tr("delete track"), std::move(ops));
}

bool nameIsLoopMarker(const QString &name)
{
    return smfTextIsMarker(name);
}

namespace {

// Latin-1 (SMF text metas have no declared encoding), capped at 64 chars,
// trimmed — MidiTimeline's reading of a name meta's text.
QString trackNameText(const SmfEvent &ev)
{
    const int len = std::min<int>(int(ev.blob.size()), 64);
    return QString::fromLatin1(ev.blob.constData(), len).trimmed();
}

// Where the track's display name lives, mirroring MidiTimeline's reader:
// the chunk's first unprefixed 0x03. An 0x03 scoped to a channel by a MIDI
// Channel Prefix (SmfChannelPrefix — format 0's per-track naming mechanism;
// conversion rewrites those, but a foreign format-1 file may still carry
// them) is never a chunk name. SIZE_MAX when absent.
size_t trackNameLoc(const SmfTrack &track)
{
    SmfChannelPrefix prefix;
    for (size_t i = 0; i < track.events.size(); i++) {
        const SmfEvent &ev = track.events[i];
        prefix.observe(ev);
        if (ev.isMeta() && ev.metaType == 0x03 && prefix.channel < 0)
            return i;
    }
    return SIZE_MAX;
}

std::vector<size_t> trackNameLocs(const SmfTrack &track)
{
    std::vector<size_t> locations;
    SmfChannelPrefix prefix;
    for (size_t i = 0; i < track.events.size(); i++) {
        const SmfEvent &ev = track.events[i];
        prefix.observe(ev);
        if (ev.isMeta() && ev.metaType == 0x03 && prefix.channel < 0)
            locations.push_back(i);
    }
    return locations;
}

} // namespace

QString SongDocument::trackName(int engineTrack) const
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return QString();
    const SmfTrack &track = m_smf.tracks[smfTrack];
    const size_t nameIndex = trackNameLoc(track);
    return nameIndex == SIZE_MAX ? QString() : trackNameText(track.events[nameIndex]);
}

void SongDocument::renameTrack(int engineTrack, const QString &name)
{
    const int smfTrack = smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return;
    const QString trimmed = name.trimmed().left(64);
    if (nameIsLoopMarker(trimmed))
        return;
    const SmfTrack &track = m_smf.tracks[smfTrack];
    std::vector<size_t> nameIndices = trackNameLocs(track);

    std::vector<EditOp> ops;
    if (!nameIndices.empty()) {
        const size_t first = nameIndices.front();
        if (trimmed.isEmpty()) {
            appendRemoveOps(ops, smfTrack, std::move(nameIndices));
        } else {
            nameIndices.erase(nameIndices.begin());
            appendRemoveOps(ops, smfTrack, std::move(nameIndices));
            if (trackNameText(track.events[first]) != trimmed) {
                EditOp op;
                op.type = EditOp::ModifyEvent;
                op.smfTrack = smfTrack;
                op.index = first;
                op.event = track.events[first];
                op.event.blob = trimmed.toLatin1();
                ops.push_back(op);
            }
        }
    } else {
        if (trimmed.isEmpty())
            return;
        EditOp op;
        op.type = EditOp::InsertEvent;
        op.smfTrack = smfTrack;
        op.event.tick = 0;
        op.event.status = 0xFF;
        op.event.metaType = 0x03;
        op.event.blob = trimmed.toLatin1();
        ops.push_back(op);
    }
    if (ops.empty())
        return;
    pushEdit(tr("rename track"), std::move(ops));
}

bool SongDocument::moveTrack(int engineTrack, int targetEngine)
{
    if (engineTrack == targetEngine)
        return false;
    const int fromChunk = smfTrackFor(engineTrack);
    const int toChunk = smfTrackFor(targetEngine);
    if (fromChunk < 0 || toChunk < 0)
        return false;

    std::vector<EditOp> ops;
    // mid2agb reads time signatures and loop markers only from the first chunk.
    // When the move changes which chunk is first, those globals stay with
    // position 0: strip them from the old seq chunk and re-insert into the new
    // one. Everything else — channel events, the track's name meta — travels
    // with its chunk.
    std::vector<SmfEvent> rescued;
    if (fromChunk == 0 || toChunk == 0) {
        const auto &evs = m_smf.tracks[0].events;
        std::vector<size_t> indices;
        // Classify exactly as the canonical readers do: time signatures via
        // metaIsTimeSig, and the whole marker family mid2agb understands
        // (smfMetaIsMarker, the same set renameTrack refuses). Name metas — the
        // chunk's name (first unprefixed 0x03, marker text included) and
        // channel-scoped non-marker 0x03s, as findLoopMarkerEvent and
        // MidiTimeline classify them — are never markers: they travel with
        // their chunk.
        bool nameSeen = false;
        SmfChannelPrefix prefix;
        for (size_t i = 0; i < evs.size(); i++) {
            const SmfEvent &ev = evs[i];
            prefix.observe(ev);
            if (!ev.isMeta())
                continue;
            if (ev.metaType == 0x03 && (prefix.channel >= 0 ? !smfMetaIsMarker(ev) : !nameSeen)) {
                if (prefix.channel < 0)
                    nameSeen = true;
                continue;
            }
            const bool marker = smfMetaIsMarker(ev);
            if (metaIsTimeSig(ev) || marker) {
                indices.push_back(i);
                rescued.push_back(ev);
            }
        }
        appendRemoveOps(ops, 0, std::move(indices));
    }
    EditOp move;
    move.type = EditOp::MoveTrack;
    move.smfTrack = fromChunk;
    move.smfTrackTo = toChunk;
    ops.push_back(move);
    // Re-inserted in original order: InsertEvent lands each at the end of
    // its tick group, so same-tick globals keep their relative order (the
    // last signature at a tick is the one that wins).
    for (const SmfEvent &ev : rescued) {
        EditOp insert;
        insert.type = EditOp::InsertEvent;
        insert.smfTrack = 0;
        insert.event = ev;
        ops.push_back(insert);
    }
    pushEdit(tr("move track"), std::move(ops));
    return true;
}

void SongDocument::setCfg(const SongCfg &cfg)
{
    if (cfgSemanticEqual(cfg, m_cfg))
        return;
    m_history.pushDocument(std::make_unique<SongCfgCommand>(this, cfg));
}

std::unique_ptr<MidiTimeline> SongDocument::buildTimeline(double sampleRate) const
{
    auto timeline = MidiTimeline::build(m_smf, m_tempoPoints, sampleRate);
    if (timeline)
        timeline->extendedClocks = m_cfg.extendedClocks;
    return timeline;
}

// The insertion primitive behind EditOp::InsertEvent placement and the
// detached export copy; see the declaration in songdocument.h.
size_t SongDocument::insertEventIntoTrack(SmfTrack &track, const SmfEvent &event)
{
    auto &events = track.events;
    auto it = std::upper_bound(
        events.begin(), events.end(), event.tick,
        [](Tick tick, const SmfEvent &candidate) { return tick < candidate.tick; });
    // Canonical placement within the tick group: walk back over same-tick
    // events the new one is pinned ahead of — a setup event over notes, a
    // note-end over note-ons. Metas, sysex and unconstrained channel types
    // are barriers the insertion never crosses.
    while (it != events.begin()) {
        const SmfEvent &previous = *std::prev(it);
        if (previous.tick != event.tick || !pinnedBefore(event, previous))
            break;
        --it;
    }
    const size_t index = size_t(it - events.begin());
    events.insert(it, event);
    if (event.tick > track.endTick)
        track.endTick = event.tick;
    return index;
}

void SongDocument::applyOps(std::vector<EditOp> &ops)
{
    for (EditOp &op : ops) {
        switch (op.type) {
        case EditOp::InsertEvent: {
            Q_ASSERT(!isTempoMeta(op.event));
            SmfTrack &track = m_smf.tracks[op.smfTrack];
            if (op.event.isNoteOn() && !op.preservesNoteId) {
                op.event.noteId = NoteId{};
                mintNoteId(&op.event);
                op.preservesNoteId = true;
            }
            op.oldEndTick = track.endTick;
            op.index = insertEventIntoTrack(track, op.event);
            break;
        }
        case EditOp::RemoveEvent: {
            auto &events = m_smf.tracks[op.smfTrack].events;
            op.oldEvent = events[op.index];
            events.erase(events.begin() + long(op.index));
            break;
        }
        case EditOp::ModifyEvent: {
            Q_ASSERT(!isTempoMeta(op.event));
            auto &events = m_smf.tracks[op.smfTrack].events;
            op.oldEvent = events[op.index];
            if (op.event.isNoteOn()) {
                if (op.oldEvent.isNoteOn()) {
                    op.event.noteId = op.oldEvent.noteId;
                } else if (!op.preservesNoteId) {
                    op.event.noteId = NoteId{};
                    mintNoteId(&op.event);
                    op.preservesNoteId = true;
                }
            } else {
                op.event.noteId = NoteId{};
            }
            events[op.index] = op.event;
            break;
        }
        case EditOp::MoveEvent: {
            auto &events = m_smf.tracks[op.smfTrack].events;
            const SmfEvent event = events[op.index];
            events.erase(events.begin() + long(op.index));
            events.insert(events.begin() + long(op.indexTo), event);
            break;
        }
        case EditOp::InsertTrack:
            if (!op.preservesNoteId) {
                for (SmfEvent &event : op.trackData.events) {
                    event.noteId = NoteId{};
                    mintNoteId(&event);
                }
                op.preservesNoteId = true;
            }
            m_smf.tracks.insert(m_smf.tracks.begin() + long(op.smfTrack), op.trackData);
            break;
        case EditOp::RemoveTrack:
            op.trackData = m_smf.tracks[op.smfTrack];
            m_smf.tracks.erase(m_smf.tracks.begin() + long(op.smfTrack));
            break;
        case EditOp::SetTrackEnd: {
            SmfTrack &track = m_smf.tracks[op.smfTrack];
            op.oldEndTick = track.endTick;
            track.endTick = op.event.tick;
            break;
        }
        case EditOp::MoveTrack:
            moveChunk(m_smf.tracks, op.smfTrack, op.smfTrackTo);
            break;
        }
    }
}

void SongDocument::revertOps(std::vector<EditOp> &ops)
{
    for (auto it = ops.rbegin(); it != ops.rend(); ++it) {
        EditOp &op = *it;
        switch (op.type) {
        case EditOp::InsertEvent: {
            SmfTrack &track = m_smf.tracks[op.smfTrack];
            track.events.erase(track.events.begin() + long(op.index));
            track.endTick = op.oldEndTick;
            break;
        }
        case EditOp::RemoveEvent: {
            auto &events = m_smf.tracks[op.smfTrack].events;
            events.insert(events.begin() + long(op.index), op.oldEvent);
            break;
        }
        case EditOp::ModifyEvent:
            m_smf.tracks[op.smfTrack].events[op.index] = op.oldEvent;
            break;
        case EditOp::MoveEvent: {
            auto &events = m_smf.tracks[op.smfTrack].events;
            const SmfEvent event = events[op.indexTo];
            events.erase(events.begin() + long(op.indexTo));
            events.insert(events.begin() + long(op.index), event);
            break;
        }
        case EditOp::InsertTrack:
            m_smf.tracks.erase(m_smf.tracks.begin() + long(op.smfTrack));
            break;
        case EditOp::RemoveTrack:
            m_smf.tracks.insert(m_smf.tracks.begin() + long(op.smfTrack), op.trackData);
            break;
        case EditOp::SetTrackEnd:
            m_smf.tracks[op.smfTrack].endTick = op.oldEndTick;
            break;
        case EditOp::MoveTrack:
            moveChunk(m_smf.tracks, op.smfTrackTo, op.smfTrack);
            break;
        }
    }
}

void SongDocument::pushEdit(const QString &text, std::vector<EditOp> ops)
{
    if (ops.empty())
        return;
    m_history.pushDocument(std::make_unique<SongEditCommand>(this, text, std::move(ops)));
}
