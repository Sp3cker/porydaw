#include "rollcheckplayhead.h"

#include <QCoreApplication>
#include <QEvent>
#include <QMouseEvent>
#include <QObject>
#include <QPaintEvent>
#include <QPainter>
#include <QPixmap>
#include <QRegion>
#include <QWidget>
#include <QtGlobal>
#include <algorithm>
#include <cmath>
#include <vector>

#include "core/miditimeline.h"
#include "ui/eventlistview.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"

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
        int maxWidth = 0;
        for (const DirtyRegion &region : m_regions) {
            if (region.widget == widget)
                maxWidth = std::max(maxWidth, region.bounds.width());
        }
        return maxWidth;
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
            if (isPlayheadRed(image.pixelColor(x, y), playheadColor)) {
                if (++consecutivePixels >= 3)
                    return true;
            } else {
                consecutivePixels = 0;
            }
        }
    }
    return false;
}

int rgbManhattanDistance(const QColor &a, const QColor &b)
{
    return std::abs(a.red() - b.red()) + std::abs(a.green() - b.green())
        + std::abs(a.blue() - b.blue());
}

bool hasVerticalRenderDifferenceAtX(const QPixmap &referenceFrame,
                                    const QPixmap &targetFrame, qreal x,
                                    const QRect &logicalArea)
{
    if (referenceFrame.size() != targetFrame.size()
        || referenceFrame.devicePixelRatio() != targetFrame.devicePixelRatio()
        || logicalArea.isEmpty()) {
        return false;
    }
    const QImage referenceImage = referenceFrame.toImage();
    const QImage targetImage = targetFrame.toImage();
    const qreal devicePixelRatio = targetFrame.devicePixelRatio();
    const int left = std::max(0, qFloor((x - 1.0) * devicePixelRatio));
    const int right = std::min(targetImage.width() - 1,
                               qCeil((x + 1.0) * devicePixelRatio));
    const int top =
        std::max(0, qFloor(logicalArea.top() * devicePixelRatio));
    const int bottom = std::min(
        targetImage.height() - 1,
        qCeil((logicalArea.bottom() + 1) * devicePixelRatio) - 1);
    for (int imageX = left; imageX <= right; ++imageX) {
        int consecutivePixels = 0;
        for (int imageY = top; imageY <= bottom; ++imageY) {
            const int distance = rgbManhattanDistance(
                referenceImage.pixelColor(imageX, imageY),
                targetImage.pixelColor(imageX, imageY));
            if (distance > 12) {
                if (++consecutivePixels >= 3)
                    return true;
            } else {
                consecutivePixels = 0;
            }
        }
    }
    return false;
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
        if (isPlayheadRed(image.pixelColor(x, y), playheadColor))
            ++width;
    }
    return width;
}

void processPaints()
{
    QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
    QCoreApplication::processEvents();
}

QPixmap grabPlayheadOverlay(SongView &view, songview::PlayheadOverlay &marker,
                            QStringList &failures) {
#ifdef __APPLE__
  (void)marker;
  return renderMacPlayheadOverlay(view, failures);
#else
  (void)view;
  (void)failures;
  return marker.grab();
#endif
}

QPixmap grabSongViewWithPlayhead(SongView &view,
                                 songview::PlayheadOverlay &marker,
                                 QStringList &failures) {
  QPixmap pixmap = view.grab();
#ifdef __APPLE__
  const QPixmap overlay = renderMacPlayheadOverlay(view, failures);
  if (!overlay.isNull()) {
    QPainter painter(&pixmap);
    painter.drawPixmap(marker.mapTo(&view, QPoint()), overlay);
  }
#else
  (void)marker;
  (void)failures;
#endif
  return pixmap;
}

