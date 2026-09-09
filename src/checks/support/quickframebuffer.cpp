#include "checks/support/quickframebuffer.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <memory>

#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QEventLoop>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QString>
#include <QtGlobal>

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

bool showQuickViewport(SongView &view, const QSize &size)
{
    songview::TimelineQuickView *const quickCanvas = view.quickView();
    // A detached canvas has neither scene root nor borrowed window; the
    // explicit scene host attaches both, and this helper never constructs
    // a hidden host.
    QQuickItem *const quickRoot = quickCanvas ? quickCanvas->rootObject() : nullptr;
    QQuickWindow *const quickWindow = quickCanvas ? quickCanvas->quickWindow() : nullptr;
    if (!quickRoot || !quickWindow)
        return false;
    quickWindow->resize(size);
    quickWindow->show();
    pumpQuick();
    return true;
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
    if (error)
        error->clear();
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
    QQuickItem *const quickRoot = quickCanvas->rootObject();
    if (!quickRoot) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas has no attached scene root");
        return {};
    }
    QQuickWindow *const quickWindow = quickCanvas->quickWindow();
    if (!quickWindow) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas has no QQuickWindow");
        return {};
    }

    if (!quickWindow->isVisible()) {
        if (error)
            *error = QStringLiteral("Quick window is hidden; expose it explicitly "
                                    "before capturing");
        return {};
    }
    QDeadlineTimer timeout{1000};
    while (!timeout.hasExpired()) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        if (quickWindow->isExposed())
            break;
    }
    if (timeout.hasExpired()) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline window did not become exposed");
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

    // Canvas-local crop mapped to window-local through the attached root
    // item: the translated viewport may sit anywhere inside the host
    // window, so never assume a zero origin.
    const QRectF windowRect = quickRoot->mapRectToScene(QRectF(viewportRect));
    const qreal devicePixelRatio = quickWindow->devicePixelRatio();
    if (devicePixelRatio <= 0.0) {
        if (error)
            *error = QStringLiteral("Qt Quick window has no device pixel ratio");
        return {};
    }
    const int left = qRound(windowRect.x() * devicePixelRatio);
    const int top = qRound(windowRect.y() * devicePixelRatio);
    const int right = qRound((windowRect.x() + windowRect.width()) * devicePixelRatio);
    const int bottom = qRound((windowRect.y() + windowRect.height()) * devicePixelRatio);
    const QRect crop{left, top, right - left, bottom - top};
    if (crop.width() <= 0 || crop.height() <= 0 || !framebuffer.rect().contains(crop)) {
        if (error)
            *error = QStringLiteral("requested crop falls outside the Qt Quick framebuffer "
                                    "(framebuffer=%1x%2 crop=[%3,%4 %5x%6] requested-viewport="
                                    "[%7,%8 %9x%10] window-rect=[%11,%12 %13x%14] "
                                    "Quick-window-size=%15x%16 dpr=%17)")
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
                         .arg(windowRect.x(), 0, 'f', 1)
                         .arg(windowRect.y(), 0, 'f', 1)
                         .arg(windowRect.width(), 0, 'f', 1)
                         .arg(windowRect.height(), 0, 'f', 1)
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
