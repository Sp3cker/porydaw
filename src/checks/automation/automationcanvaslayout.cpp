// Qt Test coverage for the automation canvas' published layout and input surface.

#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QEventLoop>
#include <QImage>
#include <QQuickItem>
#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>

#include "checks/support/quickframebuffer.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

constexpr uint8_t kPanController = 10;
constexpr uint8_t kLfoController = 21;
constexpr uint8_t kNewLaneController = 11;

void pumpQuick()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents(QEventLoop::AllEvents);
}

QQuickItem *automationScrollbar(songview::TimelineQuickView &quick)
{
    QObject *const root = quick.rootObject();
    return root ? root->findChild<QQuickItem *>(QStringLiteral("drawerAutomationScrollBar"))
                : nullptr;
}

QRectF itemSceneRect(const songview::TimelineInputItem &item)
{
    return {item.mapToScene(QPointF{}), QSizeF(item.width(), item.height())};
}

std::optional<QRectF> textRect(QAbstractItemModel *model, const QString &text)
{
    if (!model)
        return std::nullopt;

    for (int row = 0; row < model->rowCount(); ++row) {
        const QModelIndex index = model->index(row, 0);
        if (model->data(index, songview::TimelineQuickTextModel::TextRole).toString() == text)
            return model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
    }
    return std::nullopt;
}

bool rowsHaveUniqueIds(const std::vector<AutomationRow> &rows)
{
    for (auto row = rows.cbegin(); row != rows.cend(); ++row) {
        if (std::find_if(rows.cbegin(), row, [&row](const AutomationRow &candidate) {
                return candidate.id == row->id;
            }) != row) {
            return false;
        }
    }
    return true;
}

} // namespace

void AutomationEditingTest::automationBandAndInputsExposed()
{
    SongView &view = m_tab->view();
    const std::optional<songview::TimelineBandGeometry> band =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    songview::TimelineQuickView *const quick = view.quickView();
    QObject *const root = quick ? quick->rootObject() : nullptr;
    auto *const gutter = root ? root->findChild<songview::TimelineInputItem *>(
                                    QStringLiteral("timelineAutomationGutterInput"))
                              : nullptr;
    auto *const quickScene = view.findChild<songview::TimelineQuickScene *>();

    QVERIFY(band.has_value());
    QVERIFY(!band->rect.isEmpty());
    QVERIFY(m_automationInput);
    QVERIFY(gutter);
    QVERIFY(quickScene);
    QCOMPARE(m_automationInput->window(), m_quickWindow.data());
    QCOMPARE(gutter->window(), m_quickWindow.data());
}

