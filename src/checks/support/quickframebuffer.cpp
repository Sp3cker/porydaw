#include "checks/support/quickframebuffer.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <memory>

#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QEventLoop>
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QString>
#include <QWidget>
#include <QtGlobal>

#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::support {

void pumpQuick()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

QRect devicePixelRect(const QImage &image, const QRect &logicalRect)
{
    if (image.isNull())
        return {};

    const qreal dpr = image.devicePixelRatio() > 0.0 ? image.devicePixelRatio() : 1.0;
    const QRectF logicalBounds =
        QRectF(logicalRect).intersected(QRectF(QPointF{}, image.deviceIndependentSize()));
    if (logicalBounds.isEmpty())
        return {};

    const int left = std::clamp(qFloor(logicalBounds.left() * dpr), 0, image.width());
    const int top = std::clamp(qFloor(logicalBounds.top() * dpr), 0, image.height());
    const int right = std::clamp(qCeil(logicalBounds.right() * dpr), 0, image.width());
    const int bottom = std::clamp(qCeil(logicalBounds.bottom() * dpr), 0, image.height());
    return {left, top, right - left, bottom - top};
}

QRect widgetRectIn(const QWidget &widget, const QWidget &owner)
{
    return {widget.mapTo(&owner, QPoint{}), widget.size()};
}

int playheadWidthAt(const QImage &image, int logicalY, qreal logicalX, const QColor &color)
{
    const int halfWidth = songview::playheadTriangleHalfWidth() + layout::space(layout::Space::One);
    int width = 0;
    for (int x = qFloor(logicalX) - halfWidth; x <= qCeil(logicalX) + halfWidth; ++x) {
        if (hasPlayheadPixel(image, QRect{x, logicalY, 1, 1}, color))
            ++width;
    }
    return width;
}

bool isPlayheadPixel(const QColor &actual, const QColor &expected)
{
    constexpr int tolerance = 24;
    return actual.alpha() >= 32 && std::abs(actual.red() - expected.red()) <= tolerance &&
           std::abs(actual.green() - expected.green()) <= tolerance &&
           std::abs(actual.blue() - expected.blue()) <= tolerance;
}

bool hasPlayheadPixel(const QImage &image, const QRect &logicalRect, const QColor &color)
{
    const QRect deviceRect = devicePixelRect(image, logicalRect);
    if (deviceRect.isEmpty())
        return false;
    for (int y = deviceRect.top(); y <= deviceRect.bottom(); ++y) {
        for (int x = deviceRect.left(); x <= deviceRect.right(); ++x) {
            if (isPlayheadPixel(image.pixelColor(x, y), color))
                return true;
        }
    }
    return false;
}

qreal quickRootX(const QQuickItem &item, QQuickItem &root)
{
    return item.mapToItem(&root, QPointF{}).x();
}

TimelineQuickLayerRevisions timelineQuickLayerRevisions(const songview::TimelineQuickScene &scene)
{
    TimelineQuickLayerRevisions revisions{};
    for (std::size_t index = 0; index < revisions.size(); ++index)
        revisions[index] = scene.layer(static_cast<songview::TimelineQuickLayer>(index)).revision;
    return revisions;
}

