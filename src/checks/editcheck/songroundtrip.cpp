#include <algorithm>
#include <cstdio>

#include "checks/editcheck/support.h"
#include "core/xcmd.h"

namespace editcheck {

void runSongRoundTrip(const SongInfo &song, int &checked, int &failures)
{
    if (!song.isPlayable())
        return;

    SongDocument doc;
    QString error;
    if (!doc.load(song, &error)) {
        std::fprintf(stderr, "editcheck: FAIL %s: %s\n", qUtf8Printable(song.label),
                     qUtf8Printable(error));
        failures++;
        return;
    }
    const QByteArray baseline = doc.smf().write();

    // Pick a track that has notes to edit on.
    int track = -1;
    for (int t = 0; t < doc.engineTrackCount(); t++) {
        if (!doc.notesForTrack(t).empty()) {
            track = t;
            break;
        }
    }

    const uint32_t step = doc.ticksPerClock();
    // Edit far past the end of the song so scripted notes and lane points
    // can't collide with (or re-pair against) the song's real content.
    uint64_t base = 0;
    for (const SmfTrack &tr : doc.smf().tracks)
        base = std::max(base, tr.endTick);
    base += step * 100;
    SongEditScenario scenario{doc, song.label, track, base, step, failures};
    checkSongRawEventContracts(scenario);

    bool ok = true;
    if (track >= 0) {
        ok = checkSongNoteEdits(scenario);
        if (ok)
            ok = checkSongRangeEdits(scenario);
        if (ok)
            ok = checkSongNoteMoveContracts(scenario);
        if (ok)
            ok = checkSongTimeRangeAndAutomation(scenario);
    }
    if (ok)
        ok = checkSongTrackAndSongContracts(scenario);

    // Loop markers: move an existing one / create where absent, and cfg.
    const uint64_t loopStart = doc.loopTick(false);
    doc.setLoopTick(false, loopStart == UINT64_MAX ? 0 : int64_t(loopStart + step));
    if (ok && !scenario.checkSorted("events unsorted after setLoopTick"))
        ok = false;
    SongCfg cfg = doc.cfg();
    cfg.masterVolume = cfg.masterVolume == 80 ? 90 : 80;
    doc.setCfg(cfg);

    if (track >= 0) {
        const int smfTrack = doc.smfTrackFor(track);
        const uint8_t channel = doc.channelFor(track);
        const uint8_t status = uint8_t(0xB0 | (channel & 0x0F));

        SmfEvent sel1;
        sel1.tick = base + step;
        sel1.status = status;
        sel1.data0 = xcmd::kSelectorController;
        sel1.data1 = 0x08;
        doc.insertRawEvent(smfTrack, sel1);

        SmfEvent payload;
        payload.tick = base + 2 * step;
        payload.status = status;
        payload.data0 = xcmd::kPayloadController;
        payload.data1 = 34;
        doc.insertRawEvent(smfTrack, payload);

        SmfEvent sel2;
        sel2.tick = base + 3 * step;
        sel2.status = status;
        sel2.data0 = xcmd::kSelectorController;
        sel2.data1 = 0x09;
        doc.insertRawEvent(smfTrack, sel2);

        const QByteArray liveSmfBytes = doc.smf().write();
        const int liveUndoIndex = doc.undoStack()->index();
        const bool liveDirty = doc.isDirty();

        const SongSaveSnapshot snapshot = doc.captureSaveSnapshot();

        if (doc.smf().write() != liveSmfBytes)
            scenario.fail("captureSaveSnapshot mutated live SMF bytes");
        if (doc.undoStack()->index() != liveUndoIndex)
            scenario.fail("captureSaveSnapshot mutated undo index");
        if (doc.isDirty() != liveDirty)
            scenario.fail("captureSaveSnapshot mutated dirty state");

        if (smfTrack < 0 || size_t(smfTrack) >= snapshot.smf.tracks.size()) {
            scenario.fail("save snapshot missing SMF track");
        } else {
            const SmfTrack &snapTrack = snapshot.smf.tracks[size_t(smfTrack)];
            bool hasFirstSelector = false;
            bool hasDanglingSelector = false;
            std::vector<SmfEvent> payloadEvents;
            for (const SmfEvent &ev : snapTrack.events) {
                if (ev.tick == base + step && ev.isChannel() &&
                    ev.data0 == xcmd::kSelectorController) {
                    hasFirstSelector = true;
                } else if (ev.tick == base + 2 * step && ev.isChannel() &&
                           (ev.data0 == xcmd::kSelectorController ||
                            ev.data0 == xcmd::kPayloadController)) {
                    payloadEvents.push_back(ev);
                } else if (ev.tick == base + 3 * step && ev.isChannel() &&
                           ev.data0 == xcmd::kSelectorController) {
                    hasDanglingSelector = true;
                }
            }

            if (hasFirstSelector)
                scenario.fail("save snapshot retained delayed CC30 selector at first tick");
            if (payloadEvents.size() != 2 || payloadEvents[0].data0 != xcmd::kSelectorController ||
                payloadEvents[0].data1 != 0x08 ||
                payloadEvents[1].data0 != xcmd::kPayloadController ||
                payloadEvents[1].data1 != 34) {
                scenario.fail("save snapshot did not emit exact ordered CC30=0x08 then CC29=34 at "
                              "payload tick");
            }
            if (hasDanglingSelector)
                scenario.fail("save snapshot retained dangling CC30 selector");
        }
    }

    // Undo everything: the document must be byte-identical to the load.
    while (doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    if (doc.smf().write() != baseline)
        scenario.fail("undo-all did not restore the original bytes");
    else if (doc.cfg().masterVolume != song.cfg.masterVolume)
        scenario.fail("undo-all did not restore song settings");
    else {
        // Redo everything, then undo again: redo must be deterministic.
        while (doc.undoStack()->canRedo())
            doc.undoStack()->redo();
        const QByteArray redone = doc.smf().write();
        while (doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        if (doc.smf().write() != baseline)
            scenario.fail("undo after redo did not restore the original bytes");
        else if (redone == baseline && track >= 0)
            scenario.fail("redo-all produced no change (edits were lost)");
    }

    checked++;
}
} // namespace editcheck
