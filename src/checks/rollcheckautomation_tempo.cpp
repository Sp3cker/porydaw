#include <algorithm>
#include <cstdio>
#include <vector>

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QScrollArea>
#include <QScrollBar>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

bool tempoPinnedToViewport(const AutomationPage &page)
{
    const QRect tempo = page.canvas()->pinnedTempoRect();
    return !tempo.isEmpty() &&
           tempo.bottom() + 1 - page.verticalScroll() == page.automationViewportSize().height();
}

// Band input delivery: the Quick input item normalizes raw events in
// viewport coordinates, so content-coordinate probes shift by the page
// scroll before each send.
struct AutomationBandInput {
    AutomationPage &page;
    songview::TimelineInputItem &item;

    void mouse(QEvent::Type type, const QPointF &contentPosition, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendMouse(item, type, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  button, buttons, modifiers);
    }
};

songview::TimelineInputItem *automationInputItem(SongView &view)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(
                     QStringLiteral("timelineAutomationInput"))
               : nullptr;
}

QPoint tempoHeaderPoint(const AutomationPage &page)
{
    const QRect tempo = page.canvas()->pinnedTempoRect();
    return {page.canvas()->plotOrigin() / 2, tempo.center().y()};
}

} // namespace

void checkAutomationTempoGeometry(SongView &view, AutomationPage &page,
                                  const std::vector<AutomationRow> &rows, const QString &songLabel,
                                  int &failures)
{
    auto *scroll = page.findChild<QScrollArea *>(QStringLiteral("automationScroll"));
    if (!scroll || !scroll->verticalScrollBar() || !scroll->viewport())
        return;

    const auto check = [&](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-check: %s FAIL %s\n", qUtf8Printable(songLabel),
                     qUtf8Printable(message));
        ++failures;
    };
    const AutomationBandInput band{page, *automationInputItem(view)};
    // Content y in page coordinates: the retained native viewport plus the
    // inverse of the page's vertical scroll.
    const auto contentPageY = [&](int contentY) {
        QWidget *const viewport = page.scrollViewport();
        return viewport ? viewport->mapTo(&page, QPoint(0, contentY - page.verticalScroll())).y()
                        : -1;
    };
    const auto captureAutomationViewport = [&] {
        QString error;
        const QImage image = checks::support::captureQuickBand(view, *scroll->viewport(), &error);
        check(!image.isNull(),
              QStringLiteral("automation viewport framebuffer capture failed: %1").arg(error));
        return image;
    };
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorViewState originalViewState = view.editorViewState();
    EditorViewState configuredViewState = originalViewState;
    const int requestedTempoHeight = geometry.rowDefaultHeight + 5;
    const int configuredTempoHeight =
        std::clamp(requestedTempoHeight, geometry.rowMinimumHeight, geometry.rowMaximumHeight);
    configuredViewState.laneHeights[tempoRow] = requestedTempoHeight;
    view.applyEditorViewState(configuredViewState);
    pump();

    const int originalPageHeight = page.height();
    page.resize(page.width(), 2 * geometry.rowDefaultHeight);
    pump();
    QScrollBar *vertical = scroll->verticalScrollBar();
    vertical->setValue(vertical->minimum());
    pump();

    const int collapsedHeight = geometry.addLaneStripHeight;
    const QRect collapsedBody = page.canvas()->laneBody(LaneHandle{0});
    const int collapsedMinimumHeight = page.canvas()->minimumContentHeight();
    check(collapsedBody.isEmpty() && page.canvas()->pinnedTempoRect().height() == collapsedHeight &&
              tempoPinnedToViewport(page),
          QStringLiteral("collapsed Tempo must leave LaneHandle{0} without a body"));

    const QPoint collapsedHeader = tempoHeaderPoint(page);
    band.mouse(QEvent::MouseButtonPress, collapsedHeader, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, collapsedHeader, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    pump();
    const QRect expandedBody = page.canvas()->laneBody(LaneHandle{0});
    const int expandedMinimumHeight = page.canvas()->minimumContentHeight();
    check(!expandedBody.isEmpty() && expandedBody.height() == configuredTempoHeight &&
              expandedBody == page.canvas()->pinnedTempoRect() && tempoPinnedToViewport(page) &&
              expandedMinimumHeight > collapsedMinimumHeight,
          QStringLiteral("expanded Tempo must use its configured pinned row height"));

    const int scrollBefore = vertical->value();
    const QRect bodyBeforeScroll = page.canvas()->laneBody(LaneHandle{0});
    const QPoint pageBeforeScroll = QPoint(0, contentPageY(bodyBeforeScroll.top()));
    const QImage viewportBeforeScroll = captureAutomationViewport();
    vertical->setValue(vertical->maximum());
    pump();
    const QImage viewportAfterScroll = captureAutomationViewport();
    const int scrollAfter = vertical->value();
    const QRect bodyAfterScroll = page.canvas()->laneBody(LaneHandle{0});
    const QPoint pageAfterScroll = QPoint(0, contentPageY(bodyAfterScroll.top()));
    const QRect finalCcBody = page.canvas()->laneBody(LaneHandle{int(rows.size())});
    const int trailingContentBottom = finalCcBody.bottom() + 1 + geometry.addLaneStripHeight;
    const QPoint trailingPageBottom = QPoint(0, contentPageY(trailingContentBottom));
    check(
        scrollAfter > scrollBefore &&
            bodyAfterScroll.top() - bodyBeforeScroll.top() == scrollAfter - scrollBefore &&
            pageAfterScroll.y() == pageBeforeScroll.y() &&
            bodyAfterScroll == page.canvas()->pinnedTempoRect() && tempoPinnedToViewport(page) &&
            !finalCcBody.isEmpty() && trailingContentBottom > bodyBeforeScroll.top() &&
            trailingContentBottom <= bodyAfterScroll.top() &&
            trailingPageBottom.y() <= pageAfterScroll.y(),
        QStringLiteral("Tempo must stay pinned while CC and add-lane content scrolls beneath it"));
    check(!viewportBeforeScroll.isNull() && viewportAfterScroll != viewportBeforeScroll,
          QStringLiteral("vertical scroll did not update the automation Quick viewport"));

    const int viewportHeightBeforeResize = scroll->viewport()->height();
    const int scrollBeforeViewportResize = vertical->value();
    const QRect bodyBeforeViewportResize = page.canvas()->laneBody(LaneHandle{0});
    const QPoint tempoPageBottomBeforeResize =
        QPoint(0, contentPageY(bodyBeforeViewportResize.bottom() + 1));
    const QPoint viewportPageBottomBeforeResize =
        scroll->viewport()->mapTo(&page, QPoint(0, viewportHeightBeforeResize));
    page.resize(page.width(), geometry.rowDefaultHeight);
    pump();
    const int viewportHeightAfterResize = scroll->viewport()->height();
    const int scrollAfterViewportResize = vertical->value();
    const QRect bodyAfterViewportResize = page.canvas()->laneBody(LaneHandle{0});
    const QPoint tempoPageBottomAfterResize =
        QPoint(0, contentPageY(bodyAfterViewportResize.bottom() + 1));
    const QPoint viewportPageBottomAfterResize =
        scroll->viewport()->mapTo(&page, QPoint(0, viewportHeightAfterResize));
    check(vertical->maximum() > 0 && scrollAfterViewportResize == scrollBeforeViewportResize &&
              viewportHeightAfterResize < viewportHeightBeforeResize &&
              bodyAfterViewportResize.height() == bodyBeforeViewportResize.height() &&
              bodyAfterViewportResize.top() - bodyBeforeViewportResize.top() ==
                  viewportHeightAfterResize - viewportHeightBeforeResize &&
              bodyAfterViewportResize == page.canvas()->pinnedTempoRect() &&
              tempoPinnedToViewport(page) &&
              tempoPageBottomBeforeResize.y() == viewportPageBottomBeforeResize.y() &&
              tempoPageBottomAfterResize.y() == viewportPageBottomAfterResize.y(),
          QStringLiteral("Tempo pin must follow a viewport resize without a scroll gesture"));

    vertical->setValue(vertical->minimum());
    pump();
    const QPoint expandedHeader = tempoHeaderPoint(page);
    band.mouse(QEvent::MouseButtonPress, expandedHeader, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, expandedHeader, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    pump();
    const QRect recollapsedBody = page.canvas()->laneBody(LaneHandle{0});
    const int recollapsedMinimumHeight = page.canvas()->minimumContentHeight();
    check(recollapsedBody.isEmpty() && recollapsedMinimumHeight < expandedMinimumHeight &&
              recollapsedMinimumHeight == collapsedMinimumHeight,
          QStringLiteral("collapsing Tempo must remove its body and recover canvas space"));

    const QPoint recollapsedHeader = tempoHeaderPoint(page);
    band.mouse(QEvent::MouseButtonPress, recollapsedHeader, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, recollapsedHeader, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    pump();
    const QRect reexpandedBody = page.canvas()->laneBody(LaneHandle{0});
    const int reexpandedMinimumHeight = page.canvas()->minimumContentHeight();
    check(!reexpandedBody.isEmpty() && reexpandedBody.height() == configuredTempoHeight &&
              reexpandedMinimumHeight == expandedMinimumHeight &&
              reexpandedBody == page.canvas()->pinnedTempoRect() && tempoPinnedToViewport(page),
          QStringLiteral(
              "re-expanding Tempo must restore its configured height and pinned position"));

    const QPoint reexpandedHeader = tempoHeaderPoint(page);
    band.mouse(QEvent::MouseButtonPress, reexpandedHeader, Qt::LeftButton, Qt::LeftButton,
               Qt::NoModifier);
    band.mouse(QEvent::MouseButtonRelease, reexpandedHeader, Qt::LeftButton, Qt::NoButton,
               Qt::NoModifier);
    pump();
    check(page.canvas()->laneBody(LaneHandle{0}).isEmpty() &&
              page.canvas()->minimumContentHeight() == collapsedMinimumHeight,
          QStringLiteral("temporary Tempo expansion must be reset for later checks"));

    page.resize(page.width(), originalPageHeight);
    view.applyEditorViewState(originalViewState);
    pump();
}