QImage captureQuickBand(SongView &view, const QRect &rectInSongView, QString *error)
{
    if (error)
        error->clear();
    if (rectInSongView.isEmpty()) {
        if (error)
            *error = QStringLiteral("Qt Quick framebuffer crop is empty");
        return {};
    }

    const auto quickCanvases =
        view.findChildren<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    if (quickCanvases.size() != 1) {
        if (error)
            *error = QStringLiteral("expected exactly one Qt Quick timeline canvas");
        return {};
    }
    songview::TimelineQuickView *const quickCanvas = quickCanvases.constFirst();
    if (quickCanvas->parentWidget() != &view) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas is not a direct SongView child");
        return {};
    }

    QQuickWindow *const quickWindow = quickCanvas->quickWindow();
    if (!quickWindow) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas has no QQuickWindow");
        return {};
    }
    QWidget *const hostWidget = view.window();

    view.show();
    quickCanvas->show();
    view.ensurePolished();
    quickCanvas->ensurePolished();
    quickCanvas->update();

    QDeadlineTimer timeout{1000};
    while (!timeout.hasExpired()) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        QWindow *const hostWindow = hostWidget ? hostWidget->windowHandle() : nullptr;
        if (quickCanvas->isVisibleTo(hostWidget) && hostWindow && hostWindow->isExposed())
            break;
    }
    if (timeout.hasExpired()) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas did not become exposed");
        return {};
    }

    const auto frameRendered = std::make_shared<std::atomic_bool>(false);
    const QMetaObject::Connection frameRenderedConnection = QObject::connect(
        quickWindow, &QQuickWindow::afterRendering, quickWindow,
        [frameRendered] { frameRendered->store(true, std::memory_order_release); },
        Qt::QueuedConnection);
    quickWindow->update();
    QCoreApplication::sendPostedEvents();
    QDeadlineTimer frameTimeout{1000};
    while (!frameRendered->load(std::memory_order_acquire) && !frameTimeout.hasExpired())
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    QObject::disconnect(frameRenderedConnection);
    if (!frameRendered->load(std::memory_order_acquire)) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas did not render a frame");
        return {};
    }

    const QImage framebuffer = quickWindow->grabWindow();
    if (framebuffer.isNull() || framebuffer.size().isEmpty()) {
        if (error)
            *error = QStringLiteral("Qt Quick framebuffer is empty after rendering");
        return {};
    }

    const qreal devicePixelRatio = quickWindow->devicePixelRatio();
    if (devicePixelRatio <= 0.0) {
        if (error)
            *error = QStringLiteral("Qt Quick window has no device pixel ratio");
        return {};
    }
    const QPoint cropOrigin = quickCanvas->mapFrom(&view, rectInSongView.topLeft());
    const int left = qRound(cropOrigin.x() * devicePixelRatio);
    const int top = qRound(cropOrigin.y() * devicePixelRatio);
    const int right = qRound((cropOrigin.x() + rectInSongView.width()) * devicePixelRatio);
    const int bottom = qRound((cropOrigin.y() + rectInSongView.height()) * devicePixelRatio);
    const QRect crop{left, top, right - left, bottom - top};
    if (crop.width() <= 0 || crop.height() <= 0 || !framebuffer.rect().contains(crop)) {
        if (error) {
            const QRect quickHostGeometry = quickCanvas->geometry();
            *error =
                QStringLiteral("requested crop falls outside the Qt Quick framebuffer "
                               "(framebuffer=%1x%2 crop=[%3,%4 %5x%6] requested-SongView=[%7,%8 "
                               "%9x%10] Quick-host=[%11,%12 %13x%14] Quick-window-size=%15x%16 "
                               "dpr=%17)")
                    .arg(framebuffer.width())
                    .arg(framebuffer.height())
                    .arg(crop.x())
                    .arg(crop.y())
                    .arg(crop.width())
                    .arg(crop.height())
                    .arg(rectInSongView.x())
                    .arg(rectInSongView.y())
                    .arg(rectInSongView.width())
                    .arg(rectInSongView.height())
                    .arg(quickHostGeometry.x())
                    .arg(quickHostGeometry.y())
                    .arg(quickHostGeometry.width())
                    .arg(quickHostGeometry.height())
                    .arg(quickWindow->width())
                    .arg(quickWindow->height())
                    .arg(devicePixelRatio, 0, 'f', 2);
        }
        return {};
    }

    QImage bandFramebuffer = framebuffer.copy(crop);
    if (bandFramebuffer.size() != crop.size()) {
        if (error)
            *error = QStringLiteral("Qt Quick framebuffer crop has incorrect dimensions");
        return {};
    }
    bandFramebuffer.setDevicePixelRatio(devicePixelRatio);
    return bandFramebuffer;
}

} // namespace checks::support
