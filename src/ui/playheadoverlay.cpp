#include "playheadoverlay.h"
#include "theme/themeruntime.h"

#include <QEvent>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QtMath>
#include <algorithm>
#include <utility>

namespace songview {

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

#ifndef PORYDAW_USE_DIRECT_PLAYHEAD
PlayheadOverlay::~PlayheadOverlay() = default;
#endif

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible, bool playing) {
  if (m_timelineX == timelineX && m_visible == visible && m_playing == playing)
    return;

  const bool playingChanged = m_playing != playing;

  m_timelineX = timelineX;
  m_visible = visible;
  m_playing = playing;

#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
  if (playingChanged && updateImages() && m_platform)
    setPlatformImages();
#else
  if (playingChanged)
    (void)updateImages();
#endif
  updatePlayhead();
}

void PlayheadOverlay::observeSurfaceGeometry() {
  QWidget *owner = parentWidget();
  Q_ASSERT(owner);

  const auto observe = [this, owner](QWidget *surface) {
    for (QWidget *widget = surface; widget; widget = widget->parentWidget()) {
      widget->installEventFilter(this);
      if (widget == owner) {
        break;
      }
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
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
      if (updateImages() && m_platform)
        setPlatformImages();
      updatePlayhead();
#else
      (void)updateImages();
      updatePlayhead();
#endif
    }
    break;
  }
  default:
    break;
  }
}

void PlayheadOverlay::paintEvent(QPaintEvent *event) {
  (void)event;
  if (m_platformApplied || !m_visible || m_playheadGeometry.isEmpty())
    return;

  QPainter painter(this);
  const qreal x = finalX();
  const int top = m_playheadGeometry.top();

  if (!m_bodyImage.isNull() && !m_visibleSurfaceRegion.isEmpty()) {
    painter.setClipRegion(m_visibleSurfaceRegion);
    painter.drawImage(QPointF(x - m_bodyImageLeftExtent, top), m_bodyImage);
  }

  if (!m_triangleImage.isNull() && !m_triangleClip.isEmpty()) {
    painter.setClipRect(m_triangleClip, Qt::ReplaceClip);
    painter.drawImage(QPointF(x - kPlayheadTriangleHalfWidth, top),
                      m_triangleImage);
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
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
  bool platformCreated = false;
  if (!m_platform && !m_platformAttempted && owner.isVisible()) {
    m_platformAttempted = true;
    if (!qEnvironmentVariableIsSet("PORYDAW_FORCE_WIDGET_PLAYHEAD")) {
      initializePlatform(owner);
      platformCreated = true;
    }
  }
#endif
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
  const bool imagesChanged = updateImages();
  if (m_platform && (imagesChanged || platformCreated))
    setPlatformImages();
  if (m_platform)
    setPlatformLayout();
  updatePlayhead();
#else
  (void)updateImages();
  m_platformApplied = false;
  updatePaintRegion();
#endif
  raise();
}

void PlayheadOverlay::updatePlayhead() {
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
  m_platformApplied = m_platform && setPlatformPosition();
  updatePaintRegion();
#else
  m_platformApplied = false;
  updatePaintRegion();
#endif
}

bool PlayheadOverlay::updateImages() {
  const QColor currentThemeColor = m_color;
  const int currentHeight = m_playheadGeometry.height();
  const qreal currentDpr = m_devicePixelRatio > 0.0 ? m_devicePixelRatio : 1.0;
  const bool geometryValid = !m_playheadGeometry.isEmpty() && currentHeight > 0;
  bool imagesChanged = false;

  if (!geometryValid) {
    imagesChanged = !m_bodyImage.isNull() || !m_triangleImage.isNull();
    m_bodyImage = QImage();
    m_triangleImage = QImage();
    m_cachedBodyValid = false;
    m_cachedTriangleValid = false;
    return imagesChanged;
  }

  const bool bodyNeedsUpdate =
      !m_cachedBodyValid || m_cachedBodyHeight != currentHeight ||
      m_cachedBodyPlaying != m_playing || m_cachedBodyDpr != currentDpr ||
      m_cachedBodyThemeColor != currentThemeColor;

  if (bodyNeedsUpdate) {
    imagesChanged = true;
    m_cachedBodyHeight = currentHeight;
    m_cachedBodyPlaying = m_playing;
    m_cachedBodyDpr = currentDpr;
    m_cachedBodyThemeColor = currentThemeColor;
    m_cachedBodyValid = true;

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
          QColor stopColor = currentThemeColor;
          stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
          gradient.setColorAt(stop.position, stopColor);
        }
        painter.fillRect(QRectF(0, 0, leftExtent, currentHeight), gradient);
      }
      if (!m_playing && rightExtent > 0.0) {
        QLinearGradient gradient(leftExtent + rightExtent, 0, leftExtent, 0);
        for (const auto &stop : kPlayheadGradientStops) {
          QColor stopColor = currentThemeColor;
          stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
          gradient.setColorAt(stop.position, stopColor);
        }
        painter.fillRect(QRectF(leftExtent, 0, rightExtent, currentHeight),
                         gradient);
      }

      QPen corePen(currentThemeColor, kPlayheadLineWidth, Qt::SolidLine,
                   Qt::FlatCap);
      painter.setPen(corePen);
      painter.drawLine(QPointF(leftExtent, 0),
                       QPointF(leftExtent, currentHeight));
      painter.end();

      m_bodyImage = std::move(bodyImg);
    } else {
      m_bodyImage = QImage();
    }
  }

  const bool triangleNeedsUpdate =
      !m_cachedTriangleValid ||
      m_cachedTrianglePointsUp != m_trianglePointsUp ||
      m_cachedTriangleDpr != currentDpr ||
      m_cachedTriangleThemeColor != currentThemeColor;

  if (triangleNeedsUpdate) {
    imagesChanged = true;
    m_cachedTrianglePointsUp = m_trianglePointsUp;
    m_cachedTriangleDpr = currentDpr;
    m_cachedTriangleThemeColor = currentThemeColor;
    m_cachedTriangleValid = true;

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
      painter.fillPath(path, currentThemeColor);
      painter.end();

      m_triangleImage = std::move(triImg);
    } else {
      m_triangleImage = QImage();
    }
  }
  return imagesChanged;
}

