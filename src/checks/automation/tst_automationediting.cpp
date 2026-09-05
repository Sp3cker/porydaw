// Qt Test coverage for the automation canvas' real SongTab transaction path.
// The fixture deliberately uses a normal CC lane: 0xC0 is a program change,
// while the values below enter the document through its 0xB0 CC lane API.

#include "checks/automation/tst_automationediting.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include <algorithm>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QQuickItem>

#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kController = 10;
constexpr uint64_t kDraggedTick = 48;
constexpr uint64_t kIndependentTick = 96;
constexpr uint64_t kBlankTick = 144;
constexpr uint64_t kEndTick = 192;
constexpr int kDraggedValue = 40;
constexpr int kCommittedValue = 84;
constexpr int kIndependentValue = 100;
constexpr int kBlankProbeValue = 64;

SmfEvent programChange(uint64_t tick, uint8_t program)
{
    SmfEvent event;
    event.status = 0xC0;
    event.tick = tick;
    event.data0 = program;
    return event;
}

SmfFile automationEditingSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {programChange(0, 0)};
    track.endTick = kEndTick;
    smf.tracks.push_back(track);
    return smf;
}

bool transientLayerContainsNodeAt(const songview::TimelineQuickLayerData &layer,
                                  const QPointF &center)
{
    return std::any_of(layer.triangles.cbegin(), layer.triangles.cend(),
                       [&center](const songview::TimelineQuickTriangle &triangle) {
                           return triangle.first == center;
                       });
}

} // namespace

void AutomationEditingTest::init()
{
    m_heldButton = Qt::NoButton;
    m_lastWindowPos = {};

    m_bank = LoadedVoiceGroup{};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    const std::optional<SongName> name = SongName::create(QStringLiteral("automation-editing"));
    QVERIFY(name.has_value());
    m_tab = std::make_unique<SongTab>(std::move(*name));
    m_tab->resize(960, 480);
    // MidiStage builds the timeline projection, so its sample rate must be
    // fixed before staging it into the tab.
    m_tab->setSampleRate(48000.0);

    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("automation-editing-check"), QString());
    QVERIFY(identity.has_value());

    SongInfo song;
    song.label = QStringLiteral("automation-editing");
    song.hasMid = true;
    // The tab's load protocol is MIDI, then the borrowed bank, then identity.
    m_tab->applyMidiStage(std::move(song), automationEditingSmf(), track_limits::kHardwareCapacity);
    QVERIFY(m_tab->presentationError().isEmpty());
    m_tab->applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&m_bank), QString()});
    m_tab->applyVoicegroupBound(*identity);

    QTRY_VERIFY(m_tab->isReady());
    QVERIFY(m_tab->voicegroupLease().get() == &m_bank);

    SongView &view = m_tab->view();
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 320);

    m_page = view.editorDrawer() ? view.editorDrawer()->automationPage() : nullptr;
    QVERIFY(m_page);
    songview::TimelineQuickView *quick = view.quickView();
    QVERIFY(quick);
    m_quickWindow = quick->quickWindow();
    QVERIFY(m_quickWindow);
    QObject *const quickRoot = quick->rootObject();
    QVERIFY(quickRoot);
    m_automationInput = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationInput"));
    QVERIFY(m_automationInput);

    arrangeCcLane();
    // QTest delivers integral window positions. Give the 0...127 CC domain
    // the largest supported lane so this literal target is representable by
    // that real input path instead of changing the expected controller value.
    EditorViewState automationState = view.editorViewState();
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    automationState.laneHeights[ccRow] = AutomationGeometry::resolve().rowMaximumHeight;
    view.applyEditorViewState(automationState);
    QTRY_VERIFY(ccLaneHandle().valid());
    QTRY_VERIFY(!m_page->canvas()->laneBody(ccLaneHandle()).isEmpty());
    QTRY_COMPARE(m_page->canvas()->laneBody(ccLaneHandle()).height(),
                 AutomationGeometry::resolve().rowMaximumHeight);

    m_tab->show();
    QTRY_VERIFY(m_quickWindow->isVisible() && m_quickWindow->isExposed());
    QTRY_VERIFY(!m_automationInput->bounds().isEmpty());
    QTRY_COMPARE(m_automationInput->window(), m_quickWindow.data());
    const QPointF draggedViewport =
        ccPoint(kDraggedTick, kDraggedValue) - QPointF(0.0, m_page->verticalScroll());
    QVERIFY(m_automationInput->bounds().contains(draggedViewport));
    QVERIFY(laneValue(kDraggedTick) == kDraggedValue);
    QVERIFY(laneValue(kIndependentTick) == kIndependentValue);

    focusAutomationBand();
}

