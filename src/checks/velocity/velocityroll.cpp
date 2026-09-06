#include "checks/velocity/tst_velocityediting.h"

#include <algorithm>
#include <cstdint>
#include <optional>

#include <QApplication>
#include <QQuickItem>
#include <QRect>

#include <QtTest>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/pitchprojection.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

struct RollDragTarget {
    qreal noteStartX = 0.0;
    qreal noteEndX = 0.0;
    qreal noteTop = 0.0;
    qreal noteBottom = 0.0;
    QPoint pressLocal;
    QPoint dragLocal;
};

std::optional<RollDragTarget> presentRollDragTarget(SongView &view,
                                                    songview::TimelineInputItem &rollInput,
                                                    const DocNote &note, int dragDelta)
{
    const int noteRow = view.pitchProjection().rowForPitch(note.key);
    if (noteRow == songview::PitchProjection::cHiddenRow)
        return std::nullopt;

    view.ensureRangeVisible(note.tick, note.tick + note.duration, true);
    view.ensureKeyVisible(note.key);

    const qreal dpr = rollInput.devicePixelRatio();
    const auto resolveTarget = [&]() {
        const qreal noteStartX = view.camera().displayX(double(note.tick), 0.0, dpr);
        const qreal noteEndX = view.camera().displayX(double(note.tick + note.duration), 0.0, dpr);
        const qreal noteTop = view.pitchProjection().rowTop(noteRow, view.camera().keyHeight(),
                                                            view.camera().scrollY(), dpr);
        const qreal noteBottom = view.pitchProjection().rowBottom(
            noteRow, view.camera().keyHeight(), view.camera().scrollY(), dpr);
        const QPoint pressLocal =
            QPointF((noteStartX + noteEndX) / 2.0, (noteTop + noteBottom) / 2.0).toPoint();
        return RollDragTarget{noteStartX, noteEndX,   noteTop,
                              noteBottom, pressLocal, pressLocal - QPoint(0, dragDelta)};
    };

    const RollDragTarget revealed = resolveTarget();
    view.scrollRollBy((revealed.noteTop + revealed.noteBottom) / 2.0 -
                      rollInput.bounds().center().y());
    return resolveTarget();
}

} // namespace

// Shared prologue for the three roll-drag regressions below: it selects the
// drag pair, hides the velocity band, resolves a fully visible note target,
// focuses the roll input, and presses + moves through the real window until
// both selected notes hold staged previews with document, history, and the
// timeline projection frozen.
void VelocityEditingTest::beginStagedRollDrag(RollDragSession *session)
{
    selectDragPair();
    QVERIFY(m_later.noteId != m_quietStacked.noteId);
    QVERIFY(m_later.noteId != m_loudStacked.noteId);

    const Qt::KeyboardModifiers velocityDragModifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    QVERIFY(velocityDragModifiers != Qt::NoModifier);
    session->dragModifiers = velocityDragModifiers;

    SongView &view = m_tab->view();
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::Velocity));
    const std::optional<songview::TimelineBandGeometry> &rollBand =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(rollBand.has_value());
    QTRY_COMPARE(m_rollInput->size(), QSizeF(rollBand->plotRect.size()));
    QVERIFY(m_rollInput->isVisible());

    const int dragDelta = QApplication::startDragDistance() + 16;
    QVERIFY(m_rollInput->bounds().height() > 2 * dragDelta);
    const std::optional<RollDragTarget> target =
        presentRollDragTarget(view, *m_rollInput, m_later, dragDelta);
    QVERIFY(target.has_value());
    const QPoint rollPressLocal = target->pressLocal;
    const QPoint rollDragLocal = target->dragLocal;
    QVERIFY(target->noteStartX < rollPressLocal.x() && rollPressLocal.x() < target->noteEndX);
    QVERIFY(target->noteTop < rollPressLocal.y() && rollPressLocal.y() < target->noteBottom);
    QVERIFY(m_rollInput->bounds().contains(rollPressLocal));
    QVERIFY(m_rollInput->bounds().contains(rollDragLocal));

    // The clamp saturates for large deltas, so this is not a tautology: the
    // fixture pair must have headroom for the staged previews to stay exact
    // unsaturated sums.
    session->expectedQuiet = std::clamp(int(m_quietStacked.velocity) + dragDelta, 1, 127);
    session->expectedLater = std::clamp(int(m_later.velocity) + dragDelta, 1, 127);
    QCOMPARE(session->expectedQuiet, int(m_quietStacked.velocity) + dragDelta);
    QCOMPARE(session->expectedLater, int(m_later.velocity) + dragDelta);

    session->revisionBefore = m_tab->document().revision();
    session->undoIndexBefore = m_tab->document().undoStack()->index();
    session->undoDepthBefore = m_tab->document().undoStack()->count();
    // Emplaced after the baseline snapshots so the counts isolate the
    // gesture; a failed setup check destroys them with the session.
    session->documentChanged.emplace(&m_tab->document(), &SongDocument::documentChanged);
    session->edited.emplace(m_tab.get(), &SongTab::edited);
    QVERIFY(session->documentChanged->isValid());
    QVERIFY(session->edited->isValid());

    QVERIFY(
        m_tab->view().quickView()->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Roll);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(), static_cast<QQuickItem *>(m_rollInput.data()));

    session->pressWindow = m_rollInput->mapToScene(rollPressLocal).toPoint();
    session->dragWindow = m_rollInput->mapToScene(rollDragLocal).toPoint();
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(session->pressWindow));
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(session->dragWindow));

    mousePress(Qt::LeftButton, session->pressWindow, velocityDragModifiers);
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(m_rollInput.data()));
    mouseMove(session->dragWindow, velocityDragModifiers);

    // The public roll drag applies an integral upward pixel delta to every
    // selected note while holding the document, history, and current timeline
    // projection frozen. The unselected stacked sibling never receives a preview.
    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), session->expectedQuiet);
    QCOMPARE(int(*laterPreview), session->expectedLater);
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), session->revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->index(), session->undoIndexBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), session->undoDepthBefore);
    QCOMPARE(session->documentChanged->count(), 0);
    QCOMPARE(session->edited->count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

// The cancelled contract shared by the controller and Escape paths: once the
// still-held synthetic pointer's move and release are swallowed, previews stay
// cleared and document, history, timeline, and selection match the pre-drag
// state exactly.
void VelocityEditingTest::verifyCancelledRollDragIdle(const RollDragSession &session)
{
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), session.revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->index(), session.undoIndexBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), session.undoDepthBefore);
    QCOMPARE(session.documentChanged->count(), 0);
    QCOMPARE(session.edited->count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::rollDragCommitsOnce()
{
    RollDragSession session;
    beginStagedRollDrag(&session);
    if (QTest::currentTestFailed())
        return;

    mouseRelease(Qt::LeftButton, session.dragWindow, session.dragModifiers);

    // One release produces one document command and republished timeline values.
    QCOMPARE(session.documentChanged->count(), 1);
    QCOMPARE(session.edited->count(), 1);
    QCOMPARE(m_tab->document().revision(), session.revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), session.undoDepthBefore + 1);
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), session.expectedQuiet);
    QCOMPARE(documentVelocity(m_later.noteId), session.expectedLater);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), session.expectedQuiet);
    QCOMPARE(timelineVelocity(m_later.noteId), session.expectedLater);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::controllerCancellationStopsRollDrag()
{
    // Whole-document serialization roundtrip: the cancelled gesture and every
    // revival attempt must leave the song byte-identical.
    const QByteArray smfBefore = m_tab->document().smf().write();

    RollDragSession session;
    beginStagedRollDrag(&session);
    if (QTest::currentTestFailed())
        return;

    // Cancellation is meaningful only after the real roll gesture has staged
    // changed previews for both selected notes.
    m_tab->view().cancelActiveInteractions();
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());

    // A still-held synthetic pointer can no longer revive or commit the
    // cancelled gesture. The direct pass runs first: it probes raw
    // item-local drag state before any window-routed release could
    // sanitize it. The window pass then exercises post-ungrab delivery
    // routing and clears the held pointer.
    const QPointF revivalLocal = m_rollInput->mapFromScene(QPointF(session.pressWindow));
    checks::events::sendMouse(*m_rollInput, QEvent::MouseMove, revivalLocal, Qt::NoButton,
                              Qt::LeftButton, session.dragModifiers);
    checks::events::sendMouse(*m_rollInput, QEvent::MouseButtonRelease, revivalLocal,
                              Qt::LeftButton, Qt::NoButton, session.dragModifiers);
    verifyCancelledRollDragIdle(session);

    mouseMove(session.pressWindow, session.dragModifiers);
    mouseRelease(Qt::LeftButton, session.pressWindow, session.dragModifiers);
    verifyCancelledRollDragIdle(session);
    QCOMPARE(m_tab->document().smf().write(), smfBefore);
}

