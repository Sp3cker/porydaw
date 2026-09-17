#include "checks/editcheck/tst_songdocument_support.h"

#include <algorithm>
#include <utility>

namespace songdocument_test {

bool SyntheticDocument::stage(SmfFile smf, const QString &label)
{
    if (!directory.isValid()) {
        error = QStringLiteral("could not create synthetic project directory");
        return false;
    }

    song.label = label;
    song.midPath = directory.filePath(label + QStringLiteral(".mid"));
    song.hasMid = true;
    return smf.writeFile(song.midPath, &error) && document.load(song, &error);
}

std::unique_ptr<SyntheticDocument> makeDocument(SmfFile smf, const QString &label)
{
    auto fixture = std::make_unique<SyntheticDocument>();
    if (!fixture->stage(std::move(smf), label))
        return nullptr;
    return fixture;
}

SmfEvent channel(uint8_t status, uint64_t tick, uint8_t data0, uint8_t data1)
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

SmfEvent meta(uint8_t type, uint64_t tick, const QByteArray &blob)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xFF;
    event.metaType = type;
    event.blob = blob;
    return event;
}

SmfTrack conductor()
{
    SmfTrack track;
    track.events.push_back(meta(0x01, 0, QByteArrayLiteral("contract fixture")));
    track.endTick = 48;
    return track;
}

TempoPoint tempo(uint64_t tick, uint32_t bpm)
{
    return {Tick(tick), 60'000'000U / bpm};
}

bool containsTempo(const SongDocument &document, const TempoPoint &point)
{
    return std::find(document.tempoPoints().begin(), document.tempoPoints().end(), point) !=
           document.tempoPoints().end();
}

bool tracksSorted(const SmfFile &smf)
{
    return std::ranges::all_of(smf.tracks, [](const SmfTrack &track) {
        return std::ranges::is_sorted(track.events, {}, &SmfEvent::tick);
    });
}

bool noteEndsBeforeOnsAt(const SongDocument &document, int engineTrack, uint64_t tick)
{
    const int smfTrack = document.smfTrackFor(engineTrack);
    if (smfTrack < 0)
        return true;

    bool sawNoteOn = false;
    for (const SmfEvent &event : document.smf().tracks[size_t(smfTrack)].events) {
        if (event.tick != tick || !event.isChannel())
            continue;
        if (event.isNoteOn())
            sawNoteOn = true;
        else if (event.isNoteEnd() && sawNoteOn)
            return false;
    }
    return true;
}

bool notePairsConsistent(const SongDocument &document, int engineTrack)
{
    const int track = document.smfTrackFor(engineTrack);
    if (track < 0)
        return false;
    const auto &events = document.smf().tracks[size_t(track)].events;
    const auto notes = document.notesForTrack(engineTrack);
    std::vector<unsigned> starts(events.size()), ends(events.size());
    uint64_t lastEnd[128] = {};
    for (const DocNote &note : notes) {
        if (note.unterminated() || note.duration == 0 || note.onIndex >= events.size() ||
            note.endIndex >= events.size() || note.key >= 128 || note.tick < lastEnd[note.key])
            return false;
        const auto &on = events[note.onIndex];
        const auto &end = events[note.endIndex];
        if (!on.isNoteOn() || !end.isNoteEnd() || on.data0 != end.data0 ||
            on.channel() != end.channel() || end.tick <= on.tick ||
            uint64_t(on.tick) + note.duration != end.tick || ++starts[note.onIndex] != 1 ||
            ++ends[note.endIndex] != 1)
            return false;
        lastEnd[note.key] = end.tick;
    }
    for (size_t i = 0; i < events.size(); ++i) {
        const auto &event = events[i];
        if (!event.isChannel() || event.channel() != document.channelFor(engineTrack))
            continue;
        if ((event.isNoteOn() && starts[i] != 1) || (event.isNoteEnd() && ends[i] != 1))
            return false;
    }
    return true;
}

bool hasLiveTempo(const SongDocument &document)
{
    for (const SmfTrack &track : document.smf().tracks) {
        for (const SmfEvent &event : track.events) {
            if (isTempoMeta(event))
                return true;
        }
    }
    return false;
}

bool sameNotes(const std::vector<DocNote> &left, const std::vector<DocNote> &right)
{
    if (left.size() != right.size())
        return false;
    for (size_t index = 0; index < left.size(); ++index) {
        if (left[index].tick != right[index].tick || left[index].key != right[index].key ||
            left[index].duration != right[index].duration ||
            left[index].velocity != right[index].velocity)
            return false;
    }
    return true;
}

SavedDocState captureDocState(SongDocument &document, int engineTrack)
{
    SavedDocState state;
    state.bytes = document.smf().write();
    state.revision = document.revision();
    state.saveStateToken = document.captureSaveSnapshot().saveStateToken;
    state.undoCount = document.undoStack()->count();
    state.undoIndex = document.undoStack()->index();
    state.undoClean = document.undoStack()->isClean();
    state.canRedo = document.undoStack()->canRedo();
    state.engineTrackCount = document.engineTrackCount();
    state.tempos = document.tempoPoints();
    state.notes = document.notesForTrack(engineTrack);
    return state;
}

QString docStateMismatch(SongDocument &document, const SavedDocState &saved, int engineTrack)
{
    if (document.smf().write() != saved.bytes)
        return QStringLiteral("smf bytes");
    if (document.revision() != saved.revision)
        return QStringLiteral("revision");
    if (document.captureSaveSnapshot().saveStateToken != saved.saveStateToken)
        return QStringLiteral("save state token");
    if (document.undoStack()->count() != saved.undoCount)
        return QStringLiteral("undo count");
    if (document.undoStack()->index() != saved.undoIndex)
        return QStringLiteral("undo index");
    if (document.undoStack()->isClean() != saved.undoClean)
        return QStringLiteral("undo clean");
    if (document.undoStack()->canRedo() != saved.canRedo)
        return QStringLiteral("can redo");
    if (document.engineTrackCount() != saved.engineTrackCount)
        return QStringLiteral("engine track count");
    if (!(document.tempoPoints() == saved.tempos))
        return QStringLiteral("tempo points");
    const auto notes = document.notesForTrack(engineTrack);
    if (notes.size() != saved.notes.size())
        return QStringLiteral("note count");
    for (size_t i = 0; i < notes.size(); ++i) {
        if (notes[i].noteId != saved.notes[i].noteId)
            return QStringLiteral("note id at %1").arg(i);
        if (notes[i].velocity != saved.notes[i].velocity)
            return QStringLiteral("note velocity at %1").arg(i);
    }
    return {};
}

bool findsTimeSig(const SongDocument &document, uint64_t tick, DocTimeSig *out)
{
    for (const DocTimeSig &signature : document.timeSigs()) {
        if (signature.tick == tick) {
            *out = signature;
            return true;
        }
    }
    return false;
}

int firstEditableTrack(const SongDocument &document)
{
    for (int track = 0; track < document.engineTrackCount(); ++track) {
        if (!document.notesForTrack(track).empty())
            return track;
    }
    return -1;
}

uint64_t distantBase(const SongDocument &document)
{
    uint64_t endTick = 0;
    for (const SmfTrack &track : document.smf().tracks)
        endTick = std::max(endTick, uint64_t(track.endTick));
    return endTick + uint64_t(document.ticksPerClock()) * 100;
}

} // namespace songdocument_test
