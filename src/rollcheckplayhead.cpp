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
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

#ifdef __APPLE__
#include <QGuiApplication>
#endif

#include "core/miditimeline.h"
#include "ui/eventlistview.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/timelinesurface.h"

namespace {
#ifdef __APPLE__
bool usesNativeMacPlayheadRenderer()
{
    return QGuiApplication::platformName() == QLatin1String("cocoa");
}
#endif

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

QPixmap grabSongViewWithPlayhead(SongView &view,
                                 songview::PlayheadOverlay &marker,
                                 QStringList &failures)
{
    QPixmap pixmap = view.grab();
#ifdef __APPLE__
    if (usesNativeMacPlayheadRenderer()) {
        const QPixmap overlay = renderMacPlayheadOverlay(view, failures);
        if (!overlay.isNull()) {
            QPainter painter(&pixmap);
            painter.drawPixmap(marker.mapTo(&view, QPoint()), overlay);
        }
    }
#else
    (void)marker;
    (void)failures;
#endif
    return pixmap;
}

class PaintRegionProbe : public QObject
{
public:
    void clear() { m_regions.clear(); }

    bool repainted(const QWidget *widget) const {
      return std::any_of(
          m_regions.cbegin(), m_regions.cend(),
          [=](const DirtyRegion &region) { return region.widget == widget; });
    }

    int maxPaintWidth(const QWidget *widget) const {
      int maxWidth = 0;
      for (const DirtyRegion &region : m_regions) {
        if (region.widget == widget)
          maxWidth = std::max(maxWidth, region.bounds.width());
      }
      return maxWidth;
    }