void AutomationEditingTest::cleanup()
{
    // This is deliberately unconditional: a failed assertion after a press
    // must still cancel, release, and ungrab before the borrowed bank outlives
    // the tab teardown.
    bool mouseGrabCleared = true;
    if (m_quickWindow) {
        QTest::keyClick(m_quickWindow, Qt::Key_Escape, Qt::NoModifier);
        if (m_heldButton != Qt::NoButton)
            QTest::mouseRelease(m_quickWindow, m_heldButton, Qt::NoModifier, m_lastWindowPos);
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        mouseGrabCleared = QTest::qWaitFor(
            [this] { return !m_quickWindow || !m_quickWindow->mouseGrabberItem(); });
    }
    m_heldButton = Qt::NoButton;
    m_page.clear();
    m_automationInput.clear();
    m_quickWindow.clear();
    m_tab.reset();

    QVERIFY(mouseGrabCleared);
}

void AutomationEditingTest::ccDragCommitsOnce()
{
    auto *quickScene = m_tab->view().findChild<songview::TimelineQuickScene *>();
    QVERIFY(quickScene);

    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    const std::optional<ArmedCcDrag> arm = armCcDrag(quickScene);
    QVERIFY(arm.has_value());

    // The retained transient scene shows the grabbed CC node at its provisional
    // target, independently of the frozen document.
    QTRY_VERIFY(quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                arm->transientRevisionBefore);
    QTRY_VERIFY(transientLayerContainsNodeAt(
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient), arm->targetViewport));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QCOMPARE(laneValue(kDraggedTick), kDraggedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);

    mouseRelease(Qt::LeftButton, arm->dragEndWindow, Qt::NoModifier);

    // Exactly one release-time document transaction changes the grabbed CC;
    // the independent literal lane point prevents a broad replacement from
    // looking correct by accident.
    QCOMPARE(documentChanged.count(), 1);
    QCOMPARE(edited.count(), 1);
    QCOMPARE(m_tab->document().revision(), frozen.revision + 1);
    QCOMPARE(m_tab->document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(m_tab->document().undoStack()->index(), frozen.undoIndex + 1);
    QVERIFY(m_tab->document().smf().write() != frozen.smf);
    QCOMPARE(laneValue(kDraggedTick), kCommittedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);
    QTRY_COMPARE(timelineCcValue(kDraggedTick), kCommittedValue);
    QCOMPARE(timelineCcValue(kIndependentTick), kIndependentValue);

    QVERIFY(m_tab->history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(m_tab->history().requestUndo()));
    QCOMPARE(laneValue(kDraggedTick), kDraggedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);
    QTRY_COMPARE(timelineCcValue(kDraggedTick), kDraggedValue);
    QCOMPARE(timelineCcValue(kIndependentTick), kIndependentValue);

    QVERIFY(m_tab->history().canRedo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(m_tab->history().requestRedo()));
    QCOMPARE(laneValue(kDraggedTick), kCommittedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);
    QTRY_COMPARE(timelineCcValue(kDraggedTick), kCommittedValue);
    QCOMPARE(timelineCcValue(kIndependentTick), kIndependentValue);
}