void AutomationEditingTest::scrollbarChromeTracksZeroRangeResize()
{
    SongView &view = m_tab->view();
    EditorDrawer *const drawer = view.editorDrawer();
    songview::TimelineQuickView *const quick = view.quickView();
    QVERIFY(drawer);
    QVERIFY(quick);

    DrawerChrome &chrome = drawer->chrome();
    const QRectF initialRect = chrome.automationScrollbarRect();
    QQuickItem *const initialItem = automationScrollbar(*quick);
    QVERIFY(initialRect.isValid());
    QVERIFY(!initialRect.isEmpty());
    QCOMPARE(initialRect.width(), qreal(layout::space(layout::Space::Two)));
    QVERIFY(initialItem);
    QVERIFY(initialItem->isVisible());
    QVERIFY(quick->geometry().contains(initialRect.toAlignedRect()));
    QVERIFY(m_quickWindow->mask().isEmpty());

    const std::optional<songview::TimelineBandGeometry> band =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band.has_value());
    const int originalHeight = view.drawerSectionHeight(EditorDrawerPage::Automations);
    const int overhead = std::max(0, originalHeight - band->rect.height());
    const int fittingHeight = std::min(drawer->maximumSectionHeight(),
                                       m_page->canvas()->minimumContentHeight() + overhead);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, fittingHeight);
    pumpQuick();

    const QRectF fittingRect = chrome.automationScrollbarRect();
    QQuickItem *const fittingItem = automationScrollbar(*quick);
    QVERIFY(fittingRect.isValid());
    QVERIFY(!fittingRect.isEmpty());
    QVERIFY(fittingItem);
    QVERIFY(fittingItem->isVisible());
    QCOMPARE(chrome.automationMaximumScrollY(), 0);
    QCOMPARE(chrome.automationViewportHeight(), chrome.automationContentHeight());
    QCOMPARE(qRound(fittingItem->height()), chrome.automationViewportHeight());
    QCOMPARE(fittingItem->property("thumbHeight").toInt(), qRound(fittingItem->height()));

    const int fittingViewportHeight = chrome.automationViewportHeight();
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, drawer->maximumSectionHeight());
    pumpQuick();

    const QRectF resizedRect = chrome.automationScrollbarRect();
    QQuickItem *const resizedItem = automationScrollbar(*quick);
    QVERIFY(resizedRect.isValid());
    QVERIFY(!resizedRect.isEmpty());
    QVERIFY(resizedItem);
    QVERIFY(resizedItem->isVisible());
    QCOMPARE(chrome.automationMaximumScrollY(), 0);
    QVERIFY(chrome.automationViewportHeight() > fittingViewportHeight);
    QCOMPARE(chrome.automationContentHeight(), chrome.automationViewportHeight());
    QCOMPARE(resizedItem->property("contentHeight").toInt(), chrome.automationContentHeight());
    QCOMPARE(resizedItem->property("viewportHeight").toInt(), chrome.automationViewportHeight());
    QCOMPARE(qRound(resizedItem->height()), chrome.automationViewportHeight());
    QCOMPARE(resizedItem->property("thumbHeight").toInt(), qRound(resizedItem->height()));

    view.setDrawerSectionHeight(EditorDrawerPage::Automations, originalHeight);
    pumpQuick();
}

void AutomationEditingTest::layoutAlignsPlotGutterAndRollGrid()
{
    SongView &view = m_tab->view();
    songview::TimelineQuickView *const quick = view.quickView();
    QVERIFY(quick);
    QObject *const root = quick->rootObject();
    QVERIFY(root);
    auto *const gutter = root->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationGutterInput"));
    QVERIFY(gutter);

    const std::optional<songview::TimelineBandGeometry> automation =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    const std::optional<songview::TimelineBandGeometry> roll =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    QVERIFY(automation.has_value());
    QVERIFY(roll.has_value());
    QVERIFY(!automation->plotRect.isEmpty());
    QVERIFY(!roll->plotRect.isEmpty());

    const QRect gutterRect = automation->gutterRect();
    QVERIFY(quick->geometry().contains(gutterRect));
    const QPoint hostOrigin = quick->geometry().topLeft();
    QCOMPARE(automation->plotRect.left(), view.timelineSplitX());
    QCOMPARE(roll->plotRect.left(), view.timelineSplitX());
    QVERIFY(m_tab->view().editorDrawer()->chrome().automationScrollbarRect().right() <=
            automation->rect.left());
    QCOMPARE(itemSceneRect(*m_automationInput),
             QRectF(automation->plotRect.translated(-hostOrigin)));
    QCOMPARE(itemSceneRect(*gutter), QRectF(gutterRect.translated(-hostOrigin)));
    QCOMPARE(qRound(m_automationInput->width()), automation->plotRect.width());
    QCOMPARE(qRound(gutter->width()), gutterRect.width());
    QCOMPARE(qRound(gutter->height()), automation->rect.height());
}

