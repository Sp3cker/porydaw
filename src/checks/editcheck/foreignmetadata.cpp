#include <QFile>

#include <QTemporaryDir>

#include <vector>

#include <cstdio>
#include <utility>

#include "core/miditimeline.h"

#include "checks/editcheck/support.h"

namespace editcheck {

int markerVsNameFailures()
{
    int failures = 0;

    // A PREFIXED 0x03 carrying marker text has no name position (a chunk's
    // name is its first unprefixed 0x03), so every classifier
    // (MidiTimeline::build, findLoopMarkerEvent, trackNameLoc) reads it as
    // a marker — mid2agb's rule: a foreign format-1 file whose chunk opens
    // with a prefixed 0x03 "[" has a loop the playback timeline, the loop
    // UI, and the compiled ROM all agree on, and renaming the track edits
    // the real name meta, never the marker.
    {
        auto failM = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL marker-vs-name: %s\n", what);
            failures++;
        };
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
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        SmfTrack tr;
        tr.events.push_back(meta(0, 0x20, QByteArray(1, char(0))));
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("[")));
        tr.events.push_back(chEvent(0x90, 0, 60, 100)); // clears the prefix
        tr.events.push_back(meta(0, 0x03, QByteArrayLiteral("Real")));
        tr.events.push_back(chEvent(0x80, 24, 60, 0));
        tr.endTick = 24;
        smf.tracks.push_back(tr);

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/marker.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("marker");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            failM("could not write/load the synthetic file");
        if (ok && doc.trackName(0) != QStringLiteral("Real")) {
            failM("marker-text 0x03 was mistaken for the track name");
            ok = false;
        }
        if (ok && doc.loopTick(false) != 0) {
            failM("the loop UI did not see the prefixed marker");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->loopStartTick != 0) {
                failM("playback did not see the prefixed marker (build/UI disagree)");
                ok = false;
            }
        }
        if (ok) {
            doc.renameTrack(0, QStringLiteral("Renamed"));
            if (doc.trackName(0) != QStringLiteral("Renamed") || doc.loopTick(false) != 0) {
                failM("rename clobbered the loop marker instead of the name");
            }
        }
    }
    return failures;
}