    bool repaintedAnyBroadly(const QWidget *allowed, int maxWidth) const
    {
        return std::any_of(m_regions.cbegin(), m_regions.cend(),
                           [=](const DirtyRegion &region) {
                               return region.widget != allowed
                                   && region.bounds.width() > maxWidth;
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
    QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
    QCoreApplication::processEvents();
}

void checkPianoRollKeyboardCacheUpdate(songview::TimelineSurface &pianoRoll,
                                       PaintRegionProbe &paintProbe,
                                       QStringList &failures) {
  QEvent leaveEvent(QEvent::Leave);
  QCoreApplication::sendEvent(&pianoRoll, &leaveEvent);
  processPaints();
  const QImage beforeHover = pianoRoll.grab().toImage();
  processPaints();

  const songview::TimelineSurfaceDiagnostics diagnosticsBefore =
      pianoRoll.diagnostics();
  paintProbe.clear();
  const QPoint hoverPosition(1, pianoRoll.height() / 2);
  QMouseEvent hoverEvent(QEvent::MouseMove, QPointF(hoverPosition),
                         QPointF(pianoRoll.mapToGlobal(hoverPosition)),
                         Qt::NoButton, Qt::NoButton, Qt::NoModifier);
  QCoreApplication::sendEvent(&pianoRoll, &hoverEvent);
  processPaints();

  const bool pianoRollRepainted = paintProbe.repainted(&pianoRoll);
  const int repaintWidth = paintProbe.maxPaintWidth(&pianoRoll);
  const songview::TimelineSurfaceDiagnostics diagnosticsAfter =
      pianoRoll.diagnostics();
  const QImage afterHover = pianoRoll.grab().toImage();

  if (!pianoRollRepainted || repaintWidth > songview::kKeyboardW) {
    failures.append(
        QStringLiteral("partial timeline cache update repainted %1 px "
                       "(budget %2)")
            .arg(repaintWidth)
            .arg(songview::kKeyboardW));
  }
  if (diagnosticsAfter.contentPaintCount !=
      diagnosticsBefore.contentPaintCount + 1) {
    failures.append("partial timeline cache update painted content more "
                    "than once");
  }
  if (beforeHover.size() != afterHover.size() ||
      beforeHover.devicePixelRatio() != afterHover.devicePixelRatio()) {
    failures.append("partial timeline cache update changed image geometry");
    return;
  }

  const int keyboardPixelWidth =
      std::min(afterHover.width(),
               qCeil(songview::kKeyboardW * afterHover.devicePixelRatio()));
  const qreal cacheDevicePixelRatio = pianoRoll.devicePixelRatioF();
  const int cacheKeyboardPixelWidth =
      std::min(qCeil(pianoRoll.width() * cacheDevicePixelRatio),
               qCeil(songview::kKeyboardW * cacheDevicePixelRatio));
  const int cachePixelHeight =
      qCeil(pianoRoll.height() * cacheDevicePixelRatio);
  const quint64 maxKeyboardPaintPixels =
      quint64(cacheKeyboardPixelWidth) * quint64(cachePixelHeight);
  if (diagnosticsAfter.contentPaintPixelCount <=
      diagnosticsBefore.contentPaintPixelCount) {
    failures.append("partial timeline cache update painted no content pixels");
  } else if (diagnosticsAfter.contentPaintPixelCount -
                 diagnosticsBefore.contentPaintPixelCount >
             maxKeyboardPaintPixels) {
    failures.append(
        QStringLiteral("partial timeline cache update painted %1 device "
                       "pixels (budget %2)")
            .arg(diagnosticsAfter.contentPaintPixelCount -
                 diagnosticsBefore.contentPaintPixelCount)
            .arg(maxKeyboardPaintPixels));
  }
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

void checkEventListRendering(SongView &view, songview::PlayheadOverlay &marker,
                             qreal stoppedMarkerCenter, const QRect &rulerArea,
                             const QColor &playheadColor,
                             QStringList &failures) {
  auto *events = view.findChild<EventListView *>();
  if (!events) {
    failures.append("EventListView child not found");
    return;
  }
  const QPoint markerOffset = marker.mapTo(&view, QPoint());
  const qreal playheadXInView = markerOffset.x() + stoppedMarkerCenter;
  view.setEventListVisible(true);
  processPaints();
  const QRect eventListArea =
      QRect(events->mapTo(&view, QPoint()), events->size())
          .intersected(view.rect());
  const QPixmap overlayPixmap = grabPlayheadOverlay(view, marker, failures);
  if (overlayPixmap.isNull())
    return;
  const QImage overlayImage = overlayPixmap.toImage();
  const qreal overlayDpr = overlayPixmap.devicePixelRatio();
  if (!events->isVisible() || eventListArea.isEmpty()) {
    failures.append("event list is not visible for the playhead check");
    return;
  }
  if (playheadXInView < eventListArea.left() ||
      playheadXInView > eventListArea.right()) {
    failures.append("could not map playhead into the event list");
    return;
  }
  const QRect eventListOverlayArea = eventListArea.translated(-markerOffset);
  const int triangleHeight = std::min(songview::kPlayheadTriangleHeight + 1,
                                      eventListOverlayArea.height());
  const QRect triangleArea(eventListOverlayArea.left(),
                           eventListOverlayArea.top(),
                           eventListOverlayArea.width(), triangleHeight);
  const auto hasLine = [&](const QRect &area) {
    return hasPlayheadRedLine(overlayImage, overlayDpr, stoppedMarkerCenter,
                              area, playheadColor);
  };
  const auto redWidth = [&](int y) {
    return playheadRedWidth(overlayImage, overlayDpr, stoppedMarkerCenter, y,
                            playheadColor);
  };
  if (!hasLine(triangleArea))
    failures.append("playhead triangle did not render below the time ruler");
  if (redWidth(triangleArea.bottom() - 1) <= redWidth(triangleArea.top()))
    failures.append("playhead triangle did not point up in the event list");
  if (hasLine(QRect(eventListOverlayArea.left(),
                    eventListOverlayArea.top() + triangleHeight,
                    eventListOverlayArea.width(),
                    eventListOverlayArea.height() - triangleHeight))) {
    failures.append("playhead line overpainted the event list");
  }
  if (hasLine(rulerArea.translated(-markerOffset)))
    failures.append("playhead rendered in the event-list time ruler");
  const QRect upperTimelineArea =
      QRect(0, 0, view.width(), eventListArea.top()).translated(-markerOffset);
  const QRect lowerTimelineArea =
      QRect(0, eventListArea.bottom() + 1, view.width(),
            view.height() - eventListArea.bottom() - 1)
          .translated(-markerOffset);
  if (!hasLine(upperTimelineArea) && !hasLine(lowerTimelineArea)) {
    failures.append("playhead overlay did not render on visible timeline "
                    "surfaces");
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
    uint64_t firstTick = 0;
    uint64_t firstSample = 0, secondSample = 0;
    int firstX = 0, secondX = 0;
    bool foundInterval = false;
    for (int x = plotWidth / 3; x + 12 < plotWidth; ++x) {
        const uint64_t candidateFirstTick = tickAtContentX(x);
        const uint64_t candidateSecondTick = tickAtContentX(x + 12);
        const int candidateFirstX = view.contentX(double(candidateFirstTick));
        const int candidateSecondX = view.contentX(double(candidateSecondTick));
        if (candidateFirstX < 0 || candidateSecondX >= plotWidth
            || candidateSecondX <= candidateFirstX
            || candidateSecondX - candidateFirstX > 32)
            continue;
        // Skip intervals straddling a program change: the frames at the two
        // probe positions would then differ beyond the playhead itself.
        const uint64_t candidateFirstSample = timeline.sampleForTick(candidateFirstTick);
        const uint64_t candidateSecondSample = timeline.sampleForTick(candidateSecondTick);
        const uint64_t firstDisplayTick =
            uint64_t(timeline.tickForSample(candidateFirstSample));
        const uint64_t secondDisplayTick =
            uint64_t(timeline.tickForSample(candidateSecondSample));
        const bool crossesProgramChange = std::any_of(
            timeline.events.cbegin(), timeline.events.cend(),
            [=](const TimelineEvent &event) {
                return event.type == 0xC && event.tick > firstDisplayTick
                    && event.tick <= secondDisplayTick;
            });
        if (crossesProgramChange)
            continue;
        firstTick = candidateFirstTick;
        firstSample = candidateFirstSample;
        secondSample = candidateSecondSample;
        firstX = candidateFirstX;
        secondX = candidateSecondX;
        foundInterval = true;
        break;
    }
    if (!foundInterval) {
        failures.append("could not choose nearby visible playhead ticks");
        return;
    }

    const songview::TimelineSurfaces surfaces = view.timelineSurfaces();
    struct CachedSurfaceCheck {
      const char *name;
      songview::CachedTimelineBand band;
    };
    const std::array<CachedSurfaceCheck, 3> cachedSurfaces{{
        {"piano roll", surfaces.roll},
        {"automation lanes", surfaces.lanes},
        {"event strip", surfaces.strip},
    }};

    PaintRegionProbe probe;
    view.installEventFilter(&probe);
    for (QWidget *child : view.findChildren<QWidget *>())
        child->installEventFilter(&probe);
    const QColor playheadColor(226, 66, 66);
    const auto expectedCenter = [&](uint64_t sample) {
      const QPoint timelineOrigin = surfaces.ruler.widget.mapTo(
          &view, QPoint(surfaces.ruler.timelineOrigin, 0));
      return qreal(marker.mapFrom(&view, timelineOrigin).x()) +
             view.contentX(timeline.tickForSample(sample));
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

    view.setPlayheadSample(0, false);
    for (const CachedSurfaceCheck &surface : cachedSurfaces)
      surface.band.widget.update();
    processPaints();
    for (const CachedSurfaceCheck &surface : cachedSurfaces) {
      if (surface.band.widget.diagnostics().estimatedContentCacheBytes == 0)
        (void)surface.band.widget.grab();
    }
    processPaints();
    for (const CachedSurfaceCheck &surface : cachedSurfaces) {
      const songview::TimelineSurfaceDiagnostics diagnostics =
          surface.band.widget.diagnostics();
      const QString surfaceName = QString::fromLatin1(surface.name);
      if (diagnostics.contentPaintCount == 0 ||
          diagnostics.contentPaintPixelCount == 0) {
        failures.append(
            QStringLiteral("%1 did not warm its timeline content cache")
                .arg(surfaceName));
      }

      const qreal dpr = surface.band.widget.devicePixelRatioF();
      const quint64 expectedCacheBytes =
          quint64(qCeil(surface.band.widget.width() * dpr)) *
          quint64(qCeil(surface.band.widget.height() * dpr)) * quint64(4);
      constexpr quint64 maxEstimatedCacheBytes = 256ULL * 1024ULL * 1024ULL;
      if (expectedCacheBytes > 0 &&
          expectedCacheBytes <= maxEstimatedCacheBytes &&
          diagnostics.estimatedContentCacheBytes != expectedCacheBytes) {
        failures.append(
            QStringLiteral("%1 reported %2 estimated cache bytes (expected %3)")
                .arg(surfaceName)
                .arg(diagnostics.estimatedContentCacheBytes)
                .arg(expectedCacheBytes));
      }
    }

    checkPianoRollKeyboardCacheUpdate(surfaces.roll.widget, probe, failures);
    probe.clear();
    const auto diagnosticsBefore = [&cachedSurfaces] {
      std::array<songview::TimelineSurfaceDiagnostics, 3> diagnostics;
      for (std::size_t i = 0; i < diagnostics.size(); ++i)
        diagnostics[i] = cachedSurfaces[i].band.widget.diagnostics();
      return diagnostics;
    }();
    view.setPlayheadSample(firstSample, false);
    processPaints();
    const qreal firstMarkerCenter = playheadCenter(
        grabPlayheadOverlay(view, marker, failures), playheadColor);
    checkCenter(firstMarkerCenter, firstSample, QStringLiteral("stopped"));
    const QRect rulerArea(surfaces.ruler.widget.mapTo(&view, QPoint()),
                          surfaces.ruler.widget.size());
    if (firstMarkerCenter >= 0.0) {
        const QPixmap composedPixmap =
            grabSongViewWithPlayhead(view, marker, failures);
        const qreal playheadX =
            marker.mapTo(&view, QPoint()).x() + firstMarkerCenter;
        if (hasPlayheadRedLine(composedPixmap.toImage(),
                               composedPixmap.devicePixelRatio(), playheadX,
                               rulerArea, playheadColor)) {
            failures.append("playhead rendered in the time ruler");
        }
    }
    view.setPlayheadSample(firstSample, true);
    processPaints();
    probe.clear();
#ifdef __APPLE__
    if (usesNativeMacPlayheadRenderer() &&
        renderMacPlayheadOverlay(view, failures).isNull())
      return;
#endif
    view.setPlayheadSample(secondSample, true);
    processPaints();
    const auto diagnosticsAfter = [&cachedSurfaces] {
      std::array<songview::TimelineSurfaceDiagnostics, 3> diagnostics;
      for (std::size_t i = 0; i < diagnostics.size(); ++i)
        diagnostics[i] = cachedSurfaces[i].band.widget.diagnostics();
      return diagnostics;
    }();
    bool cacheRegenerated = false;
    for (std::size_t i = 0; i < diagnosticsBefore.size(); ++i) {
      if (diagnosticsAfter[i] != diagnosticsBefore[i]) {
        cacheRegenerated = true;
        break;
      }
    }
    if (cacheRegenerated)
      failures.append("playhead move regenerated cached timeline content");
    // Dirty strip: move delta + full glow diameter + full triangle width.
    const int maxPlayheadExposureWidth =
        secondX - firstX + 2 * songview::kPlayheadGlowRadius
        + 2 * songview::kPlayheadTriangleHalfWidth;
    const bool overlayPaintedBroadly =
        probe.repaintedBroadly(&marker, maxPlayheadExposureWidth);
    const bool anotherWidgetPaintedBroadly =
        probe.repaintedAnyBroadly(&marker, maxPlayheadExposureWidth);
    const QPixmap playingPixmap =
        grabPlayheadOverlay(view, marker, failures);
    const qreal playingMarkerCenter = playheadCenter(playingPixmap, playheadColor);
    checkCenter(playingMarkerCenter, secondSample, QStringLiteral("playing"));
    if (overlayPaintedBroadly)
        failures.append("playhead move repainted the overlay broadly");
    if (anotherWidgetPaintedBroadly)
        failures.append("playhead move repainted another timeline widget broadly");
    view.setPlayheadSample(secondSample, false);
    processPaints();
    const QPixmap stoppedPixmap =
        grabPlayheadOverlay(view, marker, failures);
    const qreal stoppedMarkerCenter = playheadCenter(stoppedPixmap, playheadColor);
    checkCenter(stoppedMarkerCenter, secondSample, QStringLiteral("stopped"));
    if (playingPixmap.toImage() == stoppedPixmap.toImage())
        failures.append("playing and stopped playheads rendered identically");
    checkEventListRendering(view, marker, stoppedMarkerCenter, rulerArea,
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
    if (usesNativeMacPlayheadRenderer())
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
