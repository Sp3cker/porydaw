#include "checks/automation/hover/tst_automationhover.h"

#include <QtTest>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>

#include <QAction>
#include <QCoreApplication>
#include <QCursor>
#include <QKeySequence>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/automation/automationquickmenu.h"
#include "checks/automation/hover/hoverfixture.h"
#include "checks/quickpopupguard.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/linearramp.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/layout.h"
#include "ui/mousehints/mousehints.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr Tick kProbeTick = 96;

qreal expectedRootContentX(const automation_hover::Fixture &fixture, Tick tick)
{
    const SongView &view = fixture.rig->view();
    return view.timelineSplitX() + view.camera().contentX(tick);
}

// QTest mouse events never move the platform cursor, so a stationary-cursor
// path (tool toggle, popup recovery) would re-read a stale QCursor::pos().
// Deliver the ordinary move first, then warp the real cursor to match.
void moveCursorTo(automation_hover::Fixture &fixture, QPoint windowPosition)
{
    automation_hover::mouseMove(fixture, windowPosition);
    if (QQuickWindow *const window = automation_hover::quickWindow(fixture))
        QCursor::setPos(window->mapToGlobal(windowPosition));
}

void rightClick(automation_hover::Fixture &fixture, QPoint windowPosition)
{
    moveCursorTo(fixture, windowPosition);
    QTest::mousePress(automation_hover::quickWindow(fixture), Qt::RightButton, Qt::NoModifier,
                      windowPosition);
    fixture.heldButton = Qt::RightButton;
    QTest::mouseRelease(automation_hover::quickWindow(fixture), Qt::RightButton, Qt::NoModifier,
                        windowPosition);
    fixture.heldButton = Qt::NoButton;
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
    QVERIFY(topology.reactivatedHeldText);
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
    QVERIFY(tempoTopology.reactivatedHeldText);
    QVERIFY(tempoTopology == ccTopology);
}