void checkPianoRollKeyboardCacheUpdate(QWidget &pianoRoll,
                                        PaintRegionProbe &paintProbe,
                                        QStringList &failures)
{
    QEvent leaveEvent(QEvent::Leave);
    QCoreApplication::sendEvent(&pianoRoll, &leaveEvent);
    processPaints();
    const QImage beforeHover = pianoRoll.grab().toImage();
    processPaints();

    const qulonglong contentPaintsBefore =
        pianoRoll.property("contentPaintCount").toULongLong();
    paintProbe.clear();
    const QPoint hoverPosition(1, pianoRoll.height() / 2);
    QMouseEvent hoverEvent(QEvent::MouseMove, QPointF(hoverPosition),
                           QPointF(pianoRoll.mapToGlobal(hoverPosition)),
                           Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&pianoRoll, &hoverEvent);
    processPaints();

    const bool pianoRollRepainted = paintProbe.repainted(&pianoRoll);
    const int repaintWidth = paintProbe.maxPaintWidth(&pianoRoll);
    const qulonglong contentPaintsAfter =
        pianoRoll.property("contentPaintCount").toULongLong();
    const QImage afterHover = pianoRoll.grab().toImage();

    if (!pianoRollRepainted || repaintWidth > songview::kKeyboardW) {
        failures.append(
            QStringLiteral("partial timeline cache update repainted %1 px "
                           "(budget %2)")
                .arg(repaintWidth)
                .arg(songview::kKeyboardW));
    }
    if (contentPaintsAfter != contentPaintsBefore + 1)
        failures.append("partial timeline cache update painted content more "
                        "than once");
    if (beforeHover.size() != afterHover.size()
        || beforeHover.devicePixelRatio() != afterHover.devicePixelRatio()) {
        failures.append("partial timeline cache update changed image geometry");
        return;
    }

    const int keyboardPixelWidth =
        std::min(afterHover.width(),
                 qCeil(songview::kKeyboardW
                       * afterHover.devicePixelRatio()));
    bool keyboardChanged = false;
    bool timelineChanged = false;
    for (int y = 0; y < afterHover.height(); ++y) {
        for (int x = 0; x < afterHover.width(); ++x) {
            if (beforeHover.pixel(x, y) == afterHover.pixel(x, y))
                continue;
            if (x < keyboardPixelWidth)
                keyboardChanged = true;
            else
                timelineChanged = true;
        }
    }
    if (!keyboardChanged)
        failures.append("partial timeline cache update did not change the "
                        "keyboard");
    if (timelineChanged)
        failures.append("partial timeline cache update changed pixels outside "
                        "the keyboard");
}

