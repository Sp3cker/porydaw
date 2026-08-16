#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPainter>
#include <QWidget>
#include <QtGlobal>

#include "ui/activity/trackactivitymeter.h"
#include "ui/layout.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace {

constexpr int kMeterHeight = 32;
constexpr int kRenderMargin = 5;

class PaintCounter final : public QObject
{
  public:
    int paints = 0;

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::Paint)
            ++paints;
        return false;
    }
};

void drainPaintEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void reset(PaintCounter &parentPaints, PaintCounter &meterPaints)
{
    drainPaintEvents();
    parentPaints.paints = 0;
    meterPaints.paints = 0;
}

bool isOpaque(const QImage &image)
{
    if (image.isNull())
        return false;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (image.pixelColor(x, y).alpha() != 255)
                return false;
        }
    }
    return true;
}

int paintedRowsAt(const QImage &image, int x)
{
    if (image.isNull() || image.height() == 0)
        return 0;

    const QColor bottom = image.pixelColor(x, image.height() - 1);
    int rows = 0;
    for (int y = image.height() - 1; y >= 0; --y) {
        if (image.pixelColor(x, y) != bottom)
            break;
        ++rows;
    }
    return rows;
}

bool transparentOutside(const QImage &image, const QRect &strip)
{
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (!strip.contains(x, y) && image.pixelColor(x, y).alpha() != 0)
                return false;
        }
    }
    return true;
}

} // namespace

int runTrackActivityMeterCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "trackactivitymetercheck: FAIL: %s\n", message);
            ++failures;
        }
    };

    QWidget parent;
    parent.resize(80, 48);
    TrackActivityMeter meter(QColor(Qt::red), &parent);
    meter.setFixedHeight(kMeterHeight);
    meter.move(12, 6);
    parent.show();
    drainPaintEvents();

    check(meter.parentWidget() == &parent, "meter must remain a direct child of its row");
    check(meter.objectName() == QStringLiteral("trackActivityMeter"),
          "meter must retain its object name");
    check(meter.testAttribute(Qt::WA_OpaquePaintEvent), "meter must paint an opaque surface");
    check(meter.testAttribute(Qt::WA_TransparentForMouseEvents),
          "meter must not handle row mouse events");
    check(meter.width() == layout::space(layout::Space::One),
          "meter must retain its fixed strip width");
    check(meter.geometry() == QRect(12, 6, layout::space(layout::Space::One), kMeterHeight),
          "meter must retain its assigned strip geometry");
    check(meter.isVisible(), "meter must be visible with its parent row");

    PaintCounter parentPaints;
    PaintCounter meterPaints;
    parent.installEventFilter(&parentPaints);
    meter.installEventFilter(&meterPaints);
    reset(parentPaints, meterPaints);

    TrackActivityMeter::State active{{0.5f, 0.5f}, true, 1.0f};
    meter.setState(active);
    drainPaintEvents();
    check(meterPaints.paints > 0, "a state change must repaint the meter child");
    check(parentPaints.paints == 0, "a meter state change must not repaint its parent row");

    reset(parentPaints, meterPaints);
    const qreal devicePixelRatio = meter.devicePixelRatioF();
    if (const char *requestedScale = std::getenv("QT_SCALE_FACTOR")) {
        char *end = nullptr;
        const double scale = std::strtod(requestedScale, &end);
        if (requestedScale[0] != '\0' && end && *end == '\0' && scale > 0.0) {
            check(std::abs(devicePixelRatio - scale) < 0.001,
                  "the requested Qt scale must reach the meter widget");
        }
    }
    const float physicalHeight = float(meter.height() * devicePixelRatio);
    check(physicalHeight > 1.0f, "meter must have physical pixels to paint");
    TrackActivityMeter::State withinPixel = active;
    withinPixel.intensity.left += 0.2f / physicalHeight;
    meter.setState(withinPixel);
    drainPaintEvents();
    check(meterPaints.paints == 0,
          "a state change within one physical pixel must not repaint the meter");
    check(parentPaints.paints == 0, "a sub-pixel state change must not repaint the parent row");

    TrackActivityMeter::State acrossPixel = active;
    acrossPixel.intensity.left += 0.7f / physicalHeight;
    meter.setState(acrossPixel);
    drainPaintEvents();
    check(meterPaints.paints > 0,
          "a state change across a physical-pixel boundary must repaint the meter");
    check(parentPaints.paints == 0,
          "a physical-pixel meter change must not repaint the parent row");

    reset(parentPaints, meterPaints);
    TrackActivityMeter::State pausedMode = acrossPixel;
    pausedMode.playing = false;
    meter.setState(pausedMode);
    drainPaintEvents();
    check(meterPaints.paints > 0,
          "a playing/paused mode change must repaint even when the bar heights agree");
    check(parentPaints.paints == 0, "a mode change must not repaint the parent row");

    TrackActivityMeter::State capped{{1.0f, 1.0f}, true, 0.15f};
    meter.setState(capped);
    drainPaintEvents();
    const QImage cappedImage = meter.grab().toImage();
    check(!cappedImage.isNull(), "meter must produce a grabbed frame");
    check(cappedImage.width() == qRound(meter.width() * devicePixelRatio) &&
              cappedImage.height() == qRound(meter.height() * devicePixelRatio),
          "grabbed frame dimensions must be physical-device-pixel dimensions");
    check(std::abs(cappedImage.devicePixelRatio() - devicePixelRatio) < 0.001,
          "grabbed frame must preserve the meter device-pixel ratio");
    check(isOpaque(cappedImage), "opaque meter painting must cover its entire strip");

    const int leftX = cappedImage.width() / 4;
    const int expectedCappedRows = qRound(0.15 * cappedImage.height());
    const int cappedRows = paintedRowsAt(cappedImage, leftX);
    check(cappedRows == expectedCappedRows,
          "playing activity must be capped at 0.15 in physical pixels");

    TrackActivityMeter::State uncapped = capped;
    uncapped.playing = false;
    meter.setState(uncapped);
    drainPaintEvents();
    const QImage pausedImage = meter.grab().toImage();
    const int uncappedRows = paintedRowsAt(pausedImage, pausedImage.width() / 4);
    check(uncappedRows == pausedImage.height() && uncappedRows > cappedRows,
          "paused activity must ignore the playing cap and fill the strip");
    check(cappedImage.pixelColor(leftX, cappedImage.height() / 4) !=
              pausedImage.pixelColor(pausedImage.width() / 4, pausedImage.height() / 4),
          "playing activity must leave a dimmed background behind its capped bar");

    TrackActivityMeter::State stereo{{1.0f, 0.25f}, true, 1.0f};
    meter.setState(stereo);
    drainPaintEvents();
    const QImage stereoImage = meter.grab().toImage();
    const int stereoLeftX = stereoImage.width() / 4;
    const int stereoRightX = stereoImage.width() * 3 / 4;
    const int topY = stereoImage.height() / 4;
    const int bottomY = stereoImage.height() - 1;
    check(stereoImage.pixelColor(stereoLeftX, topY) != stereoImage.pixelColor(stereoRightX, topY),
          "left and right stereo levels must paint independently");
    check(stereoImage.pixelColor(stereoLeftX, bottomY) ==
              stereoImage.pixelColor(stereoRightX, bottomY),
          "both stereo levels must rise from the bottom origin");

    QImage canvas(meter.width() + 2 * kRenderMargin, meter.height() + 2 * kRenderMargin,
                  QImage::Format_ARGB32_Premultiplied);
    canvas.fill(Qt::transparent);
    {
        QPainter painter(&canvas);
        meter.render(&painter, QPoint(kRenderMargin, kRenderMargin));
    }
    check(transparentOutside(canvas,
                             QRect(kRenderMargin, kRenderMargin, meter.width(), meter.height())),
          "meter painting must not escape its strip");

    if (failures == 0)
        std::printf("trackactivitymetercheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
