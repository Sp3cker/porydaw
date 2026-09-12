#include "miditimeline.h"

#include <algorithm>

#include "smf.h"
#include "timedefaults.h"

namespace {

struct RawEvent {
    Tick tick;
    uint16_t smfTrack;
    uint8_t type;
    uint8_t data0;
    uint8_t data1;
    NoteId noteId;
    int origIndex; // insertion order: stable-sort tiebreaker so setup events
                   // (program change, CC) stay ahead of note-ons at the same tick
};

// Parsed-but-not-played data destined for MidiTimeline::otherEvents; the
// engine track is resolved after all tracks are mapped.
struct RawOther {
    Tick tick;
    uint16_t smfTrack;
    QString label;
};

// True when buf is exactly the single character `marker` after stripping
// leading/trailing ASCII whitespace.
bool textIsLoopMarker(const char *buf, uint32_t len, char marker)
{
    uint32_t s = 0, e = len;
    while (s < e && (buf[s] == ' ' || buf[s] == '\t' || buf[s] == '\r' || buf[s] == '\n'))
        s++;
    while (e > s &&
           (buf[e - 1] == ' ' || buf[e - 1] == '\t' || buf[e - 1] == '\r' || buf[e - 1] == '\n'))
        e--;
    return (e - s == 1) && buf[s] == marker;
}

// The canonical tick <-> sample conversion table: built once, before any
// sample position, and shared by every consumer (events, loop endpoints,
// other-event positions, sampleForTick/tickForSample) so a position is
// rounded exactly once. Segment origins accumulate unrounded in double; a
// segment's length is
//   double(deltaTicks) * double(uspqn) / double(tpqn) / 1000000.0 * sampleRate
// with the exact FF 51 microseconds-per-quarter-note. Same-tick entries keep
// file order; conversion is last-wins.
std::vector<TempoMapPoint> buildTempoMap(const std::vector<TempoPoint> &tempoPoints, uint32_t tpqn,
                                         double sampleRate)
{
    std::vector<TempoMapPoint> map;
    map.reserve(tempoPoints.size() + 1);
    if (tempoPoints.empty() || tempoPoints.front().tick != 0) {
        // SMF default tempo at tick 0.
        map.push_back({0, 0.0, 120.0, 500000});
    }
    double origin = 0.0;
    for (const TempoPoint &tc : tempoPoints) {
        if (!map.empty()) {
            // Length of the segment the previous point closes: its own tempo.
            const TempoMapPoint &prev = map.back();
            origin = prev.samplePos + double(tc.tick - prev.tick) *
                                          double(prev.microsecondsPerQuarterNote) / double(tpqn) /
                                          1000000.0 * sampleRate;
        }
        map.push_back({tc.tick, origin, 60000000.0 / double(tc.microsecondsPerQuarterNote),
                       tc.microsecondsPerQuarterNote});
    }
    return map;
}

// Round a tick through the canonical tempo map: unrounded origin of the
// segment in effect plus that segment's exact length, rounded once — the
// same rounding the scheduled events use.
uint64_t quantizedSampleForTick(uint64_t tick, const std::vector<TempoMapPoint> &tempoMap,
                                uint32_t tpqn, double sampleRate)
{
    // tempoMap always has an entry at tick 0.
    const TempoMapPoint *tp = &tempoMap.front();
    for (const TempoMapPoint &p : tempoMap) {
        if (p.tick > tick)
            break;
        tp = &p;
    }
    const double segment = double(tick - tp->tick) * double(tp->microsecondsPerQuarterNote) /
                           double(tpqn) / 1000000.0 * sampleRate;
    return uint64_t(tp->samplePos + segment + 0.5);
}

TimelineEvent makeTempoEvent(uint64_t samplePos, Tick tick, double bpm)
{
    int b = static_cast<int>(bpm + 0.5);
    b = std::clamp(b, 1, 0x3FFF);
    TimelineEvent ev;
    ev.samplePos = samplePos;
    ev.tick = tick;
    ev.type = TIMELINE_EVT_TEMPO;
    ev.track = 0;
    ev.data0 = static_cast<uint8_t>(b & 0x7F);
    ev.data1 = static_cast<uint8_t>((b >> 7) & 0x7F);
    return ev;
}

} // namespace

