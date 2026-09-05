#include "checks/velocity/tst_velocityediting.h"

#include <cmath>
#include <optional>

#include <QtTest>

#include "ui/editordrawer/editordrawer.h"
#include "ui/keymap.h"
#include "ui/songview.h"

void VelocityEditingTest::lateUnlockKeepsGestureSnapped_data()
{
    QTest::addColumn<int>("program");
    QTest::addColumn<int>("startLevel");
    QTest::addColumn<int>("endLevel");
    QTest::addColumn<int>("expectedQuiet");
    QTest::addColumn<int>("expectedLater");

    QTest::newRow("square") << 1 << 4 << 5 << 44 << 92;
    QTest::newRow("wave") << 2 << 1 << 2 << 64 << 127;
    QTest::newRow("noise") << 3 << 4 << 5 << 44 << 92;
}

void VelocityEditingTest::lateUnlockKeepsGestureSnapped()
{
    QFETCH(int, program);
    QFETCH(int, startLevel);
    QFETCH(int, endLevel);
    QFETCH(int, expectedQuiet);
    QFETCH(int, expectedLater);
    constexpr uint8_t kQuietOrigin = 33;
    constexpr uint8_t kLaterOrigin = 87;

    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 0, program);
    QTRY_COMPARE(m_tab->view().currentProgram(0), program);
    QTRY_VERIFY(m_area->isPsgContext());
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);
    EditorDrawer *const drawer = m_tab->view().editorDrawer();
    QVERIFY(drawer);
    drawer->chrome().setDetentChecked(true);
    QTRY_VERIFY(drawer->chrome().detentEnabled() && drawer->chrome().detentChecked());
    QTRY_VERIFY(m_area->useDetents());

    m_tab->document().setNotesVelocity({m_quietStacked}, kQuietOrigin);
    m_tab->document().setNotesVelocity({m_later}, kLaterOrigin);
    QTRY_COMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietOrigin));
    QTRY_COMPARE(timelineVelocity(m_later.noteId), int(kLaterOrigin));
    selectDragPair();

    const QPointF pressLocal(nodePoint(kQuietOrigin, m_quietStacked.tick).x(),
                             m_area->axis().levelToY(startLevel));
    const QPointF moveLocal(nodePoint(kQuietOrigin, m_quietStacked.tick).x(),
                            m_area->axis().levelToY(endLevel));
    QVERIFY(m_velocityInput->bounds().contains(pressLocal));
    QVERIFY(m_velocityInput->bounds().contains(moveLocal));
    const Qt::KeyboardModifiers unlock =
        keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
    QVERIFY(unlock != Qt::NoModifier);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    mousePress(Qt::LeftButton, windowPoint(pressLocal));
    mouseMove(windowPoint(moveLocal), unlock);

    // Unlock is sampled at press. These literals prove the later modifier did
    // not turn this frozen intrinsic gesture into a continuous one.
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
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietOrigin));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLaterOrigin));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietOrigin));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kLaterOrigin));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    mouseRelease(Qt::LeftButton, windowPoint(moveLocal));

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
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

void VelocityEditingTest::unlockedRelativeKeepsOffsets_data()
{
    QTest::addColumn<int>("program");
    QTest::addColumn<int>("startLevel");
    QTest::addColumn<int>("expectedQuiet");
    QTest::addColumn<int>("expectedLater");

    QTest::newRow("square") << 1 << 4 << 40 << 94;
    QTest::newRow("wave") << 2 << 1 << 40 << 94;
    QTest::newRow("noise") << 3 << 4 << 40 << 94;
}

void VelocityEditingTest::unlockedRelativeKeepsOffsets()
{
    QFETCH(int, program);
    QFETCH(int, startLevel);
    QFETCH(int, expectedQuiet);
    QFETCH(int, expectedLater);
    constexpr uint8_t kQuietOrigin = 33;
    constexpr uint8_t kLaterOrigin = 87;
    constexpr int kRawDelta = 7;

    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 0, program);
    QTRY_COMPARE(m_tab->view().currentProgram(0), program);
    QTRY_VERIFY(m_area->isPsgContext());
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);
    EditorDrawer *const drawer = m_tab->view().editorDrawer();
    QVERIFY(drawer);
    drawer->chrome().setDetentChecked(true);
    QTRY_VERIFY(drawer->chrome().detentEnabled() && drawer->chrome().detentChecked());
    QTRY_VERIFY(m_area->useDetents());

    m_tab->document().setNotesVelocity({m_quietStacked}, kQuietOrigin);
    m_tab->document().setNotesVelocity({m_later}, kLaterOrigin);
    QTRY_COMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietOrigin));
    QTRY_COMPARE(timelineVelocity(m_later.noteId), int(kLaterOrigin));
    selectDragPair();

    const QPointF pressLocal(nodePoint(kQuietOrigin, m_quietStacked.tick).x(),
                             m_area->axis().levelToY(startLevel));
    const QPoint pressWindow = windowPoint(pressLocal);
    const QPointF deliveredPressLocal = m_velocityInput->mapFromScene(QPointF(pressWindow));
    const int moveAxisVelocity = m_area->axis().yToVelocity(deliveredPressLocal.y()) + kRawDelta;
    const QPointF moveLocal = nodePoint(uint8_t(moveAxisVelocity), m_quietStacked.tick);
    const QPoint moveWindow = windowPoint(moveLocal);
    const QPointF deliveredMoveLocal = m_velocityInput->mapFromScene(QPointF(moveWindow));
    QVERIFY(m_velocityInput->bounds().contains(deliveredPressLocal));
    QVERIFY(m_velocityInput->bounds().contains(deliveredMoveLocal));
    // QTest delivers integral window coordinates. Derive the continuous target
    // from that representable press rather than the floating-point level center:
    // the Wave center is on a half velocity step and can round to its lower
    // neighbor after the window-to-item mapping.
    QCOMPARE(m_area->axis().yToVelocity(deliveredMoveLocal.y()) -
                 m_area->axis().yToVelocity(deliveredPressLocal.y()),
             kRawDelta);
    const Qt::KeyboardModifiers unlock =
        keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
    QVERIFY(unlock != Qt::NoModifier);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    mousePress(Qt::LeftButton, pressWindow, unlock);
    mouseMove(moveWindow);

    // The continuous delta is chosen in input geometry only; 40 and 94 are
    // independent fixture-literal results for the raw origins 33 and 87.
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
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietOrigin));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLaterOrigin));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietOrigin));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kLaterOrigin));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    mouseRelease(Qt::LeftButton, moveWindow);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
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

