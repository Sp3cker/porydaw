#include "checks/velocity/tst_velocityediting.h"

#include <optional>

#include <QtTest>

#include "ui/editordrawer/editordrawer.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

void VelocityEditingTest::rulerUnlockKeepsRawVelocity_data()
{
    QTest::addColumn<int>("program");
    QTest::addColumn<bool>("unlockOnPress");
    QTest::addColumn<int>("expectedVelocity");

    QTest::newRow("square-modifier-unlock") << 1 << true << 73;
    QTest::newRow("square-detents-disabled") << 1 << false << 73;
    QTest::newRow("wave-modifier-unlock") << 2 << true << 73;
    QTest::newRow("wave-detents-disabled") << 2 << false << 73;
    QTest::newRow("noise-modifier-unlock") << 3 << true << 73;
    QTest::newRow("noise-detents-disabled") << 3 << false << 73;
}

void VelocityEditingTest::rulerUnlockKeepsRawVelocity()
{
    QFETCH(int, program);
    QFETCH(bool, unlockOnPress);
    QFETCH(int, expectedVelocity);

    constexpr int kRawVelocity = 73;

    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 0, program);
    selectDragPair();
    QTRY_COMPARE(m_tab->view().currentProgram(0), program);
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);

    DrawerChrome &chrome = m_tab->view().editorDrawer()->chrome();
    QVERIFY(chrome.detentVisible());
    QVERIFY(chrome.detentEnabled());
    chrome.setDetentChecked(unlockOnPress);
    QTRY_COMPARE(chrome.detentChecked(), unlockOnPress);
    QCOMPARE(m_area->useDetents(), unlockOnPress);

    const Qt::KeyboardModifiers unlock =
        keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
    QVERIFY(unlock != Qt::NoModifier);
    const Qt::KeyboardModifiers pressModifiers = unlockOnPress ? unlock : Qt::NoModifier;

    songview::TimelineQuickView *const quickView = m_tab->view().quickView();
    QVERIFY(quickView);
    QObject *const quickRoot = quickView->rootObject();
    QVERIFY(quickRoot);
    songview::TimelineInputItem *const gutterInput =
        quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityGutterInput"));
    QVERIFY(gutterInput);
    QCOMPARE(gutterInput->window(), m_quickWindow.data());

    const QPointF gutterLocal{gutterInput->bounds().center().x(),
                              m_area->axis().velocityToY(kRawVelocity)};
    QVERIFY(gutterInput->bounds().contains(gutterLocal));
    const QPoint gutterWindow = gutterInput->mapToScene(gutterLocal).toPoint();

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    mousePress(Qt::LeftButton, gutterWindow, pressModifiers);
    QTRY_COMPARE(documentChanged.count(), 1);
    QTRY_COMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), expectedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), expectedVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), expectedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), expectedVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    // The press captures the unlock choice; releasing without its modifier is
    // intentionally harmless and cannot create a second immediate ruler edit.
    mouseRelease(Qt::LeftButton, gutterWindow);
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), expectedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), expectedVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), expectedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), expectedVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::lockedPaintUsesDetents_data()
{
    QTest::addColumn<int>("program");
    QTest::addColumn<int>("expectedVelocity");

    QTest::newRow("square") << 1 << 76;
    QTest::newRow("wave") << 2 << 64;
    QTest::newRow("noise") << 3 << 76;
}

void VelocityEditingTest::lockedPaintUsesDetents()
{
    QFETCH(int, program);
    QFETCH(int, expectedVelocity);

    constexpr uint8_t kRawVelocity = 73;

    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 0, program);
    selectDragPair();
    QTRY_COMPARE(m_tab->view().currentProgram(0), program);
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);

    DrawerChrome &chrome = m_tab->view().editorDrawer()->chrome();
    QVERIFY(chrome.detentVisible());
    QVERIFY(chrome.detentEnabled());
    chrome.setDetentChecked(true);
    QTRY_VERIFY(chrome.detentChecked() && m_area->useDetents());

    // Tick 0 contains no fixture note. Beginning there makes this a paint
    // gesture rather than a relative drag from the unselected 70-velocity cap.
    QVERIFY(m_quietStacked.tick > 0 && m_loudStacked.tick > 0 && m_later.tick > 0);
    const QPoint paintStart = windowPoint(nodePoint(kRawVelocity, 0));
    const QPoint quietPaint = windowPoint(nodePoint(kRawVelocity, m_quietStacked.tick));
    const QPoint paintEnd = windowPoint(nodePoint(kRawVelocity, m_later.tick));
    QVERIFY(m_velocityInput->bounds().contains(nodePoint(kRawVelocity, 0)));
    QVERIFY(paintStart != quietPaint);
    QVERIFY(quietPaint != paintEnd);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    mousePress(Qt::LeftButton, paintStart);
    mouseMove(quietPaint);
    mouseMove(paintEnd);

    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), expectedVelocity);
    QCOMPARE(int(*laterPreview), expectedVelocity);
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

    mouseRelease(Qt::LeftButton, paintEnd);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), expectedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), expectedVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), expectedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), expectedVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::unlockedPaintKeepsRawVelocities_data()
{
    QTest::addColumn<int>("program");
    QTest::addColumn<int>("firstExpectedVelocity");
    QTest::addColumn<int>("lastExpectedVelocity");

    QTest::newRow("square") << 1 << 37 << 91;
    QTest::newRow("wave") << 2 << 37 << 91;
    QTest::newRow("noise") << 3 << 37 << 91;
}

void VelocityEditingTest::unlockedPaintKeepsRawVelocities()
{
    QFETCH(int, program);
    QFETCH(int, firstExpectedVelocity);
    QFETCH(int, lastExpectedVelocity);

    constexpr uint8_t kFirstRawVelocity = 37;
    constexpr uint8_t kLastRawVelocity = 91;

    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 0, program);
    selectDragPair();
    QTRY_COMPARE(m_tab->view().currentProgram(0), program);
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);

    DrawerChrome &chrome = m_tab->view().editorDrawer()->chrome();
    QVERIFY(chrome.detentVisible());
    QVERIFY(chrome.detentEnabled());
    chrome.setDetentChecked(true);
    QTRY_VERIFY(chrome.detentChecked() && m_area->useDetents());

    const Qt::KeyboardModifiers unlock =
        keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
    QVERIFY(unlock != Qt::NoModifier);
    QVERIFY(m_quietStacked.tick > 0 && m_loudStacked.tick > 0 && m_later.tick > 0);
    const QPoint paintStart = windowPoint(nodePoint(kFirstRawVelocity, 0));
    const QPoint quietPaint = windowPoint(nodePoint(kFirstRawVelocity, m_quietStacked.tick));
    const QPoint paintEnd = windowPoint(nodePoint(kLastRawVelocity, m_later.tick));
    QVERIFY(m_velocityInput->bounds().contains(nodePoint(kFirstRawVelocity, 0)));
    QVERIFY(paintStart != quietPaint);
    QVERIFY(quietPaint != paintEnd);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    mousePress(Qt::LeftButton, paintStart, unlock);
    mouseMove(quietPaint);
    mouseMove(paintEnd);

    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), firstExpectedVelocity);
    QCOMPARE(int(*laterPreview), lastExpectedVelocity);
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

    // Detent unlock is fixed on press. Subsequent motion and release omit it.
    mouseRelease(Qt::LeftButton, paintEnd);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), firstExpectedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), lastExpectedVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), firstExpectedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), lastExpectedVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}
