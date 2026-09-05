// Qt Test pilot suite for velocity editing transactions, driven through a
// real SongTab. Migrates the interaction contract of
// checkRelativeDragDefersCommit (src/checks/rollcheckpsgvelocity.cpp) onto
// idiomatic QTest input at the timeline Quick window; see
// docs/velocity-qt-test-migration-plan.md sections 6-7 for the locked
// fixture, gating, and cleanup policy.

#include "checks/velocity/tst_velocityediting.h"
#include "checks/fwd.hpp"

#include <QApplication>
#include <QtTest>

#include <optional>
#include <utility>

#include "core/songdocument.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityaxis.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

// In-memory fixture: format 1, division 24, one track, endTick 84. A
// duplicate-note pair sits at (tick 12, key 60) with velocities 20 and 70;
// the quiet duplicate and the separate (tick 60, key 64) note form the drag
// pair, while the loud duplicate is the other stacked fixture note.
constexpr uint64_t kDuplicateTick = 12;
constexpr uint64_t kLaterTick = 60;
constexpr uint8_t kDuplicateKey = 60;
constexpr uint8_t kLaterKey = 64;
constexpr uint8_t kQuietStackedVelocity = 20;
constexpr uint8_t kLoudStackedVelocity = 70;
constexpr uint8_t kLaterVelocity = 70;
constexpr uint64_t kEndTick = 84;
// Relative-drag deltas in whole velocity steps; every expected velocity below
// is the fixture literal plus or minus these (no clamping branch needed).
constexpr int kDragUpSteps = 28;
constexpr int kDragDownSteps = 4;

SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

SmfFile velocityEditingSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {
        noteEvent(0xC0, 0, 0, 0),
        noteEvent(0x90, kDuplicateTick, kDuplicateKey, kQuietStackedVelocity),
        noteEvent(0x90, kDuplicateTick, kDuplicateKey, kLoudStackedVelocity),
        noteEvent(0x80, 36, kDuplicateKey, 0),
        noteEvent(0x80, 36, kDuplicateKey, 0),
        noteEvent(0x90, kLaterTick, kLaterKey, kLaterVelocity),
        noteEvent(0x80, kEndTick, kLaterKey, 0),
    };
    track.endTick = kEndTick;
    smf.tracks.push_back(track);
    return smf;
}

} // namespace