QRegion PlayheadOverlay::playheadRegion() const {
  const qreal x = finalX();
  const qreal dpr = m_devicePixelRatio > 0.0 ? m_devicePixelRatio : 1.0;
  const int top = m_playheadGeometry.top();

  QRegion region;
  if (!m_bodyImage.isNull()) {
    const QRect bodyRect =
        QRectF(x - m_bodyImageLeftExtent, top, m_bodyImage.width() / dpr,
               m_bodyImage.height() / dpr)
            .toAlignedRect();
    region += QRegion(bodyRect).intersected(m_visibleSurfaceRegion);
  }

  if (!m_triangleImage.isNull()) {
    const QRect triangleRect =
        QRectF(x - kPlayheadTriangleHalfWidth, top,
               m_triangleImage.width() / dpr, m_triangleImage.height() / dpr)
            .toAlignedRect();
    region += QRegion(triangleRect).intersected(m_triangleClip);
  }
  return region;
}

void PlayheadOverlay::updatePaintRegion() {
  if (m_platformApplied) {
    if (!m_lastPaintedRegion.isEmpty()) {
      update(m_lastPaintedRegion);
      m_lastPaintedRegion = QRegion();
    }
    return;
  }

  QRegion currentRegion;
  if (m_visible && !m_playheadGeometry.isEmpty()) {
    currentRegion = playheadRegion();
  }

  const QRegion dirty = m_lastPaintedRegion + currentRegion;
  m_lastPaintedRegion = currentRegion;
  if (!dirty.isEmpty()) {
    update(dirty);
  }
}

} // namespace songview