int sameTickDuplicateFailures()
{
    int failures = 0;

    // Same-tick duplicate setters (a foreign file's repeated channel-init
    // block): the loader preserves them — sanitizing is the import wizard's
    // job — but every editing surface resolves the run LAST-wins, matching
    // playback, and writing onto an occupied tick replaces what sits there
    // instead of stacking another duplicate. Undo restores the duplicates.
    {
        auto failD = [&](const char *what) {
            std::fprintf(stderr, "editcheck: FAIL same-tick-dup: %s\n", what);
            failures++;
        };
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
        const auto tempoMeta = [&meta](uint64_t tick, uint32_t microsecondsPerQuarterNote) {
            QByteArray blob(3, '\0');
            blob[0] = char((microsecondsPerQuarterNote >> 16) & 0xFF);
            blob[1] = char((microsecondsPerQuarterNote >> 8) & 0xFF);
            blob[2] = char(microsecondsPerQuarterNote & 0xFF);
            return meta(tick, 0x51, std::move(blob));
        };
        const TempoPoint slowTempo = tempoPoint(24, 20);
        const TempoPoint inRangeTempo = tempoPoint(48, 150);
        const TempoPoint fastTempo = tempoPoint(72, 255);
        const TempoPoint exactTempo{96, 375'001};
        const std::vector<TempoPoint> expectedTempo{slowTempo, inRangeTempo, fastTempo, exactTempo};
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        SmfTrack conductor;
        conductor.events.push_back(meta(0, 0x01, QByteArrayLiteral("conductor")));
        conductor.events.push_back(tempoMeta(24, 6'000'000)); // 10 BPM, clamps to 20
        conductor.events.push_back(tempoMeta(48, tempoPoint(48, 120).microsecondsPerQuarterNote));
        conductor.events.push_back(tempoMeta(48, inRangeTempo.microsecondsPerQuarterNote));
        conductor.events.push_back(meta(48, 0x01, QByteArrayLiteral("shared tick")));
        conductor.events.push_back(tempoMeta(72, 200'000)); // 300 BPM, clamps to 255
        conductor.events.push_back(tempoMeta(96, exactTempo.microsecondsPerQuarterNote));
        conductor.endTick = 120;
        smf.tracks.push_back(conductor);
        SmfTrack ch0;
        ch0.events.push_back(chEvent(0xC0, 0, 5, 0));
        ch0.events.push_back(chEvent(0xB0, 0, 7, 100));
        ch0.events.push_back(chEvent(0xC0, 0, 9, 0));
        ch0.events.push_back(chEvent(0xB0, 0, 7, 80));
        ch0.events.push_back(chEvent(0x90, 0, 60, 100));
        ch0.events.push_back(meta(48, 0x51, QByteArray("\x09\x27\xC0", 3)));
        ch0.events.push_back(chEvent(0x80, 96, 60, 0));
        ch0.endTick = 96;
        smf.tracks.push_back(ch0);

        QTemporaryDir tmp;
        const QString midPath = tmp.path() + QStringLiteral("/dups.mid");
        QString werror;
        SongInfo info;
        info.label = QStringLiteral("dups");
        info.midPath = midPath;
        info.hasMid = true;
        SongDocument doc;
        bool ok = tmp.isValid() && smf.writeFile(midPath, &werror) && doc.load(info, &werror);
        if (!ok)
            failD("could not write/load the synthetic file");
        int changedSignals = 0;
        QObject::connect(&doc, &SongDocument::documentChanged,
                         [&changedSignals] { changedSignals++; });
        const QByteArray baseline = ok ? doc.smf().write() : QByteArray();
        const auto hasLiveTempoMeta = [&doc] {
            for (const SmfTrack &track : doc.smf().tracks) {
                for (const SmfEvent &event : track.events) {
                    if (isTempoMeta(event))
                        return true;
                }
            }
            return false;
        };
        const auto ccPointsAt = [&doc](uint8_t cc, uint64_t tick) {
            std::vector<DocLanePoint> at;
            for (const DocLanePoint &pt : doc.lanePoints(0, cc)) {
                if (pt.tick == tick)
                    at.push_back(pt);
            }
            return at;
        };
        if (ok && (doc.lanePoints(0, DOC_CC_VOICE).size() != 2 || ccPointsAt(7, 0).size() != 2)) {
            failD("the loader no longer preserves same-tick duplicates");
            ok = false;
        }
        DocLanePoint pt;
        if (ok && (!doc.findLanePoint(0, 7, 0, &pt) || pt.value != 80)) {
            failD("findLanePoint did not return the last CC at the tick");
            ok = false;
        }
        if (ok && (!doc.findLanePoint(0, DOC_CC_VOICE, 0, &pt) || pt.value != 9)) {
            failD("findLanePoint did not return the last program at the tick");
            ok = false;
        }
        if (ok && doc.tempoPoints() != expectedTempo) {
            failD("tempo load did not clamp bounds or preserve exact later tempo points");
            ok = false;
        }
        if (ok && hasLiveTempoMeta()) {
            failD("tempo load retained a live raw FF 51 event");
            ok = false;
        }
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->tempoMap.size() != 5 || timeline->tempoMap[0].tick != 0 ||
                timeline->tempoMap[0].bpm != 120.0 ||
                timeline->tempoMap[1].tick != slowTempo.tick ||
                timeline->tempoMap[2].tick != inRangeTempo.tick ||
                timeline->tempoMap[3].tick != fastTempo.tick ||
                timeline->tempoMap[4].tick != exactTempo.tick) {
                failD("timeline did not use the typed tempo points");
                ok = false;
            }
        }
        if (ok) {
            const QByteArray liveBytes = doc.smf().write();
            SmfFile expected = doc.smf();
            auto &expectedEvents = expected.tracks.front().events;
            expectedEvents.insert(
                expectedEvents.begin() + 1,
                {tempoMeta(slowTempo.tick, slowTempo.microsecondsPerQuarterNote),
                 tempoMeta(inRangeTempo.tick, inRangeTempo.microsecondsPerQuarterNote)});
            expectedEvents.insert(
                expectedEvents.begin() + 4,
                {tempoMeta(fastTempo.tick, fastTempo.microsecondsPerQuarterNote),
                 tempoMeta(exactTempo.tick, exactTempo.microsecondsPerQuarterNote)});
            QFile savedFile(midPath);
            const bool saved = doc.save(&werror);
            const bool readSaved = saved && savedFile.open(QIODevice::ReadOnly);
            const QByteArray savedBytes = readSaved ? savedFile.readAll() : QByteArray();
            if (!saved || !readSaved || savedBytes != expected.write() ||
                doc.smf().write() != liveBytes) {
                failD("save did not serialize tempo first without restoring live FF 51 events");
                ok = false;
            }
        }
        if (ok) {
            // Resubmitting the audible value still removes its same-tick
            // shadow, so this remains a real, exactly undoable edit.
            doc.findLanePoint(0, 7, 0, &pt);
            const QByteArray before = doc.smf().write();
            const uint64_t beforeRevision = doc.revision();
            const int beforeUndoCount = doc.undoStack()->count();
            const int beforeUndoIndex = doc.undoStack()->index();
            changedSignals = 0;
            doc.moveLanePoints({{0, 7, pt, pt.tick, pt.value}});
            const auto after = ccPointsAt(7, 0);
            if (after.size() != 1 || after[0].value != 80 || doc.revision() != beforeRevision + 1 ||
                doc.undoStack()->count() != beforeUndoCount + 1 ||
                doc.undoStack()->index() != beforeUndoIndex + 1 || changedSignals != 1) {
                failD("an exact duplicate resubmission did not canonicalize as one edit");
                ok = false;
            }
            const uint64_t canonicalRevision = doc.revision();
            changedSignals = 0;
            doc.undoStack()->undo();
            const auto restored = ccPointsAt(7, 0);
            if (ok &&
                (restored.size() != 2 || restored[0].value != 100 || restored[1].value != 80 ||
                 doc.smf().write() != before || doc.revision() != canonicalRevision + 1 ||
                 doc.undoStack()->count() != beforeUndoCount + 1 ||
                 doc.undoStack()->index() != beforeUndoIndex || changedSignals != 1)) {
                failD("undo did not exactly restore the shadowed duplicate");
                ok = false;
            }
        }
        if (ok) {
            // addLanePoint replaces the whole run on its tick.
            doc.addLanePoint(0, 7, 0, 70);
            if (ccPointsAt(7, 0).size() != 1) {
                failD("addLanePoint stacked another duplicate on the tick");
                ok = false;
            }
            doc.undoStack()->undo();
        }
        if (ok) {
            doc.addLanePoint(0, 7, 48, 55);
            if (!doc.findLanePoint(0, 7, 48, &pt) || ccPointsAt(7, 48).size() != 1) {
                failD("controller no-op fixture did not create one point");
                ok = false;
            } else {
                const QByteArray before = doc.smf().write();
                const uint64_t beforeRevision = doc.revision();
                const int beforeUndoCount = doc.undoStack()->count();
                const int beforeUndoIndex = doc.undoStack()->index();
                changedSignals = 0;
                doc.moveLanePoints({{0, 7, pt, pt.tick, pt.value}});
                if (doc.smf().write() != before || doc.revision() != beforeRevision ||
                    doc.undoStack()->count() != beforeUndoCount ||
                    doc.undoStack()->index() != beforeUndoIndex || changedSignals != 0) {
                    failD("an unchanged controller point mutated the document");
                    ok = false;
                }
            }
            if (ok) {
                // A cross-tick move landing on an occupied tick replaces the
                // run there too.
                doc.moveLanePoints({{0, 7, pt, 0, 55}});
                if (ccPointsAt(7, 0).size() != 1 || !ccPointsAt(7, 48).empty()) {
                    failD("a cross-tick move did not replace the destination run");
                    ok = false;
                }
            }
        }
        if (ok) {
            const TempoPoint noOpTempo = tempoPoint(48, 120);
            doc.applyTempoEdit({{}, {noOpTempo}});
            if (!containsTempoPoint(doc, noOpTempo) || hasLiveTempoMeta()) {
                failD("tempo edit did not keep live SMF free of FF 51 events");
                ok = false;
            } else {
                const QByteArray before = doc.smf().write();
                const auto beforeTempo = doc.tempoPoints();
                const uint64_t beforeRevision = doc.revision();
                const int beforeUndoCount = doc.undoStack()->count();
                const int beforeUndoIndex = doc.undoStack()->index();
                changedSignals = 0;
                doc.applyTempoEdit({{}, {noOpTempo}});
                if (doc.smf().write() != before || doc.tempoPoints() != beforeTempo ||
                    doc.revision() != beforeRevision ||
                    doc.undoStack()->count() != beforeUndoCount ||
                    doc.undoStack()->index() != beforeUndoIndex || changedSignals != 0) {
                    failD("an unchanged global tempo point mutated the document");
                    ok = false;
                }
            }
            if (ok) {
                doc.undoStack()->undo();
                if (!containsTempoPoint(doc, tempoPoint(48, 150)) || hasLiveTempoMeta()) {
                    failD("tempo undo did not keep live SMF free of FF 51 events");
                    ok = false;
                } else {
                    doc.undoStack()->redo();
                }
            }
        }
        if (ok) {
            while (doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            if (doc.smf().write() != baseline)
                failD("undo-all did not restore the duplicated file byte-for-byte");
        }
    }
    return failures;
}
} // namespace editcheck
