#include "playheadoverlay.h"

#include <QPainter>
#include <QRegion>
#include <QWidget>

namespace songview {

namespace {

QRegion computePlayheadRegion(const PlayheadOverlay &overlay) {
  const qreal x = overlay.finalX();
  const qreal dpr =
      overlay.m_devicePixelRatio > 0.0 ? overlay.m_devicePixelRatio : 1.0;
  const int top = overlay.m_playheadGeometry.top();

  QRegion region;

  if (!overlay.m_bodyImage.isNull()) {
    const QRect bodyRect = QRectF(x - overlay.m_bodyImageLeftExtent, top,
                                  overlay.m_bodyImage.width() / dpr,
                                  overlay.m_bodyImage.height() / dpr)
                               .toAlignedRect();
    region += QRegion(bodyRect).intersected(overlay.m_visibleSurfaceRegion);
  }

  if (!overlay.m_triangleImage.isNull()) {
    const QRect triRect = QRectF(x - kPlayheadTriangleHalfWidth, top,
                                 overlay.m_triangleImage.width() / dpr,
                                 overlay.m_triangleImage.height() / dpr)
                              .toAlignedRect();
    region += QRegion(triRect).intersected(overlay.m_triangleClip);
  }

  return region;
}

} // namespace

class PlayheadOverlay::Platform final {
public:
  explicit Platform(PlayheadOverlay &overlay) : m_overlay(overlay) {}

  void synchronize() {
    QRegion currentRegion;
    if (m_overlay.m_visible && !m_overlay.m_playheadGeometry.isEmpty()) {
      currentRegion = computePlayheadRegion(m_overlay);
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
