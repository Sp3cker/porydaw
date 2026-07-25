#include "playheadoverlay.h"
#include "theme/themeruntime.h"

#include <QEvent>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QtMath>
#include <utility>

namespace songview {

PlayheadOverlay::PlayheadOverlay(QWidget &owner, const Surfaces &surfaces)
    : QWidget(&owner), m_surfaces(surfaces) {

  setAttribute(Qt::WA_TransparentForMouseEvents);
  setAttribute(Qt::WA_NoSystemBackground);

  // The filter chain is captured once, here: each surface's ancestors up
  // to the owner as they stand at construction. Reparenting a surface
  // afterwards would leave the new ancestors unwatched and geometry sync
  // silently stale — SongView must finish building its hierarchy before
  // creating the overlay.
  const auto observeSurfaceGeometry = [this, &owner](QWidget &surface) {
    for (QWidget *widget = &surface; widget; widget = widget->parentWidget()) {
      widget->installEventFilter(this);
      if (widget == &owner)
        break;
    }
  };
  observeSurfaceGeometry(m_surfaces.ruler);
  observeSurfaceGeometry(m_surfaces.roll);
  observeSurfaceGeometry(m_surfaces.lanes);
  observeSurfaceGeometry(m_surfaces.strip);

  initializePlatform();
  synchronizeGeometry();
  show();
}

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible, bool playing) {
  if (m_timelineX == timelineX && m_visible == visible && m_playing == playing)
    return;

  m_timelineX = timelineX;
  m_visible = visible;
  m_playing = playing;

  updateArtwork();
  synchronizePlatform();
}

bool PlayheadOverlay::eventFilter(QObject *, QEvent *event) {
  switch (event->type()) {
  case QEvent::Show:
  case QEvent::Hide:
  case QEvent::Move:
  case QEvent::Resize:
  case QEvent::LayoutRequest:
  case QEvent::WinIdChange:
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
  case QEvent::StyleChange:
  case QEvent::FontChange:
    updateArtwork();
    synchronizePlatform();
    break;
  default:
    break;
  }
}

void PlayheadOverlay::paintEvent(QPaintEvent *event) { paintPlatform(event); }

QRect PlayheadOverlay::visibleSurfaceRect(const QWidget &surface,
                                          QWidget &owner, int origin) const {
  if (origin >= surface.width())
    return {};
  QPoint offset = surface.mapTo(&owner, QPoint(0, 0));
  QRect visible(offset + QPoint(origin, 0),
                QSize(surface.width() - origin, surface.height()));
  for (const QWidget *widget = &surface; widget;
       widget = widget->parentWidget()) {
    if (!widget->isVisible())
      return {};

    visible &= QRect(widget->mapTo(&owner, QPoint(0, 0)), widget->size());
    if (widget == &owner)
      break;
  }
  return visible;
}

void PlayheadOverlay::synchronizeGeometry() {
  QWidget *ownerWidget = parentWidget();
  Q_ASSERT(ownerWidget);
  QWidget &owner = *ownerWidget;

  const QRect rulerGeometry(m_surfaces.ruler.mapTo(&owner, QPoint(0, 0)),
                            m_surfaces.ruler.size());
  const int playheadTop = rulerGeometry.bottom() + 1;
  const QRect playheadGeometry(0, playheadTop, owner.width(),
                               owner.height() - playheadTop);
  const QRect rulerVisible =
      visibleSurfaceRect(m_surfaces.ruler, owner, m_surfaces.rulerOrigin);
  const QRect triangleClip(rulerVisible.left(), playheadTop,
                           rulerVisible.width(), kPlayheadTriangleHeight + 1);

  const QRegion visibleSurfaces =
      QRegion(
          visibleSurfaceRect(m_surfaces.roll, owner, m_surfaces.rollOrigin)) +
      visibleSurfaceRect(m_surfaces.lanes, owner, m_surfaces.lanesOrigin) +
      visibleSurfaceRect(m_surfaces.strip, owner, m_surfaces.stripOrigin);

  const int timelineOrigin =
      m_surfaces.ruler.mapTo(&owner, QPoint(m_surfaces.rulerOrigin, 0)).x();

  const bool overlayGeometryChanged = geometry() != owner.rect();
  if (overlayGeometryChanged)
    setGeometry(owner.rect());

  m_visibleSurfaceRegion = visibleSurfaces;
  m_playheadGeometry = playheadGeometry;
  m_triangleClip = triangleClip;
  m_timelineOrigin = timelineOrigin;
  m_trianglePointsUp = !m_surfaces.roll.isVisible();
  m_devicePixelRatio = owner.devicePixelRatioF();

  updateArtwork();
  synchronizePlatform();
  raise();
}

