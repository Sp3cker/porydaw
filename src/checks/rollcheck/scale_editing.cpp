#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/rollcheck/rollcheck.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QEvent>
#include <QObject>
#include <QPoint>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <cstdint>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "porydaw_scale.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

using namespace checks::rollcheck;

void PianoRollTest::scaleFoldKeyboardNudges_data()
{
    QTest::addColumn<bool>("fold");
    QTest::addColumn<int>("modifiers");
    QTest::addColumn<int>("expectedPitch");
    QTest::addColumn<QString>("failure");

    QTest::newRow("fold-degree") << true << int(Qt::NoModifier) << 62
                                 << QStringLiteral(
                                        "Fold Up did not move C up one scale degree to D");
    QTest::newRow("fold-octave") << true << int(Qt::ShiftModifier) << 72
                                 << QStringLiteral("Fold Shift+Up did not move C up an octave");
    QTest::newRow("chromatic") << false << int(Qt::NoModifier) << 61
                               << QStringLiteral("Off Up did not move C up a semitone");
}

void PianoRollTest::scaleFoldKeyboardNudges()
{
    QFETCH(bool, fold);
    QFETCH(int, modifiers);
    QFETCH(int, expectedPitch);
    QFETCH(QString, failure);

    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int scaleTrack = view.selectionModel().primaryTrack();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const auto noteIdAt = [&](uint64_t tick, uint8_t key) {
        DocNote note;
        return doc.findNote(scaleTrack, tick, key, &note) ? note.noteId : NoteId{};
    };

    doc.addNote(scaleTrack, tBase, 60, dur, 100);
    view.selectionModel().setNoteSelection({noteIdAt(tBase, 60)});
    view.setScaleHighlight(false);
    view.setScaleFold(fold);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    sendKeyStroke(*roll, Qt::Key_Up, Qt::KeyboardModifiers(modifiers), false);
    DocNote moved;
    if (!doc.findNote(scaleTrack, tBase, uint8_t(expectedPitch), &moved))
        QFAIL(qPrintable(failure));
    while (doc.undoStack()->index() > undo)
        doc.undoStack()->undo();
    view.selectionModel().clearNoteSelection();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldMultiNoteMapping()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *roll = &check.rollInput();
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());
    const auto noteIdAt = [&](uint64_t tick, uint8_t key) {
        DocNote note;
        return doc.findNote(scaleTrack, tick, key, &note) ? note.noteId : NoteId{};
    };

    // D4. Multi-note selection maps to distinct degrees (60,61 -> 62,64).
    {
        const int cmd0 = doc.undoStack()->index();
        doc.addNote(scaleTrack, tBase, 60, dur, 100);
        doc.addNote(scaleTrack, tBase, 61, dur, 100);
        view.selectionModel().setNoteSelection({noteIdAt(tBase, 60), noteIdAt(tBase, 61)});
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
        DocNote moved;
        const bool okA = doc.findNote(scaleTrack, tBase, 62, &moved);
        const bool okB = doc.findNote(scaleTrack, tBase, 64, &moved);
        if (!okA || !okB)
            QFAIL("Fold Up did not map selected notes to distinct degrees");
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldRepeatedPitchMapping()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *roll = &check.rollInput();
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());
    const auto noteIdAt = [&](uint64_t tick, uint8_t key) {
        DocNote note;
        return doc.findNote(scaleTrack, tick, key, &note) ? note.noteId : NoteId{};
    };

    // D5. Repeated source pitch: two C60 notes both go to D62.
    {
        const int cmd0 = doc.undoStack()->index();
        const uint64_t tA = tBase, tB = tBase + uint64_t(doc.ticksPerClock());
        doc.addNote(scaleTrack, tA, 60, dur, 100);
        doc.addNote(scaleTrack, tB, 60, dur, 100);
        view.selectionModel().setNoteSelection({noteIdAt(tA, 60), noteIdAt(tB, 60)});
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
        DocNote moved;
        const bool okA = doc.findNote(scaleTrack, tA, 62, &moved);
        const bool okB = doc.findNote(scaleTrack, tB, 62, &moved);
        if (!okA || !okB)
            QFAIL("Repeated Fold source pitch did not share the destination");
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldExceptionNudge()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *roll = &check.rollInput();
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());
    const auto noteIdAt = [&](uint64_t tick, uint8_t key) {
        DocNote note;
        return doc.findNote(scaleTrack, tick, key, &note) ? note.noteId : NoteId{};
    };

    // D6. Off-scale source entry (exception) nudges to the first scale
    // pitch above (61 -> 62).
    {
        const int cmd0 = doc.undoStack()->index();
        doc.addNote(scaleTrack, tBase, 61, dur, 100);
        view.selectionModel().setNoteSelection({noteIdAt(tBase, 61)});
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false);
        DocNote moved;
        if (!doc.findNote(scaleTrack, tBase, 62, &moved))
            QFAIL("Fold Up did not move an off-scale exception to the next degree");
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldExceptionDraw()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *roll = &check.rollInput();
    const int pianoRollDefaultKeyHeight = check.pianoRollDefaultKeyHeight();
    const auto &proj = view.pitchProjection();
    const auto foldCenterY = [&](int pitch) -> int {
        const int row = view.pitchProjection().rowForPitch(pitch);
        if (row == songview::PitchProjection::cHiddenRow)
            return -1;
        const qreal dpr = roll->devicePixelRatio();
        const qreal top =
            std::round((double(row) * view.camera().keyHeight() - view.camera().scrollY()) * dpr) /
            dpr;
        const qreal bottom =
            std::round((double(row + 1) * view.camera().keyHeight() - view.camera().scrollY()) *
                       dpr) /
            dpr;
        return int(std::floor((top + bottom) / 2.0));
    };
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());

    // D7. Fold rejects drawing into an off-scale exception row.
    {
        const int cmd0 = doc.undoStack()->index();
        doc.addNote(scaleTrack, tBase, 61, dur, 100);
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        const int r61 = proj.rowForPitch(61);
        SongView::ViewState d7 = view.viewState();
        d7.valid = true;
        d7.keyHeight = pianoRollDefaultKeyHeight;
        d7.scrollY =
            double(std::max(0, r61 * pianoRollDefaultKeyHeight - 4 * pianoRollDefaultKeyHeight));
        view.applyViewState(d7);
        (void)view.grab();
        QCoreApplication::processEvents();
        const size_t before = doc.notesForTrack(scaleTrack).size();
        drawNote(*roll, QPoint(40, foldCenterY(61)));
        QCoreApplication::processEvents();
        if (doc.notesForTrack(scaleTrack).size() != before)
            QFAIL("Fold accepted a draw into an off-scale exception row");
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldExceptionAudition()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *rollGutter = &check.rollGutterInput();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const int pianoRollDefaultKeyHeight = check.pianoRollDefaultKeyHeight();
    const auto &proj = view.pitchProjection();
    const auto foldCenterY = [&](int pitch) -> int {
        const int row = view.pitchProjection().rowForPitch(pitch);
        if (row == songview::PitchProjection::cHiddenRow)
            return -1;
        const qreal dpr = rollGutter->devicePixelRatio();
        const qreal top =
            std::round((double(row) * view.camera().keyHeight() - view.camera().scrollY()) * dpr) /
            dpr;
        const qreal bottom =
            std::round((double(row + 1) * view.camera().keyHeight() - view.camera().scrollY()) *
                       dpr) /
            dpr;
        return int(std::floor((top + bottom) / 2.0));
    };
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());

    // D8. The exception row's piano key still auditions its pitch.
    {
        const int cmd0 = doc.undoStack()->index();
        doc.addNote(scaleTrack, tBase, 61, dur, 100);
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        const int r61 = proj.rowForPitch(61);
        SongView::ViewState d8 = view.viewState();
        d8.valid = true;
        d8.keyHeight = pianoRollDefaultKeyHeight;
        d8.scrollY =
            double(std::max(0, r61 * pianoRollDefaultKeyHeight - 4 * pianoRollDefaultKeyHeight));
        view.applyViewState(d8);
        (void)view.grab();
        QCoreApplication::processEvents();
        int audKey = -1;
        auto conn = QObject::connect(&view, &SongView::auditionNote, &view,
                                     [&](int, int key, int velocity) {
                                         if (velocity > 0)
                                             audKey = key;
                                     });
        checks::events::sendMouse(*rollGutter, QEvent::MouseButtonPress,
                                  QPoint(pianoKeyboardWidth / 2, foldCenterY(61)), Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QObject::disconnect(conn);
        if (audKey != 61)
            QFAIL("Fold exception-row piano key did not audition pitch 61");
        checks::events::sendMouse(*rollGutter, QEvent::MouseButtonRelease,
                                  QPoint(pianoKeyboardWidth / 2, foldCenterY(61)), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldPointerDrag()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *roll = &check.rollInput();
    const int pianoRollDefaultKeyHeight = check.pianoRollDefaultKeyHeight();
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    const auto &proj = view.pitchProjection();
    const auto foldCenterY = [&](int pitch) -> int {
        const int row = view.pitchProjection().rowForPitch(pitch);
        if (row == songview::PitchProjection::cHiddenRow)
            return -1;
        const qreal dpr = roll->devicePixelRatio();
        const qreal top =
            std::round((double(row) * view.camera().keyHeight() - view.camera().scrollY()) * dpr) /
            dpr;
        const qreal bottom =
            std::round((double(row + 1) * view.camera().keyHeight() - view.camera().scrollY()) *
                       dpr) /
            dpr;
        return int(std::floor((top + bottom) / 2.0));
    };
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;

    // D9+D12. A vertical pointer drag previews and commits the fold
    // degree; the layout only rebuilds once the gesture commits. The
    // source pitch is an off-scale exception NOT present anywhere in the
    // track: adding it adds exactly one fold row, and committing the
    // drag away collapses it — deterministic regardless of the song.
    {
        const int cmd0 = doc.undoStack()->index();
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);
        (void)view.grab();
        QCoreApplication::processEvents();
        bool occ[128] = {};
        for (const DocNote &dn : doc.notesForTrack(scaleTrack))
            occ[dn.key] = true;
        // The lowest off-scale (non-diatonic) pitch the track never uses.
        int src = -1, dst = -1;
        for (int k = 48; k < 96; k++) {
            if (porydaw_scale::isScalePitch(scaleMajor, 0, k) || occ[k])
                continue;
            src = k;
            dst = porydaw_scale::nextScalePitch(scaleMajor, 0, k, 1);
            break;
        }
        if (src < 0 || dst < 0 || dst == src)
            QFAIL("Fold drag could not pick a free off-scale pitch");
        // Occupied-only Fold needs a visible scale row for the pointer
        // target. Add a distant support note when the track does not
        // already use that destination pitch.
        if (!occ[dst])
            doc.addNote(scaleTrack,
                        uint64_t(check.timeline().lengthTicks) + doc.ticksPerClock() * 32,
                        uint8_t(dst), doc.ticksPerClock(), 100);
        const int rowsBeforeSource = proj.visibleRowCount();
        doc.addNote(scaleTrack, tBase, uint8_t(src), uint32_t(doc.ticksPerClock()) * 4, 100);
        QCoreApplication::processEvents();
        const int rowsWithNote = proj.visibleRowCount();
        if (rowsWithNote != rowsBeforeSource + 1)
            QFAIL("Fold drag did not gain the occupied off-scale row");
        view.ensureTickVisible(tBase);
        const int rSrc = proj.rowForPitch(src);
        SongView::ViewState d9 = view.viewState();
        d9.valid = true;
        d9.keyHeight = pianoRollDefaultKeyHeight;
        d9.scrollY =
            double(std::max(0, rSrc * pianoRollDefaultKeyHeight - 4 * pianoRollDefaultKeyHeight));
        view.applyViewState(d9);
        (void)view.grab();
        QCoreApplication::processEvents();
        // Press the note center for a Move drag: horizontally the center
        // avoids the 3px edge-grip zones on this 5px-wide, 4-tick note.
        const int x = int((view.camera().contentX(double(tBase)) +
                           view.camera().contentX(double(tBase) + doc.ticksPerClock() * 4)) /
                          2.0);
        const QPoint press(x, foldCenterY(src));
        int dragAud = -1;
        auto dconn = QObject::connect(&view, &SongView::auditionNote, &view,
                                      [&](int, int key, int velocity) {
                                          if (velocity > 0)
                                              dragAud = key;
                                      });
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, press, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (view.selectionModel().noteSelection().size() != 1)
            QFAIL("Fold drag press did not grab the off-scale note");
        if (proj.visibleRowCount() != rowsWithNote)
            QFAIL("Fold rebuilt its layout during a pointer drag");
        const int rDst = proj.rowForPitch(dst);
        if (rDst == projHidden)
            QFAIL("Fold drag target row is hidden");
        const QPoint target(x, foldCenterY(dst));
        checks::events::sendMouse(*roll, QEvent::MouseMove, target, Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        if (proj.visibleRowCount() != rowsWithNote)
            QFAIL("Fold rebuilt its layout mid-drag");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, target, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QObject::disconnect(dconn);
        QCoreApplication::processEvents();
        DocNote moved;
        if (!doc.findNote(scaleTrack, tBase, uint8_t(dst), &moved))
            QFAIL("Fold drag did not commit the note to its scale degree");
        if (proj.visibleRowCount() != rowsBeforeSource)
            QFAIL("Fold did not rebuild its occupied rows after the drag commit");
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldHorizontalException()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());

    // D10. A horizontal-only move preserves an off-scale exception pitch.
    {
        const int cmd0 = doc.undoStack()->index();
        doc.addNote(scaleTrack, tBase, 61, dur, 100);
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        DocNote n;
        if (doc.findNote(scaleTrack, tBase, 61, &n)) {
            const uint64_t next = tBase + uint64_t(doc.ticksPerClock()) * 4;
            doc.moveNotes({n}, int64_t(next) - int64_t(tBase), 0, /*mergeable=*/true);
            DocNote moved;
            if (!doc.findNote(scaleTrack, next, 61, &moved))
                QFAIL("Fold horizontal move changed the exception pitch");
        }
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::scaleFoldOutOfRange()
{
    PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const int scaleTrack = view.selectionModel().primaryTrack();
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    songview::TimelineInputItem *roll = &check.rollInput();
    const uint64_t tBase =
        uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
    const uint32_t dur = uint32_t(doc.ticksPerClock());
    const auto noteIdAt = [&](uint64_t tick, uint8_t key) {
        DocNote note;
        return doc.findNote(scaleTrack, tick, key, &note) ? note.noteId : NoteId{};
    };

    // D11. Out-of-range diatonic nudge is atomic: no move, no command.
    {
        const int cmd0 = doc.undoStack()->index();
        doc.addNote(scaleTrack, tBase, 127, dur, 100); // B = top C-major pitch
        view.selectionModel().setNoteSelection({noteIdAt(tBase, 127)});
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        const int cmdsBefore = doc.undoStack()->count();
        sendKeyStroke(*roll, Qt::Key_Up, Qt::NoModifier, false); // out of range
        if (doc.undoStack()->count() != cmdsBefore)
            QFAIL("Fold out-of-range nudge pushed an undo command");
        DocNote still;
        if (!doc.findNote(scaleTrack, tBase, 127, &still))
            QFAIL("Fold out-of-range nudge moved the top pitch");
        while (doc.undoStack()->index() > cmd0)
            doc.undoStack()->undo();
        view.selectionModel().clearNoteSelection();
    }
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.setScaleRoot(0);
    view.setScaleId(scaleMajor);
    if (doc.undoStack()->index() != undo)
        QFAIL("gesture pass pushed an unexpected number of undo commands");
    QCOMPARE(doc.smf().write(), before);
}