void VelocityEditingTest::unlockedRampInterpolates_data()
{
    QTest::addColumn<int>("program");
    QTest::addColumn<int>("expectedQuiet");
    QTest::addColumn<int>("expectedMiddle");
    QTest::addColumn<int>("expectedLater");

    QTest::newRow("square") << 1 << 37 << 65 << 93;
    QTest::newRow("wave") << 2 << 37 << 65 << 93;
    QTest::newRow("noise") << 3 << 37 << 65 << 93;
}

void VelocityEditingTest::unlockedRampInterpolates()
{
    QFETCH(int, program);
    QFETCH(int, expectedQuiet);
    QFETCH(int, expectedMiddle);
    QFETCH(int, expectedLater);
    constexpr uint64_t kMiddleTick = 36;
    constexpr uint32_t kMiddleDuration = 12;
    constexpr uint8_t kMiddleOriginalVelocity = 56;

    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 0, program);
    QTRY_COMPARE(m_tab->view().currentProgram(0), program);
    QTRY_VERIFY(m_area->isPsgContext());
    QTRY_VERIFY(m_area->axis().mode() == VelocityAxis::Mode::Intrinsic);
    EditorDrawer *const drawer = m_tab->view().editorDrawer();
    QVERIFY(drawer);
    drawer->chrome().setDetentChecked(true);
    QTRY_VERIFY(drawer->chrome().detentEnabled() && drawer->chrome().detentChecked());
    QTRY_VERIFY(m_area->useDetents());

    m_tab->document().addNote(0, kMiddleTick, m_quietStacked.key, kMiddleDuration,
                              kMiddleOriginalVelocity);
    DocNote middle;
    QVERIFY(m_tab->document().findNote(0, kMiddleTick, m_quietStacked.key, &middle));
    QCOMPARE(int(middle.velocity), int(kMiddleOriginalVelocity));
    QTRY_COMPARE(timelineVelocity(middle.noteId), int(kMiddleOriginalVelocity));
    m_tab->view().selectionModel().setNoteSelection(
        {m_quietStacked.noteId, middle.noteId, m_later.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, middle.noteId, m_later.noteId}));

    const QPointF firstExact =
        m_velocityInput->mapToScene(nodePoint(uint8_t(expectedQuiet), m_quietStacked.tick));
    const QPointF middleExact =
        m_velocityInput->mapToScene(nodePoint(uint8_t(expectedMiddle), kMiddleTick));
    const QPointF lastExact =
        m_velocityInput->mapToScene(nodePoint(uint8_t(expectedLater), m_later.tick));
    QPoint rampStart = firstExact.toPoint();
    QPoint rampEnd = lastExact.toPoint();
    rampStart.setX(static_cast<int>(std::ceil(firstExact.x())));
    rampEnd.setX(static_cast<int>(std::floor(lastExact.x())));
    const qreal doubledMiddleExactX = 2.0 * middleExact.x();
    QCOMPARE(doubledMiddleExactX, std::round(doubledMiddleExactX));
    QCOMPARE(rampStart.x() + rampEnd.x(), static_cast<int>(doubledMiddleExactX));
    QVERIFY(rampStart != rampEnd);
    const Qt::KeyboardModifiers unlock =
        keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
    QVERIFY(unlock != Qt::NoModifier);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    mousePress(Qt::LeftButton, rampStart, unlock | Qt::ShiftModifier);
    mouseMove(rampEnd);

    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> middlePreview = m_tab->view().previewVelocity(middle.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(middlePreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), expectedQuiet);
    QCOMPARE(int(*middlePreview), expectedMiddle);
    QCOMPARE(int(*laterPreview), expectedLater);
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(documentVelocity(middle.noteId), int(kMiddleOriginalVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(m_quietStacked.velocity));
    QCOMPARE(timelineVelocity(middle.noteId), int(kMiddleOriginalVelocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(m_later.velocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, middle.noteId, m_later.noteId}));

    mouseRelease(Qt::LeftButton, rampEnd);

    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(middle.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), expectedQuiet);
    QCOMPARE(documentVelocity(middle.noteId), expectedMiddle);
    QCOMPARE(documentVelocity(m_later.noteId), expectedLater);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), expectedQuiet);
    QCOMPARE(timelineVelocity(middle.noteId), expectedMiddle);
    QCOMPARE(timelineVelocity(m_later.noteId), expectedLater);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, middle.noteId, m_later.noteId}));
}
