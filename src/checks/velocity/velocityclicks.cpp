#include "checks/velocity/tst_velocityediting.h"

#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QString>
#include <QtTest>
#include <cstddef>
#include <cstdint>
#include <optional>

#include "core/songdocument.h"
#include "ui/editordrawer/velocityaxis.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kBlankVelocity = 40;
constexpr uint8_t kGraduationVelocity = 127;
constexpr uint8_t kQuietVelocityAfterSetup = 1;
constexpr uint8_t kLoudVelocity = 70;
constexpr uint8_t kClickVelocity = 40;

} // namespace

void VelocityEditingTest::blankClickDeselectsOnRelease()
{
    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId, m_later.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    const QRectF plotBounds = m_velocityInput->bounds();
    const QPointF blankLocal{plotBounds.right() - layout::singlePixel(),
                             m_area->axis().velocityToY(kBlankVelocity)};
    QVERIFY(plotBounds.contains(blankLocal));
    QVERIFY(blankLocal.x() > nodePoint(kLoudVelocity, m_later.tick + m_later.duration).x());

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPoint(blankLocal));
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
    mouseRelease(Qt::LeftButton, windowPoint(blankLocal));

    QVERIFY(m_tab->view().selectionModel().noteSelection().empty());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), 20);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kLoudVelocity));
}

void VelocityEditingTest::graduationClickEditsSelectedNotes()
{
    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId, m_loudStacked.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_loudStacked.noteId}));

    songview::TimelineQuickView *const quickView =
        m_tab->view().findChild<songview::TimelineQuickView *>(
            QStringLiteral("timelineQuickCanvas"));
    QVERIFY(quickView);
    QObject *const quickRoot = quickView->rootObject();
    QVERIFY(quickRoot);
    songview::TimelineInputItem *const gutterInput =
        quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityGutterInput"));
    QVERIFY(gutterInput);
    QCOMPARE(gutterInput->window(), m_quickWindow.data());

    const VelocityAxisLabel *maximumLabel = nullptr;
    for (std::size_t index = 0; index < m_area->axis().labelCount(); ++index) {
        const VelocityAxisLabel &label = m_area->axis().labels()[index];
        if (label.velocity == kGraduationVelocity) {
            maximumLabel = &label;
            break;
        }
    }
    QVERIFY(maximumLabel);

    const QPointF gutterLocal{gutterInput->bounds().center().x(), maximumLabel->y};
    QVERIFY(gutterInput->bounds().contains(gutterLocal));
    const QPoint gutterWindow = gutterInput->mapToScene(gutterLocal).toPoint();

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, gutterWindow);
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(), static_cast<QQuickItem *>(gutterInput));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_loudStacked.noteId}));
    QTRY_COMPARE(documentVelocity(m_quietStacked.noteId), int(kGraduationVelocity));
    QTRY_COMPARE(documentVelocity(m_loudStacked.noteId), int(kGraduationVelocity));
    mouseRelease(Qt::LeftButton, gutterWindow);

    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kGraduationVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kGraduationVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QTRY_COMPARE(timelineVelocity(m_quietStacked.noteId), int(kGraduationVelocity));
    QTRY_COMPARE(timelineVelocity(m_loudStacked.noteId), int(kGraduationVelocity));
    QTRY_COMPARE(timelineVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_loudStacked.noteId}));
}

void VelocityEditingTest::clickBelowSelectedNodeChangesOnlySelection()
{
    m_tab->view().selectionModel().setNoteSelection({m_loudStacked.noteId});
    QVERIFY(noteSelectionIs({m_loudStacked.noteId}));

    m_tab->document().setNotesVelocity({m_quietStacked}, kQuietVelocityAfterSetup);
    QTRY_COMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocityAfterSetup));
    QTRY_COMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietVelocityAfterSetup));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({m_loudStacked.noteId}));

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    const QPoint windowPos = windowPoint(nodePoint(kClickVelocity, m_loudStacked.tick));

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPos);
    QTRY_COMPARE(m_quickWindow->mouseGrabberItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));
    const std::optional<uint8_t> loudPreview = m_tab->view().previewVelocity(m_loudStacked.noteId);
    QVERIFY(loudPreview.has_value());
    QCOMPARE(int(*loudPreview), int(kClickVelocity));
    QVERIFY(noteSelectionIs({m_loudStacked.noteId}));
    mouseRelease(Qt::LeftButton, windowPos);

    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocityAfterSetup));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kClickVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QTRY_COMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietVelocityAfterSetup));
    QTRY_COMPARE(timelineVelocity(m_loudStacked.noteId), int(kClickVelocity));
    QTRY_COMPARE(timelineVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({m_loudStacked.noteId}));
}