void AutomationEditingTest::escapeCancelsCcDrag()
{
    auto *quickScene = m_tab->view().findChild<songview::TimelineQuickScene *>();
    QVERIFY(quickScene);

    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    const std::optional<ArmedCcDrag> arm = armCcDrag(quickScene);
    QVERIFY(arm.has_value());

    // This is a live CC-node drag, not a right-band selection: its retained
    // transient node reaches the requested provisional target.
    QTRY_VERIFY(quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).revision >
                arm->transientRevisionBefore);
    QTRY_VERIFY(transientLayerContainsNodeAt(
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient), arm->targetViewport));
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QCOMPARE(laneValue(kDraggedTick), kDraggedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);

    QTest::keyClick(m_quickWindow, Qt::Key_Escape, Qt::NoModifier);
    QTRY_VERIFY(quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).rects.empty());
    QTRY_VERIFY(
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).triangles.empty());
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QCOMPARE(laneValue(kDraggedTick), kDraggedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);

    // Escape terminates the drag; later pointer traffic cannot revive or
    // release-commit the cancelled gesture.
    mouseMove(arm->dragEndWindow, Qt::NoModifier);
    QTRY_VERIFY(quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).rects.empty());
    QTRY_VERIFY(
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).triangles.empty());
    mouseRelease(Qt::LeftButton, arm->dragEndWindow, Qt::NoModifier);
    QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    QCOMPARE(laneValue(kDraggedTick), kDraggedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);
}

void AutomationEditingTest::releaseWithoutActivationDoesNotCommit()
{
    const QPointF blank = ccPoint(kBlankTick, kBlankProbeValue);
    QVERIFY(m_automationInput->bounds().contains(blank - QPointF(0.0, m_page->verticalScroll())));
    QCOMPARE(laneValue(kBlankTick), -1);

    const QByteArray smfBefore = m_tab->document().smf().write();
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoCountBefore = m_tab->document().undoStack()->count();
    const int undoIndexBefore = m_tab->document().undoStack()->index();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    mousePress(Qt::LeftButton, windowPoint(blank), Qt::NoModifier);
    mouseRelease(Qt::LeftButton, windowPoint(blank), Qt::NoModifier);

    // A blank, unactivated sweep commits cursor placement—not a document
    // mutation. Stationary clicks on existing nodes intentionally delete.
    QTRY_COMPARE(m_tab->view().editCursorTick(), kBlankTick);
    QCOMPARE(m_tab->document().smf().write(), smfBefore);
    QCOMPARE(m_tab->document().revision(), revisionBefore);
    QCOMPARE(m_tab->document().undoStack()->count(), undoCountBefore);
    QCOMPARE(m_tab->document().undoStack()->index(), undoIndexBefore);
    QCOMPARE(documentChanged.count(), 0);
    QCOMPARE(edited.count(), 0);
    QCOMPARE(laneValue(kDraggedTick), kDraggedValue);
    QCOMPARE(laneValue(kIndependentTick), kIndependentValue);
    QCOMPARE(laneValue(kBlankTick), -1);
}

void AutomationEditingTest::arrangeCcLane()
{
    m_tab->document().writeLanePoints(
        0, kController, 0, kEndTick,
        {{kDraggedTick, kDraggedValue}, {kIndependentTick, kIndependentValue}});
}

LaneHandle AutomationEditingTest::ccLaneHandle() const
{
    if (!m_page)
        return {};
    const EditorAutomationRowId wanted{EditorAutomationRowKind::ControlChange, 0, kController};
    const auto &rows = m_page->canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == wanted)
            return {index + 1};
    }
    return {};
}

QPointF AutomationEditingTest::ccPoint(uint64_t tick, int value) const
{
    const LaneHandle lane = ccLaneHandle();
    const QRect body = m_page ? m_page->canvas()->laneBody(lane) : QRect{};
    if (!m_tab || !m_automationInput || body.isEmpty())
        return {};
    const qreal x =
        m_tab->view().camera().displayX(double(tick), 0.0, m_automationInput->devicePixelRatio());
    const qreal y =
        AutomationProjection::valueY(body, AutomationGeometry::resolve(), 0, 127, value);
    return {x, y};
}

QPoint AutomationEditingTest::windowPoint(const QPointF &contentPoint) const
{
    const QPointF viewportPoint(contentPoint.x(), contentPoint.y() - m_page->verticalScroll());
    return m_automationInput->mapToScene(viewportPoint).toPoint();
}

