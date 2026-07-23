#pragma once

#include <QColor>
#include <QLinearGradient>
#include <QPainter>
#include <QPen>
#include <QPixmap>
#include <QtMath>
#include <utility>
#include <QRegion>
#include <QWidget>

class QEvent;
class QPaintEvent;

namespace songview {
constexpr int kPlayheadGlowRadius = 10;
constexpr int kPlayheadTriangleHalfWidth = 4;
constexpr int kPlayheadTriangleHeight = 8;

namespace playhead_detail {

// Paused = centered on the bar, dimmer. Playing = 1 unit less radius and
// left-trailing only. Core is 1px in both states.
constexpr qreal kLineWidth = 1.0;
constexpr qreal kPeakPlaying = 0.13;
constexpr qreal kPeakPaused = 0.06;

// Quadratic bloom: t=0 outer (α=0) → t=1 at the bar (α=peak).
inline void setQuadStops(QLinearGradient &gradient, const QColor &color,
                         qreal peakAlpha)
{
    QColor stopColor = color;
    for (int i = 0; i <= 8; ++i) {
        const qreal t = qreal(i) / 8.0;
        stopColor.setAlphaF(peakAlpha * t * t);
        gradient.setColorAt(t, stopColor);
    }
}

inline void paintGlow(QPainter &painter, qreal x, int top, int height,
                      qreal left, qreal right, const QColor &color,
                      qreal peakAlpha)
{
    if (left > 0.0) {
        QLinearGradient gradient(x - left, 0, x, 0);
        setQuadStops(gradient, color, peakAlpha);
        painter.fillRect(QRectF(x - left, top, left, height), gradient);
    }
    if (right > 0.0) {
        QLinearGradient gradient(x + right, 0, x, 0);
        setQuadStops(gradient, color, peakAlpha);
        painter.fillRect(QRectF(x, top, right, height), gradient);
    }
}

} // namespace playhead_detail

class PlayheadLineCache
{
public:
    // Measured: inlining this into the 60Hz paint call site is worth it.
    Q_ALWAYS_INLINE void paint(QPainter &painter, qreal x, int top, int height,
                               bool playing, const QColor &color)
    {
        const qreal devicePixelRatio = painter.device()->devicePixelRatioF();
        if (!m_valid || m_color != color || m_playing != playing
            || m_height != height || m_devicePixelRatio != devicePixelRatio)
            rebuild(height, playing, color, devicePixelRatio);
        painter.drawPixmap(QPointF(x - m_leftExtent, top), m_glow);
        QPen core(color, playhead_detail::kLineWidth, Qt::SolidLine, Qt::FlatCap);
        painter.setPen(core);
        painter.drawLine(QPointF(x, top), QPointF(x, top + height - 1));
    }

private:
    void rebuild(int height, bool playing, const QColor &color,
                 qreal devicePixelRatio)
    {
        m_leftExtent =
            playing ? qreal(kPlayheadGlowRadius - 1) : qreal(kPlayheadGlowRadius);
        m_rightExtent = playing ? 0.0 : qreal(kPlayheadGlowRadius);
        const qreal peak =
            playing ? playhead_detail::kPeakPlaying : playhead_detail::kPeakPaused;
        QPixmap glow(qCeil((m_leftExtent + m_rightExtent) * devicePixelRatio),
                     qCeil(height * devicePixelRatio));
        glow.setDevicePixelRatio(devicePixelRatio);
        glow.fill(Qt::transparent);
        QPainter glowPainter(&glow);
        playhead_detail::paintGlow(glowPainter, m_leftExtent, 0, height,
                                   m_leftExtent, m_rightExtent, color, peak);
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
    qreal m_rightExtent = 0.0;
    qreal m_devicePixelRatio = 0.0;
    int m_height = 0;
    bool m_playing = false;
    bool m_valid = false;
};

// Triangle marker under the time ruler. Sized to that band only — not a
// full-window transparent sheet. Playhead bars live on TimelineSurface.
class PlayheadOverlay final : public QWidget
{
public:
    struct Surfaces
    {
        QWidget *ruler;
        int rulerOrigin;
        QWidget *roll; // visibility flips the triangle for the event-list page
    };

    PlayheadOverlay(QWidget *owner, const Surfaces &surfaces, const QColor &color);

    // timelineX is content-local (same as TimelineSurface::setPlayhead).
    void setPlayhead(qreal timelineX, bool visible);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void paintEvent(QPaintEvent *event) override;

private:
    QRect visibleTimelineBand(QWidget *owner) const;
    QRegion playheadRegion(qreal localX) const;
    void synchronizeGeometry();

    Surfaces m_surfaces;
    QColor m_color;
    qreal m_timelineX = 0.0;
    // Tick 0's content x in this widget's local coordinates.
    qreal m_localOrigin = 0.0;
    bool m_visible = false;
};

} // namespace songview
