#include "playheadrenderer.hpp"

#include <QColor>
#include <QEvent>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QPixmap>
#include <QWidget>
#include <QtMath>
#include <utility>

namespace songview {

namespace {

const QPainterPath kPlayheadTriangle = [] {
  QPainterPath path;
  path.moveTo(-kPlayheadTriangleHalfWidth, 0);
  path.lineTo(kPlayheadTriangleHalfWidth, 0);
  path.lineTo(0, kPlayheadTriangleHeight);
  path.closeSubpath();
  return path;
}();

void applyPlayheadQuadStops(QLinearGradient &g, const QColor &color,
                            qreal peakAlpha) {
  QColor stopColor = color;
  for (const auto &stop : kPlayheadGradientStops) {
    stopColor.setAlphaF(peakAlpha * stop.alphaFactor);
    g.setColorAt(stop.position, stopColor);
  }
}

void paintGlow(QPainter &painter, qreal x, int top, int height, qreal left,
               qreal right, const QColor &color, qreal peakAlpha) {
  if (left > 0.0) {
    QLinearGradient gradient(x - left, 0, x, 0);
    applyPlayheadQuadStops(gradient, color, peakAlpha);
    painter.fillRect(QRectF(x - left, top, left, height), gradient);
  }
  if (right > 0.0) {
    QLinearGradient gradient(x + right, 0, x, 0);
    applyPlayheadQuadStops(gradient, color, peakAlpha);
    painter.fillRect(QRectF(x, top, right, height), gradient);
  }
}

QRegion computePlayheadRegion(qreal x, const PlayheadPresentation &pres) {
  if (pres.layout.playheadGeometry.isEmpty())
    return {};

  constexpr qreal kAntialiasPadding = 1.0;
  const QRect bounds =
      QRectF(x - kPlayheadGlowRadius - kAntialiasPadding,
             pres.layout.playheadGeometry.top(),
             2.0 * kPlayheadGlowRadius + kPlayheadTriangleHalfWidth +
                 kAntialiasPadding * 2.0,
             pres.layout.playheadGeometry.height())
          .toAlignedRect()
          .intersected(pres.layout.playheadGeometry);
  return QRegion(bounds).intersected(pres.layout.visibleSurfaceRegion +
                                     pres.layout.triangleClip);
}

} // namespace

class PlayheadGlowCache {
public:
  Q_ALWAYS_INLINE void paint(QPainter &painter, qreal x, int top, int height,
                             bool playing, const QColor &color) {
    const qreal devicePixelRatio = painter.device()->devicePixelRatioF();
    if (!m_valid || m_color != color || m_playing != playing ||
        m_height != height || m_devicePixelRatio != devicePixelRatio)
      rebuild(height, playing, color, devicePixelRatio);
    painter.drawPixmap(QPointF(x - m_leftExtent, top), m_glow);
  }

private:
  void rebuild(int height, bool playing, const QColor &color,
               qreal devicePixelRatio) {
    m_leftExtent = playheadGlowLeftExtent(playing);
    const qreal rightExtent = playheadGlowRightExtent(playing);
    const qreal peak = playheadPeakAlpha(playing);
    QPixmap glow(qCeil((m_leftExtent + rightExtent) * devicePixelRatio),
                 qCeil(height * devicePixelRatio));
    glow.setDevicePixelRatio(devicePixelRatio);
    glow.fill(Qt::transparent);
    QPainter glowPainter(&glow);
    paintGlow(glowPainter, m_leftExtent, 0, height, m_leftExtent, rightExtent,
              color, peak);
    m_glow = std::move(glow);
    m_color = color;
    m_playing = playing;
    m_height = height;
    m_devicePixelRatio = devicePixelRatio;
    m_valid = true;
  }

  QPixmap m_glow;
  QColor m_color;
  qreal m_leftExtent = 0.0;
  qreal m_devicePixelRatio = 0.0;
  int m_height = 0;
  bool m_playing = false;
  bool m_valid = false;
};

class PlayheadRenderer::Impl {
public:
  explicit Impl(QWidget &overlay) : m_overlay(overlay) {}

  void synchronize(const PlayheadPresentation &presentation) {
    if (m_hasPresentation && m_presentation == presentation)
      return;

    QRegion dirty;
    if (m_hasPresentation && m_presentation.state.visible) {
      dirty +=
          computePlayheadRegion(m_presentation.state.finalX, m_presentation);
    }

    if (presentation.state.visible)
      dirty += computePlayheadRegion(presentation.state.finalX, presentation);

    m_presentation = presentation;
    m_hasPresentation = true;

    if (!dirty.isEmpty())
      m_overlay.update(dirty);
  }

  void paint(QPaintEvent *) {
    if (!m_presentation.state.visible ||
        m_presentation.layout.playheadGeometry.isEmpty() ||
        (m_presentation.layout.visibleSurfaceRegion.isEmpty() &&
         m_presentation.layout.triangleClip.isEmpty())) {
      return;
    }

    QPainter painter(&m_overlay);
    painter.setClipRegion(m_presentation.layout.visibleSurfaceRegion);
    painter.setRenderHint(QPainter::Antialiasing);

    const int playheadTop = m_presentation.layout.playheadGeometry.top();
    const int height = m_presentation.layout.playheadGeometry.height();
    const qreal playheadX = m_presentation.state.finalX;
    const QColor color = m_presentation.appearance.themeColor;
    m_glowCache.paint(painter, playheadX, playheadTop, height,
                      m_presentation.appearance.playing, color);

    QPen core(color, kPlayheadLineWidth, Qt::SolidLine, Qt::FlatCap);
    painter.setPen(core);
    painter.drawLine(
        QPointF(playheadX, playheadTop),
        QPointF(playheadX, m_presentation.layout.playheadGeometry.bottom()));

    painter.setClipRect(m_presentation.layout.triangleClip, Qt::ReplaceClip);
    const bool trianglePointsUp = m_presentation.layout.trianglePointsUp;
    painter.translate(playheadX,
                      playheadTop +
                          (trianglePointsUp ? kPlayheadTriangleHeight : 0));
    if (trianglePointsUp)
      painter.scale(1.0, -1.0);
    painter.fillPath(kPlayheadTriangle, color);
  }

private:
  QWidget &m_overlay;
  PlayheadPresentation m_presentation;
  PlayheadGlowCache m_glowCache;
  bool m_hasPresentation = false;
};

PlayheadRenderer::PlayheadRenderer(QWidget &overlay)
    : m_impl(std::make_unique<Impl>(overlay)) {}

PlayheadRenderer::~PlayheadRenderer() = default;

void PlayheadRenderer::synchronize(const PlayheadPresentation &presentation) {
  m_impl->synchronize(presentation);
}

void PlayheadRenderer::paint(QPaintEvent *event) { m_impl->paint(event); }

} // namespace songview