void PlayheadOverlay::updateArtwork() {
  const QColor currentThemeColor =
      themes::color(themes::Role::song_view_playhead);
  const int currentHeight = m_playheadGeometry.height();
  const qreal currentDpr = m_devicePixelRatio > 0.0 ? m_devicePixelRatio : 1.0;

  if (m_cachedHeight == currentHeight && m_cachedPlaying == m_playing &&
      m_cachedTrianglePointsUp == m_trianglePointsUp &&
      m_cachedDevicePixelRatio == currentDpr &&
      m_cachedThemeColor == currentThemeColor) {
    return;
  }

  m_cachedHeight = currentHeight;
  m_cachedPlaying = m_playing;
  m_cachedTrianglePointsUp = m_trianglePointsUp;
  m_cachedDevicePixelRatio = currentDpr;
  m_cachedThemeColor = currentThemeColor;
  m_themeColor = currentThemeColor;

  if (m_playheadGeometry.isEmpty() || currentHeight <= 0) {
    m_bodyImage = QImage();
    m_triangleImage = QImage();
    return;
  }

  const qreal leftExtent = playheadGlowLeftExtent(m_playing);
  const qreal rightExtent = playheadGlowRightExtent(m_playing);
  const qreal peakAlpha = playheadPeakAlpha(m_playing);
  m_bodyImageLeftExtent = leftExtent;

  const qreal bodyWidthLogical = leftExtent + rightExtent;
  const int bodyPixelWidth = qCeil(bodyWidthLogical * currentDpr);
  const int bodyPixelHeight = qCeil(currentHeight * currentDpr);

  if (bodyPixelWidth > 0 && bodyPixelHeight > 0) {
    QImage bodyImg(bodyPixelWidth, bodyPixelHeight,
                   QImage::Format_ARGB32_Premultiplied);
    bodyImg.setDevicePixelRatio(currentDpr);
    bodyImg.fill(Qt::transparent);

    QPainter painter(&bodyImg);
    painter.setRenderHint(QPainter::Antialiasing);

    if (leftExtent > 0.0) {
      QLinearGradient gradient(0, 0, leftExtent, 0);
      for (const auto &stop : kPlayheadGradientStops) {
        QColor stopColor = m_themeColor;
        stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
        gradient.setColorAt(stop.position, stopColor);
      }
      painter.fillRect(QRectF(0, 0, leftExtent, currentHeight), gradient);
    }
    if (rightExtent > 0.0) {
      QLinearGradient gradient(leftExtent + rightExtent, 0, leftExtent, 0);
      for (const auto &stop : kPlayheadGradientStops) {
        QColor stopColor = m_themeColor;
        stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
        gradient.setColorAt(stop.position, stopColor);
      }
      painter.fillRect(QRectF(leftExtent, 0, rightExtent, currentHeight),
                       gradient);
    }

    QPen corePen(m_themeColor, kPlayheadLineWidth, Qt::SolidLine, Qt::FlatCap);
    painter.setPen(corePen);
    painter.drawLine(QPointF(leftExtent, 0),
                     QPointF(leftExtent, currentHeight));
    painter.end();

    m_bodyImage = std::move(bodyImg);
  } else {
    m_bodyImage = QImage();
  }

  const qreal triWidthLogical = 2.0 * kPlayheadTriangleHalfWidth;
  const qreal triHeightLogical = kPlayheadTriangleHeight;
  const int triPixelWidth = qCeil(triWidthLogical * currentDpr);
  const int triPixelHeight = qCeil(triHeightLogical * currentDpr);

  if (triPixelWidth > 0 && triPixelHeight > 0) {
    QImage triImg(triPixelWidth, triPixelHeight,
                  QImage::Format_ARGB32_Premultiplied);
    triImg.setDevicePixelRatio(currentDpr);
    triImg.fill(Qt::transparent);

    QPainter painter(&triImg);
    painter.setRenderHint(QPainter::Antialiasing);

    QPainterPath path;
    if (!m_trianglePointsUp) {
      path.moveTo(0, 0);
      path.lineTo(triWidthLogical, 0);
      path.lineTo(kPlayheadTriangleHalfWidth, triHeightLogical);
      path.closeSubpath();
    } else {
      path.moveTo(0, triHeightLogical);
      path.lineTo(triWidthLogical, triHeightLogical);
      path.lineTo(kPlayheadTriangleHalfWidth, 0);
      path.closeSubpath();
    }
    painter.fillPath(path, m_themeColor);
    painter.end();

    m_triangleImage = std::move(triImg);
  } else {
    m_triangleImage = QImage();
  }
}

} // namespace songview
