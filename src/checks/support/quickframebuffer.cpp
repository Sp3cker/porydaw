#include "checks/support/quickframebuffer.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <memory>

#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QEventLoop>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QString>
#include <QtGlobal>

#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::support {

bool waitForQuickFrame(QQuickWindow &window, QString *error)
{
    if (error)
        error->clear();
    if (!window.isVisible()) {
        if (error)
            *error = QStringLiteral("Quick window is hidden; expose it explicitly "
                                    "before capturing");
        return false;
    }
    QDeadlineTimer timeout{1000};
    while (!timeout.hasExpired()) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        if (window.isExposed())
            break;
    }
    if (timeout.hasExpired()) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline window did not become exposed");
        return false;
    }

    const auto frameRendered = std::make_shared<std::atomic_bool>(false);
    const QMetaObject::Connection frameRenderedConnection = QObject::connect(
        &window, &QQuickWindow::afterRendering, &window,
        [frameRendered] { frameRendered->store(true, std::memory_order_release); },
        Qt::QueuedConnection);
    window.update();
    QCoreApplication::sendPostedEvents();
    QDeadlineTimer frameTimeout{1000};
    while (!frameRendered->load(std::memory_order_acquire) && !frameTimeout.hasExpired())
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    QObject::disconnect(frameRenderedConnection);
    if (!frameRendered->load(std::memory_order_acquire)) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas did not render a frame");
        return false;
    }
    return true;
}

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

bool showQuickViewport(SongView &view, const QSize &size)
{
    songview::TimelineQuickView *const quickCanvas = view.quickView();
    QQuickWindow *const quickWindow = quickCanvas ? quickCanvas->quickWindow() : nullptr;
    if (!quickWindow)
        return false;
    quickWindow->resize(size);
    quickWindow->show();
    return waitForQuickFrame(*quickWindow);
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

bool hasSolidPlayheadPixel(const QImage &image, const QRect &logicalRect, const QColor &color)
{
    const QRect deviceRect = devicePixelRect(image, logicalRect);
    if (deviceRect.isEmpty())
        return false;

    const int solidAlpha = std::max(64, color.alpha() / 2);
    for (int y = deviceRect.top(); y <= deviceRect.bottom(); ++y) {
        for (int x = deviceRect.left(); x <= deviceRect.right(); ++x) {
            const QColor actual = image.pixelColor(x, y);
            if (actual.alpha() >= solidAlpha && isPlayheadPixel(actual, color))
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

QImage captureQuickBand(SongView &view, const QRect &viewportRect, QString *error)
{
    if (viewportRect.isEmpty()) {
        if (error)
            *error = QStringLiteral("Qt Quick framebuffer crop is empty");
        return {};
    }

    songview::TimelineQuickView *const quickCanvas = view.quickView();
    if (!quickCanvas) {
        if (error)
            *error = QStringLiteral("SongView has no Qt Quick timeline canvas");
        return {};
    }
    QQuickWindow *const quickWindow = quickCanvas->quickWindow();
    if (!quickWindow) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas has no QQuickWindow");
        return {};
    }

    if (!waitForQuickFrame(*quickWindow, error))
        return {};

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
    const int left = qRound(viewportRect.x() * devicePixelRatio);
    const int top = qRound(viewportRect.y() * devicePixelRatio);
    const int right = qRound((viewportRect.x() + viewportRect.width()) * devicePixelRatio);
    const int bottom = qRound((viewportRect.y() + viewportRect.height()) * devicePixelRatio);
    const QRect crop{left, top, right - left, bottom - top};
    if (crop.width() <= 0 || crop.height() <= 0 || !framebuffer.rect().contains(crop)) {
        if (error)
            *error = QStringLiteral("requested crop falls outside the Qt Quick framebuffer "
                                    "(framebuffer=%1x%2 crop=[%3,%4 %5x%6] requested-viewport="
                                    "[%7,%8 %9x%10] Quick-window-size=%11x%12 dpr=%13)")
                         .arg(framebuffer.width())
                         .arg(framebuffer.height())
                         .arg(crop.x())
                         .arg(crop.y())
                         .arg(crop.width())
                         .arg(crop.height())
                         .arg(viewportRect.x())
                         .arg(viewportRect.y())
                         .arg(viewportRect.width())
                         .arg(viewportRect.height())
                         .arg(quickWindow->width())
                         .arg(quickWindow->height())
                         .arg(devicePixelRatio, 0, 'f', 2);
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