void VelocityEditingTest::init()
{
    m_heldButton = Qt::NoButton;
    m_lastWindowPos = QPoint();

    m_bank = LoadedVoiceGroup{};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    const std::optional<SongName> name = SongName::create(QStringLiteral("velocity-editing"));
    QVERIFY(name.has_value());
    m_tab = std::make_unique<SongTab>(std::move(*name));
    m_tab->resize(960, 480);
    // The sample rate must land before MidiStage: the stage builds the
    // timeline projection from it.
    m_tab->setSampleRate(48000.0);

    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("velocity-editing-check"), QString());
    QVERIFY(identity.has_value());

    SongInfo song;
    song.label = QStringLiteral("velocity-editing");
    song.hasMid = true;
    m_tab->applyMidiStage(std::move(song), velocityEditingSmf(), track_limits::kHardwareCapacity);
    QVERIFY(m_tab->presentationError().isEmpty());
    m_tab->applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&m_bank), QString()});
    m_tab->applyVoicegroupBound(*identity);

    QTRY_VERIFY(m_tab->isReady());
    QVERIFY(m_tab->voicegroupLease().get() == &m_bank);

    const std::vector<DocNote> notes = m_tab->document().notesForTrack(0);
    QVERIFY2(notes.size() == 3, "the fixture track must carry exactly three notes");
    if (notes.size() == 3) {
        m_quietStacked = notes[0];
        m_loudStacked = notes[1];
        m_later = notes[2];
    }
    QVERIFY2(m_quietStacked.noteId != m_loudStacked.noteId &&
                 m_quietStacked.velocity == kQuietStackedVelocity &&
                 m_loudStacked.velocity == kLoudStackedVelocity && m_later.tick == kLaterTick &&
                 m_later.velocity == kLaterVelocity,
             "fixture notes must resolve in SMF event order with their literal velocities");

    SongView &view = m_tab->view();
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 320);

    m_area = view.editorDrawer() ? view.editorDrawer()->velocityArea() : nullptr;
    QVERIFY(m_area);
    songview::TimelineQuickView *quick = view.quickView();
    QVERIFY(quick);
    m_quickWindow = quick->quickWindow();
    QVERIFY(m_quickWindow);
    QObject *const quickRoot = quick->rootObject();
    QVERIFY(quickRoot);
    m_velocityInput = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineVelocityInput"));
    QVERIFY(m_velocityInput);
    m_rollInput =
        quickRoot->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    QVERIFY(m_rollInput);

    m_tab->show();
    QTRY_VERIFY(m_quickWindow->isVisible() && m_quickWindow->isExposed());
    QTRY_VERIFY(!m_velocityInput->bounds().isEmpty());
    QTRY_COMPARE(m_velocityInput->window(), m_quickWindow.data());
    QTRY_VERIFY(m_area->axis().drawableSpan() > 0.0);
    // Program 0 is DirectSound, so the initial axis stays continuous; later
    // detent cases select the immutable PSG bank entries through the document.
    QCOMPARE(m_area->axis().mode(), VelocityAxis::Mode::Continuous);
    // The located input points must land on the live input extent; a
    // mis-mapped fixture fails here instead of vacuously mid-case.
    QVERIFY(m_velocityInput->bounds().contains(nodePoint(kQuietStackedVelocity, kDuplicateTick)) &&
            m_velocityInput->bounds().contains(nodePoint(kLaterVelocity, kLaterTick)));
}

void VelocityEditingTest::cleanup()
{
    // Unconditional quiesce, separate from the verification below and
    // independent of how the body ended: cancel any surviving interaction,
    // release every recorded held input, then drop any residual grab.
    bool mouseGrabCleared = true;
    if (m_quickWindow) {
        QTest::keyClick(m_quickWindow, Qt::Key_Escape);
        if (m_heldButton != Qt::NoButton)
            QTest::mouseRelease(m_quickWindow, m_heldButton, Qt::NoModifier, m_lastWindowPos);
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        mouseGrabCleared = QTest::qWaitFor(
            [this] { return !m_quickWindow || !m_quickWindow->mouseGrabberItem(); });
    }
    m_heldButton = Qt::NoButton;
    m_area.clear();
    m_velocityInput.clear();
    m_rollInput.clear();
    m_quickWindow.clear();
    // The tab dies before the bank member it borrows.
    m_tab.reset();

    QVERIFY(mouseGrabCleared);
}

void VelocityEditingTest::dragCommitsOnce()
{
    selectDragPair();

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    mousePress(Qt::LeftButton, windowPoint(nodePoint(kQuietStackedVelocity, kDuplicateTick)));
    mouseMove(windowPoint(nodePoint(kQuietStackedVelocity + kDragUpSteps, kDuplicateTick)));

    // First held move: every selected note previews its literal expectation,
    // the loud stacked note does not, and the document stays frozen.
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    const std::optional<uint8_t> firstQuietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> firstLaterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(firstQuietPreview.has_value());
    QVERIFY(firstLaterPreview.has_value());
    QCOMPARE(int(*firstQuietPreview), kQuietStackedVelocity + kDragUpSteps);
    QCOMPARE(int(*firstLaterPreview), kLaterVelocity + kDragUpSteps);
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));

    mouseMove(windowPoint(nodePoint(kQuietStackedVelocity - kDragDownSteps, kDuplicateTick)));

    // Second held move: previews update again while everything stays deferred.
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    const std::optional<uint8_t> secondQuietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> secondLaterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(secondQuietPreview.has_value());
    QVERIFY(secondLaterPreview.has_value());
    QCOMPARE(int(*secondQuietPreview), kQuietStackedVelocity - kDragDownSteps);
    QCOMPARE(int(*secondLaterPreview), kLaterVelocity - kDragDownSteps);

    mouseRelease(Qt::LeftButton,
                 windowPoint(nodePoint(kQuietStackedVelocity - kDragDownSteps, kDuplicateTick)));

    // Exactly one commit on release: previews clear, only the selected ids
    // change, and the selection survives.
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), revisionBefore + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore + 1);
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_loudStacked.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity - kDragDownSteps);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity - kDragDownSteps);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity - kDragDownSteps);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity - kDragDownSteps);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);

    // Undo through the real history restores document and timeline alike and
    // keeps the selection identities; redo reapplies the same commit.
    QVERIFY(m_tab->history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(m_tab->history().requestUndo()));
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);

    QVERIFY(m_tab->history().canRedo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(m_tab->history().requestRedo()));
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity - kDragDownSteps);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity - kDragDownSteps);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity - kDragDownSteps);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity - kDragDownSteps);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
}