void AutomationEditingTest::rowStackAndGridResolution()
{
    SongView &view = m_tab->view();
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, 0, 7};
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, 0, kPanController};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    const EditorAutomationRowId bend{EditorAutomationRowKind::ControlChange, 0, DOC_CC_BEND};

    m_tab->document().addLanePoint(0, kLfoController, 72, 96);
    m_tab->document().addLanePoint(0, DOC_CC_BEND, 72, 8191);
    m_tab->document().addLanePoint(0, DOC_CC_VOICE, 24, 3);
    EditorViewState state = view.editorViewState();
    state.hideLane(volume);
    state.emptyLanes.insert(pan);
    state.laneRanges[lfo] = 91;
    view.applyEditorViewState(state);
    pumpQuick();

    const auto &rows = m_page->canvas()->rows();
    QVERIFY(!rows.empty());
    QCOMPARE(m_page->canvas()->laneBody({1}).top(), 0);
    QVERIFY(findRow(pan).valid());
    QVERIFY(findRow(lfo).valid());
    QVERIFY(findRow(bend).valid());
    QVERIFY(!findRow(volume).valid());
    QVERIFY(std::none_of(rows.cbegin(), rows.cend(), [](const AutomationRow &row) {
        return row.id.kind == EditorAutomationRowKind::Tempo || row.id.controller == DOC_CC_VOICE;
    }));
    QVERIFY(rows.back().id == bend);
    QCOMPARE(m_page->automationViewState().laneRanges.at(lfo), uint8_t{91});

    const DrawerPageGridState grid = {
        view.grid().gridTicksAt(48),
        view.grid().snapTicksAt(48),
    };
    QVERIFY(grid.gridTicks > 0);
    QVERIFY(grid.snapTicks > 0);
    const uint64_t snap = view.grid().snapTick(30.0, false);
    const uint64_t spacing = view.grid().snapTicksAt(snap);
    QCOMPARE(view.grid().snapTick(double(snap) + 0.1 * double(spacing), false), snap);
    QCOMPARE(view.grid().snapTick(double(snap) + 0.4 * double(spacing), false), snap);
    QVERIFY(view.grid().snapTick(double(snap) + 1.1 * double(spacing), false) != snap);
}

void AutomationEditingTest::middleMousePanSurvivesRefresh()
{
    SongView &view = m_tab->view();
    const QRect body = m_page->canvas()->laneBody(
        findRow(EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kPanController}));
    QVERIFY(!body.isEmpty());

    const QPointF start(160.0, body.center().y());
    const QPointF firstMove = start - QPointF(24.0, 0.0);
    const QPointF secondMove = start - QPointF(48.0, 0.0);
    const qreal dpr = m_automationInput->devicePixelRatio();
    const qreal before = view.camera().displayX(240.0, 0.0, dpr);

    mousePress(*m_automationInput, Qt::MiddleButton, start);
    mouseMove(*m_automationInput, firstMove);
    QCOMPARE(m_automationInput->cursor().shape(), Qt::ClosedHandCursor);
    mouseMove(*m_automationInput, secondMove);
    mouseRelease(*m_automationInput, Qt::MiddleButton, secondMove);

    const qreal after = view.camera().displayX(240.0, 0.0, dpr);
    QVERIFY(qAbs((before - after) - 48.0) < 0.5);
    view.setEditorHorizontalScroll(0.0);
}

void AutomationEditingTest::boundaryHoverAndEmptyLaneUpdateTextAndGrid()
{
    SongView &view = m_tab->view();
    songview::TimelineQuickView *const quick = view.quickView();
    auto *const scene = view.findChild<songview::TimelineQuickScene *>();
    QVERIFY(quick);
    QVERIFY(scene);
    QObject *const root = quick->rootObject();
    QVERIFY(root);
    auto *const gutter = root->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationGutterInput"));
    QVERIFY(gutter);

    m_page->addEmptyLane(0, kLfoController);
    pumpQuick();
    const LaneHandle lfo =
        findRow(EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kLfoController});
    const QRect lfoBody = m_page->canvas()->laneBody(lfo);
    QVERIFY(lfo.valid());
    QVERIFY(!lfoBody.isEmpty());

    const std::optional<songview::TimelineBandGeometry> band =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    QVERIFY(band.has_value());
    QString captureError;
    const QImage baseline = checks::support::captureQuickBand(view, band->rect, &captureError);
    QVERIFY2(!baseline.isNull(), qPrintable(captureError));

    const QPoint boundary(layout::space(layout::Space::One), lfoBody.bottom() + 1);
    mouseMove(*gutter, boundary);
    pumpQuick();
    const QImage hover = checks::support::captureQuickBand(view, band->rect, &captureError);
    QVERIFY2(!hover.isNull(), qPrintable(captureError));
    QCOMPARE(gutter->cursor().shape(), Qt::SplitVCursor);
    QVERIFY(hover == baseline);

    QAbstractItemModel *const textModel = scene->automationTextModel();
    const QString lfoTitle = CCLanes::laneLabel(kLfoController);
    const std::optional<QRectF> lfoBefore = textRect(textModel, lfoTitle);
    const quint64 gridBefore = scene->layer(songview::TimelineQuickLayer::AutomationGrid).revision;
    m_page->addEmptyLane(0, kNewLaneController);
    pumpQuick();

    QVERIFY(lfoBefore.has_value());
    QVERIFY(textRect(textModel, lfoTitle).has_value());
    QVERIFY(textRect(textModel, CCLanes::laneLabel(kNewLaneController)).has_value());
    QVERIFY(scene->layer(songview::TimelineQuickLayer::AutomationGrid).revision > gridBefore);
    QVERIFY(rowsHaveUniqueIds(m_page->canvas()->rows()));
}

