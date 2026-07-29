#include "timelinesurface.h"

#include <QEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QResizeEvent>
#include <limits>

namespace songview {

TimelineSurface::TimelineSurface(QWidget *parent) : QWidget(parent) {}

void TimelineSurface::invalidateContent() {
  m_dirtyContentRegion = rect();
  QWidget::update();
}

void TimelineSurface::invalidateContent(const QRegion &region) {
  const QRegion clipped = region.intersected(rect());
  if (clipped.isEmpty())
    return;
  m_dirtyContentRegion |= clipped;
  QWidget::update(clipped);
}

TimelineSurfaceDiagnostics TimelineSurface::diagnostics() const noexcept {
  return m_diagnostics;
}

void TimelineSurface::paintEvent(QPaintEvent *) {
  const qreal dpr = devicePixelRatioF();
  const QSize pixelSize(qCeil(width() * dpr), qCeil(height() * dpr));
  const qint64 estimatedCacheBytes =
      qint64(pixelSize.width()) * qint64(pixelSize.height()) * 4;
  constexpr qint64 maxEstimatedCacheBytes = 256 * 1024 * 1024;
  const bool estimateFitsBudget =
      pixelSize.width() > 0 && pixelSize.height() > 0 &&
      estimatedCacheBytes > 0 && estimatedCacheBytes <= maxEstimatedCacheBytes;

  if (!estimateFitsBudget) {
    m_contentCache = {};
    m_diagnostics.estimatedContentCacheBytes = 0;
    QPainter painter(this);
    countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
    paintContent(painter);
    return;
  }

  if (m_contentCache.size() != pixelSize ||
      !qFuzzyCompare(m_contentCache.devicePixelRatio(), dpr)) {
    m_contentCache = QPixmap(pixelSize);
    if (!m_contentCache.isNull()) {
      m_contentCache.setDevicePixelRatio(dpr);
      m_dirtyContentRegion = rect();
      m_diagnostics.estimatedContentCacheBytes = quint64(estimatedCacheBytes);
    }
  }

  if (m_contentCache.isNull()) {
    m_diagnostics.estimatedContentCacheBytes = 0;
    QPainter painter(this);
    countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
    paintContent(painter);
    return;
  }

  if (m_dirtyContentRegion.isEmpty()) {
    QPainter painter(this);
    painter.drawPixmap(QPointF(0, 0), m_contentCache);
    return;
  }

  const QRegion dirtyRegion = m_dirtyContentRegion.intersected(rect());
  if (dirtyRegion == QRegion(rect())) {
    m_contentCache.fill(Qt::transparent);
    QPainter cachePainter(&m_contentCache);
    countContentPaint(quint64(pixelSize.width()) * quint64(pixelSize.height()));
    paintContent(cachePainter);
  } else {
    for (const QRect &logicalRect : dirtyRegion) {
      const int deviceLeft = qFloor(logicalRect.left() * dpr);
      const int deviceTop = qFloor(logicalRect.top() * dpr);
      const int deviceRight = qCeil((logicalRect.right() + 1) * dpr);
      const int deviceBottom = qCeil((logicalRect.bottom() + 1) * dpr);
      const QRect deviceRect = QRect(QPoint(deviceLeft, deviceTop),
                                     QPoint(deviceRight - 1, deviceBottom - 1))
                                   .intersected(QRect(QPoint(), pixelSize));
      if (deviceRect.isEmpty())
        continue;

      QPixmap dirtyPatch(deviceRect.size());
      if (dirtyPatch.isNull()) {
        QPainter painter(this);
        countContentPaint(quint64(pixelSize.width()) *
                          quint64(pixelSize.height()));
        paintContent(painter);
        return;
      }
      dirtyPatch.setDevicePixelRatio(dpr);
      dirtyPatch.fill(Qt::transparent);

      const QPointF logicalPatchOrigin(deviceRect.left() / dpr,
                                       deviceRect.top() / dpr);
      {
        QPainter patchPainter(&dirtyPatch);
        patchPainter.translate(-logicalPatchOrigin);
        countContentPaint(quint64(deviceRect.width()) *
                          quint64(deviceRect.height()));
        paintContent(patchPainter);
      }
      {
        QPainter cachePainter(&m_contentCache);
        cachePainter.setCompositionMode(QPainter::CompositionMode_Source);
        cachePainter.drawPixmap(logicalPatchOrigin, dirtyPatch);
      }
    }
  }
  m_dirtyContentRegion -= dirtyRegion;

  QPainter painter(this);
  painter.drawPixmap(QPointF(0, 0), m_contentCache);
}

void TimelineSurface::changeEvent(QEvent *event) {
  QWidget::changeEvent(event);
  switch (event->type()) {
  case QEvent::PaletteChange:
  case QEvent::ApplicationPaletteChange:
  case QEvent::FontChange:
  case QEvent::StyleChange:
  case QEvent::ThemeChange:
    invalidateContent();
    break;
  default:
    break;
  }
}

void TimelineSurface::resizeEvent(QResizeEvent *event) {
  QWidget::resizeEvent(event);
  m_contentCache = {};
  m_diagnostics.estimatedContentCacheBytes = 0;
  invalidateContent();
}

void TimelineSurface::countContentPaint(quint64 pixelCount) noexcept {
  constexpr quint64 max = std::numeric_limits<quint64>::max();
  if (m_diagnostics.contentPaintCount != max)
    ++m_diagnostics.contentPaintCount;
  if (m_diagnostics.contentPaintPixelCount > max - pixelCount)
    m_diagnostics.contentPaintPixelCount = max;
  else
    m_diagnostics.contentPaintPixelCount += pixelCount;
}

} // namespace songview
