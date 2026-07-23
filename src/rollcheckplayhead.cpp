#include "rollcheckplayhead.h"

#include <QCoreApplication>
#include <QEvent>
#include <QObject>
#include <QPaintEvent>
#include <QRegion>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <vector>

#include "core/miditimeline.h"
#include "ui/eventlistview.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"

namespace {

class PaintRegionProbe : public QObject
{
public:
    void clear() { m_regions.clear(); }
    bool repainted(const QWidget *widget) const
    {
        return std::any_of(m_regions.cbegin(), m_regions.cend(),
                           [=](const DirtyRegion &region) {
                               return region.widget == widget;
                           });
    }

    bool repaintedBroadly(const QWidget *widget, int maxWidth) const
    {
        return std::any_of(m_regions.cbegin(), m_regions.cend(),
                           [=](const DirtyRegion &region) {
                               return region.widget == widget
                                   && region.bounds.width() > maxWidth;
                           });
    }

    int maxPaintWidth(const QWidget *widget) const
    {
        int maxW = 0;
        for (const DirtyRegion &region : m_regions) {
            if (region.widget == widget)
                maxW = std::max(maxW, region.bounds.width());
        }
        return maxW;
    }

private:
    struct DirtyRegion
    {
        QWidget *widget;
        QRect bounds;
    };

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Paint) {
            m_regions.push_back(
                {static_cast<QWidget *>(watched),
                 static_cast<QPaintEvent *>(event)->region().boundingRect()});
        }
        return QObject::eventFilter(watched, event);
    }

    std::vector<DirtyRegion> m_regions;
};

songview::PlayheadOverlay *findPlayheadOverlay(SongView &view)
{
    for (QWidget *widget : view.findChildren<QWidget *>()) {
        if (auto *overlay = dynamic_cast<songview::PlayheadOverlay *>(widget))
            return overlay;
    }
    return nullptr;
}

QWidget *findTimeRuler(SongView &view, const songview::PlayheadOverlay *overlay)
{
    if (QWidget *named = view.findChild<QWidget *>(QStringLiteral("timeRuler")))
        return named;
    for (QWidget *child :
         view.findChildren<QWidget *>(QString(), Qt::FindDirectChildrenOnly)) {
        const QRect childArea(child->mapTo(&view, QPoint()), child->size());
        if (child != overlay && child->isVisible() && childArea.top() == 0
            && childArea.width() == view.width())
            return child;
    }
    return nullptr;
}

bool isPlayheadRed(const QColor &pixel, const QColor &playheadColor)
{
    const int colorDistance = std::abs(pixel.red() - playheadColor.red())
        + std::abs(pixel.green() - playheadColor.green())
        + std::abs(pixel.blue() - playheadColor.blue());
    return colorDistance <= 12 && pixel.alpha() > 0;
}

bool isCompositedPlayheadRed(const QColor &pixel, const QColor &playheadColor)
{
    return isPlayheadRed(pixel, playheadColor)
        || (pixel.red() - pixel.green() >= 24
            && pixel.red() - pixel.blue() >= 24);
}

qreal playheadCenter(const QPixmap &pixmap, const QColor &playheadColor)
{
    const QImage image = pixmap.toImage();
    const qreal devicePixelRatio = pixmap.devicePixelRatio();
    qreal weightedX = 0.0;
    qreal totalWeight = 0.0;
    for (int x = 0; x < image.width(); ++x) {
        for (int y = 0; y < image.height(); ++y) {
            const QColor pixel = image.pixelColor(x, y);
            if (isPlayheadRed(pixel, playheadColor) && pixel.alpha() > 80) {
                weightedX += qreal(x) * pixel.alpha();
                totalWeight += pixel.alpha();
            }
        }
    }
    return totalWeight > 0.0 ? weightedX / totalWeight / devicePixelRatio : -1.0;
}