void VelocityEditingTest::escapeCancelsDrag()
{
    selectDragPair();

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    focusVelocityBand();
    mousePress(Qt::LeftButton, windowPoint(nodePoint(kQuietStackedVelocity, kDuplicateTick)));
    mouseMove(windowPoint(nodePoint(kQuietStackedVelocity + kDragUpSteps, kDuplicateTick)));
    const std::optional<uint8_t> firstQuietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> firstLaterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(firstQuietPreview.has_value());
    QVERIFY(firstLaterPreview.has_value());
    QCOMPARE(int(*firstQuietPreview), kQuietStackedVelocity + kDragUpSteps);
    QCOMPARE(int(*firstLaterPreview), kLaterVelocity + kDragUpSteps);
    mouseMove(windowPoint(nodePoint(kQuietStackedVelocity - kDragDownSteps, kDuplicateTick)));
    // The preview is live, not stuck: the second held move changed it before
    // Escape cancels the gesture.
    const std::optional<uint8_t> secondQuietPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    const std::optional<uint8_t> secondLaterPreview = m_tab->view().previewVelocity(m_later.noteId);
    QVERIFY(secondQuietPreview.has_value());
    QVERIFY(secondLaterPreview.has_value());
    QCOMPARE(int(*secondQuietPreview), kQuietStackedVelocity - kDragDownSteps);
    QCOMPARE(int(*secondLaterPreview), kLaterVelocity - kDragDownSteps);

    QTest::keyClick(m_quickWindow, Qt::Key_Escape);
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QTRY_VERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);

    // A later move and release after the cancel must not commit anything.
    mouseMove(windowPoint(nodePoint(kQuietStackedVelocity + kDragUpSteps, kDuplicateTick)));
    mouseRelease(Qt::LeftButton,
                 windowPoint(nodePoint(kQuietStackedVelocity + kDragUpSteps, kDuplicateTick)));
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
}

