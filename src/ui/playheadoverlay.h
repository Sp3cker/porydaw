#pragma once

#include "songview/timelinebandlayout.h"

#include <QColor>
#include <QPainterPath>
#include <QRect>
#include <QRegion>
#include <QSize>
#include <QWidget>
#include <memory>

class QEvent;
class QPaintEvent;

namespace songview {

// Shared playhead metrics: platform compositors and the QWidget fallback
// resolve the same font-scaled geometry.
int playheadGlowRadius();
int playheadTriangleHalfWidth();
int playheadTriangleHeight();
qreal playheadLineWidth();
qreal playheadGlowLeftExtent(bool playing);
qreal playheadGlowRightExtent(bool playing);
qreal playheadPeakAlpha(bool playing);

/// Whether the platform-native playhead renderer is enabled for this process.
bool platformPlayheadRendererEnabled();

class PlayheadOverlay final : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PlayheadOverlay)

  public:
    explicit PlayheadOverlay(QWidget &owner, const TimelineBandLayout &layout);

    void setPlayhead(qreal timelineX, bool visible, bool playing);
    // layout is SongView's canonical snapshot; band rects are already
    // owner-clipped (see songview::TimelineBandLayout) and stored verbatim.
    void updateBands(const TimelineBandLayout &layout);

  protected:
    void paintEvent(QPaintEvent *event) override;
    void changeEvent(QEvent *event) override;

  private:
    qreal finalX() const { return static_cast<qreal>(m_timelineOrigin) + m_timelineX; }

    QRegion fallbackPaintRegion() const;
    const QPainterPath &playheadTrianglePath();
    void synchronizeGeometry();
    void updateFallbackRegion();
    void exposeFallbackPixels(const QRegion &region);
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    class Platform;
    struct PlatformDeleter {
        void operator()(Platform *platform) const;
    };

    void initializePlatform(QWidget &owner);
    void setPlatformLayout();
    void setPlatformImages();
    bool setPlatformPosition();
#endif
    void updatePlayhead();

    TimelineBandLayout m_layout;
    QColor m_color;
    QPainterPath m_playheadTrianglePath;
    QSize m_playheadTrianglePathSize;

#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    std::unique_ptr<Platform, PlatformDeleter> m_platform;
#endif
    QRegion m_visibleSurfaceRegion;
    QRect m_bodyGeometry;
    QRect m_triangleClip;
    qreal m_timelineX = 0.0;
    int m_timelineOrigin = 0;
    bool m_visible = false;
    bool m_playing = false;
    bool m_trianglePointsUp = false;
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    qreal m_devicePixelRatio = 1.0;
#endif
    QRegion m_fallbackPaintRegion;
    bool m_platformApplied = false;
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    bool m_platformAttempted = false;
#endif
};

} // namespace songview