std::optional<AutomationEditingTest::ArmedCcDrag>
AutomationEditingTest::armCcDrag(songview::TimelineQuickScene *quickScene)
{
    if (!m_page || !m_automationInput || !m_quickWindow || !quickScene)
        return std::nullopt;

    const QPointF source = ccPoint(kDraggedTick, kDraggedValue);
    const QPointF target = ccPoint(kDraggedTick, kCommittedValue);
    const QPointF scrollOffset(0.0, m_page->verticalScroll());
    if (!m_automationInput->bounds().contains(source - scrollOffset) ||
        !m_automationInput->bounds().contains(target - scrollOffset)) {
        return std::nullopt;
    }

    // The threshold-crossing move only arms the drag and becomes its relative
    // origin. Derive the second move from delivered integral positions: its
    // delta must be target minus press, relative to that activation origin.
    const int activationTravel = AutomationGeometry::resolve().nodeDragActivationDistance + 2;
    const QPointF activation = source + QPointF(0.0, -activationTravel);
    const QPoint sourceWindow = windowPoint(source);
    const QPoint targetWindow = windowPoint(target);
    const QPoint activationWindow = windowPoint(activation);
    const QPoint dragEndWindow = activationWindow + (targetWindow - sourceWindow);
    const quint64 transientRevisionBefore =
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;

    mousePress(Qt::LeftButton, sourceWindow, Qt::NoModifier);
    mouseMove(activationWindow, Qt::NoModifier);
    mouseMove(dragEndWindow, Qt::NoModifier);

    return ArmedCcDrag{
        .dragEndWindow = dragEndWindow,
        .targetViewport = target - scrollOffset,
        .transientRevisionBefore = transientRevisionBefore,
    };
}

AutomationEditingTest::FrozenDocumentState
AutomationEditingTest::frozenDocumentState(int documentChanges, int edits) const
{
    return {
        .smf = m_tab->document().smf().write(),
        .revision = m_tab->document().revision(),
        .undoCount = m_tab->document().undoStack()->count(),
        .undoIndex = m_tab->document().undoStack()->index(),
        .documentChanges = documentChanges,
        .edits = edits,
    };
}

void AutomationEditingTest::mousePress(Qt::MouseButton button, const QPoint &windowPos,
                                       Qt::KeyboardModifiers modifiers)
{
    m_lastWindowPos = windowPos;
    QTest::mouseEvent(QTest::MouseMove, m_quickWindow, Qt::NoButton, modifiers, m_lastWindowPos);
    QTest::mousePress(m_quickWindow, button, modifiers, m_lastWindowPos);
    m_heldButton = button;
}

void AutomationEditingTest::mouseMove(const QPoint &windowPos, Qt::KeyboardModifiers modifiers)
{
    m_lastWindowPos = windowPos;
    QTest::mouseEvent(QTest::MouseMove, m_quickWindow, Qt::NoButton, modifiers, m_lastWindowPos);
}

void AutomationEditingTest::mouseRelease(Qt::MouseButton button, const QPoint &windowPos,
                                         Qt::KeyboardModifiers modifiers)
{
    m_lastWindowPos = windowPos;
    QTest::mouseRelease(m_quickWindow, button, modifiers, m_lastWindowPos);
    m_heldButton = Qt::NoButton;
}

void AutomationEditingTest::focusAutomationBand()
{
    QVERIFY(m_tab->view().quickView()->focusBand(songview::TimelineBand::Automation,
                                                 Qt::OtherFocusReason));
    QTRY_VERIFY(m_tab->view().quickView()->focusedBand() == songview::TimelineBand::Automation);
    QTRY_COMPARE(m_quickWindow->activeFocusItem(),
                 static_cast<QQuickItem *>(m_automationInput.data()));
}

int AutomationEditingTest::laneValue(uint64_t tick) const
{
    DocLanePoint point;
    if (!m_tab->document().findLanePoint(0, kController, tick, &point))
        return -1;
    return point.value;
}

int AutomationEditingTest::timelineCcValue(uint64_t tick) const
{
    // Reacquire after every document mutation: SongTab replaces this immutable
    // projection during its documentChanged transaction.
    const std::shared_ptr<const MidiTimeline> timeline = m_tab->timeline();
    if (!timeline)
        return -1;
    for (const TimelineEvent &event : timeline->events) {
        if (event.type == 0xB && event.track == 0 && event.tick == tick &&
            event.data0 == kController) {
            return event.data1;
        }
    }
    return -1;
}

// Dispatched once per process by the automation-editing catalog row; the
// catalog already passed only the Qt payload (args.mid(1)).
int runAutomationEditingCheck(const QStringList &qtArguments)
{
    AutomationEditingTest test;
    QStringList arguments{QStringLiteral("automation-editing")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
