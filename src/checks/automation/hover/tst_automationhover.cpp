#include "checks/automation/hover/tst_automationhover.h"

#include <QtTest>

#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>

#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/automation/hover/hoverfixture.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint8_t kInsertedController = 11;
constexpr uint64_t kProbeTick = 96;

qreal expectedRootContentX(const automation_hover::Fixture &fixture, uint64_t tick)
{
    const SongView &view = fixture.rig->view();
    return view.timelineSplitX() + view.camera().contentX(tick) - view.quickView()->geometry().x();
}

} // namespace

AutomationHoverTest::AutomationHoverTest() = default;

AutomationHoverTest::~AutomationHoverTest() = default;

void AutomationHoverTest::init()
{
    auto fixture = std::make_unique<automation_hover::Fixture>();
    QString error;
    QVERIFY2(automation_hover::create(*fixture, error), qPrintable(error));
    m_fixture = std::move(fixture);
    QVERIFY(automation_hover::plotInput(*m_fixture));
    QVERIFY(automation_hover::gutterInput(*m_fixture));
    QVERIFY(automation_hover::quickWindow(*m_fixture));
    QVERIFY(m_fixture->rig->quickScene());
}

void AutomationHoverTest::cleanup()
{
    bool grabCleared = true;
    if (m_fixture && automation_hover::quickWindow(*m_fixture)) {
        QTest::keyClick(automation_hover::quickWindow(*m_fixture), Qt::Key_Escape, Qt::NoModifier);
        if (m_fixture->heldButton != Qt::NoButton) {
            QTest::mouseRelease(automation_hover::quickWindow(*m_fixture), m_fixture->heldButton,
                                Qt::NoModifier, m_fixture->lastWindowPosition);
        }
        if (QQuickItem *grabber = automation_hover::quickWindow(*m_fixture)->mouseGrabberItem())
            grabber->ungrabMouse();
        grabCleared = QTest::qWaitFor([this] {
            return !m_fixture || !automation_hover::quickWindow(*m_fixture) ||
                   !automation_hover::quickWindow(*m_fixture)->mouseGrabberItem();
        });
    }
    m_fixture.reset();
    QVERIFY(grabCleared);
}

void AutomationHoverTest::directInputHostRouting()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    const auto frozen = automation_hover::documentState(*m_fixture);
    const auto idle = automation_hover::observe(*m_fixture);

    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition);

    QTRY_VERIFY(m_fixture->rig->view().quickView()->hoverVisible());
    QTRY_VERIFY(automation_hover::observe(*m_fixture).revision > idle.revision);
    const qreal expectedRootX = expectedRootContentX(*m_fixture, lane->insertionTick);
    QTRY_VERIFY(std::abs(m_fixture->rig->view().quickView()->hoverRootContentX() - expectedRootX) <=
                layout::singlePixel());
    const auto &layer =
        m_fixture->rig->quickScene()->layer(songview::TimelineQuickLayer::AutomationHover);
    QVERIFY(automation_hover::hasFilledNodeAt(layer, lane->insertionViewport));
    QVERIFY(automation_hover::hasValueText(*m_fixture, automation_hover::observe(*m_fixture)));
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
}

void AutomationHoverTest::focusLostKeepsGrab()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    const auto frozen = automation_hover::documentState(*m_fixture);

    automation_hover::mousePress(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(automation_hover::quickWindow(*m_fixture)->mouseGrabberItem());
    QQuickItem *const grabber = automation_hover::quickWindow(*m_fixture)->mouseGrabberItem();

    automation_hover::canvas(*m_fixture)
        ->inputCancelled(songview::TimelineInputCancelReason::FocusLost);
    QCoreApplication::processEvents();

    QVERIFY(automation_hover::quickWindow(*m_fixture)->mouseGrabberItem() == grabber);
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
    automation_hover::mouseRelease(*m_fixture, m_fixture->lastWindowPosition);
}

void AutomationHoverTest::deactivationClears()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(automation_hover::observe(*m_fixture).chromeVisible);
    const auto frozen = automation_hover::documentState(*m_fixture);

    automation_hover::mousePress(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(automation_hover::quickWindow(*m_fixture)->mouseGrabberItem());
    automation_hover::canvas(*m_fixture)
        ->inputCancelled(songview::TimelineInputCancelReason::WindowDeactivated);

    QTRY_VERIFY(automation_hover::isClear(*m_fixture));
    QTRY_VERIFY(!automation_hover::quickWindow(*m_fixture)->mouseGrabberItem());
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
    m_fixture->heldButton = Qt::NoButton;
}

