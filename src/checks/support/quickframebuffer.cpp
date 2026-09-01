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

QImage captureQuickBand(SongView &view, QWidget &band, QString *error)
{
    if (error)
        error->clear();

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

    const auto bands = view.timelineBands();
    if (bands.size() < 2) {
        if (error)
            *error = QStringLiteral("timeline bands not found");
        return {};
    }
    const auto bandRectInSongView = [&view](const QWidget &timelineBand) {
        return QRect{timelineBand.mapTo(&view, QPoint{}), timelineBand.size()};
    };
    const QRect hostUnion =
        bandRectInSongView(bands.front().widget).united(bandRectInSongView(bands.back().widget));
    if (quickCanvas->geometry() != hostUnion) {
        if (error)
            *error = QStringLiteral("Qt Quick timeline canvas does not span the timeline bands");
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
        const QPoint bandOrigin = band.mapTo(&view, QPoint{}) - quickCanvas->mapTo(&view, QPoint{});
        const int left = qRound(bandOrigin.x() * devicePixelRatio);
        const int top = qRound(bandOrigin.y() * devicePixelRatio);
        const int right = qRound((bandOrigin.x() + band.width()) * devicePixelRatio);
        const int bottom = qRound((bandOrigin.y() + band.height()) * devicePixelRatio);
        const QRect crop{left, top, right - left, bottom - top};
        if (crop.width() <= 0 || crop.height() <= 0 || crop.left() < 0 || crop.top() < 0 ||
            crop.x() + crop.width() > framebuffer.width() ||
            crop.y() + crop.height() > framebuffer.height()) {
            if (error)
                *error =
                    QStringLiteral("timeline-band crop falls outside the Qt Quick framebuffer");
            return {};
        }

        QImage bandFramebuffer = framebuffer.copy(crop);
        if (bandFramebuffer.size() != crop.size()) {
            if (error)
                *error = QStringLiteral("timeline-band framebuffer crop has incorrect dimensions");
            return {};
        }
        bandFramebuffer.setDevicePixelRatio(devicePixelRatio);
        return bandFramebuffer;
    }

    if (error)
        *error = QStringLiteral("Qt Quick timeline-band framebuffer could not be captured");
    return {};
}

} // namespace checks::support