void checkEventListRendering(SongView &view,
                             songview::PlayheadOverlay &marker,
                             QWidget &lanes, QWidget &strip,
                             uint64_t referenceSample, uint64_t targetSample,
                             qreal stoppedMarkerCenter,
                             const QRect &rulerArea,
                             const QColor &playheadColor,
                             QStringList &failures)
{
    auto *events = view.findChild<EventListView *>();
    if (!events) {
        failures.append("EventListView child not found");
        return;
    }
    view.setEventListVisible(true);
    processPaints();
    const QRect eventListArea =
        QRect(events->mapTo(&view, QPoint()), events->size())
            .intersected(view.rect());
    view.setPlayheadSample(referenceSample, false);
    processPaints();
    const QPixmap referencePixmap =
        grabSongViewWithPlayhead(view, marker, failures);
    view.setPlayheadSample(targetSample, false);
    processPaints();
    const QPixmap targetPixmap =
        grabSongViewWithPlayhead(view, marker, failures);
    const qreal playheadX =
        marker.mapTo(&view, QPoint()).x() + stoppedMarkerCenter;
    const QImage targetImage = targetPixmap.toImage();
    const qreal targetDpr = targetPixmap.devicePixelRatio();
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
        return hasPlayheadRedLine(targetImage, targetDpr, playheadX, area,
                                  playheadColor);
    };
    const auto redWidth = [&](int y) {
        return playheadRedWidth(targetImage, targetDpr, playheadX, y,
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
    const QRect laneArea =
        QRect(lanes.mapTo(&view, QPoint()), lanes.size())
            .intersected(view.rect());
    if (!lanes.isVisible() || laneArea.isEmpty()
        || !hasVerticalRenderDifferenceAtX(referencePixmap, targetPixmap,
                                           playheadX, laneArea)) {
        failures.append("playhead did not render in automation lanes with the "
                        "event list visible");
    }
    const QRect stripArea =
        QRect(strip.mapTo(&view, QPoint()), strip.size())
            .intersected(view.rect());
    if (!strip.isVisible() || stripArea.isEmpty()
        || !hasVerticalRenderDifferenceAtX(referencePixmap, targetPixmap,
                                           playheadX, stripArea)) {
        failures.append("playhead did not render in the event strip with the "
                        "event list visible");
    }
}

void checkFractionalMovement(SongView &view, const MidiTimeline &timeline,
                             songview::PlayheadOverlay &marker,
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
    view.setPlayheadSample(fractionalStartSample, true);
    processPaints();
    const qreal fractionalStart = playheadCenter(
        grabPlayheadOverlay(view, marker, failures), playheadColor);
    view.setPlayheadSample(fractionalEndSample, true);
    processPaints();
    const qreal fractionalEnd = playheadCenter(
        grabPlayheadOverlay(view, marker, failures), playheadColor);
    const qreal expectedDelta =
        (timeline.tickForSample(fractionalEndSample)
         - timeline.tickForSample(fractionalStartSample)) * view.pxPerTick();
    if (std::abs((fractionalEnd - fractionalStart) - expectedDelta) > 0.2) {
        failures.append("fractional playhead movement did not match its timeline "
                        "position");
    }
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
    const uint64_t secondTick = tickAtContentX(plotWidth / 3 + 12);
    const int firstX = view.contentX(double(firstTick));
    const int secondX = view.contentX(double(secondTick));
    const int moveDelta = secondX - firstX;
    if (firstX < 0 || secondX >= plotWidth
        || moveDelta <= songview::kPlayheadGlowRadius + 1
        || moveDelta > 32) {
        failures.append("could not choose nearby visible playhead ticks");
        return;
    }

    QWidget *ruler = findTimeRuler(view, &marker);
    QWidget *roll = view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    QWidget *lanes = view.findChild<QWidget *>(QStringLiteral("automationArea"));
    std::vector<QWidget *> timelineSurfaces;
    for (QWidget *widget : view.findChildren<QWidget *>()) {
        if (widget->property("estimatedContentCacheBytes").isValid())
            timelineSurfaces.push_back(widget);
    }
    QWidget *strip = nullptr;
    for (QWidget *surface : timelineSurfaces) {
        if (surface != roll && surface != lanes) {
            if (strip) {
                strip = nullptr;
                break;
            }
            strip = surface;
        }
    }
    if (!ruler || !roll || !lanes || !strip || timelineSurfaces.size() != 3) {
        failures.append("timeline surfaces not found for the playhead check");
        return;
    }

    view.setPlayheadSample(0, false);
    for (QWidget *surface : timelineSurfaces)
        surface->update();
    processPaints();
    for (QWidget *surface : timelineSurfaces) {
        if (surface->property("estimatedContentCacheBytes").toULongLong() == 0)
            (void)surface->grab();
    }
    processPaints();
    for (QWidget *surface : timelineSurfaces) {
        if (!surface->property("contentPaintCount").isValid()
            || surface->property("estimatedContentCacheBytes").toULongLong()
                == 0) {
            failures.append(
                QStringLiteral("%1 did not warm its timeline content cache")
                    .arg(surface == roll
                             ? QStringLiteral("piano roll")
                             : surface == lanes
                             ? QStringLiteral("automation lanes")
                             : QStringLiteral("event strip")));
        }
    }

    PaintRegionProbe probe;
    std::vector<QWidget *> observedWidgets{&view};
    view.installEventFilter(&probe);
    for (QWidget *child : view.findChildren<QWidget *>()) {
        observedWidgets.push_back(child);
        child->installEventFilter(&probe);
    }
    checkPianoRollKeyboardCacheUpdate(*roll, probe, failures);
    probe.clear();
    const QColor playheadColor =
        themes::color(themes::Role::song_view_playhead);
    const auto expectedCenter = [&](uint64_t sample) {
      const QPoint timelineOrigin =
          ruler->mapTo(&view, QPoint(songview::kGutterW, 0));
      return qreal(marker.mapFrom(&view, timelineOrigin).x()) +
             view.contentX(timeline.tickForSample(sample));
    };
    const auto checkCenter = [&](qreal center, uint64_t sample,
                                 const QString &state) {
      const qreal expected = expectedCenter(sample);
      if (!marker.isVisible() || center < 0.0 ||
          std::abs(center - expected) > 1.0) {
        failures.append(
            QStringLiteral(
                "%1 playhead did not render at its expected position")
                .arg(state));
      }
    };
    const auto contentPaintCount = [](const QWidget *surface) {
      return surface->property("contentPaintCount").toULongLong();
    };
    const uint64_t firstSample = timeline.sampleForTick(firstTick);
    const uint64_t secondSample = timeline.sampleForTick(secondTick);

    view.setPlayheadSample(firstSample, true);
    processPaints();
    const QPixmap firstComposedPixmap =
        grabSongViewWithPlayhead(view, marker, failures);
    processPaints();
    probe.clear();
    const qulonglong rollContentPaintsBefore = contentPaintCount(roll);
    const qulonglong lanesContentPaintsBefore = contentPaintCount(lanes);
    const qulonglong stripContentPaintsBefore = contentPaintCount(strip);
    view.setPlayheadSample(secondSample, true);
    processPaints();

    const qulonglong rollContentPaintsAfter = contentPaintCount(roll);
    const qulonglong lanesContentPaintsAfter = contentPaintCount(lanes);
    const qulonglong stripContentPaintsAfter = contentPaintCount(strip);
#ifndef __APPLE__
    // Freeze paint-event evidence before any grab/render can create unrelated
    // paint events.
    const bool rollRepainted = probe.repainted(roll);
    const bool lanesRepainted = probe.repainted(lanes);
    const bool stripRepainted = probe.repainted(strip);
    const bool markerRepainted = probe.repainted(&marker);
    const bool rulerRepainted = probe.repainted(ruler);
    const int expectedMoveDistancePx = qCeil(
        std::abs(expectedCenter(secondSample) - expectedCenter(firstSample)));
    const int maxPlayheadExposureWidth =
        expectedMoveDistancePx + 2 * songview::kPlayheadGlowRadius +
        songview::kPlayheadTriangleHalfWidth + 4;
    const auto failIfBroad = [&](QWidget *widget, const QString &name) {
      if (probe.repaintedBroadly(widget, maxPlayheadExposureWidth)) {
        failures.append(QStringLiteral("playhead move broadly repainted %1 "
                                       "(max %2, budget %3)")
                            .arg(name)
                            .arg(probe.maxPaintWidth(widget))
                            .arg(maxPlayheadExposureWidth));
      }
    };
    failIfBroad(roll, QStringLiteral("the piano roll"));
    failIfBroad(lanes, QStringLiteral("the automation lanes"));
    failIfBroad(strip, QStringLiteral("the event strip"));
    failIfBroad(&marker, QStringLiteral("the overlay"));
    for (QWidget *widget : observedWidgets) {
      if (widget == &marker ||
          std::find(timelineSurfaces.cbegin(), timelineSurfaces.cend(),
                    widget) != timelineSurfaces.cend() ||
          !probe.repaintedBroadly(widget, maxPlayheadExposureWidth)) {
        continue;
      }
      const QString widgetName =
          widget->objectName().isEmpty()
              ? QString::fromLatin1(widget->metaObject()->className())
              : widget->objectName();
      failures.append(
          QStringLiteral("playhead move broadly repainted unexpected SongView "
                         "descendant %1 (max %2, budget %3)")
              .arg(widgetName)
              .arg(probe.maxPaintWidth(widget))
              .arg(maxPlayheadExposureWidth));
    }
    if (rulerRepainted)
      failures.append("playhead move repainted the time ruler");
    if (!rollRepainted || !lanesRepainted || !stripRepainted ||
        !markerRepainted) {
      failures.append("playhead move did not repaint all playhead surfaces");
    }
#endif
    if (rollContentPaintsAfter != rollContentPaintsBefore ||
        lanesContentPaintsAfter != lanesContentPaintsBefore ||
        stripContentPaintsAfter != stripContentPaintsBefore) {
      failures.append("playhead move regenerated cached timeline content");
    }

    const QPixmap playingPixmap = grabPlayheadOverlay(view, marker, failures);
    const qreal playingMarkerCenter =
        playheadCenter(playingPixmap, playheadColor);
    checkCenter(playingMarkerCenter, secondSample, QStringLiteral("playing"));
    if (hasPlayheadRedLine(
            playingPixmap.toImage(), playingPixmap.devicePixelRatio(),
            expectedCenter(firstSample), marker.rect(), playheadColor)) {
      failures.append("playhead move left a stale line at its old position");
    }
    const QRect rulerArea(ruler->mapTo(&view, QPoint()), ruler->size());
    if (playingMarkerCenter >= 0.0) {
      const QPixmap composedPixmap =
          grabSongViewWithPlayhead(view, marker, failures);
      const qreal playheadX =
          marker.mapTo(&view, QPoint()).x() + playingMarkerCenter;
      if (hasPlayheadRedLine(composedPixmap.toImage(),
                             composedPixmap.devicePixelRatio(), playheadX,
                             rulerArea, playheadColor)) {
        failures.append("playhead rendered in the time ruler");
      }
      struct VisibleTimelineSurface {
        QWidget *widget;
        const char *name;
      };
      const VisibleTimelineSurface visibleTimelineSurfaces[] = {
          {roll, "the piano roll"},
          {lanes, "the automation lanes"},
          {strip, "the event strip"},
      };
      for (const VisibleTimelineSurface &surface : visibleTimelineSurfaces) {
        const QRect area = QRect(surface.widget->mapTo(&view, QPoint()),
                                 surface.widget->size())
                               .intersected(view.rect());
        if (!surface.widget->isVisible() || area.isEmpty() ||
            !hasVerticalRenderDifferenceAtX(firstComposedPixmap, composedPixmap,
                                            playheadX, area)) {
          failures.append(
              QStringLiteral("playing playhead did not render in %1")
                  .arg(QLatin1String(surface.name)));
        }
      }
    }

    view.setPlayheadSample(secondSample, false);
    processPaints();
    const QPixmap stoppedPixmap = grabPlayheadOverlay(view, marker, failures);
    const qreal stoppedMarkerCenter =
        playheadCenter(stoppedPixmap, playheadColor);
    checkCenter(stoppedMarkerCenter, secondSample, QStringLiteral("stopped"));
    if (playingPixmap.toImage() == stoppedPixmap.toImage())
      failures.append("playing and stopped playheads rendered identically");
    checkEventListRendering(view, marker, *lanes, *strip, firstSample,
                            secondSample, stoppedMarkerCenter, rulerArea,
                            playheadColor, failures);
    view.setEventListVisible(false);
    processPaints();
    checkFractionalMovement(view, timeline, marker, playheadColor, firstTick,
                            failures);
}

} // namespace

QStringList playheadOverlayCheckFailures(SongView &view, const MidiTimeline &timeline)
{
    QStringList failures;
#ifdef __APPLE__
    checkMacPlayheadLifecycle(failures);
#endif
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
