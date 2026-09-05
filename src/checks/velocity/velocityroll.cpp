#include "checks/velocity/tst_velocityediting.h"

#include <algorithm>
#include <cstdint>
#include <optional>

#include <QApplication>
#include <QQuickItem>
#include <QRect>

#include <QtTest>

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

void VelocityEditingTest::rollDragCommitsOnce()
{
    selectDragPair();
    QVERIFY(m_later.noteId != m_quietStacked.noteId);
    QVERIFY(m_later.noteId != m_loudStacked.noteId);

    const Qt::KeyboardModifiers velocityDragModifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    QVERIFY(velocityDragModifiers != Qt::NoModifier);

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

    const int expectedQuiet = std::clamp(int(m_quietStacked.velocity) + dragDelta, 1, 127);
    const int expectedLater = std::clamp(int(m_later.velocity) + dragDelta, 1, 127);
    QCOMPARE(expectedQuiet, int(m_quietStacked.velocity) + dragDelta);
    QCOMPARE(expectedLater, int(m_later.velocity) + dragDelta);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    QVERIFY(
        m_tab->view().quickView()->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Roll);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(), static_cast<QQuickItem *>(m_rollInput.data()));

    const QPoint rollPressWindow = m_rollInput->mapToScene(rollPressLocal).toPoint();
    const QPoint rollDragWindow = m_rollInput->mapToScene(rollDragLocal).toPoint();
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(rollPressWindow));
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(rollDragWindow));

    mousePress(Qt::LeftButton, rollPressWindow, velocityDragModifiers);
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(m_rollInput.data()));
    mouseMove(rollDragWindow, velocityDragModifiers);

    // The public roll drag applies an integral upward pixel delta to every
    // selected note while holding the document, history, and current timeline
    // projection frozen. The unselected stacked sibling never receives a preview.
    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), expectedQuiet);
    QCOMPARE(int(*laterPreview), expectedLater);
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    mouseRelease(Qt::LeftButton, rollDragWindow, velocityDragModifiers);

    // One release produces one document command and republished timeline values.
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), expectedQuiet);
    QCOMPARE(documentVelocity(m_later.noteId), expectedLater);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), expectedQuiet);
    QCOMPARE(timelineVelocity(m_later.noteId), expectedLater);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::controllerCancellationStopsRollDrag()
{
    selectDragPair();
    QVERIFY(m_later.noteId != m_quietStacked.noteId);
    QVERIFY(m_later.noteId != m_loudStacked.noteId);

    const Qt::KeyboardModifiers velocityDragModifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    QVERIFY(velocityDragModifiers != Qt::NoModifier);

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

    const int expectedQuiet = std::clamp(int(m_quietStacked.velocity) + dragDelta, 1, 127);
    const int expectedLater = std::clamp(int(m_later.velocity) + dragDelta, 1, 127);
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    QVERIFY(
        m_tab->view().quickView()->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Roll);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(), static_cast<QQuickItem *>(m_rollInput.data()));

    const QPoint rollPressWindow = m_rollInput->mapToScene(rollPressLocal).toPoint();
    const QPoint rollDragWindow = m_rollInput->mapToScene(rollDragLocal).toPoint();
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(rollPressWindow));
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(rollDragWindow));
    mousePress(Qt::LeftButton, rollPressWindow, velocityDragModifiers);
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(m_rollInput.data()));

    mouseMove(rollDragWindow, velocityDragModifiers);

    // Cancellation is meaningful only after the real roll gesture has staged
    // changed previews for both selected notes.
    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), expectedQuiet);
    QCOMPARE(int(*laterPreview), expectedLater);
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    m_tab->view().cancelActiveInteractions();
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());

    // A still-held synthetic pointer can no longer revive or commit the
    // cancelled gesture.
    mouseMove(rollPressWindow, velocityDragModifiers);
    mouseRelease(Qt::LeftButton, rollPressWindow, velocityDragModifiers);
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::escapeStopsRollDrag()
{
    selectDragPair();
    QVERIFY(m_later.noteId != m_quietStacked.noteId);
    QVERIFY(m_later.noteId != m_loudStacked.noteId);

    const Qt::KeyboardModifiers velocityDragModifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    QVERIFY(velocityDragModifiers != Qt::NoModifier);

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

    const int expectedQuiet = std::clamp(int(m_quietStacked.velocity) + dragDelta, 1, 127);
    const int expectedLater = std::clamp(int(m_later.velocity) + dragDelta, 1, 127);
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    QVERIFY(
        m_tab->view().quickView()->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Roll);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(), static_cast<QQuickItem *>(m_rollInput.data()));

    const QPoint rollPressWindow = m_rollInput->mapToScene(rollPressLocal).toPoint();
    const QPoint rollDragWindow = m_rollInput->mapToScene(rollDragLocal).toPoint();
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(rollPressWindow));
    QVERIFY(QRect(QPoint(), m_quickWindow->size()).contains(rollDragWindow));
    mousePress(Qt::LeftButton, rollPressWindow, velocityDragModifiers);

    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(m_rollInput.data()));
    mouseMove(rollDragWindow, velocityDragModifiers);

    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), expectedQuiet);
    QCOMPARE(int(*laterPreview), expectedLater);
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    // Escape is delivered to the live Roll focus item rather than bypassing
    // keyboard routing through a controller call.
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Roll);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(), static_cast<QQuickItem *>(m_rollInput.data()));
    QTest::keyClick(m_quickWindow, Qt::Key_Escape);
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());

    mouseMove(rollPressWindow, velocityDragModifiers);
    mouseRelease(Qt::LeftButton, rollPressWindow, velocityDragModifiers);
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    // Roll Escape is also the editor's selection-dismiss command; unlike
    // controller cancellation, its documented terminal state is no selection.
    QVERIFY(m_tab->view().selectionModel().noteSelection().empty());
}

void VelocityEditingTest::velocityFocusIgnoresPitchShortcut()
{
    selectDragPair();

    DocNote quietBefore;
    DocNote laterBefore;
    QVERIFY(m_tab->document().findNote(m_quietStacked.noteId, &quietBefore));
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
    DocNote laterAfter;
    QVERIFY(m_tab->document().findNote(m_quietStacked.noteId, &quietAfter));
    QVERIFY(m_tab->document().findNote(m_later.noteId, &laterAfter));
    QCOMPARE(quietAfter.key, quietBefore.key);
    QCOMPARE(laterAfter.key, laterBefore.key);
    QCOMPARE(quietAfter.velocity, quietBefore.velocity);
    QCOMPARE(laterAfter.velocity, laterBefore.velocity);
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}
