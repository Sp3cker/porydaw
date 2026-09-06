#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/rollcheck/rollcheck.h"

#include <QByteArray>
#include <QtTest>
#include <array>
#include <cmath>

#include "core/songdocument.h"
#include "porydaw_scale.h"
#include "ui/songview.h"
#include <cstdint>

using namespace checks::rollcheck;

void PianoRollTest::scaleFoldOccupancy()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(true);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    const auto &proj = view.pitchProjection();
    const uint64_t cTick =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const auto firstFreeOffScale = [&](const bool occ[128]) {
        for (int k = 1; k < 128; k += 12)
            if (!occ[k])
                return k;
        return -1;
    };

    // C1. Occupancy is timeline-wide: an off-scale note at a distant
    // tick still creates its row.
    {
        bool occ[128] = {};
        for (const DocNote &n : doc.notesForTrack(scaleTrack))
            occ[n.key] = true;
        const int base = firstFreeOffScale(occ);
        if (base < 0) {
            QFAIL("no free off-scale pitch for the Fold occupancy probe");
        } else {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, cTick, uint8_t(base), doc.ticksPerClock(), 100);
            if (proj.rowForPitch(base) == projHidden)
                QFAIL("Fold occupancy ignored a far-tick off-scale note");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldTrackScope()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(true);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    const auto &proj = view.pitchProjection();
    const uint64_t cTick =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const int other = doc.engineTrackCount() > 1 ? (scaleTrack == 0 ? 1 : 0) : -1;
    const auto firstFreeOffScale = [&](const bool occ[128]) {
        for (int k = 1; k < 128; k += 12)
            if (!occ[k])
                return k;
        return -1;
    };

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
            QFAIL("no off-scale pitch for the cross-scaleTrack Fold probe");
        } else {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(other, cTick, uint8_t(base), doc.ticksPerClock(), 100);
            if (proj.rowForPitch(base) != projHidden)
                QFAIL("Fold created a row from another scaleTrack's note");
            doc.undoStack()->undo();
            doc.addNote(scaleTrack, cTick, uint8_t(base), doc.ticksPerClock(), 100);
            if (proj.rowForPitch(base) == projHidden)
                QFAIL("Fold did not add the selected scaleTrack's occupied pitch");
            if (base + 12 < 128) {
                doc.addNote(other, cTick, uint8_t(base + 12), doc.ticksPerClock(), 100);
                if (proj.rowForPitch(base + 12) != projHidden)
                    QFAIL("Fold added a same-class octave from another scaleTrack");
                doc.undoStack()->undo();
            }
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldProjectionLock()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(true);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    const auto &proj = view.pitchProjection();
    const uint64_t cTick =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const auto firstFreeOffScale = [&](const bool occ[128]) {
        for (int k = 1; k < 128; k += 12)
            if (!occ[k])
                return k;
        return -1;
    };

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
                    QFAIL("Fold rebuilt its layout mid-gesture");
                view.setProjectionLocked(false);
                view.flushProjectionIfDirty();
                if (proj.visibleRowCount() >= withNote)
                    QFAIL("Fold did not rebuild its layout on gesture release");
            }
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldUndoLifecycle()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(true);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    const auto &proj = view.pitchProjection();
    const uint64_t cTick =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const auto firstFreeOffScale = [&](const bool occ[128]) {
        for (int k = 1; k < 128; k += 12)
            if (!occ[k])
                return k;
        return -1;
    };

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
                QFAIL("Fold occupancy did not appear after add");
            doc.undoStack()->undo(); // delete
            if (proj.visibleRowCount() != withNote - 1)
                QFAIL("Fold layout did not shrink after delete/undo");
            doc.undoStack()->redo(); // re-add
            if (proj.rowForPitch(base) == projHidden)
                QFAIL("Fold layout did not restore after redo");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldRootInvariant()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(true);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    const auto &proj = view.pitchProjection();

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
            QFAIL("Fold root change rebuilt occupied-pitch geometry");
        if (std::abs(view.camera().scrollY() - scrollBefore) > 1e-9)
            QFAIL("Fold root change moved the camera");
        for (int pitch = 0; pitch < 128; pitch++) {
            if (proj.rowForPitch(pitch) != rowsBefore[pitch]) {
                QFAIL("Fold root change altered the occupied-pitch set");
                break;
            }
        }
        view.setScaleRoot(0);
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}