void AutomationHoverTest::hoverRevivesAfterCancellation()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(automation_hover::observe(*m_fixture).chromeVisible);
    const quint64 firstRevision = automation_hover::observe(*m_fixture).revision;

    automation_hover::canvas(*m_fixture)
        ->inputCancelled(songview::TimelineInputCancelReason::WindowDeactivated);
    QTRY_VERIFY(automation_hover::isClear(*m_fixture));
    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition);

    QTRY_VERIFY(automation_hover::observe(*m_fixture).chromeVisible);
    QTRY_VERIFY(std::abs(m_fixture->rig->view().quickView()->hoverRootContentX() -
                         expectedRootContentX(*m_fixture, lane->insertionTick)) <=
                layout::singlePixel());
    QTRY_VERIFY(automation_hover::observe(*m_fixture).revision > firstRevision);
}

void AutomationHoverTest::idleCancellationsDoNotMutate()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    const auto frozen = automation_hover::documentState(*m_fixture);

    automation_hover::canvas(*m_fixture)
        ->inputCancelled(songview::TimelineInputCancelReason::Hidden);
    automation_hover::canvas(*m_fixture)
        ->inputCancelled(songview::TimelineInputCancelReason::PointerUngrabbed);
    QCoreApplication::processEvents();

    QVERIFY(automation_hover::isClear(*m_fixture));
    QVERIFY(!automation_hover::quickWindow(*m_fixture)->mouseGrabberItem());
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
}

void AutomationHoverTest::guideGhostTextAndRing_data()
{
    QTest::addColumn<int>("laneKind");
    QTest::newRow("Tempo") << int(automation_hover::LaneKind::Tempo);
    QTest::newRow("CC") << int(automation_hover::LaneKind::Cc);
}

void AutomationHoverTest::guideGhostTextAndRing()
{
    QFETCH(int, laneKind);
    const auto kind = static_cast<automation_hover::LaneKind>(laneKind);
    const auto prepared = automation_hover::prepareLane(*m_fixture, kind);
    QVERIFY(prepared.has_value());
    QString error;
    const auto topology = automation_hover::topologyFor(*m_fixture, *prepared, error);

    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(topology.insertionGuide);
    QVERIFY(topology.heldGhost);
    QVERIFY(topology.insertionText);
    QVERIFY(topology.nodeRing);
    QVERIFY(topology.nodeText);
    QVERIFY(topology.suppressesInsertionGhost);
    QVERIFY(topology.repeatDoesNotChurn);
    QVERIFY(topology.leaveCleared);
}

void AutomationHoverTest::repeatHoverDoesNotChurn()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    const auto frozen = automation_hover::documentState(*m_fixture);
    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(automation_hover::observe(*m_fixture).chromeVisible);
    const auto first = automation_hover::observe(*m_fixture);

    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition, false);
    QCoreApplication::processEvents();
    const auto repeated = automation_hover::observe(*m_fixture);
    QCOMPARE(repeated.revision, first.revision);
    QVERIFY(repeated == first);
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
}

void AutomationHoverTest::leaveClearsRetainedHover()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    const auto frozen = automation_hover::documentState(*m_fixture);

    automation_hover::mouseMove(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(automation_hover::observe(*m_fixture).chromeVisible);
    const auto &hoverLayer =
        m_fixture->rig->quickScene()->layer(songview::TimelineQuickLayer::AutomationHover);
    QVERIFY(automation_hover::hasFilledNodeAt(hoverLayer, lane->insertionViewport));
    QVERIFY(automation_hover::hasValueText(*m_fixture, automation_hover::observe(*m_fixture)));

    QVERIFY(automation_hover::leavePlot(*m_fixture));
    QTRY_VERIFY(automation_hover::isClear(*m_fixture));

    QVERIFY(automation_hover::leavePlot(*m_fixture));
    QTRY_VERIFY(automation_hover::isClear(*m_fixture));
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
}

