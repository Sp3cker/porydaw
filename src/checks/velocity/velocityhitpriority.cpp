#include "checks/velocity/tst_velocityediting.h"

#include <QtTest>

#include <cstdint>
#include <optional>

#include "core/songdocument.h"
#include "ui/songview.h"

namespace {

constexpr uint64_t kOverlapTick = 20;
constexpr uint64_t kStemOnlyTick = 16;
constexpr uint8_t kOverlapKey = 60;
constexpr uint32_t kOverlapDuration = 24;
constexpr uint8_t kQuietVelocity = 20;
constexpr uint8_t kLoudVelocity = 70;

} // namespace

void VelocityEditingTest::selectedCircleWinsOverStem()
{
    m_tab->document().addNote(0, kOverlapTick, kOverlapKey, kOverlapDuration, kQuietVelocity);

    DocNote overlap;
    QVERIFY(m_tab->document().findNote(0, kOverlapTick, kOverlapKey, &overlap));
    QTRY_COMPARE(timelineVelocity(overlap.noteId), int(kQuietVelocity));

    m_tab->view().selectionModel().setNoteSelection({overlap.noteId});
    QVERIFY(noteSelectionIs({overlap.noteId}));
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPoint(nodePoint(kQuietVelocity, kOverlapTick)));
    QTRY_VERIFY(m_quickWindow->mouseGrabberItem());
    QVERIFY(noteSelectionIs({overlap.noteId}));
    mouseRelease(Qt::LeftButton, windowPoint(nodePoint(kQuietVelocity, kOverlapTick)));

    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(overlap.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({overlap.noteId}));
}

void VelocityEditingTest::unselectedCircleWinsOverSelectedStem()
{
    m_tab->document().addNote(0, kOverlapTick, kOverlapKey, kOverlapDuration, kQuietVelocity);

    DocNote overlap;
    QVERIFY(m_tab->document().findNote(0, kOverlapTick, kOverlapKey, &overlap));
    QTRY_COMPARE(timelineVelocity(overlap.noteId), int(kQuietVelocity));

    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPoint(nodePoint(kQuietVelocity, kOverlapTick)));
    QTRY_VERIFY(m_quickWindow->mouseGrabberItem());
    QVERIFY(noteSelectionIs({overlap.noteId}));
    mouseRelease(Qt::LeftButton, windowPoint(nodePoint(kQuietVelocity, kOverlapTick)));

    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(overlap.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({overlap.noteId}));
}

void VelocityEditingTest::selectedStemWinsAtStackedStem()
{
    m_tab->document().setNotesVelocity({m_loudStacked}, kQuietVelocity);
    m_tab->document().addNote(0, kOverlapTick, kOverlapKey, kOverlapDuration, kQuietVelocity);

    DocNote overlap;
    QVERIFY(m_tab->document().findNote(0, kOverlapTick, kOverlapKey, &overlap));
    QTRY_COMPARE(timelineVelocity(m_loudStacked.noteId), int(kQuietVelocity));
    QTRY_COMPARE(timelineVelocity(overlap.noteId), int(kQuietVelocity));

    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPoint(nodePoint(kQuietVelocity, kStemOnlyTick)));
    QTRY_VERIFY(m_quickWindow->mouseGrabberItem());
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
    mouseRelease(Qt::LeftButton, windowPoint(nodePoint(kQuietVelocity, kStemOnlyTick)));

    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(overlap.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
}

void VelocityEditingTest::movedNodeDoesNotClickThrough()
{
    QVERIFY(m_tab->view().selectionModel().noteSelection().empty());
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPoint(nodePoint(kLoudVelocity, 60)));
    QTRY_VERIFY(m_quickWindow->mouseGrabberItem());
    QVERIFY(noteSelectionIs({m_later.noteId}));
    mouseMove(windowPoint(nodePoint(kLoudVelocity, 12)));
    QTRY_VERIFY(m_tab->view().previewVelocity(m_later.noteId).has_value());
    const std::optional<uint8_t> preview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(preview.has_value());
    QCOMPARE(int(*preview), int(kLoudVelocity));
    mouseRelease(Qt::LeftButton, windowPoint(nodePoint(kLoudVelocity, 12)));

    QTRY_VERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({m_later.noteId}));
}

void VelocityEditingTest::rightPressPreservesSelectedGroup()
{
    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId, m_later.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::RightButton, windowPoint(nodePoint(kQuietVelocity, 12)));
    QTRY_VERIFY(m_quickWindow->mouseGrabberItem());
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
    mouseRelease(Qt::RightButton, windowPoint(nodePoint(kQuietVelocity, 12)));

    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(documentVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(documentVelocity(m_later.noteId), int(kLoudVelocity));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), int(kQuietVelocity));
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), int(kLoudVelocity));
    QCOMPARE(timelineVelocity(m_later.noteId), int(kLoudVelocity));
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}
