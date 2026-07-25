#include "playheadoverlay.h"

#include <QPainter>
#include <QRegion>
#include <QWidget>

namespace songview {

class PlayheadOverlay::Platform final {
public:
  explicit Platform(PlayheadOverlay &overlay) : m_overlay(overlay) {}

  void synchronize() {
    QRegion currentRegion;
    if (m_overlay.m_visible && !m_overlay.m_playheadGeometry.isEmpty()) {
      currentRegion = computePlayheadRegion();
    }

    const QRegion dirty = m_lastRegion + currentRegion;
    m_lastRegion = currentRegion;

    if (!dirty.isEmpty()) {
      m_overlay.update(dirty);
    }
  }

  void paint(QPaintEvent *) {
    if (!m_overlay.m_visible || m_overlay.m_playheadGeometry.isEmpty()) {
      return;
    }

    QPainter painter(&m_overlay);
    const qreal x = m_overlay.finalX();
    const int top = m_overlay.m_playheadGeometry.top();

    if (!m_overlay.m_bodyImage.isNull() &&
        !m_overlay.m_visibleSurfaceRegion.isEmpty()) {
      painter.setClipRegion(m_overlay.m_visibleSurfaceRegion);
      painter.drawImage(QPointF(x - m_overlay.m_bodyImageLeftExtent, top),
                        m_overlay.m_bodyImage);
    }

    if (!m_overlay.m_triangleImage.isNull() &&
        !m_overlay.m_triangleClip.isEmpty()) {
      painter.setClipRect(m_overlay.m_triangleClip, Qt::ReplaceClip);
      painter.drawImage(QPointF(x - kPlayheadTriangleHalfWidth, top),
                        m_overlay.m_triangleImage);
    }
  }

private:
  QRegion computePlayheadRegion() const {
    const qreal x = m_overlay.finalX();
    const qreal dpr =
        m_overlay.m_devicePixelRatio > 0.0 ? m_overlay.m_devicePixelRatio : 1.0;
    const int top = m_overlay.m_playheadGeometry.top();

    QRegion region;

    if (!m_overlay.m_bodyImage.isNull()) {
      const QRect bodyRect = QRectF(x - m_overlay.m_bodyImageLeftExtent, top,
                                    m_overlay.m_bodyImage.width() / dpr,
                                    m_overlay.m_bodyImage.height() / dpr)
                                 .toAlignedRect();
      region += QRegion(bodyRect).intersected(m_overlay.m_visibleSurfaceRegion);
    }

    if (!m_overlay.m_triangleImage.isNull()) {
      const QRect triRect = QRectF(x - kPlayheadTriangleHalfWidth, top,
                                   m_overlay.m_triangleImage.width() / dpr,
                                   m_overlay.m_triangleImage.height() / dpr)
                                .toAlignedRect();
      region += QRegion(triRect).intersected(m_overlay.m_triangleClip);
    }

    return region;
  }

  PlayheadOverlay &m_overlay;
  QRegion m_lastRegion;
};
void PlayheadOverlay::initializePlatform() {
  m_platform.reset(new Platform(*this));
}

void PlayheadOverlay::synchronizePlatform() {
  if (m_platform) {
    m_platform->synchronize();
  }
}

void PlayheadOverlay::paintPlatform(QPaintEvent *event) {
  if (m_platform) {
    m_platform->paint(event);
  }
}

void PlayheadOverlay::PlatformDeleter::operator()(Platform *platform) const {
  delete platform;
}
PlayheadOverlay::~PlayheadOverlay() = default;

} // namespace songview
