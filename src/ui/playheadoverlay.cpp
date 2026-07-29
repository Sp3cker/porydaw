#include "playheadoverlay.h"
#include "theme/themeruntime.h"

#include <QDebug>
#include <QEvent>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <algorithm>

namespace songview {

#ifndef PORYDAW_USE_NATIVE_PLAYHEAD
std::unique_ptr<PlayheadBackend> createPlayheadBackend(QWidget &) { return {}; }
#endif

PlayheadOverlay::PlayheadOverlay(QWidget *owner, TimelineSurfaces surfaces)
    : QWidget(owner), m_surfaces(surfaces),
      m_color(themes::color(themes::Role::song_view_playhead)) {
  Q_ASSERT(owner);

  setAttribute(Qt::WA_TransparentForMouseEvents);
  setAttribute(Qt::WA_NoSystemBackground);

  observeSurfaceGeometry();

  synchronizeGeometry();
  show();
}

PlayheadOverlay::~PlayheadOverlay() = default;

void PlayheadOverlay::observeSurfaceGeometry() {
  const auto observe = [this](QWidget *surface) {
    for (QWidget *widget = surface; widget; widget = widget->parentWidget()) {
      widget->installEventFilter(this);
    }
  };
  observe(&m_surfaces.ruler.widget);
  observe(&m_surfaces.roll.widget);
  observe(&m_surfaces.lanes.widget);
  observe(&m_surfaces.strip.widget);
}

bool PlayheadOverlay::eventFilter(QObject *, QEvent *event) {
  switch (event->type()) {
  case QEvent::Show:
  case QEvent::WinIdChange:
    synchronizeGeometry();
    break;
  case QEvent::ParentChange:
    observeSurfaceGeometry();
    synchronizeGeometry();
    break;
  case QEvent::Hide:
  case QEvent::Move:
  case QEvent::Resize:
  case QEvent::LayoutRequest:
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
  case QEvent::DevicePixelRatioChange:
#else
  case QEvent::ScreenChangeInternal:
#endif
    synchronizeGeometry();
    break;
  default:
    break;
  }
  return false;
}

void PlayheadOverlay::changeEvent(QEvent *event) {
  QWidget::changeEvent(event);
  switch (event->type()) {
  case QEvent::ApplicationPaletteChange:
  case QEvent::PaletteChange:
  case QEvent::StyleChange: {
    const QColor newColor = themes::color(themes::Role::song_view_playhead);
    if (m_color != newColor) {
      m_color = newColor;
      ++m_staticGeneration;
      synchronizeBackend();
    }
    break;
  }
  default:
    break;
  }
}

void PlayheadOverlay::paintEvent(QPaintEvent *event) {
  if (m_backendApplied) {
    (void)event;
    return;
  }
  if (!m_visible || m_playheadGeometry.isEmpty()) {
    return;
  }

  QPainter painter(this);
  painter.setRenderHint(QPainter::Antialiasing);

  const qreal x = finalX();
  const int top = m_playheadGeometry.top();
  const int height = m_playheadGeometry.height();

  if (!m_visibleSurfaceRegion.isEmpty()) {
    painter.setClipRegion(m_visibleSurfaceRegion);

    const qreal leftExtent = playheadGlowLeftExtent(m_playing);
    const qreal rightExtent = playheadGlowRightExtent(m_playing);
    const qreal peakAlpha = playheadPeakAlpha(m_playing);

    if (leftExtent > 0.0) {
      QLinearGradient gradient(x - leftExtent, 0, x, 0);
      for (const auto &stop : kPlayheadGradientStops) {
        QColor stopColor = m_color;
        stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
        gradient.setColorAt(stop.position, stopColor);
      }
      painter.fillRect(QRectF(x - leftExtent, top, leftExtent, height),
                       gradient);
    }

    if (!m_playing && rightExtent > 0.0) {
      QLinearGradient gradient(x + rightExtent, 0, x, 0);
      for (const auto &stop : kPlayheadGradientStops) {
        QColor stopColor = m_color;
        stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
        gradient.setColorAt(stop.position, stopColor);
      }
      painter.fillRect(QRectF(x, top, rightExtent, height), gradient);
    }

    QPen corePen(m_color, kPlayheadLineWidth, Qt::SolidLine, Qt::FlatCap);
    painter.setPen(corePen);
    painter.drawLine(QPointF(x, top), QPointF(x, top + height));
  }

  if (!m_triangleClip.isEmpty()) {
    painter.setClipRect(m_triangleClip, Qt::ReplaceClip);

    QPainterPath path;
    if (!m_trianglePointsUp) {
      path.moveTo(x - kPlayheadTriangleHalfWidth, top);
      path.lineTo(x + kPlayheadTriangleHalfWidth, top);
      path.lineTo(x, top + kPlayheadTriangleHeight);
      path.closeSubpath();
    } else {
      path.moveTo(x - kPlayheadTriangleHalfWidth,
                  top + kPlayheadTriangleHeight);
      path.lineTo(x + kPlayheadTriangleHalfWidth,
                  top + kPlayheadTriangleHeight);
      path.lineTo(x, top);
      path.closeSubpath();
    }
    painter.fillPath(path, m_color);
  }
}

QRect PlayheadOverlay::visibleSurfaceRect(const QWidget *surface,
                                          QWidget *owner, int origin) const {
  if (!surface || origin >= surface->width())
    return {};
  QPoint offset = surface->mapTo(owner, QPoint(0, 0));
  QRect visible(offset + QPoint(origin, 0),
                QSize(surface->width() - origin, surface->height()));
  for (const QWidget *widget = surface; widget;
       widget = widget->parentWidget()) {
    if (!widget->isVisible())
      return {};

    visible &= QRect(widget->mapTo(owner, QPoint(0, 0)), widget->size());
    if (widget == owner)
      break;
  }
  return visible;
}

void PlayheadOverlay::synchronizeGeometry() {
  QWidget *ownerWidget = parentWidget();
  Q_ASSERT(ownerWidget);
  QWidget &owner = *ownerWidget;

  const QRect rulerGeometry(m_surfaces.ruler.widget.mapTo(&owner, QPoint(0, 0)),
                            m_surfaces.ruler.widget.size());
  const int playheadTop = rulerGeometry.bottom() + 1;
  const QRect playheadGeometry(0, playheadTop, owner.width(),
                               std::max(0, owner.height() - playheadTop));
  const QRect rulerVisible = visibleSurfaceRect(
      &m_surfaces.ruler.widget, &owner, m_surfaces.ruler.timelineOrigin);
  const QRect triangleClip(rulerVisible.left(), playheadTop,
                           rulerVisible.width(), kPlayheadTriangleHeight + 1);

  const QRegion visibleSurfaces =
      QRegion(visibleSurfaceRect(&m_surfaces.roll.widget, &owner,
                                 m_surfaces.roll.timelineOrigin)) +
      visibleSurfaceRect(&m_surfaces.lanes.widget, &owner,
                         m_surfaces.lanes.timelineOrigin) +
      visibleSurfaceRect(&m_surfaces.strip.widget, &owner,
                         m_surfaces.strip.timelineOrigin);

  const int timelineOrigin =
      m_surfaces.ruler.widget
          .mapTo(&owner, QPoint(m_surfaces.ruler.timelineOrigin, 0))
          .x();

  const bool overlayGeometryChanged = geometry() != owner.rect();
  if (overlayGeometryChanged)
    setGeometry(owner.rect());

  m_visibleSurfaceRegion = visibleSurfaces;
  m_playheadGeometry = playheadGeometry;
  m_triangleClip = triangleClip;
  m_timelineOrigin = timelineOrigin;
  m_trianglePointsUp = !m_surfaces.roll.widget.isVisible();
  m_devicePixelRatio = owner.devicePixelRatioF();

  ++m_staticGeneration;
  synchronizeBackend();
  raise();
}

void PlayheadOverlay::synchronizeBackend() {
  if (m_backendSyncing) {
    m_backendSyncPending = true;
    return;
  }

  m_backendSyncing = true;
  do {
    m_backendSyncPending = false;
    QWidget *owner = parentWidget();
    if (!m_backend && !m_backendAttempted && owner && owner->isVisible()) {
      m_backendAttempted = true;
      if (!qEnvironmentVariableIsSet("PORYDAW_FORCE_WIDGET_PLAYHEAD"))
        m_backend = createPlayheadBackend(*owner);
    }

    if (m_backend) {
      const PlayheadFrame frame{size(),
                                m_visibleSurfaceRegion,
                                m_triangleClip,
                                m_playheadGeometry,
                                m_color,
                                finalX(),
                                m_devicePixelRatio,
                                m_staticGeneration,
                                m_visible,
                                m_playing,
                                m_trianglePointsUp};
      const PlayheadSyncResult result = m_backend->synchronize(frame);
      m_backendApplied = result.state == PlayheadSyncState::Applied;
      if (result.state == PlayheadSyncState::Failed) {
        qWarning().noquote()
            << "Native playhead failed; using QWidget fallback:"
            << result.error;
        m_backend.reset();
      }
    } else {
      m_backendApplied = false;
    }
  } while (m_backendSyncPending && m_backend);
  m_backendSyncing = false;
  updatePaintRegion();
}

void PlayheadOverlay::updatePlayhead() { synchronizeBackend(); }

QRegion PlayheadOverlay::playheadRegion() const {
  const qreal x = finalX();
  const int top = m_playheadGeometry.top();
  const int height = m_playheadGeometry.height();

  const qreal leftExtent = playheadGlowLeftExtent(m_playing);
  const qreal rightExtent = playheadGlowRightExtent(m_playing);

  const QRect bodyRect =
      QRectF(x - leftExtent, top, leftExtent + rightExtent, height)
          .toAlignedRect();
  const QRect triangleRect =
      QRectF(x - kPlayheadTriangleHalfWidth, top,
             2 * kPlayheadTriangleHalfWidth, kPlayheadTriangleHeight + 1)
          .toAlignedRect();

  return (QRegion(bodyRect).intersected(m_visibleSurfaceRegion)) +
         (QRegion(triangleRect).intersected(m_triangleClip));
}

void PlayheadOverlay::updatePaintRegion() {
  QRegion currentRegion;
  if (!m_backendApplied && m_visible && !m_playheadGeometry.isEmpty()) {
    currentRegion = playheadRegion();
  }

  const QRegion dirty = m_lastPaintedRegion + currentRegion;
  m_lastPaintedRegion = currentRegion;
  if (!dirty.isEmpty()) {
    update(dirty);
  }
}

} // namespace songview
