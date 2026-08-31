#include "rollcheckrendering.h"

#include "rollcheckplayhead.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPixmap>
#include <QWidget>
#include <algorithm>
#include <cmath>

#ifdef __APPLE__
#include <QGuiApplication>
#endif

namespace rollcheck::rendering {
namespace {

bool isPlayheadRed(const QColor &pixel, const QColor &playheadColor)
{
    const int colorDistance = std::abs(pixel.red() - playheadColor.red()) +
                              std::abs(pixel.green() - playheadColor.green()) +
                              std::abs(pixel.blue() - playheadColor.blue());
    return colorDistance <= 12 && pixel.alpha() > 0;
}

bool isCompositedPlayheadRed(const QColor &pixel, const QColor &playheadColor)
{
    return isPlayheadRed(pixel, playheadColor) ||
           (pixel.red() - pixel.green() >= 24 && pixel.red() - pixel.blue() >= 24);
}

} // namespace

bool usesNativeMacPlayheadRenderer()
{
#ifdef __APPLE__
    return QGuiApplication::platformName() == QLatin1String("cocoa") &&
           songview::platformPlayheadRendererEnabled();
#else
    return false;
#endif
}

QPixmap grabPlayheadOverlay(SongView &view, songview::PlayheadOverlay &marker,
                            QStringList &failures)
{
#ifdef __APPLE__
    if (usesNativeMacPlayheadRenderer())
        return renderMacPlayheadOverlay(view, failures);
#else
    (void)view;
    (void)failures;
#endif
    return marker.grab();
}

songview::PlayheadOverlay *findPlayheadOverlay(SongView &view)
{
    for (QWidget *widget : view.findChildren<QWidget *>()) {
        if (auto *overlay = dynamic_cast<songview::PlayheadOverlay *>(widget))
            return overlay;
    }
    return nullptr;
}

qreal playheadCenter(const QPixmap &pixmap, const QColor &playheadColor, int minimumAlpha)
{
    const QImage image = pixmap.toImage();
    const qreal devicePixelRatio = pixmap.devicePixelRatio();
    qreal weightedX = 0.0;
    qreal totalWeight = 0.0;
    for (int x = 0; x < image.width(); ++x) {
        for (int y = 0; y < image.height(); ++y) {
            const QColor pixel = image.pixelColor(x, y);
            if (isPlayheadRed(pixel, playheadColor) && pixel.alpha() > minimumAlpha) {
                weightedX += qreal(x) * pixel.alpha();
                totalWeight += pixel.alpha();
            }
        }
    }
    return totalWeight > 0.0 ? weightedX / totalWeight / devicePixelRatio : -1.0;
}

bool hasPlayheadRedLine(const QImage &image, qreal devicePixelRatio, qreal logicalX,
                        const QRect &logicalArea, const QColor &playheadColor)
{
    if (logicalArea.isEmpty())
        return false;

    const int left = std::max(0, qFloor((logicalX - 1.0) * devicePixelRatio));
    const int right = std::min(image.width() - 1, qCeil((logicalX + 1.0) * devicePixelRatio));
    const int top = std::max(0, qFloor(logicalArea.top() * devicePixelRatio));
    const int bottom =
        std::min(image.height() - 1, qCeil((logicalArea.bottom() + 1) * devicePixelRatio) - 1);
    for (int x = left; x <= right; ++x) {
        int consecutivePixels = 0;
        for (int y = top; y <= bottom; ++y) {
            if (isCompositedPlayheadRed(image.pixelColor(x, y), playheadColor)) {
                if (++consecutivePixels >= 3)
                    return true;
            } else {
                consecutivePixels = 0;
            }
        }
    }
    return false;
}

int playheadRedWidth(const QImage &image, qreal devicePixelRatio, qreal logicalX, int logicalY,
                     const QColor &playheadColor)
{
    const int left = std::max(0, qFloor((logicalX - 4.0) * devicePixelRatio));
    const int right = std::min(image.width() - 1, qCeil((logicalX + 4.0) * devicePixelRatio));
    const int y = std::clamp(qRound(logicalY * devicePixelRatio), 0, image.height() - 1);
    int width = 0;
    for (int x = left; x <= right; ++x) {
        if (isCompositedPlayheadRed(image.pixelColor(x, y), playheadColor))
            ++width;
    }
    return width;
}

// Force queued repaint requests before sampling. Native lifecycle checks use
// their own full queued-event drain.
void processPaints()
{
    QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
    QCoreApplication::processEvents();
}

} // namespace rollcheck::rendering
