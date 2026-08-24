#include <vector>

#include "core/miditimeline.h"

#include "checks/editcheck/support.h"

namespace editcheck {
bool checkSongTrackAndSongContracts(SongEditScenario &scenario)
{
    SongDocument &doc = scenario.doc;
    const int track = scenario.track;
    const uint64_t base = scenario.base;
    const uint32_t step = scenario.step;
    bool ok = true;
    const auto fail = [&scenario](const char *what) { scenario.fail(what); };
    const auto mutateAndCheck = [&scenario, &ok](const char *what) {
        if (ok && !scenario.checkSorted(what))
            ok = false;
    };

    // Track ops: create a track (seeded with its voice), edit on it,
    // delete it again.
    if (ok && doc.canAddTrack()) {
        const int newTrack = doc.addTrack(7);
        if (newTrack < 0) {
            fail("addTrack returned no track with canAddTrack true");
            ok = false;
        } else {
            mutateAndCheck("events unsorted after addTrack");
            const auto seed = doc.lanePoints(newTrack, DOC_CC_VOICE);
            if (ok && (seed.empty() || seed.front().tick != 0 || seed.front().value != 7)) {
                fail("new track missing its seed voice");
                ok = false;
            }
            DocNote note;
            if (ok) {
                doc.addNote(newTrack, base, 72, step * 4, 100);
                if (!doc.findNote(newTrack, base, 72, &note)) {
                    fail("note on new track not found");
                    ok = false;
                }
            }
            if (ok) {
                doc.deleteTrack(newTrack);
                mutateAndCheck("events unsorted after deleteTrack");
                if (doc.findNote(newTrack, base, 72, &note)) {
                    fail("deleted track still has its note");
                    ok = false;
                }
            }
        }
    }

    // Duplicating a song track: the copy lands on a fresh engine slot
    // carrying the same notes as the source.
    if (ok && track >= 0 && doc.canAddTrack()) {
        const auto srcNotes = doc.notesForTrack(track);
        const int copy = doc.duplicateTrack(track);
        mutateAndCheck("events unsorted after duplicateTrack");
        if (copy < 0) {
            fail("duplicateTrack returned no track with canAddTrack true");
            ok = false;
        } else if (copy == track) {
            fail("duplicateTrack returned the source track");
            ok = false;
        } else if (ok) {
            const auto copyNotes = doc.notesForTrack(copy);
            bool same = copyNotes.size() == srcNotes.size();
            for (size_t i = 0; same && i < copyNotes.size(); i++) {
                same = copyNotes[i].tick == srcNotes[i].tick &&
                       copyNotes[i].key == srcNotes[i].key &&
                       copyNotes[i].duration == srcNotes[i].duration &&
                       copyNotes[i].velocity == srcNotes[i].velocity;
            }
            if (!same) {
                fail("duplicated track's notes differ from the source");
                ok = false;
            } else {
                doc.deleteTrack(copy);
                mutateAndCheck("events unsorted after deleting the duplicate");
            }
        }
    }

    // Reordering tracks: the chunks move with their events and channel
    // bytes untouched, while typed Tempo and chunk-0 time signatures and
    // loop markers remain global.
    if (ok && doc.engineTrackCount() >= 2 && track >= 0) {
        doc.applyTempoEdit({{}, {tempoPoint(base + step * 110, 145)}});
        doc.setTimeSig(base + step * 112, 5, 2);
        const uint64_t loopStartBefore = doc.loopTick(false);
        const uint64_t loopEndBefore = doc.loopTick(true);
        const auto srcNotes = doc.notesForTrack(0);
        const uint8_t srcChannel = doc.channelFor(0);
        const int last = doc.engineTrackCount() - 1;
        const int countBefore = doc.undoStack()->count();
        doc.moveTrack(0, 0); // no-op guard
        if (doc.undoStack()->count() != countBefore) {
            fail("moveTrack onto itself pushed a command");
            ok = false;
        }
        auto seqChunkHas = [&doc](uint8_t metaType, uint64_t tick) {
            for (const SmfEvent &ev : doc.smf().tracks[0].events) {
                if (ev.isMeta() && ev.metaType == metaType && ev.tick == tick)
                    return true;
            }
            return false;
        };
        auto notesMatch = [&doc](int engineTrack, const std::vector<DocNote> &want) {
            const auto got = doc.notesForTrack(engineTrack);
            if (got.size() != want.size())
                return false;
            for (size_t i = 0; i < got.size(); i++) {
                if (got[i].tick != want[i].tick || got[i].key != want[i].key ||
                    got[i].duration != want[i].duration || got[i].velocity != want[i].velocity)
                    return false;
            }
            return true;
        };
        if (ok) {
            doc.moveTrack(0, last);
            mutateAndCheck("events unsorted after moveTrack");
        }
        if (ok && doc.undoStack()->count() != countBefore + 1) {
            fail("moveTrack was not a single undo command");
            ok = false;
        }
        if (ok && (!notesMatch(last, srcNotes) || doc.channelFor(last) != srcChannel)) {
            fail("moved track's notes or channel changed");
            ok = false;
        }
        if (ok && (!containsTempoPoint(doc, tempoPoint(base + step * 110, 145)) ||
                   !seqChunkHas(0x58, base + step * 112))) {
            fail("global tempo or sequence metadata changed across the move");
            ok = false;
        }
        if (ok && (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
            fail("moveTrack lost the loop markers");
            ok = false;
        }
        if (ok) {
            doc.undoStack()->undo();
            if (!notesMatch(0, srcNotes)) {
                fail("moveTrack undo did not restore the track order");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
        if (ok) {
            doc.moveTrack(last, 0); // and back again
            mutateAndCheck("events unsorted after moveTrack back");
            if (!notesMatch(0, srcNotes) ||
                !containsTempoPoint(doc, tempoPoint(base + step * 110, 145)) ||
                !seqChunkHas(0x58, base + step * 112)) {
                fail("moving the track back did not restore its slot");
                ok = false;
            }
        }
    }

    // Reordering must not confuse chunk-0 metas that only LOOK like loop
    // markers: a first-0x03 name of "[" is the track's name and travels
    // with its chunk (findLoopMarkerEvent skips it; imported files can
    // carry such names even though renameTrack refuses them), while the
    // combined "][" marker mid2agb reads stays with chunk 0.
    if (ok && doc.engineTrackCount() >= 2 && doc.smfTrackFor(0) == 0) {
        const int last = doc.engineTrackCount() - 1;
        const int indexBefore = doc.undoStack()->index();
        const uint64_t loopStartBefore = doc.loopTick(false);
        const uint64_t loopEndBefore = doc.loopTick(true);
        doc.renameTrack(0, QString()); // the "[" below must be the first 0x03
        SmfEvent name;
        name.tick = 0;
        name.status = 0xFF;
        name.metaType = 0x03;
        name.blob = QByteArrayLiteral("[");
        doc.insertRawEvent(0, name);
        SmfEvent marker;
        marker.tick = base;
        marker.status = 0xFF;
        marker.metaType = 0x06;
        marker.blob = QByteArrayLiteral("][");
        doc.insertRawEvent(0, marker);
        doc.moveTrack(0, last);
        mutateAndCheck("events unsorted after marker-name moveTrack");
        if (ok && doc.trackName(last) != QStringLiteral("[")) {
            fail("a '['-named track lost its name in the move");
            ok = false;
        }
        if (ok && (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
            fail("a '[' track name was misread as a loop marker");
            ok = false;
        }
        bool combinedStayed = false;
        for (const SmfEvent &ev : doc.smf().tracks[0].events) {
            if (ev.isMeta() && ev.metaType == 0x06 && ev.blob == "][")
                combinedStayed = true;
        }
        if (ok && !combinedStayed) {
            fail("the '][' marker left chunk 0 in the move");
            ok = false;
        }
        while (doc.undoStack()->index() > indexBefore)
            doc.undoStack()->undo();
        mutateAndCheck("events unsorted after marker-name undo");
    }

    // Deleting an original track must not lose the loop markers, even
    // when they live in the removed chunk (they get rescued into the seq
    // chunk). Undone right away so the loop/cfg script below still runs
    // against the full song.
    if (ok && track >= 0) {
        const uint64_t loopStartBefore = doc.loopTick(false);
        const uint64_t loopEndBefore = doc.loopTick(true);
        doc.deleteTrack(track);
        mutateAndCheck("events unsorted after deleteTrack of a song track");
        if (ok && (doc.loopTick(false) != loopStartBefore || doc.loopTick(true) != loopEndBefore)) {
            fail("deleteTrack lost the loop markers");
            ok = false;
        }
        doc.undoStack()->undo();
    }

    // Track rename: set, no-op guard (trimmed match pushes nothing),
    // clear, and undo back through the chunk's Track Name meta (0x03).
    if (ok && track >= 0) {
        auto chunkNameCount = [&doc, track] {
            const int smfTrack = doc.smfTrackFor(track);
            int count = 0;
            SmfChannelPrefix prefix;
            for (const SmfEvent &event : doc.smf().tracks[smfTrack].events) {
                prefix.observe(event);
                if (event.isMeta() && event.metaType == 0x03 && prefix.channel < 0)
                    count++;
            }
            return count;
        };
        doc.renameTrack(track, QStringLiteral("editcheck name"));
        mutateAndCheck("events unsorted after renameTrack");
        if (ok &&
            (doc.trackName(track) != QStringLiteral("editcheck name") || chunkNameCount() != 1)) {
            fail("rename did not produce one authoritative track name");
            ok = false;
        }
        // The header paints from the playable projection, not the raw
        // SMF — the authoritative meta must land where MidiTimeline's
        // reader finds it.
        if (ok) {
            const auto timeline = doc.buildTimeline(48000.0);
            if (!timeline || timeline->tracks[track].name != QStringLiteral("editcheck name")) {
                fail("renamed track not visible in the timeline projection");
                ok = false;
            }
        }
        if (ok) {
            const int count = doc.undoStack()->count();
            doc.renameTrack(track, QStringLiteral("  editcheck name  "));
            if (doc.undoStack()->count() != count) {
                fail("no-op rename pushed an undo command");
                ok = false;
            }
        }
        if (ok) {
            // mid2agb reads any text meta whose whole text is a marker
            // as a loop/label command; those names must be refused.
            const int count = doc.undoStack()->count();
            doc.renameTrack(track, QStringLiteral("["));
            doc.renameTrack(track, QStringLiteral(" ][ "));
            if (doc.undoStack()->count() != count ||
                doc.trackName(track) != QStringLiteral("editcheck name")) {
                fail("loop-marker name was not refused");
                ok = false;
            }
        }
        if (ok) {
            doc.renameTrack(track, QString());
            if (!doc.trackName(track).isEmpty() || chunkNameCount() != 0) {
                fail("empty rename did not clear all track names");
                ok = false;
            }
        }
        if (ok) {
            doc.undoStack()->undo();
            if (doc.trackName(track) != QStringLiteral("editcheck name")) {
                fail("rename undo did not restore the name");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
    }

    // Time signatures: create, modify in place, move, delete.
    if (ok) {
        auto findSig = [&doc](uint64_t tick, DocTimeSig *out) {
            for (const DocTimeSig &sig : doc.timeSigs()) {
                if (sig.tick == tick) {
                    *out = sig;
                    return true;
                }
            }
            return false;
        };
        const size_t sigsBefore = doc.timeSigs().size();
        doc.setTimeSig(base, 3, 3); // 3/8
        mutateAndCheck("events unsorted after setTimeSig");
        DocTimeSig sig;
        if (ok && (!findSig(base, &sig) || sig.numerator != 3 || sig.denomPow2 != 3)) {
            fail("time signature not found after set");
            ok = false;
        }
        if (ok) {
            doc.setTimeSig(base, 7, 2); // 7/4, replacing in place
            if (!findSig(base, &sig) || sig.numerator != 7 || sig.denomPow2 != 2 ||
                doc.timeSigs().size() != sigsBefore + 1) {
                fail("time signature edit did not replace in place");
                ok = false;
            }
        }
        if (ok) {
            doc.moveTimeSig(base, base + step * 4);
            mutateAndCheck("events unsorted after moveTimeSig");
            if (findSig(base, &sig) || !findSig(base + step * 4, &sig) || sig.numerator != 7) {
                fail("time signature not moved");
                ok = false;
            }
        }
        if (ok) {
            doc.deleteTimeSig(base + step * 4);
            if (findSig(base + step * 4, &sig)) {
                fail("time signature not deleted");
                ok = false;
            }
        }
    }

    return ok;
}

} // namespace editcheck