void VelocityEditingTest::releaseWithoutMoveIsNoop()
{
    QVERIFY(m_tab->view().selectionModel().noteSelection().empty());

    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoDepthBefore = m_tab->document().undoStack()->count();

    mousePress(Qt::LeftButton, windowPoint(nodePoint(kQuietStackedVelocity, kDuplicateTick)));
    // Pressing may stage the original velocity, but must not propose a change.
    const std::optional<uint8_t> pressPreview =
        m_tab->view().previewVelocity(m_quietStacked.noteId);
    QCOMPARE(int(pressPreview.value_or(kQuietStackedVelocity)), int(kQuietStackedVelocity));
    mouseRelease(Qt::LeftButton, windowPoint(nodePoint(kQuietStackedVelocity, kDuplicateTick)));

    // No movement: no history residue and no document edit, but the click
    // still selects the quiet stacked fixture note (proving the press landed on it).
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoDepthBefore);
    QVERIFY(!m_tab->view().previewVelocity(m_quietStacked.noteId).has_value());
    QVERIFY(!m_tab->view().previewVelocity(m_later.noteId).has_value());
    QCOMPARE(documentVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(documentVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(documentVelocity(m_later.noteId), kLaterVelocity);
    QCOMPARE(timelineVelocity(m_quietStacked.noteId), kQuietStackedVelocity);
    QCOMPARE(timelineVelocity(m_loudStacked.noteId), kLoudStackedVelocity);
    QCOMPARE(timelineVelocity(m_later.noteId), kLaterVelocity);
    QVERIFY(noteSelectionIs({m_quietStacked.noteId}));
}

void VelocityEditingTest::selectDragPair()
{
    m_tab->view().selectionModel().setNoteSelection({m_quietStacked.noteId, m_later.noteId});
    QVERIFY(noteSelectionIs({m_quietStacked.noteId, m_later.noteId}));
}

QPointF VelocityEditingTest::nodePoint(uint8_t velocity, uint64_t tick) const
{
    const qreal dpr = m_velocityInput->devicePixelRatio();
    const double x = m_tab->view().camera().displayX(double(tick), 0.0, dpr);
    const double y = m_area->axis().velocityToY(velocity);
    return QPointF(x, y);
}

QPoint VelocityEditingTest::windowPoint(const QPointF &itemLocal) const
{
    return m_velocityInput->mapToScene(itemLocal).toPoint();
}

void VelocityEditingTest::mousePress(Qt::MouseButton button, const QPoint &windowPos,
                                     Qt::KeyboardModifiers modifiers)
{
    m_lastWindowPos = windowPos;
    // Deliver input only to the suite's offscreen Quick window. Do not warp
    // the desktop cursor or reconcile events from a native window system.
    QTest::mouseEvent(QTest::MouseMove, m_quickWindow, Qt::NoButton, modifiers, m_lastWindowPos);
    QTest::mousePress(m_quickWindow, button, modifiers, m_lastWindowPos);
    m_heldButton = button;
}

void VelocityEditingTest::mouseMove(const QPoint &windowPos, Qt::KeyboardModifiers modifiers)
{
    m_lastWindowPos = windowPos;
    QTest::mouseEvent(QTest::MouseMove, m_quickWindow, Qt::NoButton, modifiers, m_lastWindowPos);
}

void VelocityEditingTest::mouseRelease(Qt::MouseButton button, const QPoint &windowPos,
                                       Qt::KeyboardModifiers modifiers)
{
    m_lastWindowPos = windowPos;
    QTest::mouseRelease(m_quickWindow, button, modifiers, m_lastWindowPos);
    m_heldButton = Qt::NoButton;
}

void VelocityEditingTest::focusVelocityBand()
{
    QVERIFY(m_tab->view().quickView()->focusBand(songview::TimelineBand::Velocity,
                                                 Qt::OtherFocusReason));
    // QTest targets the Quick window explicitly, so its live focus item is
    // the delivery gate; the embedded window need not own OS foreground state.
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Velocity);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(),
                 static_cast<QQuickItem *>(m_velocityInput.data()));
}

int VelocityEditingTest::documentVelocity(NoteId noteId) const
{
    DocNote note;
    if (!m_tab->document().findNote(noteId, &note))
        return -1;
    return int(note.velocity);
}

int VelocityEditingTest::timelineVelocity(NoteId noteId) const
{
    // Reacquire per call: every committed edit rebuilds the projection.
    const std::shared_ptr<const MidiTimeline> timeline = m_tab->timeline();
    if (!timeline)
        return -1;
    for (const TimelineEvent &event : timeline->events) {
        if (event.type == 0x9 && event.noteId == noteId)
            return int(event.data1);
    }
    return -1;
}

bool VelocityEditingTest::noteSelectionIs(const std::vector<NoteId> &expected) const
{
    return m_tab->view().selectionModel().noteSelection() == expected;
}

// Dispatched once per process by the velocity-editing catalog row; the
// catalog already passed only the Qt payload (args.mid(1)).
int runVelocityEditingCheck(const QStringList &qtArguments)
{
    VelocityEditingTest test;
    QStringList arguments{QStringLiteral("velocity-editing")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
