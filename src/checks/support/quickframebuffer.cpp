#include "checks/support/quickframebuffer.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QPoint>
#include <QQuickWidget>
#include <QRect>
#include <QString>
#include <QWidget>
#include <QWindow>
#include <QtGlobal>

#include "ui/songview.h"

namespace checks::support {

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
        view.findChildren<QQuickWidget *>(QStringLiteral("timelineQuickCanvas"));
    if (quickCanvases.size() != 1) {
        if (error)
            *error = QStringLiteral("expected exactly one Qt Quick timeline canvas");
        return {};
    }
    QQuickWidget *const quickCanvas = quickCanvases.constFirst();
    if (quickCanvas->parentWidget() != &view) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas is not a direct SongView child");
        return {};
    }

    view.show();
    quickCanvas->show();
    view.ensurePolished();
    quickCanvas->ensurePolished();
    quickCanvas->update();

    QElapsedTimer timeout;
    timeout.start();
    while (timeout.elapsed() < 1000) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        QWindow *const window = view.windowHandle();
        if (!quickCanvas->isVisible() || !window || !window->isExposed())
            continue;
        const QImage initialFramebuffer = quickCanvas->grabFramebuffer();
        if (initialFramebuffer.isNull() || initialFramebuffer.size().isEmpty())
            continue;
        quickCanvas->update();
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
        const QImage framebuffer = quickCanvas->grabFramebuffer();
        if (framebuffer.isNull() || framebuffer.size().isEmpty())
            continue;

        const qreal devicePixelRatio = quickCanvas->devicePixelRatioF();
        const QPoint cropOrigin = rectInSongView.topLeft() - quickCanvas->mapTo(&view, QPoint{});
        const int left = qRound(cropOrigin.x() * devicePixelRatio);
        const int top = qRound(cropOrigin.y() * devicePixelRatio);
        const int right = qRound((cropOrigin.x() + rectInSongView.width()) * devicePixelRatio);
        const int bottom = qRound((cropOrigin.y() + rectInSongView.height()) * devicePixelRatio);
        const QRect crop{left, top, right - left, bottom - top};
        if (crop.width() <= 0 || crop.height() <= 0 || !framebuffer.rect().contains(crop)) {
            if (error)
                *error = QStringLiteral("requested crop falls outside the Qt Quick framebuffer");
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

    if (error)
        *error = QStringLiteral("Qt Quick framebuffer crop could not be captured");
    return {};
}

QImage captureQuickBand(SongView &view, QWidget &band, QString *error)
{
    return captureQuickBand(view, QRect{band.mapTo(&view, QPoint{}), band.size()}, error);
}

} // namespace checks::support
