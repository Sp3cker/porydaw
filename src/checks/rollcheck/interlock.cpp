#include "checks/rollcheck/tst_pianoroll.h"

#include <QApplication>
#include <QEvent>
#include <QObject>
#include <QPoint>
#include <QtTest>
#include <algorithm>
#include <optional>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

using checks::rollcheck::Cell;
using checks::rollcheck::makeVelocitySeed;
using checks::rollcheck::PencilVelocityFixture;
using checks::rollcheck::SnappedRows;

void PianoRollTest::gestureInterlock()
{
    auto &check = *m_fixture;
    const std::optional<PencilVelocityFixture> seed = makeVelocitySeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    auto &roll = check.rollInput();
    const QByteArray beforeSlot = doc.smf().write();
    const int undoSlot = doc.undoStack()->index();
    const SnappedRows rows{view, roll};
    const Cell &a = seed->a;
    const Cell &b = seed->b;
    const DocNote &noteA = seed->noteA;
    const DocNote &noteB = seed->noteB;
    const Qt::MouseButtons bothButtons = Qt::LeftButton | Qt::RightButton;
    const QPoint bandStart(1, 0);
    const int startDragDistance = QApplication::startDragDistance();
    const QPoint bandWarmup = bandStart + QPoint(startDragDistance + 1, 0);
    const auto beyond = [](const QPoint &origin, const QPoint &target) {
        const QPoint delta = target - origin;
        return QPoint(target.x() + (delta.x() < 0 ? -4 : 4), target.y() + (delta.y() < 0 ? -4 : 4));
    };
    const QPoint bandEnd = beyond(bandStart, QPoint(std::max(a.center.x(), b.center.x()),
                                                    std::max(a.center.y(), b.center.y())));
    const auto unchanged = [&](const QByteArray &bytes, int index, int count) {
        return doc.smf().write() == bytes && doc.undoStack()->index() == index &&
               doc.undoStack()->count() == count;
    };
    const auto containsAB = [&] {
        const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
        return std::find(selection.begin(), selection.end(), noteA.noteId) != selection.end() &&
               std::find(selection.begin(), selection.end(), noteB.noteId) != selection.end();
    };
    const Cell freeCell = check.findFreeCell();
    QVERIFY2(freeCell.key >= 0, "no free grid cell for the gesture interlock scenarios");

    view.selectionModel().clearNoteSelection();
    view.selectionModel().clearTimeSelection();
    {
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove,
                                  QPoint(a.center.x(), rows.centerY(a.key - 1)), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove, bandEnd, Qt::NoButton, bothButtons,
                                  Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandEnd, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QVERIFY2(view.selectionModel().noteSelection().empty() &&
                     !view.selectionModel().timeSelection().active(),
                 "right release did not resolve the blocked click as empty space");
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandEnd, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QVERIFY2(unchanged(before, undoIndex, undoCount),
                 "aborted left Move changed the document or undo history");
    }

    view.selectionModel().clearNoteSelection();
    view.selectionModel().clearTimeSelection();
    {
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove, bandWarmup, Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  bothButtons, Qt::NoModifier);
        const QPoint beyondB = beyond(a.center, b.center);
        checks::events::sendMouse(roll, QEvent::MouseMove, beyondB, Qt::NoButton, bothButtons,
                                  Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, beyondB, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QVERIFY2(view.selectionModel().noteSelection().empty() &&
                     !view.selectionModel().timeSelection().active(),
                 "demoted right Band did not resolve as a plain clear");
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, beyondB, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QVERIFY2(unchanged(before, undoIndex, undoCount),
                 "demoted right Band changed the document or undo history");
    }

    view.selectionModel().clearNoteSelection();
    view.selectionModel().clearTimeSelection();
    {
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, freeCell.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove, bandEnd, Qt::NoButton, bothButtons,
                                  Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandEnd, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QVERIFY2(containsAB(), "right Band did not select notes A and B from PendingDraw");
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, freeCell.center, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QVERIFY2(containsAB(), "PendingDraw park-cursor release changed the band selection");
        QVERIFY2(unchanged(before, undoIndex, undoCount),
                 "PendingDraw interlock changed the document or undo history");
    }

    view.selectionModel().clearNoteSelection();
    view.selectionModel().clearTimeSelection();
    {
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove, bandWarmup, Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  bothButtons, Qt::ControlModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                                  Qt::RightButton, Qt::ControlModifier);
        QCOMPARE(view.selectionModel().noteSelection(), std::vector<NoteId>{noteB.noteId});
        bool noteBAuditioned = false;
        const auto auditionConnection = QObject::connect(&view, &SongView::auditionNoteTimed, &view,
                                                         [&](int, int key, int velocity, quint32) {
                                                             if (key == noteB.key && velocity > 0)
                                                                 noteBAuditioned = true;
                                                         });
        checks::events::sendMouse(roll, QEvent::MouseMove, b.center + QPoint(1, 1), Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        QObject::disconnect(auditionConnection);
        QVERIFY2(noteBAuditioned, "deferred modifier click did not preserve the live right Band");
        const QPoint beyondA = beyond(b.center, a.center);
        checks::events::sendMouse(roll, QEvent::MouseMove, beyondA, Qt::NoButton, Qt::RightButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, beyondA, Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
        QVERIFY2(containsAB(), "right Band token did not survive the deferred modifier click");
        QVERIFY2(unchanged(before, undoIndex, undoCount),
                 "deferred modifier interlock changed the document or undo history");
    }

    view.selectionModel().clearNoteSelection();
    view.selectionModel().clearTimeSelection();
    {
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();
        const QPoint velocityTarget = b.center - QPoint(0, startDragDistance + 1);
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove, velocityTarget, Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        QVERIFY2(view.previewVelocity(noteB.noteId).has_value(),
                 "modifier velocity drag did not create a preview");
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandStart, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QVERIFY2(!view.previewVelocity(noteB.noteId),
                 "right release did not abort the live velocity preview");
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandStart, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(roll, QEvent::MouseMove, velocityTarget, Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        QVERIFY2(view.previewVelocity(noteB.noteId).has_value(),
                 "later modifier velocity gesture did not create a preview");
        checks::events::sendMouse(roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandStart, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QVERIFY2(!view.previewVelocity(noteB.noteId),
                 "second right release did not abort the live velocity preview");
        checks::events::sendMouse(roll, QEvent::MouseButtonRelease, bandStart, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QVERIFY2(unchanged(before, undoIndex, undoCount),
                 "right-release velocity abort changed the document or undo history");
    }
    QCOMPARE(doc.undoStack()->index(), undoSlot);
    QCOMPARE(doc.smf().write(), beforeSlot);
}
