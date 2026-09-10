// Qt Test coverage for the automation canvas' real SongTab transaction path.
// The fixture deliberately uses a normal CC lane: 0xC0 is a program change,
// while the values below enter the document through its 0xB0 CC lane API.

#include "checks/automation/tst_automationediting.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include <algorithm>
#include <optional>
#include <variant>

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

bool transientLayerContainsNodeAt(const songview::TimelineQuickLayerData &layer,
                                  const QPointF &center)
{
    return std::any_of(layer.triangles.cbegin(), layer.triangles.cend(),
                       [&center](const songview::TimelineQuickTriangle &triangle) {
                           return triangle.first == center;
                       });
}

} // namespace

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
    QVERIFY(m_automationInput->bounds().contains(blank));
    QCOMPARE(laneValue(kBlankTick), -1);

    const QByteArray smfBefore = m_tab->document().smf().write();
    const uint64_t revisionBefore = m_tab->document().revision();
    const int undoCountBefore = m_tab->document().undoStack()->count();
    const int undoIndexBefore = m_tab->document().undoStack()->index();
    QSignalSpy documentChanged(&m_tab->document(), &SongDocument::documentChanged);
    QSignalSpy edited(m_tab.get(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    mousePress(Qt::LeftButton, automationWindowPoint(blank), Qt::NoModifier);
    mouseRelease(Qt::LeftButton, automationWindowPoint(blank), Qt::NoModifier);

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

QPointF AutomationEditingTest::ccPoint(uint64_t tick, int value) const
{
    return inputPoint(findRow({EditorAutomationRowKind::ControlChange, 0, kController}),
                      double(tick), value);
}

std::optional<AutomationEditingTest::ArmedCcDrag>
AutomationEditingTest::armCcDrag(songview::TimelineQuickScene *quickScene)
{
    if (!m_page || !m_automationInput || !m_quickWindow || !quickScene)
        return std::nullopt;

    const QPointF source = ccPoint(kDraggedTick, kDraggedValue);
    const QPointF target = ccPoint(kDraggedTick, kCommittedValue);
    if (!m_automationInput->bounds().contains(source) ||
        !m_automationInput->bounds().contains(target)) {
        return std::nullopt;
    }

    // The threshold-crossing move only arms the drag and becomes its relative
    // origin. Derive the second move from delivered integral positions: its
    // delta must be target minus press, relative to that activation origin.
    const int activationTravel = AutomationGeometry::resolve().nodeDragActivationDistance + 2;
    const QPointF activation = source + QPointF(0.0, -activationTravel);
    const QPoint sourceWindow = automationWindowPoint(source);
    const QPoint targetWindow = automationWindowPoint(target);
    const QPoint activationWindow = automationWindowPoint(activation);
    const QPoint dragEndWindow = activationWindow + (targetWindow - sourceWindow);
    const quint64 transientRevisionBefore =
        quickScene->layer(songview::TimelineQuickLayer::AutomationTransient).revision;

    mousePress(Qt::LeftButton, sourceWindow, Qt::NoModifier);
    mouseMove(activationWindow, Qt::NoModifier);
    mouseMove(dragEndWindow, Qt::NoModifier);

    return ArmedCcDrag{
        .dragEndWindow = dragEndWindow,
        .targetViewport = target,
        .transientRevisionBefore = transientRevisionBefore,
    };
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

// The rendered gutter labels own parameter activation: cycling every catalog
// row — the pilot's written Pan and Volume lanes plus the empty parameters —
// must leave the frozen document, the undo state and the explicit shared
// Volume/Pan/Tempo selection untouched while the active index follows each
// clicked label.
void AutomationEditingTest::parameterTabsPreserveDocumentAndSelection()
{
    using TimeSelection = songview::EditorSelectionModel::TimeSelection;

    QSignalSpy documentChanged(&tab().document(), &SongDocument::documentChanged);
    QSignalSpy edited(&tab(), &SongTab::edited);
    QVERIFY(documentChanged.isValid());
    QVERIFY(edited.isValid());

    // An explicit Lanes selection spanning Volume, Pan and Tempo: unpainted
    // lanes and the song-global tempo flag must survive switching too.
    TimeSelection selection;
    selection.startTick = 48;
    selection.endTick = 144;
    selection.scope = TimeSelection::Lanes;
    selection.lanes = {{0, CoreTimeDefaults::kCcVolume}, {0, CoreTimeDefaults::kCcPan}};
    selection.tempo = true;
    tab().view().selectionModel().setTimeSelection(selection);
    const TimeSelection frozenSelection = tab().view().selectionModel().timeSelection();
    QVERIFY(frozenSelection.active());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count(), edited.count());

    const QStringList labels = page().canvas()->parameterLabels();
    const int labelCount = int(labels.size());
    QVERIFY(labelCount > 1);
    for (int index = 0; index < labelCount; ++index) {
        const std::optional<EditorAutomationRowId> row = page().canvas()->parameterRow(index);
        QVERIFY(row.has_value());
        QVERIFY(activateParameter(*row));
        QCOMPARE(page().canvas()->activeParameter(), index);

        const TimeSelection &current = tab().view().selectionModel().timeSelection();
        QCOMPARE(current.scope, frozenSelection.scope);
        QCOMPARE(current.startTick, frozenSelection.startTick);
        QCOMPARE(current.endTick, frozenSelection.endTick);
        QCOMPARE(current.tempo, frozenSelection.tempo);
        QVERIFY(current.lanes == frozenSelection.lanes);
        QVERIFY(frozenDocumentState(documentChanged.count(), edited.count()) == frozen);
    }
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
