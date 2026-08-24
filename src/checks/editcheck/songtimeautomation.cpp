#include <algorithm>
#include <vector>

#include "checks/editcheck/support.h"

namespace editcheck {
bool checkSongTimeRangeAndAutomation(SongEditScenario &scenario)
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

    // Remove time range: in-range content vanishes,
    // later events shift left by the span, and the last in-range
    // automation point survives at the seam. ONE undoable command.
    if (ok) {
        doc.addNotes(track, {{base + step * 50, 60, step, 90},
                             {base + step * 52, 62, step, 90},
                             {base + step * 56, 64, step, 90}});
        doc.addLanePoint(track, 7, base + step * 51, 30);
        doc.addLanePoint(track, 7, base + step * 52, 40);
        SongDocument::TimeScope scope;
        scope.tracks = {track};
        if (!doc.removeTimeRange({base + step * 51, base + step * 54}, scope)) {
            fail("removeTimeRange reported nothing to do");
            ok = false;
        }
        mutateAndCheck("events unsorted after removeTimeRange");
        DocNote n;
        DocLanePoint p;
        if (ok && (!doc.findNote(track, base + step * 50, 60, &n) ||
                   doc.findNote(track, base + step * 52, 62, &n) ||
                   !doc.findNote(track, base + step * 53, 64, &n) ||
                   !doc.findLanePoint(track, 7, base + step * 51, &p) || p.value != 40)) {
            fail("removeTimeRange produced wrong content");
            ok = false;
        }
        if (ok) {
            doc.undoStack()->undo();
            if (!doc.findNote(track, base + step * 56, 64, &n) ||
                !doc.findLanePoint(track, 7, base + step * 52, &p) || p.value != 40) {
                fail("removeTimeRange was not a single undo command");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
    }

    // Whole-song remove: the globals travel too — a time signature
    // and a tempo change inside the range survive at the seam, later
    // notes shift, loop markers before the range stay put, and the
    // end-of-track ticks close the gap so the song gets shorter.
    if (ok) {
        const auto maxEnd = [&doc] {
            uint64_t end = 0;
            for (const SmfTrack &tr : doc.smf().tracks)
                end = std::max(end, tr.endTick);
            return end;
        };
        doc.setTimeSig(base + step * 62, 3, 2);
        doc.applyTempoEdit({{}, {tempoPoint(base + step * 63, 150)}});
        doc.addNotes(track, {{base + step * 66, 65, step, 90}});
        const uint64_t endBefore = maxEnd();
        const uint64_t loopStartBefore = doc.loopTick(false);
        SongDocument::TimeScope scope;
        scope.wholeSong = true;
        if (!doc.removeTimeRange({base + step * 61, base + step * 65}, scope)) {
            fail("whole-song removeTimeRange reported nothing to do");
            ok = false;
        }
        mutateAndCheck("events unsorted after whole-song removeTimeRange");
        DocNote n;
        bool sigAtSeam = false;
        for (const DocTimeSig &sig : doc.timeSigs()) {
            if (sig.tick == base + step * 61 && sig.numerator == 3)
                sigAtSeam = true;
        }
        if (ok && (!sigAtSeam || !containsTempoPoint(doc, tempoPoint(base + step * 61, 150)) ||
                   !doc.findNote(track, base + step * 62, 65, &n) ||
                   maxEnd() != endBefore - step * 4 || doc.loopTick(false) != loopStartBefore)) {
            fail("whole-song removeTimeRange produced wrong content");
            ok = false;
        }
        if (ok) {
            doc.undoStack()->undo();
            if (!doc.findNote(track, base + step * 66, 65, &n) || maxEnd() != endBefore) {
                fail("whole-song removeTimeRange was not a single undo command");
                ok = false;
            } else {
                doc.undoStack()->redo();
            }
        }
    }

    // Voice ops: add, value-only modify (must not reorder within the
    // tick), move to a new tick, delete.
    if (ok) {
        doc.addLanePoint(track, DOC_CC_VOICE, base + step, 5);
        mutateAndCheck("events unsorted after voice add");
        DocLanePoint vc;
        if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step, &vc) || vc.value != 5) {
            fail("voice change not found after add");
            ok = false;
        } else {
            doc.moveLanePoints({{track, DOC_CC_VOICE, vc, vc.tick, 9}});
            if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step, &vc) || vc.value != 9) {
                fail("voice value edit not applied");
                ok = false;
            } else {
                doc.moveLanePoints({{track, DOC_CC_VOICE, vc, base + step * 6, 9}});
                mutateAndCheck("events unsorted after voice move");
                if (!doc.findLanePoint(track, DOC_CC_VOICE, base + step * 6, &vc)) {
                    fail("voice change not found after move");
                    ok = false;
                } else {
                    doc.deleteLanePoints(track, DOC_CC_VOICE, {vc});
                }
            }
        }
    }

    // Automation ops on the volume lane and pitch bend, plus tempo.
    if (ok) {
        doc.addLanePoint(track, 7, base + step * 2, 100);
        doc.addLanePoint(track, DOC_CC_BEND, base + step * 3, -1024);
        const TempoPoint tempo = tempoPoint(base + step * 4, 150);
        doc.applyTempoEdit({{}, {tempo}});
        mutateAndCheck("events unsorted after addLanePoint");
        DocLanePoint pt;
        if (!doc.findLanePoint(track, 7, base + step * 2, &pt) || pt.value != 100) {
            fail("lane point not found after add");
            ok = false;
        } else {
            doc.moveLanePoints({{track, 7, pt, base + step * 5, 90}});
            mutateAndCheck("events unsorted after moveLanePoints");
            if (!doc.findLanePoint(track, 7, base + step * 5, &pt) || pt.value != 90) {
                fail("lane point not found after move");
                ok = false;
            } else {
                std::vector<DocLanePoint> doomed{pt};
                DocLanePoint bendPt;
                if (doc.findLanePoint(track, DOC_CC_BEND, base + step * 3, &bendPt))
                    doc.deleteLanePoints(track, DOC_CC_BEND, {bendPt});
                doc.applyTempoEdit({{tempo}, {}});
                // Re-resolve: the deletes above shifted indices.
                if (doc.findLanePoint(track, 7, base + step * 5, &pt))
                    doc.deleteLanePoints(track, 7, {pt});
            }
        }
    }

    return ok;
}

} // namespace editcheck