std::unique_ptr<MidiTimeline> MidiTimeline::load(const QString &path, double sampleRate,
                                                 QString *error)
{
    SmfFile smf;
    if (!SmfFile::readFile(path, &smf, error)) // readFile coerces format 0 away
        return nullptr;
    return build(smf, sampleRate);
}

namespace {

std::vector<TempoPoint> extractTempoPoints(const SmfFile &smf)
{
    std::vector<TempoPoint> tempoPoints;
    for (const auto &track : smf.tracks) {
        for (const SmfEvent &event : track.events) {
            if (!event.isMeta() || event.metaType != 0x51 || event.blob.size() != 3)
                continue;
            const uint8_t *data = reinterpret_cast<const uint8_t *>(event.blob.constData());
            tempoPoints.push_back({event.tick, (static_cast<uint32_t>(data[0]) << 16) |
                                                   (static_cast<uint32_t>(data[1]) << 8) |
                                                   data[2]});
        }
    }
    // Stable sort preserves same-tick FF 51 events in file order.
    std::stable_sort(tempoPoints.begin(), tempoPoints.end(),
                     [](const TempoPoint &a, const TempoPoint &b) { return a.tick < b.tick; });
    return tempoPoints;
}

std::unique_ptr<MidiTimeline>
buildTimeline(const SmfFile &smf, const std::vector<TempoPoint> &tempoPoints, double sampleRate)
{
    const uint32_t tpqn = smf.division;
    const int numTracks = int(smf.tracks.size());

    std::vector<RawEvent> rawEvents;
    std::vector<TimeSigPoint> timeSigs;
    std::vector<RawOther> rawOthers;
    std::vector<QString> trackNames(numTracks);
    Tick loopStartTick = CoreTimeDefaults::kNoTick;
    Tick loopEndTick = CoreTimeDefaults::kNoTick;

    for (int t = 0; t < numTracks; t++) {
        // Channel Prefix scoping (SmfChannelPrefix, the shared rule):
        // format 0's per-track naming mechanism — conversion rewrites
        // those, but a foreign format-1 file may still carry prefixed
        // 0x03s, and they are never the chunk's name.
        SmfChannelPrefix prefix;
        for (const SmfEvent &sev : smf.tracks[t].events) {
            const Tick tick = sev.tick;
            prefix.observe(sev);

            if (sev.isChannel()) {
                const uint8_t type = sev.typeNibble();
                auto push = [&](uint8_t playType) {
                    RawEvent ev;
                    ev.tick = tick;
                    ev.smfTrack = uint16_t(t);
                    ev.type = playType;
                    ev.data0 = sev.data0;
                    ev.data1 = sev.data1;
                    ev.noteId = playType == 0x9 ? sev.noteId : NoteId{};
                    ev.origIndex = static_cast<int>(rawEvents.size());
                    rawEvents.push_back(ev);
                };
                switch (type) {
                case 0x8:
                    push(0x8);
                    break;
                case 0x9: // note on (velocity 0 means note off)
                    push(sev.data1 ? 0x9 : 0x8);
                    break;
                case 0xA: // polyphonic aftertouch: not played
                    rawOthers.push_back({tick, uint16_t(t),
                                         QStringLiteral("Poly aftertouch key %1 = %2")
                                             .arg(sev.data0)
                                             .arg(sev.data1)});
                    break;
                case 0xB:
                    push(0xB);
                    break;
                case 0xC:
                    push(0xC);
                    break;
                case 0xD: // channel pressure: not played
                    rawOthers.push_back(
                        {tick, uint16_t(t), QStringLiteral("Channel pressure %1").arg(sev.data0)});
                    break;
                case 0xE:
                    push(0xE);
                    break;
                }
            } else if (sev.isSysEx()) {
                rawOthers.push_back(
                    {tick, uint16_t(t), QStringLiteral("SysEx (%1 bytes)").arg(sev.blob.size())});
            } else if (sev.isMeta()) {
                const uint8_t metaType = sev.metaType;
                const QByteArray &blob = sev.blob;
                if (metaType == 0x51 && blob.size() == 3)
                    continue;
                if (metaType == 0x58 && blob.size() >= 2) {
                    timeSigs.push_back({tick, uint8_t(blob[0]), uint8_t(blob[1])});
                } else if (metaType == 0x20 && blob.size() >= 1) {
                    // Channel Prefix: scoping handled by `prefix` above.
                } else if (metaType == 0x03 && prefix.channel >= 0 && !smfMetaIsMarker(sev)) {
                    // A channel-scoped name: not this chunk's. Marker text
                    // is exempt — mid2agb reads markers regardless of the
                    // prefix, so it falls through to the marker check.
                } else if (metaType == 0x03 && prefix.channel < 0 && trackNames[t].isEmpty()) {
                    const int len = std::min<int>(blob.size(), 64);
                    trackNames[t] = QString::fromLatin1(blob.constData(), len).trimmed();
                } else if (metaType >= 0x01 && metaType <= 0x07) {
                    // Text-type meta: check for loop markers ('[' / ']').
                    const uint32_t len = uint32_t(std::min<int>(blob.size(), 32));
                    if (textIsLoopMarker(blob.constData(), len, '[') &&
                        loopStartTick == CoreTimeDefaults::kNoTick) {
                        loopStartTick = tick;
                    } else if (textIsLoopMarker(blob.constData(), len, ']') &&
                               loopEndTick == CoreTimeDefaults::kNoTick) {
                        loopEndTick = tick;
                    } else {
                        static const char *const kTextMetaNames[] = {
                            "Text",  "Copyright", "Track name", "Instrument",
                            "Lyric", "Marker",    "Cue point"};
                        const QString text =
                            QString::fromLatin1(blob.constData(), int(len)).trimmed();
                        if (!text.isEmpty())
                            rawOthers.push_back(
                                {tick, uint16_t(t),
                                 QStringLiteral("%1: %2").arg(
                                     QLatin1String(kTextMetaNames[metaType - 1]), text)});
                    }
                } else {
                    rawOthers.push_back({tick, uint16_t(t),
                                         QStringLiteral("Meta 0x%1 (%2 bytes)")
                                             .arg(metaType, 2, 16, QLatin1Char('0'))
                                             .arg(blob.size())});
                }
            }
        }
    }
    std::stable_sort(rawEvents.begin(), rawEvents.end(), [](const RawEvent &a, const RawEvent &b) {
        if (a.tick != b.tick)
            return a.tick < b.tick;
        return a.origIndex < b.origIndex;
    });

    auto timeline = std::make_unique<MidiTimeline>();
    timeline->sampleRate = sampleRate;
    timeline->ticksPerBeat = tpqn;

    // Engine track mapping: the canonical chunk -> track assignment shared
    // with document/import (mapSmfEngineTracks, smf.h). smfToEngine stays as
    // the per-event lookup.
    const SmfEngineTrackMapping mapping = mapSmfEngineTracks(smf);
    std::vector<int> smfToEngine(numTracks, -1);
    for (int engine = 0; engine < mapping.usedTrackCount; engine++) {
        const int smfTrack = mapping.tracks[engine].smfTrack;
        smfToEngine[smfTrack] = engine;
        TimelineTrack &ti = timeline->tracks[engine];
        ti.used = true;
        ti.name = trackNames[smfTrack];
    }
    timeline->usedTrackCount = mapping.usedTrackCount;
    timeline->droppedTracks = mapping.droppedTracks;

    // The one canonical tempo map, built before any sample position; every
    // conversion below and the sampleForTick/tickForSample accessors read it.
    timeline->tempoMap = buildTempoMap(tempoPoints, tpqn, sampleRate);

    timeline->events.reserve(rawEvents.size() + timeline->tempoMap.size());

    std::vector<TimelineEvent> noteEvents;
    noteEvents.reserve(rawEvents.size());
    for (const RawEvent &re : rawEvents) {
        const int engineTrack = smfToEngine[re.smfTrack];
        if (engineTrack < 0)
            continue; // beyond 16 usable tracks

        TimelineEvent ev;
        ev.samplePos = quantizedSampleForTick(re.tick, timeline->tempoMap, tpqn, sampleRate);
        ev.tick = re.tick;
        ev.type = re.type;
        ev.track = static_cast<uint8_t>(engineTrack);
        ev.data0 = re.data0;
        ev.data1 = re.data1;
        ev.noteId = re.noteId;
        noteEvents.push_back(ev);

        TimelineTrack &ti = timeline->tracks[engineTrack];
        if (ev.type == 0x9)
            ti.noteCount++;
        if (ev.type == 0xC && ti.firstProgram < 0)
            ti.firstProgram = ev.data0;
    }

    // Tempo events straight from the canonical tempo map: it already carries
    // the SMF default of 120 BPM at tick 0 when the song doesn't set a tempo
    // there, so the engine (whose tempo drives LFO and vibrato rates) never
    // runs on its unrelated init default.
    std::vector<TimelineEvent> tempoEvents;
    tempoEvents.reserve(timeline->tempoMap.size());
    for (const TempoMapPoint &tp : timeline->tempoMap) {
        const uint64_t sp = uint64_t(tp.samplePos + 0.5); // delta 0: origin, rounded once
        tempoEvents.push_back(makeTempoEvent(sp, tp.tick, tp.bpm));
    }

    // Merge, tempo first at equal positions so it takes effect before notes.
    std::merge(
        tempoEvents.begin(), tempoEvents.end(), noteEvents.begin(), noteEvents.end(),
        std::back_inserter(timeline->events),
        [](const TimelineEvent &a, const TimelineEvent &b) { return a.samplePos < b.samplePos; });

    for (const TimelineEvent &ev : timeline->events) {
        timeline->lengthSamples = std::max(timeline->lengthSamples, ev.samplePos);
        timeline->lengthTicks = std::max(timeline->lengthTicks, ev.tick);
    }

    timeline->loopStartTick = loopStartTick;
    timeline->loopEndTick = loopEndTick;
    if (loopStartTick != CoreTimeDefaults::kNoTick)
        timeline->loopStartSample =
            quantizedSampleForTick(loopStartTick, timeline->tempoMap, tpqn, sampleRate);
    if (loopEndTick != CoreTimeDefaults::kNoTick)
        timeline->loopEndSample =
            quantizedSampleForTick(loopEndTick, timeline->tempoMap, tpqn, sampleRate);
    if (timeline->loopEndTick != CoreTimeDefaults::kNoTick)
        timeline->lengthTicks = std::max(timeline->lengthTicks, timeline->loopEndTick);
    // stable: the bar grid honors the last same-tick signature in file order.
    std::stable_sort(timeSigs.begin(), timeSigs.end(),
                     [](const TimeSigPoint &a, const TimeSigPoint &b) { return a.tick < b.tick; });
    timeline->timeSigs = std::move(timeSigs);

    // Map the not-played events onto engine tracks (metas keep -1 unless their
    // SMF chunk got an engine slot) and time them for display.
    // stable: keeps same-tick strip entries in file order for display.
    std::stable_sort(rawOthers.begin(), rawOthers.end(),
                     [](const RawOther &a, const RawOther &b) { return a.tick < b.tick; });
    timeline->otherEvents.reserve(rawOthers.size());
    for (RawOther &ro : rawOthers) {
        const int engineTrack = smfToEngine[ro.smfTrack];
        timeline->otherEvents.push_back(
            {ro.tick, quantizedSampleForTick(ro.tick, timeline->tempoMap, tpqn, sampleRate),
             engineTrack, std::move(ro.label)});
        timeline->lengthTicks = std::max(timeline->lengthTicks, ro.tick);
    }

    return timeline;
}

} // namespace