void AutomationHoverTest::rowRebuildStaleReleaseDoesNotMutate()
{
    AutomationCanvas *const canvas = automation_hover::canvas(*m_fixture);
    QVERIFY(canvas);
    const EditorAutomationRowId panRow{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const EditorAutomationRowId lfoRow{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    // The drag targets the LFO node, so its parameter must be the active one.
    QVERIFY(automation_hover::activateParameter(*m_fixture, lfoRow));
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

    // With the fixed nine-identity catalog a structural rebuild no longer
    // changes row membership; the canvas's own rebuild entry is the honest
    // mid-gesture trigger, and it must end the pending gesture before the
    // stale release lands.
    canvas->rebuildRows();
    QCoreApplication::processEvents();
    QVERIFY(!canvas->laneBody(tempoBefore).isEmpty());
    QVERIFY(canvas->laneBody(LaneHandle{}).isEmpty());
    QVERIFY(canvas->laneBody(LaneHandle{9999}).isEmpty());

    automation_hover::mouseRelease(*m_fixture, activation);
    QCoreApplication::processEvents();
    QVERIFY(automation_hover::documentState(*m_fixture) == frozen);
    QVERIFY(!automation_hover::quickWindow(*m_fixture)->mouseGrabberItem());

    QVERIFY(automation_hover::findHandle(*canvas, panRow) == panBefore);
    QVERIFY(automation_hover::findHandle(*canvas, lfoRow) == lfoBefore);
    QVERIFY(automation_hover::rowMatches(*canvas, automation_hover::findHandle(*canvas, panRow),
                                         panRow));
    QVERIFY(automation_hover::rowMatches(*canvas, automation_hover::findHandle(*canvas, lfoRow),
                                         lfoRow));
}

void AutomationHoverTest::targetAndToolProfilesUpdate()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    AutomationCanvas *const canvas = automation_hover::canvas(*m_fixture);
    AutomationPage *const automationPage = automation_hover::page(*m_fixture);
    songview::TimelineInputItem *const plot = automation_hover::plotInput(*m_fixture);
    QQuickWindow *const window = automation_hover::quickWindow(*m_fixture);
    QVERIFY(canvas && automationPage && plot && window);
    ui::MouseHints &hints = ui::MouseHints::instance();

    moveCursorTo(*m_fixture, lane->nodeWindowPosition);
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString nodeText = hints.currentText();

    moveCursorTo(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString sweepText = hints.currentText();
    QVERIFY(sweepText != nodeText);

    // Stationary tool switch through the real PencilToggle key command: the
    // pointer stays on the insertion target, no popup is open, and the
    // background profile reclassifies sweep -> pencil -> sweep in place.
    const QPointer<QAction> pencil = automationPage->pencilModeAction();
    QVERIFY(!pencil.isNull());
    const QKeySequence shortcut = pencil->shortcut();
    QVERIFY(shortcut.count() == 1);
    const QKeyCombination combination = shortcut[0];
    QVERIFY(combination.key() != Qt::Key_unknown);

    QTest::keyClick(window, combination.key(), combination.keyboardModifiers());
    QVERIFY(canvas->pencilMode());
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString pencilText = hints.currentText();
    QVERIFY(pencilText != sweepText);
    QVERIFY(pencilText != nodeText);

    QTest::keyClick(window, combination.key(), combination.keyboardModifiers());
    QVERIFY(!canvas->pencilMode());
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_COMPARE(hints.currentText(), sweepText);

    // The origin phantom is the lane's leftmost point once it sits left of
    // the plot origin; scroll far enough that the real node is outside the
    // hit radius, then hover the phantom's anchor at the plot's left edge.
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QRect body = canvas->laneBody(lane->handle);
    QVERIFY(!body.isEmpty());
    m_fixture->rig->view().setEditorHorizontalScroll(geometry.pointHitRadius + 8.0);
    QCoreApplication::processEvents();
    const auto domain = CoreTimeDefaults::laneDomain(kPanController);
    const qreal phantomY = AutomationProjection::valueY(body, geometry, domain.minimum,
                                                        domain.maximum, lane->heldValue);
    moveCursorTo(*m_fixture,
                 automation_hover::windowPoint(*m_fixture, {qreal(body.left()), phantomY}));
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString phantomText = hints.currentText();
    QVERIFY(phantomText != nodeText);
    QVERIFY(phantomText != sweepText);
    QVERIFY(phantomText != pencilText);
}

void AutomationHoverTest::popupDismissalRecoversHover()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    songview::TimelineInputItem *const plot = automation_hover::plotInput(*m_fixture);
    QQuickWindow *const window = automation_hover::quickWindow(*m_fixture);
    QVERIFY(plot && window);
    ui::MouseHints &hints = ui::MouseHints::instance();
    quick_popup::PromptGuard guard(m_fixture->rig->view());

    // Fresh-hover reference at the recovery target, captured before the popup.
    moveCursorTo(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString sweepText = hints.currentText();

    moveCursorTo(*m_fixture, lane->nodeWindowPosition);
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString nodeText = hints.currentText();
    QVERIFY(nodeText != sweepText);

    rightClick(*m_fixture, lane->nodeWindowPosition);
    const automation_quick::AutomationMenu menu = automation_quick::waitForAutomationMenu(
        m_fixture->rig->view(), QStringLiteral("node menu did not open"));
    QVERIFY2(menu.session && menu.model, qPrintable(menu.diagnostic));
    QTRY_VERIFY(menu.session->owns(hints.currentSource()));
    QVERIFY(hints.currentText().isEmpty());

    // Move between real underlying targets while the popup owns the scope:
    // the underlay stays muted and the session keeps the empty claim.
    moveCursorTo(*m_fixture, lane->insertionWindowPosition);
    QCoreApplication::processEvents();
    QVERIFY(menu.session->owns(hints.currentSource()));
    QVERIFY(hints.currentText().isEmpty());

    // Dismiss through the menu's normal keyboard action without further
    // pointer movement; recovery must republish the target under the cursor,
    // not the pre-popup node description.
    QTest::keyClick(window, Qt::Key_Escape, Qt::NoModifier);
    QTRY_VERIFY(!menu.session->isOpen());
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_COMPARE(hints.currentText(), sweepText);
}

void AutomationHoverTest::liveModifierGesturesCommitAndUndo()
{
    const auto lane = automation_hover::prepareLane(*m_fixture, automation_hover::LaneKind::Cc);
    QVERIFY(lane.has_value());
    AutomationCanvas *const canvas = automation_hover::canvas(*m_fixture);
    AutomationPage *const automationPage = automation_hover::page(*m_fixture);
    songview::TimelineInputItem *const plot = automation_hover::plotInput(*m_fixture);
    QQuickWindow *const window = automation_hover::quickWindow(*m_fixture);
    QVERIFY(canvas && automationPage && plot && window);
    ui::MouseHints &hints = ui::MouseHints::instance();
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const AutomationProjection projection(geometry, automationPage);
    const QRect body = canvas->laneBody(lane->handle);
    QVERIFY(!body.isEmpty());
    const auto frozen = automation_hover::documentState(*m_fixture);

    moveCursorTo(*m_fixture, lane->insertionWindowPosition);
    QTRY_VERIFY(hints.currentSource() == plot);
    QTRY_VERIFY(!hints.currentText().isEmpty());
    const QString sweepText = hints.currentText();

    const QPointF pressViewport = lane->pointerViewport;
    const auto domain = CoreTimeDefaults::laneDomain(kPanController);
    const int laneMinimum = domain.minimum;
    const int laneMaximum = domain.maximum;

    // Live Alt: the sweep endpoint lands on the fine grid while the retained
    // hint keeps the sweep profile for the whole gesture.
    const int activation = geometry.nodeDragActivationDistance + 4;
    const QPoint activationWindow =
        automation_hover::windowPoint(*m_fixture, pressViewport + QPointF(activation, 0.0));
    const QPointF activationContent = plot->mapFromScene(QPointF(activationWindow));
    Tick fineTick = 0;
    QPoint endWindow;
    QPointF effective;
    bool found = false;
    for (int delta = 40; delta <= 400 && !found; delta += 8) {
        const QPoint candidateWindow = automation_hover::windowPoint(
            *m_fixture, pressViewport + QPointF(activation + delta, -20.0));
        const QPointF endContent = plot->mapFromScene(QPointF(candidateWindow));
        if (!plot->bounds().contains(endContent))
            continue;
        const QPointF candidateEffective = pressViewport + (endContent - activationContent);
        const Tick coarse = projection.snapTickAt(candidateEffective.x(), false);
        const Tick fine = projection.snapTickAt(candidateEffective.x(), true);
        if (fine != coarse && candidateEffective.x() > pressViewport.x()) {
            fineTick = fine;
            endWindow = candidateWindow;
            effective = candidateEffective;
            found = true;
        }
    }
    QVERIFY(found);
    const int expectedEndValue =
        std::clamp(qRound(AutomationProjection::valueAtY(body, geometry, laneMinimum, laneMaximum,
                                                         effective.y())),
                   laneMinimum, laneMaximum);

    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, lane->insertionWindowPosition);
    m_fixture->heldButton = Qt::LeftButton;
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, activationWindow);
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::AltModifier, endWindow);
    QCOMPARE(hints.currentText(), sweepText);
    QVERIFY(hints.currentSource() == plot);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::AltModifier, endWindow);
    m_fixture->heldButton = Qt::NoButton;

    DocLanePoint written;
    QVERIFY(m_fixture->document.findLanePoint(0, kPanController, fineTick, &written));
    QCOMPARE(written.value, expectedEndValue);
    QVERIFY(automation_hover::documentState(*m_fixture).smf != frozen.smf);
    m_fixture->document.undoStack()->undo();
    QCoreApplication::processEvents();
    QVERIFY(automation_hover::documentState(*m_fixture).smf == frozen.smf);
    QVERIFY(!m_fixture->document.findLanePoint(0, kPanController, fineTick, nullptr));

    // Press-captured Shift: the ramp commits the straight line between the
    // press anchor and the release endpoint even though the pointer dipped
    // far off that line mid-gesture.
    moveCursorTo(*m_fixture, lane->insertionWindowPosition);
    const Tick startTick = projection.snapTickAt(pressViewport.x(), false);
    const int startValue =
        std::clamp(qRound(AutomationProjection::valueAtY(body, geometry, laneMinimum, laneMaximum,
                                                         pressViewport.y())),
                   laneMinimum, laneMaximum);
    Tick endTick = 0;
    Tick midTick = 0;
    int endValue = 0;
    QPoint rampEndWindow;
    bool rampFound = false;
    std::vector<AutomationGridCell> cells;
    for (int delta = 240; delta <= 480 && !rampFound; delta += 60) {
        const QPoint candidateWindow =
            automation_hover::windowPoint(*m_fixture, pressViewport + QPointF(delta, -40.0));
        const QPointF candidateViewport = plot->mapFromScene(QPointF(candidateWindow));
        if (!plot->bounds().contains(candidateViewport))
            continue;
        const Tick candidateEnd = projection.snapTickAt(candidateViewport.x(), false);
        if (candidateEnd <= startTick)
            continue;
        const auto &crossed =
            projection.snapCellsCrossed(cells, projection.rawTickAt(pressViewport.x()),
                                        projection.rawTickAt(candidateViewport.x()));
        for (const AutomationGridCell &cell : crossed) {
            if (cell.tickBegin > startTick && cell.tickBegin < candidateEnd) {
                midTick = cell.tickBegin;
                break;
            }
        }
        if (midTick == 0)
            continue;
        endTick = candidateEnd;
        endValue = std::clamp(qRound(AutomationProjection::valueAtY(
                                  body, geometry, laneMinimum, laneMaximum, candidateViewport.y())),
                              laneMinimum, laneMaximum);
        rampEndWindow = candidateWindow;
        rampFound = true;
    }
    QVERIFY(rampFound);
    const int expectedMidValue =
        int(std::llround(ui::linearRampValue(double(midTick), double(startTick), double(startValue),
                                             double(endTick), double(endValue))));
    const QPoint dipWindow = automation_hover::windowPoint(
        *m_fixture, {projection.displayX(midTick, plot->devicePixelRatio()),
                     qMin(qreal(body.bottom() - geometry.valuePlotPadding),
                          qreal(body.top() + geometry.valuePlotPadding) + 4.0)});
    const QPointF dipViewport = plot->mapFromScene(QPointF(dipWindow));
    QVERIFY(plot->bounds().contains(dipViewport));
    const int dipValue = std::clamp(qRound(AutomationProjection::valueAtY(
                                        body, geometry, laneMinimum, laneMaximum, dipViewport.y())),
                                    laneMinimum, laneMaximum);
    QVERIFY(dipValue != expectedMidValue);

    QTest::mousePress(window, Qt::LeftButton, Qt::ShiftModifier, lane->insertionWindowPosition);
    m_fixture->heldButton = Qt::LeftButton;
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, dipWindow);
    QCOMPARE(hints.currentText(), sweepText);
    QTest::mouseEvent(QTest::MouseMove, window, Qt::NoButton, Qt::NoModifier, rampEndWindow);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, rampEndWindow);
    m_fixture->heldButton = Qt::NoButton;

    QVERIFY(m_fixture->document.findLanePoint(0, kPanController, startTick, &written));
    QCOMPARE(written.value, startValue);
    QVERIFY(m_fixture->document.findLanePoint(0, kPanController, endTick, &written));
    QCOMPARE(written.value, endValue);
    QVERIFY(m_fixture->document.findLanePoint(0, kPanController, midTick, &written));
    QCOMPARE(written.value, expectedMidValue);
    QVERIFY(written.value != dipValue);

    m_fixture->document.undoStack()->undo();
    QCoreApplication::processEvents();
    QVERIFY(automation_hover::documentState(*m_fixture).smf == frozen.smf);
    QVERIFY(!m_fixture->document.findLanePoint(0, kPanController, midTick, nullptr));
}

int runAutomationHoverCheck(const QStringList &qtArguments)
{
    AutomationHoverTest test;
    QStringList arguments{QStringLiteral("automation-hover")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
