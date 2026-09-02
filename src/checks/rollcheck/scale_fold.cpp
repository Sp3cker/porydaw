#include "checks/rollcheck/rollcheck.h"

#include <array>
#include <cmath>

#include "core/songdocument.h"
#include "porydaw_scale.h"
#include "ui/songview.h"

namespace checks::rollcheck {

ScenarioContinuation runScaleFoldScenarios(Harness &check)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // Block C — Fold occupancy and geometry (Wave 6) over a full timeline.
    {
        const auto &proj = view.pitchProjection();
        const int other = doc.engineTrackCount() > 1 ? (scaleTrack == 0 ? 1 : 0) : -1;
        const uint64_t cTick =
            uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
        const auto firstFreeOffScale = [&](const bool occ[128]) {
            for (int k = 1; k < 128; k += 12)
                if (!occ[k])
                    return k;
            return -1;
        };

        view.setScaleHighlight(false);
        view.setScaleFold(true);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);

        // C1. Occupancy is timeline-wide: an off-scale note at a distant
        // tick still creates its row.
        {
            bool occ[128] = {};
            for (const DocNote &n : doc.notesForTrack(scaleTrack))
                occ[n.key] = true;
            const int base = firstFreeOffScale(occ);
            if (base < 0) {
                fail("no free off-scale pitch for the Fold occupancy probe");
            } else {
                const int cmd0 = doc.undoStack()->index();
                doc.addNote(scaleTrack, cTick, uint8_t(base), doc.ticksPerClock(), 100);
                if (proj.rowForPitch(base) == projHidden)
                    fail("Fold occupancy ignored a far-tick off-scale note");
                while (doc.undoStack()->index() > cmd0)
                    doc.undoStack()->undo();
            }
        }

        // C2. Only the selected scaleTrack's notes create rows.
        if (other >= 0) {
            bool occ[128] = {};
            for (const DocNote &n : doc.notesForTrack(scaleTrack))
                occ[n.key] = true;
            int base = -1;
            for (int k = 1; k < 128; k += 12)
                if (!occ[k] && (k + 12 >= 128 || !occ[k + 12])) {
                    base = k; // leave the next octave free for the follow-up
                    break;
                }
            if (base < 0)
                base = firstFreeOffScale(occ);
            if (base < 0) {
                fail("no off-scale pitch for the cross-scaleTrack Fold probe");
            } else {
                const int cmd0 = doc.undoStack()->index();
                doc.addNote(other, cTick, uint8_t(base), doc.ticksPerClock(), 100);
                if (proj.rowForPitch(base) != projHidden)
                    fail("Fold created a row from another scaleTrack's note");
                doc.undoStack()->undo();
                doc.addNote(scaleTrack, cTick, uint8_t(base), doc.ticksPerClock(), 100);
                if (proj.rowForPitch(base) == projHidden)
                    fail("Fold did not add the selected scaleTrack's occupied pitch");
                if (base + 12 < 128) {
                    doc.addNote(other, cTick, uint8_t(base + 12), doc.ticksPerClock(), 100);
                    if (proj.rowForPitch(base + 12) != projHidden)
                        fail("Fold added a same-class octave from another scaleTrack");
                    doc.undoStack()->undo();
                }
                while (doc.undoStack()->index() > cmd0)
                    doc.undoStack()->undo();
            }
        }

        // A selected-track switch preserves Fold and replaces the row set
        // with the incoming track's exact occupancy.
        if (other >= 0) {
            view.selectTrack(other);
            if (view.scaleHighlight() || !view.scaleFold())
                fail("selected-track change altered Fold or enabled Highlight");
            bool incomingOccupancy[128] = {};
            int incomingCount = 0;
            for (const DocNote &n : doc.notesForTrack(other)) {
                if (!incomingOccupancy[n.key]) {
                    incomingOccupancy[n.key] = true;
                    incomingCount++;
                }
            }
            if (proj.visibleRowCount() != incomingCount)
                fail("Fold did not rebuild for the incoming selected track");
            for (int pitch = 0; pitch < 128; pitch++) {
                if ((proj.rowForPitch(pitch) != projHidden) != incomingOccupancy[pitch]) {
                    fail("incoming selected-track Fold rows do not match occupancy");
                    break;
                }
            }
            view.selectTrack(scaleTrack);
        }

        // C3. A held pointer gesture (projection locked) keeps the row set
        // stable until release, then rebuilds.
        {
            bool occ[128] = {};
            for (const DocNote &n : doc.notesForTrack(scaleTrack))
                occ[n.key] = true;
            const int base = firstFreeOffScale(occ);
            if (base >= 0) {
                const int cmd0 = doc.undoStack()->index();
                doc.addNote(scaleTrack, cTick, uint8_t(base), doc.ticksPerClock(), 100);
                const int withNote = proj.visibleRowCount();
                DocNote n;
                if (doc.findNote(scaleTrack, cTick, uint8_t(base), &n)) {
                    view.setProjectionLocked(true);
                    doc.deleteNotes({n}); // rebuild deferred by the lock
                    if (proj.visibleRowCount() != withNote)
                        fail("Fold rebuilt its layout mid-gesture");
                    view.setProjectionLocked(false);
                    view.flushProjectionIfDirty();
                    if (proj.visibleRowCount() >= withNote)
                        fail("Fold did not rebuild its layout on gesture release");
                }
                while (doc.undoStack()->index() > cmd0)
                    doc.undoStack()->undo();
            }
        }

        // C4. Layout rebuilds after add, delete/undo, and redo.
        {
            bool occ[128] = {};
            for (const DocNote &n : doc.notesForTrack(scaleTrack))
                occ[n.key] = true;
            const int base = firstFreeOffScale(occ);
            if (base >= 0) {
                const int cmd0 = doc.undoStack()->index();
                doc.addNote(scaleTrack, cTick, uint8_t(base), doc.ticksPerClock(), 100);
                const int withNote = proj.visibleRowCount();
                if (proj.rowForPitch(base) == projHidden)
                    fail("Fold occupancy did not appear after add");
                doc.undoStack()->undo(); // delete
                if (proj.visibleRowCount() != withNote - 1)
                    fail("Fold layout did not shrink after delete/undo");
                doc.undoStack()->redo(); // re-add
                if (proj.rowForPitch(base) == projHidden)
                    fail("Fold layout did not restore after redo");
                while (doc.undoStack()->index() > cmd0)
                    doc.undoStack()->undo();
            }
        }

        // C5. Root changes reclassify Fold editing without changing its
        // occupied-pitch geometry or camera position.
        {
            std::array<int, 128> rowsBefore = {};
            for (int pitch = 0; pitch < 128; pitch++)
                rowsBefore[pitch] = proj.rowForPitch(pitch);
            const double scrollBefore = view.camera().scrollY();
            const uint64_t revisionBefore = proj.revision();
            view.setScaleRoot(11);
            if (proj.revision() != revisionBefore)
                fail("Fold root change rebuilt occupied-pitch geometry");
            if (std::abs(view.camera().scrollY() - scrollBefore) > 1e-9)
                fail("Fold root change moved the camera");
            for (int pitch = 0; pitch < 128; pitch++) {
                if (proj.rowForPitch(pitch) != rowsBefore[pitch]) {
                    fail("Fold root change altered the occupied-pitch set");
                    break;
                }
            }
            view.setScaleRoot(0);
        }

        view.setScaleHighlight(false);
        view.setScaleFold(false);
    }

    if (doc.undoStack()->index() != undoBaseline)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
