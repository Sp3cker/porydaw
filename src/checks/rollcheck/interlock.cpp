#include "checks/rollcheck/rollcheck.h"

#include <QApplication>
#include <QEvent>
#include <QObject>
#include <QPoint>
#include <algorithm>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

namespace checks::rollcheck {

ScenarioContinuation runGestureInterlockScenarios(Harness &check,
                                                  const PencilVelocityFixture &fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const Cell &b = fixture.b;
    const DocNote &noteA = fixture.noteA;
    const DocNote &noteB = fixture.noteB;
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
    auto fail = [&](const char *what) { check.fail(what); };
    const auto assertUnchanged = [&](const QByteArray &before, int undoIndex, int undoCount,
                                     const char *what) {
        if (doc.smf().write() != before || doc.undoStack()->index() != undoIndex ||
            doc.undoStack()->count() != undoCount)
            fail(what);
    };
    const auto containsAB = [&] {
        const std::vector<NoteId> &selection = view.selectionModel().noteSelection();
        return std::find(selection.begin(), selection.end(), noteA.noteId) != selection.end() &&
               std::find(selection.begin(), selection.end(), noteB.noteId) != selection.end();
    };
    // Events are delivered synchronously; no processEvents() or QMenu is needed.
    // Every held-button sequence below ends with the matching release.
    const Cell freeCell = check.findFreeCell();
    if (freeCell.key < 0) {
        fail("no free grid cell for the gesture interlock scenarios");
        return ScenarioContinuation::Stop;
    }

    // Scenario A: a live left Move blocks right activation; releasing the right
    // button resolves the pending right click as empty space and aborts Move.
    {
        view.selectionModel().clearNoteSelection();
        view.selectionModel().clearTimeSelection();
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove,
                                  QPoint(a.center.x(), rows.centerY(a.key - 1)), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, bandEnd, Qt::NoButton, bothButtons,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandEnd, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (!view.selectionModel().noteSelection().empty() ||
            view.selectionModel().timeSelection().active())
            fail("right release did not resolve the blocked click as empty space");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandEnd, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        assertUnchanged(before, undoIndex, undoCount,
                        "aborted left Move changed the document or undo history");
    }

    // Scenario B: activating a left Move demotes a live right Band. The right
    // release then resolves its pending token as a plain clear.
    {
        view.selectionModel().clearNoteSelection();
        view.selectionModel().clearTimeSelection();
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, bandWarmup, Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, a.center, Qt::LeftButton,
                                  bothButtons, Qt::NoModifier);
        const QPoint beyondB = beyond(a.center, b.center);
        checks::events::sendMouse(*roll, QEvent::MouseMove, beyondB, Qt::NoButton, bothButtons,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, beyondB, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (!view.selectionModel().noteSelection().empty() ||
            view.selectionModel().timeSelection().active())
            fail("demoted right Band did not resolve as a plain clear");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, beyondB, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        assertUnchanged(before, undoIndex, undoCount,
                        "demoted right Band changed the document or undo history");
    }

    // Scenario C: PendingDraw does not block right resolution. The later left
    // release takes the normative park-cursor fall-through; it does not keep a
    // live right token alive.
    {
        view.selectionModel().clearNoteSelection();
        view.selectionModel().clearTimeSelection();
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, freeCell.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, bandEnd, Qt::NoButton, bothButtons,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandEnd, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (!containsAB())
            fail("right Band did not select notes A and B from PendingDraw");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, freeCell.center,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        if (!containsAB())
            fail("PendingDraw park-cursor release changed the band selection");
        assertUnchanged(before, undoIndex, undoCount,
                        "PendingDraw interlock changed the document or undo history");
    }

    // Scenario D: a deferred modifier click releases without clearing the live
    // right Band. Re-anchor the second target from note B because its press
    // overwrote the right gesture's m_pressPos.
    {
        view.selectionModel().clearNoteSelection();
        view.selectionModel().clearTimeSelection();
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, bandWarmup, Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  bothButtons, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, b.center, Qt::LeftButton,
                                  Qt::RightButton, Qt::ControlModifier);
        if (view.selectionModel().noteSelection() != std::vector<NoteId>{noteB.noteId})
            fail("deferred modifier click did not select exactly note B");
        bool noteBAuditioned = false;
        const auto auditionConnection = QObject::connect(&view, &SongView::auditionNoteTimed, &view,
                                                         [&](int, int key, int velocity, quint32) {
                                                             if (key == noteB.key && velocity > 0)
                                                                 noteBAuditioned = true;
                                                         });
        checks::events::sendMouse(*roll, QEvent::MouseMove, b.center + QPoint(1, 1), Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        QObject::disconnect(auditionConnection);
        if (!noteBAuditioned)
            fail("deferred modifier click did not preserve the live right Band");
        const QPoint beyondA = beyond(b.center, a.center);
        checks::events::sendMouse(*roll, QEvent::MouseMove, beyondA, Qt::NoButton, Qt::RightButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, beyondA, Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (!containsAB())
            fail("right Band token did not survive the deferred modifier click");
        assertUnchanged(before, undoIndex, undoCount,
                        "deferred modifier interlock changed the document or undo history");
    }

    // Scenario E: right release aborts a live modifier velocity drag and
    // leaves the velocity model ready for a later gesture.
    {
        view.selectionModel().clearNoteSelection();
        view.selectionModel().clearTimeSelection();
        const QByteArray before = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();
        const int undoCount = doc.undoStack()->count();
        const QPoint velocityTarget = b.center - QPoint(0, startDragDistance + 1);

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, velocityTarget, Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        if (!view.previewVelocity(noteB.noteId))
            fail("modifier velocity drag did not create a preview");

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandStart, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (view.previewVelocity(noteB.noteId))
            fail("right release did not abort the live velocity preview");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandStart, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, b.center, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        checks::events::sendMouse(*roll, QEvent::MouseMove, velocityTarget, Qt::NoButton,
                                  Qt::LeftButton, Qt::ControlModifier);
        if (!view.previewVelocity(noteB.noteId))
            fail("later modifier velocity gesture did not create a preview");

        checks::events::sendMouse(*roll, QEvent::MouseButtonPress, bandStart, Qt::RightButton,
                                  bothButtons, Qt::NoModifier);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandStart, Qt::RightButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (view.previewVelocity(noteB.noteId))
            fail("second right release did not abort the live velocity preview");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, bandStart, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);

        assertUnchanged(before, undoIndex, undoCount,
                        "right-release velocity abort changed the document or undo history");
    }

    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