bool hasPlayheadRedLine(const QImage &image, qreal devicePixelRatio,
                        qreal logicalX, const QRect &logicalArea,
                        const QColor &playheadColor)
{
    if (logicalArea.isEmpty())
        return false;

    const int left = std::max(0, qFloor((logicalX - 1.0) * devicePixelRatio));
    const int right = std::min(image.width() - 1,
                               qCeil((logicalX + 1.0) * devicePixelRatio));
    const int top = std::max(0, qFloor(logicalArea.top() * devicePixelRatio));
    const int bottom = std::min(
        image.height() - 1,
        qCeil((logicalArea.bottom() + 1) * devicePixelRatio) - 1);
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
int pixelDistance(const QColor &a, const QColor &b)
{
    return std::abs(a.red() - b.red()) + std::abs(a.green() - b.green())
        + std::abs(a.blue() - b.blue());
}

bool timelineSurfaceHasPlayhead(const QPixmap &background, const QPixmap &rendered,
                                qreal x)
{
    if (background.size() != rendered.size()
        || background.devicePixelRatio() != rendered.devicePixelRatio())
        return false;
    const QImage backgroundImage = background.toImage();
    const QImage renderedImage = rendered.toImage();
    const qreal devicePixelRatio = rendered.devicePixelRatio();
    const int left = std::max(0, qFloor((x - 1.0) * devicePixelRatio));
    const int right = std::min(renderedImage.width() - 1,
                               qCeil((x + 1.0) * devicePixelRatio));
    const int bottom = renderedImage.height() - 1;
    for (int imageX = left; imageX <= right; ++imageX) {
        int consecutivePixels = 0;
        for (int imageY = 0; imageY <= bottom; ++imageY) {
            if (pixelDistance(backgroundImage.pixelColor(imageX, imageY),
                              renderedImage.pixelColor(imageX, imageY)) > 12) {
                if (++consecutivePixels >= 3)
                    return true;
            } else {
                consecutivePixels = 0;
            }
        }
    }
    return false;
}

qreal timelineSurfacePlayheadCenter(const QPixmap &background,
                                    const QPixmap &rendered,
                                    const QColor &playheadColor)
{
    if (background.size() != rendered.size()
        || background.devicePixelRatio() != rendered.devicePixelRatio())
        return -1.0;
    const QImage backgroundImage = background.toImage();
    const QImage renderedImage = rendered.toImage();
    qreal weightedX = 0.0;
    qreal totalWeight = 0.0;
    for (int imageX = 0; imageX < renderedImage.width(); ++imageX) {
        for (int imageY = 0; imageY < renderedImage.height(); ++imageY) {
            const QColor backgroundColor =
                backgroundImage.pixelColor(imageX, imageY);
            const QColor renderedColor = renderedImage.pixelColor(imageX, imageY);
            const qreal red = playheadColor.red() - backgroundColor.red();
            const qreal green = playheadColor.green() - backgroundColor.green();
            const qreal blue = playheadColor.blue() - backgroundColor.blue();
            const qreal magnitude = red * red + green * green + blue * blue;
            if (magnitude == 0.0)
                continue;
            const qreal weight = std::max(
                0.0, ((renderedColor.red() - backgroundColor.red()) * red
                      + (renderedColor.green() - backgroundColor.green()) * green
                      + (renderedColor.blue() - backgroundColor.blue()) * blue)
                         / magnitude);
            weightedX += qreal(imageX) * weight;
            totalWeight += weight;
        }
    }
    return totalWeight > 0.0
        ? weightedX / totalWeight / rendered.devicePixelRatio()
        : -1.0;
}

int playheadRedWidth(const QImage &image, qreal devicePixelRatio,
                     qreal logicalX, int logicalY,
                     const QColor &playheadColor)
{
    const int left = std::max(0, qFloor((logicalX - 4.0) * devicePixelRatio));
    const int right = std::min(image.width() - 1,
                               qCeil((logicalX + 4.0) * devicePixelRatio));
    const int y = std::clamp(qRound(logicalY * devicePixelRatio),
                             0, image.height() - 1);
    int width = 0;
    for (int x = left; x <= right; ++x) {
        if (isCompositedPlayheadRed(image.pixelColor(x, y), playheadColor))
            ++width;
    }
    return width;
}

void processPaints()
{
    for (int i = 0; i < 2; ++i) {
        QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
        QCoreApplication::processEvents();
    }
}

void checkEventListRendering(SongView &view,
                             songview::PlayheadOverlay &marker,
                             QWidget &lanes, const QPixmap &lanesBackground,
                             qreal stoppedMarkerCenter, const QRect &rulerArea,
                             const QColor &playheadColor,
                             QStringList &failures)
{
    auto *events = view.findChild<EventListView *>();
    if (!events) {
        failures.append("EventListView child not found");
        return;
    }
    const qreal playheadX = marker.mapTo(&view, QPoint()).x() + stoppedMarkerCenter;
    view.setEventListVisible(true);
    processPaints();
    const QRect eventListArea =
        QRect(events->mapTo(&view, QPoint()), events->size())
            .intersected(view.rect());
    const QPixmap composedPixmap = view.grab();
    const QImage composedImage = composedPixmap.toImage();
    const qreal composedDpr = composedPixmap.devicePixelRatio();
    if (!events->isVisible() || eventListArea.isEmpty()) {
        failures.append("event list is not visible for the playhead check");
        return;
    }
    if (playheadX < eventListArea.left() || playheadX > eventListArea.right()) {
        failures.append("could not map playhead into the event list");
        return;
    }
    const int triangleHeight = std::min(songview::kPlayheadTriangleHeight + 1,
                                        eventListArea.height());
    const QRect triangleArea(eventListArea.left(), eventListArea.top(),
                             eventListArea.width(), triangleHeight);
    const auto hasLine = [&](const QRect &area) {
        return hasPlayheadRedLine(composedImage, composedDpr, playheadX, area,
                                  playheadColor);
    };
    const auto redWidth = [&](int y) {
        return playheadRedWidth(composedImage, composedDpr, playheadX, y,
                                playheadColor);
    };
    if (!hasLine(triangleArea))
        failures.append("playhead triangle did not render below the time ruler");
    if (redWidth(triangleArea.bottom() - 1) <= redWidth(triangleArea.top()))
        failures.append("playhead triangle did not point up in the event list");
    if (hasLine(QRect(eventListArea.left(),
                      eventListArea.top() + triangleHeight,
                      eventListArea.width(),
                      eventListArea.height() - triangleHeight)))
        failures.append("playhead line overpainted the event list");
    if (hasLine(rulerArea))
        failures.append("playhead rendered in the event-list time ruler");
    const qreal laneX =
        qreal(songview::kGutterW) + view.contentX(view.playheadTick());
    if (!lanes.isVisible()
        || !timelineSurfaceHasPlayhead(lanesBackground, lanes.grab(), laneX)) {
        failures.append("playhead did not render in automation lanes with the "
                        "event list visible");
    }
}

void checkFractionalMovement(SongView &view, const MidiTimeline &timeline,
                             songview::PlayheadOverlay &marker,
                             QWidget &roll, QWidget &lanes, QWidget &strip,
                             const QColor &playheadColor, uint64_t firstTick,
                             QStringList &failures)
{
    uint64_t fractionalStartSample = timeline.sampleForTick(firstTick);
    uint64_t fractionalEndSample = fractionalStartSample;
    double playheadTick = timeline.tickForSample(fractionalStartSample);
    int fractionalBucketX = view.contentX(playheadTick);
    double fractionalStartX = playheadTick * view.pxPerTick();
    const uint64_t fractionalSearchEnd = timeline.sampleForTick(firstTick + 2);
    for (uint64_t sample = fractionalStartSample + 1;
         sample <= fractionalSearchEnd; ++sample) {
        playheadTick = timeline.tickForSample(sample);
        const int x = view.contentX(playheadTick);
        const double exactX = playheadTick * view.pxPerTick();
        if (x != fractionalBucketX) {
            fractionalStartSample = sample;
            fractionalBucketX = x;
            fractionalStartX = exactX;
        } else if (exactX - fractionalStartX >= 0.4) {
            fractionalEndSample = sample;
            break;
        }
    }
    if (fractionalEndSample == fractionalStartSample) {
        failures.append("could not choose fractional playhead positions");
        return;
    }
    view.setPlayheadSample(0, false);
    processPaints();
    const QPixmap rollBackground = roll.grab();
    const QPixmap lanesBackground = lanes.grab();
    const QPixmap stripBackground = strip.grab();
    struct SurfaceCenters
    {
        qreal marker, roll, lanes, strip;
    };
    const auto captureCenters = [&] {
        return SurfaceCenters{
            playheadCenter(marker.grab(), playheadColor),
            timelineSurfacePlayheadCenter(rollBackground, roll.grab(), playheadColor),
            timelineSurfacePlayheadCenter(lanesBackground, lanes.grab(), playheadColor),
            timelineSurfacePlayheadCenter(stripBackground, strip.grab(), playheadColor),
        };
    };
    view.setPlayheadSample(fractionalStartSample, true);
    processPaints();
    const SurfaceCenters start = captureCenters();
    view.setPlayheadSample(fractionalEndSample, true);
    processPaints();
    const SurfaceCenters end = captureCenters();
    const qreal expectedDelta =
        (timeline.tickForSample(fractionalEndSample)
         - timeline.tickForSample(fractionalStartSample)) * view.pxPerTick();
    const auto checkMovement = [&](qreal start, qreal end, const QString &surface) {
        if (start < 0.0 || end < 0.0
            || std::abs((end - start) - expectedDelta) > 0.2) {
            const qreal actualDelta = end - start;
            failures.append(
                QStringLiteral("fractional playhead movement did not match its "
                               "timeline position in %1 (%2 px, expected %3 px)")
                    .arg(surface)
                    .arg(actualDelta, 0, 'f', 2)
                    .arg(expectedDelta, 0, 'f', 2));
        }
    };
    checkMovement(start.marker, end.marker, QStringLiteral("the ruler triangle"));
    checkMovement(start.roll, end.roll, QStringLiteral("the piano roll"));
    checkMovement(start.lanes, end.lanes, QStringLiteral("the automation lanes"));
    checkMovement(start.strip, end.strip, QStringLiteral("the event strip"));
}

void checkPlayheadRendering(SongView &view, const MidiTimeline &timeline,
                            songview::PlayheadOverlay &marker,
                            QStringList &failures)
{
    const int plotWidth = view.width() - songview::kGutterW;
    if (plotWidth <= 64) {
        failures.append("timeline plot is too narrow for the playhead check");
        return;
    }
    const auto tickAtContentX = [&view](int x) {
        return uint64_t(std::ceil(std::max(0.0, view.tickAtContentX(x))));
    };
    const uint64_t firstTick = tickAtContentX(plotWidth / 3);
    const uint64_t secondTick = tickAtContentX(plotWidth / 3 + 32);
    const int firstX = view.contentX(double(firstTick));
    const int secondX = view.contentX(double(secondTick));
    if (firstX < 0 || secondX >= plotWidth || secondX <= firstX
        || secondX - firstX < 2 * songview::kPlayheadGlowRadius + 2
        || secondX - firstX > 40) {
        failures.append("could not choose distinct visible playhead ticks");
        return;
    }
    QWidget *ruler = findTimeRuler(view, &marker);
    if (!ruler) {
        failures.append("time ruler not found for the playhead check");
        return;
    }
    QWidget *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    QWidget *lanes = view.findChild<QWidget *>(QStringLiteral("automationArea"));
    QWidget *strip = view.findChild<QWidget *>(QStringLiteral("otherStrip"));
    if (!roll || !lanes || !strip) {
        failures.append("timeline surfaces not found for the playhead check");
        return;
    }
    view.setPlayheadSample(0, false);
    processPaints();
    const QPixmap rollBackground = roll->grab();
    const QPixmap lanesBackground = lanes->grab();
    const QPixmap stripBackground = strip->grab();

    PaintRegionProbe probe;
    view.installEventFilter(&probe);
    for (QWidget *child : view.findChildren<QWidget *>())
        child->installEventFilter(&probe);
    const QColor playheadColor(226, 66, 66);
    const auto expectedCenter = [&](uint64_t sample) {
        const QPoint timelineOrigin =
            ruler->mapTo(&view, QPoint(songview::kGutterW, 0));
        return qreal(marker.mapFrom(&view, timelineOrigin).x())
            + view.contentX(timeline.tickForSample(sample));
    };
    const auto checkCenter = [&](qreal center, uint64_t sample,
                                 const QString &state) {
        const qreal expected = expectedCenter(sample);
        if (!marker.isVisible() || center < 0.0
            || std::abs(center - expected) > 1.0) {
            failures.append(
                QStringLiteral("%1 playhead did not render at its expected position")
                    .arg(state));
        }
    };
    const auto surfaceX = [&](int timelineOrigin, uint64_t sample) {
        return qreal(timelineOrigin)
            + view.contentX(timeline.tickForSample(sample));
    };
    const auto checkSurfaceLine = [&](QWidget &surface,
                                      const QPixmap &background,
                                      int timelineOrigin, uint64_t sample,
                                      const QString &state,
                                      const QString &name) {
        if (!timelineSurfaceHasPlayhead(background, surface.grab(),
                                        surfaceX(timelineOrigin, sample))) {
            failures.append(
                QStringLiteral("%1 playhead did not render in %2").arg(state).arg(name));
        }
    };
    struct TrackedSurface
    {
        QWidget *widget;
        const QPixmap &background;
        int origin;
        QString name;
    };
    const TrackedSurface trackedSurfaces[] = {
        {roll, rollBackground, songview::kKeyboardW, QStringLiteral("the piano roll")},
        {lanes, lanesBackground, songview::kGutterW, QStringLiteral("the automation lanes")},
        {strip, stripBackground, songview::kGutterW, QStringLiteral("the event strip")},
    };
    const auto checkAllSurfaces = [&](qreal markerCenter, uint64_t sample,
                                      const QString &state) {
        checkCenter(markerCenter, sample, state);
        for (const TrackedSurface &surface : trackedSurfaces) {
            checkSurfaceLine(*surface.widget, surface.background, surface.origin,
                             sample, state, surface.name);
        }
    };
    const uint64_t firstSample = timeline.sampleForTick(firstTick);
    const uint64_t secondSample = timeline.sampleForTick(secondTick);
    view.setPlayheadSample(firstSample, false);
    processPaints();
    const qreal firstMarkerCenter = playheadCenter(marker.grab(), playheadColor);
    checkAllSurfaces(firstMarkerCenter, firstSample, QStringLiteral("stopped"));
    const QRect rulerArea(ruler->mapTo(&view, QPoint()), ruler->size());
    if (firstMarkerCenter >= 0.0) {
        const QPixmap composedPixmap = view.grab();
        const qreal playheadX =
            marker.mapTo(&view, QPoint()).x() + firstMarkerCenter;
        if (hasPlayheadRedLine(composedPixmap.toImage(),
                               composedPixmap.devicePixelRatio(), playheadX,
                               rulerArea, playheadColor)) {
            failures.append("playhead rendered in the time ruler");
        }
    }
    probe.clear();
    view.setPlayheadSample(secondSample, false);
    processPaints();
    // Pad covers glow (surfaces) / triangle, antialias, and toAlignedRect.
    // The triangle band overlaps the roll's top playhead strip, so the
    // overlay can also pick up the wider surface exposure from composition.
    const int maxSurfaceExposureWidth =
        secondX - firstX + 2 * (songview::kPlayheadGlowRadius + 2);
    const int maxOverlayExposureWidth = maxSurfaceExposureWidth;
    const auto failIfBroad = [&](QWidget *widget, int budget, const char *name) {
        if (probe.repaintedBroadly(widget, budget)) {
            failures.append(
                QStringLiteral("playhead move repainted %1 broadly (max %2, budget %3)")
                    .arg(QLatin1String(name))
                    .arg(probe.maxPaintWidth(widget))
                    .arg(budget));
        }
    };
    failIfBroad(roll, maxSurfaceExposureWidth, "the piano roll");
    failIfBroad(lanes, maxSurfaceExposureWidth, "the automation lanes");
    failIfBroad(strip, maxSurfaceExposureWidth, "the event strip");
    failIfBroad(&marker, maxOverlayExposureWidth, "the ruler triangle");
    if (probe.repainted(ruler))
        failures.append("playhead move repainted the time ruler");
    const QPixmap stoppedPixmap = marker.grab();
    const QPixmap stoppedRoll = roll->grab();
    const QPixmap stoppedLanes = lanes->grab();
    const QPixmap stoppedStrip = strip->grab();
    const qreal stoppedMarkerCenter = playheadCenter(stoppedPixmap, playheadColor);
    checkAllSurfaces(stoppedMarkerCenter, secondSample, QStringLiteral("stopped"));
    if (timelineSurfaceHasPlayhead(rollBackground, stoppedRoll,
                                   surfaceX(songview::kKeyboardW, firstSample))) {
        failures.append("playhead move left a stale line on the piano roll");
    }
    if (timelineSurfaceHasPlayhead(lanesBackground, stoppedLanes,
                                   surfaceX(songview::kGutterW, firstSample))) {
        failures.append("playhead move left a stale line on the automation lanes");
    }
    if (timelineSurfaceHasPlayhead(stripBackground, stoppedStrip,
                                   surfaceX(songview::kGutterW, firstSample))) {
        failures.append("playhead move left a stale line on the event strip");
    }
    if (!probe.repainted(roll) || !probe.repainted(lanes) || !probe.repainted(strip)
        || !probe.repainted(&marker)) {
        failures.append("playhead move did not repaint all playhead surfaces");
    }
    view.setPlayheadSample(secondSample, true);
    processPaints();
    const QPixmap playingRoll = roll->grab();
    const QPixmap playingLanes = lanes->grab();
    const QPixmap playingStrip = strip->grab();
    const qreal playingMarkerCenter = playheadCenter(marker.grab(), playheadColor);
    checkAllSurfaces(playingMarkerCenter, secondSample, QStringLiteral("playing"));
    if (playingRoll.toImage() == stoppedRoll.toImage()
        || playingLanes.toImage() == stoppedLanes.toImage()
        || playingStrip.toImage() == stoppedStrip.toImage()) {
        failures.append("playing and stopped timeline-surface playheads rendered "
                        "identically");
    }
    view.setPlayheadSample(secondSample, false);
    processPaints();
    checkEventListRendering(view, marker, *lanes, lanesBackground,
                            stoppedMarkerCenter, rulerArea, playheadColor,
                            failures);
    view.setEventListVisible(false);
    processPaints();
    checkFractionalMovement(view, timeline, marker, *roll, *lanes, *strip,
                            playheadColor, firstTick, failures);
}

} // namespace

QStringList playheadRenderingCheckFailures(SongView &view, const MidiTimeline &timeline)
{
    QStringList failures;
    const bool viewWasVisible = view.isVisible();
    const bool viewHadDontShowOnScreen = view.testAttribute(Qt::WA_DontShowOnScreen);
    if (auto *marker = findPlayheadOverlay(view)) {
        if (!viewWasVisible) {
            view.setAttribute(Qt::WA_DontShowOnScreen);
            view.show();
            processPaints();
            (void)view.grab();
            processPaints();
        }
        checkPlayheadRendering(view, timeline, *marker, failures);
    } else {
        failures.append("unified playhead overlay not found");
    }
    view.setPlayheadSample(0, false);
    processPaints();
    if (!viewWasVisible)
        view.hide();
    view.setAttribute(Qt::WA_DontShowOnScreen, viewHadDontShowOnScreen);
    return failures;
}
