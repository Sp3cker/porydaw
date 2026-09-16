#include "checks/velocity/tst_velocityediting.h"

#include <algorithm>
#include <cmath>

#include <QApplication>
#include <QQuickItem>
#include <QtTest>

#include "ui/songview.h"

void VelocityEditingTest::primaryTrackSwitchCancelsDrag_data()
{
    QTest::addColumn<bool>("directSelectionTransition");
    QTest::newRow("production-route") << false;
}

void VelocityEditingTest::primaryTrackSwitchCancelsDrag()
{
    SongView &view = m_tab->view();
    QCOMPARE(m_tab->document().addTrack(2), 1);
    QTRY_COMPARE(view.currentProgram(1), 2);
    selectDragPair();

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    const QPoint press = windowPoint(nodePoint(20, m_quietStacked.tick));
    const QPoint moved = windowPoint(nodePoint(48, m_quietStacked.tick));
    mousePress(Qt::LeftButton, press);
    mouseMove(moved);
    QVERIFY(view.previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(view.previewVelocity(m_later.noteId).has_value());
    QVERIFY(m_area->gestureActive());

    // Direct applyPrimaryTrackTransition mid-gesture trips the selection model's
    // reentrancy assert (editorselectionmodel.cpp:72), so the arm-contract path
    // is untestable by design. The arm track check remains unverified
    // defense-in-depth behind pre-cancelling selectTrack/trackHeaderClicked routes.
    view.selectTrack(1);
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QTRY_VERIFY(!m_area->gestureActive());
    QVERIFY(!view.previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!view.previewVelocity(m_later.noteId).has_value());
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);
    QCOMPARE(m_area->axis().graduationCount(), 5);

    mouseRelease(Qt::LeftButton, moved);
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), 70);
    QCOMPARE(documentVelocity(m_later.noteId), 70);
    QVERIFY(!view.previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!view.previewVelocity(m_later.noteId).has_value());
}

void VelocityEditingTest::pointerUngrabCancelsProvisionalSelection()
{
    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    const QPointF loudNode = nodePoint(70, 12);

    mousePress(Qt::LeftButton, windowPoint(loudNode));
    QTRY_VERIFY(noteSelectionIs({m_loudStacked.noteId}));
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));

    QQuickItem *const grabber = m_quickWindow->mouseGrabberItem();
    QVERIFY(grabber);
    grabber->ungrabMouse();
    QTRY_VERIFY(!m_quickWindow->mouseGrabberItem());

    QTRY_VERIFY(noteSelectionIs({m_quietStacked.noteId}));
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), 70);
    QCOMPARE(documentVelocity(m_later.noteId), 70);

    // A release synthesized after the public grab cancellation must not
    // revive the discarded provisional gesture or create an edit.
    mouseRelease(Qt::LeftButton, windowPoint(loudNode));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), 70);
    QCOMPARE(documentVelocity(m_later.noteId), 70);
}

void VelocityEditingTest::bandSelectionExpandsAndContracts()
{
    m_tab->view().selectionModel().setNoteSelection({m_later.noteId});
    QVERIFY(noteSelectionIs({m_later.noteId}));

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    const QPointF quietNode = nodePoint(20, 12);
    const QPointF loudNode = nodePoint(70, 12);
    const QPointF laterNode = nodePoint(70, 60);
    const qreal horizontalMargin = std::abs(laterNode.x() - quietNode.x()) / 4.0;
    const qreal verticalMargin = std::abs(loudNode.y() - quietNode.y()) / 4.0;
    QVERIFY(horizontalMargin > 0.0);
    QVERIFY(verticalMargin > 0.0);

    const QPointF bandStart{quietNode.x() - horizontalMargin,
                            std::min(quietNode.y(), loudNode.y()) - verticalMargin};
    const QPointF expandedEnd{laterNode.x() + horizontalMargin,
                              std::max(quietNode.y(), loudNode.y()) + verticalMargin};
    const QPointF contractedEnd{(quietNode.x() + laterNode.x()) / 2.0, expandedEnd.y()};
    QVERIFY(m_velocityInput->bounds().contains(bandStart));
    QVERIFY(m_velocityInput->bounds().contains(expandedEnd));
    QVERIFY(m_velocityInput->bounds().contains(contractedEnd));
    QVERIFY(std::abs(expandedEnd.x() - bandStart.x()) + std::abs(expandedEnd.y() - bandStart.y()) >=
            QApplication::startDragDistance());

    mousePress(Qt::RightButton, windowPoint(bandStart));
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));
    mouseMove(windowPoint(expandedEnd));
    mouseMove(windowPoint(contractedEnd));
    mouseRelease(Qt::RightButton, windowPoint(contractedEnd));

    // The final rectangle retains the stacked pair and excludes the later
    // note that was covered only by the abandoned extent.
    QTRY_VERIFY(noteSelectionIs({m_quietStacked.noteId, m_loudStacked.noteId}));
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), 70);
    QCOMPARE(documentVelocity(m_later.noteId), 70);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), 70);
    QCOMPARE(timelineVelocity(m_later.noteId), 70);
}

void VelocityEditingTest::bandUngrabRestoresSelection()
{
    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    const QPointF quietNode = nodePoint(20, 12);
    const QPointF loudNode = nodePoint(70, 12);
    const QPointF laterNode = nodePoint(70, 60);
    const qreal horizontalMargin = std::abs(laterNode.x() - quietNode.x()) / 4.0;
    const qreal verticalMargin = std::abs(loudNode.y() - quietNode.y()) / 4.0;
    QVERIFY(horizontalMargin > 0.0);
    QVERIFY(verticalMargin > 0.0);

    const QPointF bandStart{quietNode.x() - horizontalMargin,
                            std::min(quietNode.y(), loudNode.y()) - verticalMargin};
    const QPointF expandedEnd{laterNode.x() + horizontalMargin,
                              std::max(quietNode.y(), loudNode.y()) + verticalMargin};
    QVERIFY(m_velocityInput->bounds().contains(bandStart));
    QVERIFY(m_velocityInput->bounds().contains(expandedEnd));
    QVERIFY(std::abs(expandedEnd.x() - bandStart.x()) + std::abs(expandedEnd.y() - bandStart.y()) >=
            QApplication::startDragDistance());

    mousePress(Qt::RightButton, windowPoint(bandStart));
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));
    mouseMove(windowPoint(expandedEnd));

    QQuickItem *const grabber = m_quickWindow->mouseGrabberItem();
    QVERIFY(grabber);
    grabber->ungrabMouse();
    QTRY_VERIFY(!m_quickWindow->mouseGrabberItem());
    QTRY_VERIFY(noteSelectionIs({m_quietStacked.noteId}));

    // A cancelled band must restore its pre-press selection, and subsequent
    // window-level input cannot replace it or commit a velocity change.
    mouseMove(windowPoint(expandedEnd));
    mouseRelease(Qt::RightButton, windowPoint(expandedEnd));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), 70);
    QCOMPARE(documentVelocity(m_later.noteId), 70);
}