void VelocityEditingTest::escapeStopsRollDrag()
{
    RollDragSession session;
    beginStagedRollDrag(&session);
    if (QTest::currentTestFailed())
        return;

    // Escape is delivered to the live Roll focus item rather than bypassing
    // keyboard routing through a controller call.
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Roll);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(), static_cast<QQuickItem *>(m_rollInput.data()));
    QTest::keyClick(m_quickWindow, Qt::Key_Escape);
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    mouseMove(session.pressWindow, session.dragModifiers);
    mouseRelease(Qt::LeftButton, session.pressWindow, session.dragModifiers);
    verifyCancelledRollDragIdle(session);

    // The first Escape owns gesture cancellation. Once the gesture is idle,
    // a second Escape reaches the editor's selection-dismiss command.
    QTest::keyClick(m_quickWindow, Qt::Key_Escape);
    QTRY_VERIFY(m_tab->view().selectionModel().noteSelection().empty());
    QCOMPARE(m_tab->document().revision(), session.revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), session.undoDepthBefore);
    QCOMPARE(session.documentChanged->count(), 0);
    QCOMPARE(session.edited->count(), 0);
}

void VelocityEditingTest::velocityFocusOctaveShortcutMovesSelectedNotes()
{
    selectDragPair();

    DocNote quietBefore;
    DocNote loudBefore;
    DocNote laterBefore;
    QVERIFY(m_tab->document().findNote(m_quietStacked.noteId, &quietBefore));
    QVERIFY(m_tab->document().findNote(m_loudStacked.noteId, &loudBefore));
    QVERIFY(m_tab->document().findNote(m_later.noteId, &laterBefore));
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Velocity);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));
    QTest::keyClick(m_quickWindow, Qt::Key_Up, Qt::ShiftModifier);

    DocNote quietAfter;
    DocNote loudAfter;
    DocNote laterAfter;
    QVERIFY(m_tab->document().findNote(m_quietStacked.noteId, &quietAfter));
    QVERIFY(m_tab->document().findNote(m_loudStacked.noteId, &loudAfter));
    QVERIFY(m_tab->document().findNote(m_later.noteId, &laterAfter));
    QCOMPARE(int(quietAfter.key), int(quietBefore.key) + 12);
    QCOMPARE(int(laterAfter.key), int(laterBefore.key) + 12);
    QCOMPARE(loudAfter.key, loudBefore.key);
    QCOMPARE(quietAfter.velocity, quietBefore.velocity);
    QCOMPARE(loudAfter.velocity, loudBefore.velocity);
    QCOMPARE(laterAfter.velocity, laterBefore.velocity);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}