std::unique_ptr<MidiTimeline> MidiTimeline::build(const SmfFile &smf, double sampleRate)
{
    auto tempoPoints = extractTempoPoints(smf);
    return buildTimeline(smf, tempoPoints, sampleRate);
}

std::unique_ptr<MidiTimeline> MidiTimeline::build(const SmfFile &smf,
                                                  const std::vector<TempoPoint> &tempoPoints,
                                                  double sampleRate)
{
    return buildTimeline(smf, tempoPoints, sampleRate);
}

uint64_t MidiTimeline::sampleForTick(Tick tick) const
{
    return quantizedSampleForTick(tick, tempoMap, ticksPerBeat, sampleRate);
}

double MidiTimeline::tickForSample(uint64_t samplePos) const
{
    // tempoMap always starts at tick 0. Use unrounded origins for both
    // segment selection and inversion.
    const TempoMapPoint *tp = &tempoMap.front();
    for (const TempoMapPoint &p : tempoMap) {
        if (p.samplePos > double(samplePos))
            break;
        tp = &p;
    }
    const double samplesPerTick =
        double(tp->microsecondsPerQuarterNote) / double(ticksPerBeat) / 1000000.0 * sampleRate;
    return double(tp->tick) + (double(samplePos) - tp->samplePos) / samplesPerTick;
}
