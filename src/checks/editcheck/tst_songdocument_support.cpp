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

bool notePairsConsistent(const SongDocument &document, int engineTrack)
{
    const int smfTrack = document.smfTrackFor(engineTrack);
    if (smfTrack < 0 || smfTrack >= int(document.smf().tracks.size()))
        return false;

    const uint8_t channel = document.channelFor(engineTrack);
    const auto &events = document.smf().tracks[size_t(smfTrack)].events;
    const auto notes = document.notesForTrack(engineTrack);

    for (const DocNote &note : notes) {
        if (note.engineTrack != engineTrack || note.smfTrack != smfTrack ||
            note.channel != channel || note.unterminated() || note.duration == 0 ||
            note.onIndex >= events.size() || note.endIndex >= events.size() ||
            note.endIndex <= note.onIndex)
            return false;

        const SmfEvent &on = events[note.onIndex];
        const SmfEvent &end = events[note.endIndex];
        if (!on.isChannel() || !on.isNoteOn() || on.channel() != channel || on.data0 != note.key ||
            on.data1 != note.velocity || on.tick != note.tick || !end.isChannel() ||
            !end.isNoteEnd() || end.channel() != channel || end.data0 != note.key ||
            end.tick <= on.tick || uint64_t(end.tick) - uint64_t(on.tick) != note.duration)
            return false;
    }

    for (size_t index = 0; index < events.size(); ++index) {
        const SmfEvent &event = events[index];
        if (!event.isChannel() || event.channel() != channel)
            continue;

        const bool isOn = event.isNoteOn();
        const bool isEnd = event.isNoteEnd();
        if (!isOn && !isEnd)
            continue;

        size_t claims = 0;
        for (const DocNote &note : notes) {
            if ((isOn && note.onIndex == index) || (isEnd && note.endIndex == index))
                ++claims;
        }
        if (claims != 1)
            return false;
    }

    for (size_t left = 0; left < notes.size(); ++left) {
        for (size_t right = left + 1; right < notes.size(); ++right) {
            if (notes[left].key != notes[right].key)
                continue;

            const uint64_t leftEnd = uint64_t(notes[left].tick) + notes[left].duration;
            const uint64_t rightEnd = uint64_t(notes[right].tick) + notes[right].duration;
            if (uint64_t(notes[left].tick) < rightEnd && uint64_t(notes[right].tick) < leftEnd)
                return false;
        }
    }

    return true;
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
