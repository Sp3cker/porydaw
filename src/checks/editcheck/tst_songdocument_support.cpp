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
    return {tick, 60'000'000U / bpm};
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
        endTick = std::max(endTick, track.endTick);
    return endTick + uint64_t(document.ticksPerClock()) * 100;
}

} // namespace songdocument_test
