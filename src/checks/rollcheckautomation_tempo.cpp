#include <algorithm>
#include <cstdio>
#include <vector>

#include <QCoreApplication>
#include <QMouseEvent>
#include <QScrollArea>
#include <QScrollBar>

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview.h"

namespace {

void pump()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void sendMouse(QWidget *target, QEvent::Type type, const QPointF &position, Qt::MouseButton button,
               Qt::MouseButtons buttons)
{
    QMouseEvent event(type, position, target->mapToGlobal(position.toPoint()), button, buttons,
                      Qt::NoModifier);
    QCoreApplication::sendEvent(target, &event);
}

bool tempoPinnedToViewport(const AutomationPage &page, const QScrollArea &scroll)
{
    const QRect tempo = page.canvas()->pinnedTempoRect();
    return !tempo.isEmpty() && scroll.viewport() &&
           page.canvas()->mapTo(scroll.viewport(), QPoint(0, tempo.bottom() + 1)).y() ==
               scroll.viewport()->height();
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
    const int collapsedMinimumHeight = page.canvas()->minimumHeight();
    check(collapsedBody.isEmpty() && page.canvas()->pinnedTempoRect().height() == collapsedHeight &&
              tempoPinnedToViewport(page, *scroll),
          QStringLiteral("collapsed Tempo must leave LaneHandle{0} without a body"));

    const QPoint collapsedHeader = tempoHeaderPoint(page);
    sendMouse(page.canvas(), QEvent::MouseButtonPress, collapsedHeader, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, collapsedHeader, Qt::LeftButton,
              Qt::NoButton);
    pump();

    const QRect expandedBody = page.canvas()->laneBody(LaneHandle{0});
    const int expandedMinimumHeight = page.canvas()->minimumHeight();
    check(!expandedBody.isEmpty() && expandedBody.height() == configuredTempoHeight &&
              expandedBody == page.canvas()->pinnedTempoRect() &&
              tempoPinnedToViewport(page, *scroll) &&
              expandedMinimumHeight > collapsedMinimumHeight,
          QStringLiteral("expanded Tempo must use its configured pinned row height"));

    const int scrollBefore = vertical->value();
    const QRect bodyBeforeScroll = page.canvas()->laneBody(LaneHandle{0});
    const QPoint pageBeforeScroll = page.canvas()->mapTo(&page, QPoint(0, bodyBeforeScroll.top()));
    const auto scrollPaintBefore = page.canvas()->diagnostics();
    vertical->setValue(vertical->maximum());
    pump();
    const auto scrollPaintAfter = page.canvas()->diagnostics();
    const quint64 scrollPaintPixels =
        scrollPaintAfter.contentPaintPixelCount - scrollPaintBefore.contentPaintPixelCount;
    const qreal dpr = page.canvas()->devicePixelRatioF();
    const quint64 fullCanvasPixels = quint64(qRound(page.canvas()->width() * dpr)) *
                                     quint64(qRound(page.canvas()->height() * dpr));
    const int scrollAfter = vertical->value();
    const QRect bodyAfterScroll = page.canvas()->laneBody(LaneHandle{0});
    const QPoint pageAfterScroll = page.canvas()->mapTo(&page, QPoint(0, bodyAfterScroll.top()));
    const QRect finalCcBody = page.canvas()->laneBody(LaneHandle{int(rows.size())});
    const int trailingContentBottom = finalCcBody.bottom() + 1 + geometry.addLaneStripHeight;
    const QPoint trailingPageBottom = page.canvas()->mapTo(&page, QPoint(0, trailingContentBottom));
    check(
        scrollAfter > scrollBefore &&
            bodyAfterScroll.top() - bodyBeforeScroll.top() == scrollAfter - scrollBefore &&
            pageAfterScroll.y() == pageBeforeScroll.y() &&
            bodyAfterScroll == page.canvas()->pinnedTempoRect() &&
            tempoPinnedToViewport(page, *scroll) && !finalCcBody.isEmpty() &&
            trailingContentBottom > bodyBeforeScroll.top() &&
            trailingContentBottom <= bodyAfterScroll.top() &&
            trailingPageBottom.y() <= pageAfterScroll.y(),
        QStringLiteral("Tempo must stay pinned while CC and add-lane content scrolls beneath it"));
    check(scrollPaintAfter.contentInvalidationCount > scrollPaintBefore.contentInvalidationCount &&
              scrollPaintPixels > 0 && scrollPaintPixels < fullCanvasPixels,
          QStringLiteral("vertical scroll repainted the full automation canvas cache"));

    const int viewportHeightBeforeResize = scroll->viewport()->height();
    const int scrollBeforeViewportResize = vertical->value();
    const QRect bodyBeforeViewportResize = page.canvas()->laneBody(LaneHandle{0});
    const QPoint tempoPageBottomBeforeResize =
        page.canvas()->mapTo(&page, QPoint(0, bodyBeforeViewportResize.bottom() + 1));
    const QPoint viewportPageBottomBeforeResize =
        scroll->viewport()->mapTo(&page, QPoint(0, viewportHeightBeforeResize));
    page.resize(page.width(), geometry.rowDefaultHeight);
    pump();
    const int viewportHeightAfterResize = scroll->viewport()->height();
    const int scrollAfterViewportResize = vertical->value();
    const QRect bodyAfterViewportResize = page.canvas()->laneBody(LaneHandle{0});
    const QPoint tempoPageBottomAfterResize =
        page.canvas()->mapTo(&page, QPoint(0, bodyAfterViewportResize.bottom() + 1));
    const QPoint viewportPageBottomAfterResize =
        scroll->viewport()->mapTo(&page, QPoint(0, viewportHeightAfterResize));
    check(vertical->maximum() > 0 && scrollAfterViewportResize == scrollBeforeViewportResize &&
              viewportHeightAfterResize < viewportHeightBeforeResize &&
              bodyAfterViewportResize.height() == bodyBeforeViewportResize.height() &&
              bodyAfterViewportResize.top() - bodyBeforeViewportResize.top() ==
                  viewportHeightAfterResize - viewportHeightBeforeResize &&
              bodyAfterViewportResize == page.canvas()->pinnedTempoRect() &&
              tempoPinnedToViewport(page, *scroll) &&
              tempoPageBottomBeforeResize.y() == viewportPageBottomBeforeResize.y() &&
              tempoPageBottomAfterResize.y() == viewportPageBottomAfterResize.y(),
          QStringLiteral("Tempo pin must follow a viewport resize without a scroll gesture"));

    vertical->setValue(vertical->minimum());
    pump();
    const QPoint expandedHeader = tempoHeaderPoint(page);
    sendMouse(page.canvas(), QEvent::MouseButtonPress, expandedHeader, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, expandedHeader, Qt::LeftButton,
              Qt::NoButton);
    pump();
    const QRect recollapsedBody = page.canvas()->laneBody(LaneHandle{0});
    const int recollapsedMinimumHeight = page.canvas()->minimumHeight();
    check(recollapsedBody.isEmpty() && recollapsedMinimumHeight < expandedMinimumHeight &&
              recollapsedMinimumHeight == collapsedMinimumHeight,
          QStringLiteral("collapsing Tempo must remove its body and recover canvas space"));

    const QPoint recollapsedHeader = tempoHeaderPoint(page);
    sendMouse(page.canvas(), QEvent::MouseButtonPress, recollapsedHeader, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, recollapsedHeader, Qt::LeftButton,
              Qt::NoButton);
    pump();
    const QRect reexpandedBody = page.canvas()->laneBody(LaneHandle{0});
    const int reexpandedMinimumHeight = page.canvas()->minimumHeight();
    check(!reexpandedBody.isEmpty() && reexpandedBody.height() == configuredTempoHeight &&
              reexpandedMinimumHeight == expandedMinimumHeight &&
              reexpandedBody == page.canvas()->pinnedTempoRect() &&
              tempoPinnedToViewport(page, *scroll),
          QStringLiteral(
              "re-expanding Tempo must restore its configured height and pinned position"));

    const QPoint reexpandedHeader = tempoHeaderPoint(page);
    sendMouse(page.canvas(), QEvent::MouseButtonPress, reexpandedHeader, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(page.canvas(), QEvent::MouseButtonRelease, reexpandedHeader, Qt::LeftButton,
              Qt::NoButton);
    pump();
    check(page.canvas()->laneBody(LaneHandle{0}).isEmpty() &&
              page.canvas()->minimumHeight() == collapsedMinimumHeight,
          QStringLiteral("temporary Tempo expansion must be reset for later checks"));

    page.resize(page.width(), originalPageHeight);
    view.applyEditorViewState(originalViewState);
    pump();
}