void AutomationHoverTest::tempoAndCcTopologyMatch()
{
    const auto tempo = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Tempo);
    QVERIFY(tempo.has_value());
    QString tempoError;
    const auto tempoTopology = automation_hover::topologyFor(*m_fixture, *tempo, tempoError);
    QVERIFY2(tempoError.isEmpty(), qPrintable(tempoError));

    const auto cc = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(cc.has_value());
    QString ccError;
    const auto ccTopology = automation_hover::topologyFor(*m_fixture, *cc, ccError);
    QVERIFY2(ccError.isEmpty(), qPrintable(ccError));

    QVERIFY(tempoTopology.insertionGuide);
    QVERIFY(tempoTopology.heldGhost);
    QVERIFY(tempoTopology.insertionText);
    QVERIFY(tempoTopology.nodeRing);
    QVERIFY(tempoTopology.nodeText);
    QVERIFY(tempoTopology.suppressesInsertionGhost);
    QVERIFY(tempoTopology.repeatDoesNotChurn);
    QVERIFY(tempoTopology.leaveCleared);
    QVERIFY(tempoTopology == ccTopology);
}

void AutomationHoverTest::rowRebuildStaleReleaseDoesNotMutate()
{
    AutomationCanvas *const canvas = automation_hover::canvas(*m_fixture);
    AutomationPage *const page = automation_hover::page(*m_fixture);
    QVERIFY(canvas);
    QVERIFY(page);
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const EditorAutomationRowId lfoRow{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    const EditorAutomationRowId insertedRow{EditorAutomationRowKind::ControlChange, 0,
                                            kInsertedController};
    QVERIFY(automation_hover::expandTempo(*m_fixture));
    const LaneHandle tempoBefore{0};
    const LaneHandle panBefore = automation_hover::findHandle(*canvas, panRow);
    const LaneHandle lfoBefore = automation_hover::findHandle(*canvas, lfoRow);
    QVERIFY(automation_hover::rowMatches(*canvas, panBefore, panRow));
    QVERIFY(automation_hover::rowMatches(*canvas, lfoBefore, lfoRow));
    QVERIFY(!canvas->laneBody(tempoBefore).isEmpty());

    const QRect lfoBody = canvas->laneBody(lfoBefore);
    QVERIFY(!lfoBody.isEmpty());
    const QPointF grabbed(
        m_fixture->rig->view().camera().displayX(
            kProbeTick, 0.0, automation_hover::plotInput(*m_fixture)->devicePixelRatio()),
        AutomationProjection::valueY(lfoBody, AutomationGeometry::resolve(), 0, 127, 96));
    const QPoint press = automation_hover::windowPoint(*m_fixture, grabbed);
    const QPoint activation =
        press + QPoint(AutomationGeometry::resolve().nodeDragActivationDistance + 2, 0);
    const auto frozen = automation_hover::documentState(*m_fixture);

    automation_hover::mousePress(*m_fixture, press);
    automation_hover::mouseMove(*m_fixture, activation);
    QCoreApplication::processEvents();
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);

    page->addEmptyLane(0, kInsertedController);
    QCoreApplication::processEvents();
    const LaneHandle inserted = automation_hover::findHandle(*canvas, insertedRow);
    const LaneHandle panAfter = automation_hover::findHandle(*canvas, panRow);
    const LaneHandle lfoAfter = automation_hover::findHandle(*canvas, lfoRow);
    QVERIFY(automation_hover::rowMatches(*canvas, panAfter, panRow));
    QVERIFY(automation_hover::rowMatches(*canvas, inserted, insertedRow));
    QVERIFY(automation_hover::rowMatches(*canvas, lfoAfter, lfoRow));
    QCOMPARE(lfoAfter.index, lfoBefore.index + 1);
    QVERIFY(!canvas->laneBody(tempoBefore).isEmpty());
    QVERIFY(canvas->laneBody(LaneHandle{}).isEmpty());
    QVERIFY(canvas->laneBody(LaneHandle{9999}).isEmpty());

    automation_hover::mouseRelease(*m_fixture, activation);
    QCoreApplication::processEvents();
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
    QVERIFY(!automation_hover::quickWindow(*m_fixture)->mouseGrabberItem());

    page->removeEmptyLane(0, kInsertedController);
    QCoreApplication::processEvents();
    QVERIFY(automation_hover::findHandle(*canvas, panRow) == panBefore);
    QVERIFY(automation_hover::findHandle(*canvas, lfoRow) == lfoBefore);
    QVERIFY(automation_hover::rowMatches(*canvas, automation_hover::findHandle(*canvas, panRow),
                                         panRow));
    QVERIFY(automation_hover::rowMatches(*canvas, automation_hover::findHandle(*canvas, lfoRow),
                                         lfoRow));
}

int runAutomationHoverCheck(const QStringList &qtArguments)
{
    AutomationHoverTest test;
    QStringList arguments{QStringLiteral("automation-hover")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
