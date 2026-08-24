#include <QFile>
#include <QTemporaryDir>

#include <vector>

#include <cstdio>
#include <utility>

#include "core/miditimeline.h"

#include "checks/editcheck/support.h"

namespace editcheck {

int format0ConvertFailures()
{
    int failures = 0;

    // Format 0 is coerced to format 1 at load (convertToFormat1): the
    // single chunk splits into a conductor chunk 0 carrying every
    // non-channel meta, then one chunk per used channel in ascending
    // channel order — the order mid2agb emits agb tracks for a format-0
    // file, so the build output is unchanged (--roundtrip proves that end
    // to end). Channel-Prefix names (0x20 + 0x03) become ordinary chunk
    // names. Synthetic file — decomp projects are format 1 in practice.
    {
        auto fail0 = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL format0-convert: %s\n", what);
            failures++;
        };
        SmfFile smf;
        smf.format = 0;
        smf.division = 24;
        SmfTrack tr;
        auto chEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = status;
            ev.data0 = d0;
            ev.data1 = d1;
            return ev;
        };
        auto meta = [](uint64_t tick, uint8_t type, QByteArray blob) {
            SmfEvent ev;
            ev.tick = tick;
            ev.status = 0xFF;
            ev.metaType = type;
            ev.blob = std::move(blob);
            return ev;
        };
        // Global metas, a prefixed per-channel name, and notes on the
        // non-contiguous channels 1, 4, 7 (so slot order = channel order is
        // visible). The unprefixed 0x03 precedes the prefix — after a
        // channel prefix, names are scoped until the next channel event.
        // Three preservation cases ride along: a prefixed non-name text
        // meta (0x04 "Gtr" → travels to channel 4's chunk), a prefixed
        // MARKER-text 0x03 (":" → stays in the conductor chunk with a
        // prefix, where mid2agb reads markers), and a prefixed name on the
        // silent channel 9 ("Ambient" → a name-only chunk rather than
        // silent data loss).
        tr.events.push_back(meta(0, 0x51, QByteArray("\x07\xA1\x20", 3))); // 120 BPM
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Song")));
        tr.events.push_back(meta(0, 0x20, QByteArray(1, char(4))));
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Lead")));
        tr.events.push_back(meta(0, 0x04, QByteArrayLiteral("Gtr")));
        tr.events.push_back(chEvent(0x91, 0, 60, 100));
        tr.events.push_back(chEvent(0x94, 0, 64, 100));
        tr.events.push_back(chEvent(0x97, 0, 67, 100));
        tr.events.push_back(meta(12, 0x06, QByteArrayLiteral("[")));
        tr.events.push_back(meta(12, 0x20, QByteArray(1, char(7))));
        tr.events.push_back(meta(12, 0x03, QByteArrayLiteral(":")));
        tr.events.push_back(chEvent(0x81, 24, 60, 0));
        tr.events.push_back(chEvent(0x84, 24, 64, 0));
        tr.events.push_back(chEvent(0x87, 24, 67, 0));
        tr.events.push_back(meta(36, 0x06, QByteArrayLiteral("]")));
        tr.events.push_back(meta(36, 0x20, QByteArray(1, char(9))));
        tr.events.push_back(meta(36, 0x03, QByteArrayLiteral("Ambient")));
        tr.endTick = 48;
        smf.tracks.push_back(tr);
        const QByteArray originalBytes = smf.write();

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/format0.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("format0");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            fail0("could not write/load the synthetic format-0 file");
        if (ok && (doc.smf().format != 1 || !doc.smf().wasFormat0 || doc.smf().tracks.size() != 5 ||
                   doc.engineTrackCount() != 3)) {
            fail0("load did not split into conductor + one chunk per channel");
            ok = false;
        }
        if (ok && (doc.channelFor(0) != 1 || doc.channelFor(1) != 4 || doc.channelFor(2) != 7 ||
                   doc.smfTrackFor(0) != 1)) {
            fail0("converted chunks not in ascending channel order");
            ok = false;
        }
        if (ok) {
            const auto note = [&doc](int track) {
                const auto notes = doc.notesForTrack(track);
                return notes.size() == 1 && notes[0].duration == 24 ? int(notes[0].key) : -1;
            };
            if (note(0) != 60 || note(1) != 64 || note(2) != 67) {
                fail0("notes did not land on their channel's chunk");
                ok = false;
            }
        }
        if (ok && (doc.trackName(1) != QStringLiteral("Lead") || !doc.trackName(0).isEmpty() ||
                   !doc.trackName(2).isEmpty())) {
            fail0("the prefixed name did not become its channel chunk's name");
            ok = false;
        }
        if (ok) {
            auto hasMeta = [](const SmfTrack &track, uint8_t type, const char *text) {
                for (const SmfEvent &ev : track.events)
                    if (ev.isMeta() && ev.metaType == type && ev.blob == text)
                        return true;
                return false;
            };
            const auto &chunks = doc.smf().tracks;
            // Chunk layout: 0 conductor, 1..3 channels 1/4/7, 4 the
            // name-only channel-9 chunk.
            if (!hasMeta(chunks[2], 0x04, "Gtr")) {
                fail0("prefixed instrument-name meta did not travel to its channel chunk");
                ok = false;
            }
            if (ok && (!hasMeta(chunks[0], 0x03, ":") || hasMeta(chunks[3], 0x03, ":"))) {
                fail0("prefixed marker-text meta did not stay in the conductor chunk");
                ok = false;
            }
            if (ok) {
                // ...and it kept a prefix, so no reader mistakes it for the
                // conductor's name.
                bool prefixedMarker = false;
                const auto &evs = chunks[0].events;
                for (size_t i = 1; i < evs.size(); i++) {
                    if (evs[i].isMeta() && evs[i].metaType == 0x03 && evs[i].blob == ":" &&
                        evs[i - 1].isMeta() && evs[i - 1].metaType == 0x20)
                        prefixedMarker = true;
                }
                if (!prefixedMarker) {
                    fail0("the conductor's marker-text meta lost its prefix");
                    ok = false;
                }
            }
            if (ok && !hasMeta(chunks[4], 0x03, "Ambient")) {
                fail0("prefixed name on a silent channel was lost (no name-only chunk)");
                ok = false;
            }
            if (ok) {
                for (const SmfEvent &ev : chunks[4].events) {
                    if (ev.isChannel()) {
                        fail0("the name-only chunk grew channel events");
                        ok = false;
                    }
                }
            }
        }
        if (ok) {
            // Prefixes are rewritten into chunk structure everywhere except
            // the conductor's re-prefixed marker pair (the ":" case above).
            for (size_t t = 0; t < doc.smf().tracks.size(); t++) {
                const SmfTrack &track = doc.smf().tracks[t];
                for (const SmfEvent &ev : track.events) {
                    if (t > 0 && ev.isMeta() && ev.metaType == 0x20) {
                        fail0("a Channel Prefix meta survived in a channel chunk");
                        ok = false;
                    }
                }
                if (track.endTick != 48) {
                    fail0("a converted chunk lost the end-of-track tick");
                    ok = false;
                }
            }
            for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                if (ev.isChannel()) {
                    fail0("a channel event landed in the conductor chunk");
                    ok = false;
                }
            }
        }
        if (ok && (doc.loopTick(false) != 12 || doc.loopTick(true) != 36 ||
                   doc.tempoPoints() != std::vector<TempoPoint>{tempoPoint(0, 120)})) {
            fail0("seq globals did not stay readable in chunk 0");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->usedTrackCount != 3 ||
                timeline->tracks[1].name != QStringLiteral("Lead") ||
                timeline->loopStartTick != 12) {
                fail0("conversion not reflected in the timeline projection");
                ok = false;
            }
        }
        if (ok && !tracksSorted(doc.smf())) {
            fail0("events unsorted after conversion");
            ok = false;
        }
        const QByteArray convertedLive = ok ? doc.smf().write() : QByteArray();
        QByteArray convertedSerialized;
        if (ok) {
            SmfFile saved;
            if (!doc.save(&werror) || !SmfFile::readFile(midPath, &saved, &werror)) {
                fail0("save did not persist the converted SMF");
                ok = false;
            } else {
                convertedSerialized = saved.write();
                bool tempoValid = true;
                std::vector<TempoPoint> savedTempo;
                bool tempoFirst = true;
                bool tempoOutsideSeq = false;
                for (size_t track = 0; track < saved.tracks.size(); track++) {
                    uint64_t tick = 0;
                    bool haveTick = false;
                    bool nonTempoAtTick = false;
                    for (const SmfEvent &event : saved.tracks[track].events) {
                        if (!haveTick || event.tick != tick) {
                            tick = event.tick;
                            haveTick = true;
                            nonTempoAtTick = false;
                        }
                        if (!isTempoMeta(event)) {
                            nonTempoAtTick = true;
                            continue;
                        }
                        if (track != 0)
                            tempoOutsideSeq = true;
                        if (nonTempoAtTick)
                            tempoFirst = false;
                        if (event.blob.size() != 3) {
                            tempoValid = false;
                            continue;
                        }
                        const auto *bytes =
                            reinterpret_cast<const uint8_t *>(event.blob.constData());
                        savedTempo.push_back({event.tick, (uint32_t(bytes[0]) << 16) |
                                                              (uint32_t(bytes[1]) << 8) |
                                                              bytes[2]});
                    }
                }
                auto nonTempoSaved = saved;
                for (SmfTrack &track : nonTempoSaved.tracks) {
                    std::vector<SmfEvent> events;
                    events.reserve(track.events.size());
                    for (const SmfEvent &event : track.events)
                        if (!isTempoMeta(event))
                            events.push_back(event);
                    track.events = std::move(events);
                }
                const auto hasLiveTempo = [&doc] {
                    for (const SmfTrack &track : doc.smf().tracks)
                        for (const SmfEvent &event : track.events)
                            if (isTempoMeta(event))
                                return true;
                    return false;
                };
                if (nonTempoSaved.write() != convertedLive) {
                    fail0("save changed the converted non-tempo structure");
                    ok = false;
                } else if (tempoOutsideSeq || !tempoFirst || !tempoValid ||
                           savedTempo != doc.tempoPoints()) {
                    fail0("save did not serialize typed tempo points tempo-first in chunk 0");
                    ok = false;
                } else if (hasLiveTempo()) {
                    fail0("save leaked tempo metas into the live SMF");
                    ok = false;
                }
            }
        }
        if (ok) {
            // SmfFile::read is the conversion choke point: raw re-reading
            // the original bytes yields the serialized converted form,
            // including its FF51 tempo event. Converting that already
            // converted form is a no-op (fixed point).
            SmfFile redo;
            QString rerror;
            if (!SmfFile::read(originalBytes, &redo, &rerror)) {
                fail0("could not re-read the original bytes");
                ok = false;
            } else {
                if (!redo.wasFormat0 || redo.write() != convertedSerialized) {
                    fail0("read() did not coerce deterministically");
                    ok = false;
                }
                convertToFormat1(&redo);
                if (ok && redo.write() != convertedSerialized) {
                    fail0("conversion of a converted file is not a no-op");
                    ok = false;
                }
            }
        }
        if (ok) {
            // The editing layer runs on the converted shape: undo-all
            // restores the tempo-free converted baseline, not the format-0 bytes.
            doc.renameTrack(0, QStringLiteral("Bass"));
            doc.moveTrack(0, 2);
            if (doc.trackName(2) != QStringLiteral("Bass")) {
                fail0("edits after conversion did not behave as format 1");
                ok = false;
            }
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (ok && doc.smf().write() != convertedLive)
                fail0("undo-all did not restore the converted baseline");
        }
    }
    return failures;
}
} // namespace editcheck
