#include "checks/velocity/tst_velocityediting.h"

#include <cmath>
#include <optional>

#include <QtTest>

#include "ui/songview.h"

void VelocityEditingTest::paintCommitsOnce()
{
    constexpr uint8_t kQuietPaintVelocity = 37;
    constexpr uint8_t kLaterPaintVelocity = 91;

    QCOMPARE(m_area->axis().mode(), VelocityAxis::Mode::Continuous);
    selectDragPair();

    // Each endpoint uses a selected note's x coordinate but a distant velocity
    // y coordinate, so the initial press is blank—not either stacked circle or
    // its duration stem—and therefore begins the paint interaction.
    const QPoint paintStart = windowPoint(nodePoint(kQuietPaintVelocity, m_quietStacked.tick));
    const QPoint paintEnd = windowPoint(nodePoint(kLaterPaintVelocity, m_later.tick));
    QVERIFY(paintStart != paintEnd);

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    mousePress(Qt::LeftButton, paintStart);
    mouseMove(paintEnd);

    // Painting is deferred: both selected notes receive literal positive
    // previews while the document, projection, and command history stay at
    // their pre-gesture values.
    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), int(kQuietPaintVelocity));
    QCOMPARE(int(*laterPreview), int(kLaterPaintVelocity));
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

    // Release commits the two independent literal values as one history entry,
    // updates the actual timeline projection, and does not touch the unselected
    // stacked sibling.
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietPaintVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLaterPaintVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietPaintVelocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kLaterPaintVelocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

void VelocityEditingTest::rampCommitsOnce()
{
    constexpr uint64_t kMiddleTick = 36;
    constexpr uint32_t kMiddleDuration = 12;
    constexpr uint8_t kMiddleOriginalVelocity = 42;
    constexpr uint8_t kRampStartVelocity = 37;
    constexpr uint8_t kRampMiddleVelocity = 65;
    constexpr uint8_t kRampEndVelocity = 93;

    QCOMPARE(m_area->axis().mode(), VelocityAxis::Mode::Continuous);
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
        m_velocityInput->mapToScene(nodePoint(kRampStartVelocity, m_quietStacked.tick));
    const QPointF middleExact =
        m_velocityInput->mapToScene(nodePoint(kRampMiddleVelocity, kMiddleTick));
    const QPointF lastExact =
        m_velocityInput->mapToScene(nodePoint(kRampEndVelocity, m_later.tick));
    QPoint rampStart = firstExact.toPoint();
    QPoint rampEnd = lastExact.toPoint();

    // Native QTest window positions are integral. Keep both endpoint samples
    // on the inward side of their rendered note centers, and require those
    // representable coordinates to balance exactly around the middle node.
    // Rounding both half-pixel centers with QPointF::toPoint() instead shifts
    // the sampled middle away from one half even though the endpoint values
    // still clamp to their requested velocities.
    rampStart.setX(static_cast<int>(std::ceil(firstExact.x())));
    rampEnd.setX(static_cast<int>(std::floor(lastExact.x())));
    const qreal doubledMiddleExactX = 2.0 * middleExact.x();
    QCOMPARE(doubledMiddleExactX, std::round(doubledMiddleExactX));
    QCOMPARE(rampStart.x() + rampEnd.x(), static_cast<int>(doubledMiddleExactX));
    QVERIFY(rampStart != rampEnd);

    // The midpoint is exactly halfway in both input-coordinate and target
    // velocity space: 37 + (93 - 37) / 2 == 65. The asserted literal is
    // intentionally not inferred from a preview or the production quantizer.
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    focusVelocityBand();
    mousePress(Qt::LeftButton, rampStart, Qt::ShiftModifier);
    mouseMove(rampEnd, Qt::ShiftModifier);

    // Shift paints the frozen selection as a linear ramp while remaining a
    // preview-only transaction. In particular, the added midpoint is 65,
    // independently derived from the two literal endpoints above.
    const std::optional<uint8_t> quietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> middlePreview = m_tab->view().previewVelocity(middle.noteId);
    const std::optional<uint8_t> laterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(quietPreview.has_value());
    QVERIFY(middlePreview.has_value());
    QVERIFY(laterPreview.has_value());
    QCOMPARE(int(*quietPreview), int(kRampStartVelocity));
    QCOMPARE(int(*middlePreview), int(kRampMiddleVelocity));
    QCOMPARE(int(*laterPreview), int(kRampEndVelocity));
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

    mouseRelease(Qt::LeftButton, rampEnd, Qt::ShiftModifier);

    // The ramp becomes one document command on release, clears every preview,
    // and leaves the non-selected stacked note unchanged in document and view.
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(middle.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kRampStartVelocity));
    QCOMPARE(documentVelocity(middle.noteId), int(kRampMiddleVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kRampEndVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(kRampStartVelocity));
    QCOMPARE(timelineVelocity(middle.noteId), int(kRampMiddleVelocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kRampEndVelocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(m_loudStacked.velocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, middle.noteId, m_later.noteId}));
}
