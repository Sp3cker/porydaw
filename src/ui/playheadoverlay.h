#pragma once

#include "songview/timelinebandlayout.h"

#include <QColor>
#include <QObject>
#include <QRect>
#include <QRegion>
#include <memory>

class SongView;

namespace songview {

// Shared playhead metrics: platform compositors and the Qt Quick renderer
// resolve the same font-scaled geometry.
int playheadGlowRadius();
int playheadTriangleHalfWidth();
int playheadTriangleHeight();
qreal playheadLineWidth();
qreal playheadGlowLeftExtent(bool playing);
qreal playheadGlowRightExtent(bool playing);
qreal playheadPeakAlpha(bool playing);

class PlayheadOverlay final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PlayheadOverlay)

  public:
    explicit PlayheadOverlay(SongView &owner, const TimelineBandLayout &layout);
    ~PlayheadOverlay() override;

    void setPlayhead(qreal timelineX, bool visible, bool playing);
    // layout is SongView's canonical snapshot; band rects are already
    // owner-clipped (see songview::TimelineBandLayout) and stored verbatim.
    void updateBands(const TimelineBandLayout &layout);

    // Re-reads the themed playhead color and pushes it to the active renderer.
    void syncAppearance();

  private:
    qreal finalX() const { return static_cast<qreal>(m_timelineOrigin) + m_timelineX; }

    void synchronizeGeometry();
#ifdef __APPLE__
    class Platform;
    struct PlatformDeleter {
        void operator()(Platform *platform) const;
    };

    void initializePlatform(SongView &owner);
    void setPlatformLayout();
    void setPlatformImages();
    void setPlatformPosition();
#endif
    void updatePlayhead();

    SongView &m_owner;
    TimelineBandLayout m_layout;
    QColor m_color;

#ifdef __APPLE__
    std::unique_ptr<Platform, PlatformDeleter> m_platform;
    QRegion m_visibleSurfaceRegion;
    QRect m_bodyGeometry;
    QRect m_triangleClip;
#endif
    qreal m_timelineX = 0.0;
    int m_timelineOrigin = 0;
    bool m_visible = false;
    bool m_playing = false;
    bool m_trianglePointsUp = false;
#ifdef __APPLE__
    qreal m_devicePixelRatio = 1.0;
#endif
};

} // namespace songview