void AutomationEditingTest::viewStateSwitchPreservesAutomationState()
{
    SongView &view = m_tab->view();
    const EditorAutomationRowId modulation{EditorAutomationRowKind::ControlChange, 0, 20};
    m_page->addEmptyLane(0, modulation.controller);
    m_page->setLaneRange(modulation, 64);
    const EditorViewState beforeSwitch = view.editorViewState();

    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 240);
    pumpQuick();

    const EditorViewState whileVelocity = view.editorViewState();
    QVERIFY(whileVelocity.laneHeight == beforeSwitch.laneHeight);
    QVERIFY(whileVelocity.laneHeights == beforeSwitch.laneHeights);
    QVERIFY(whileVelocity.laneRanges == beforeSwitch.laneRanges);
    QVERIFY(whileVelocity.emptyLanes == beforeSwitch.emptyLanes);
    QVERIFY(whileVelocity.hiddenLanes() == beforeSwitch.hiddenLanes());

    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 300);
    pumpQuick();
    QVERIFY(view.editorViewState().emptyLanes.contains(modulation));
    QCOMPARE(view.editorViewState().laneRanges.at(modulation), uint8_t{64});
}

void AutomationEditingTest::wheelZoomAndCtrlWheelRowHeightPreserveDrawerState()
{
    SongView &view = m_tab->view();
    songview::TimelineQuickView *const quick = view.quickView();
    QVERIFY(quick);
    QObject *const root = quick->rootObject();
    QVERIFY(root);
    auto *const gutter = root->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationGutterInput"));
    QVERIFY(gutter);

    const QRect body = m_page->canvas()->laneBody(
        findRow(EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kPanController}));
    QVERIFY(!body.isEmpty());
    const QPointF anchor(200.0, body.center().y());
    const double tickBefore = view.camera().tickAtContentX(anchor.x());
    const double zoomBefore = view.camera().pxPerBeat();
    wheel(*m_automationInput, anchor - QPointF(0.0, m_page->verticalScroll()), QPoint(0, 120));
    pumpQuick();
    QVERIFY(view.camera().pxPerBeat() > zoomBefore);
    QVERIFY(std::abs(view.camera().tickAtContentX(anchor.x()) - tickBefore) < 0.001);

    const EditorViewState beforeHeight = view.editorViewState();
    const int laneHeight = m_page->automationViewState().laneHeight;
    wheel(*gutter, QPointF(layout::space(layout::Space::One), body.center().y()), QPoint(0, 120),
          Qt::ControlModifier);
    pumpQuick();
    QVERIFY(m_page->automationViewState().laneHeight > laneHeight);
    const EditorViewState afterHeight = view.editorViewState();
    QVERIFY(afterHeight.velocity == beforeHeight.velocity);
    QVERIFY(afterHeight.automation == beforeHeight.automation);
    QVERIFY(afterHeight.activePage == beforeHeight.activePage);
}
