#include <algorithm>
#include <cstdio>

#include "checks/editcheck/support.h"

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

    checkSongXcmdSaveSnapshot(scenario);

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
