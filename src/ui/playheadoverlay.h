#pragma once

#include "songview/timelinebandlayout.h"

#include <QColor>
#include <QObject>
#include <QPointer>
#include <QRect>
#include <QRegion>
#include <memory>

class SongView;
class QWidget;

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

/// Whether the opt-in Qt Quick playhead renderer is enabled for this process.
bool quickPlayheadRendererEnabled();

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

    // Re-reads the themed playhead color and pushes it to the platform
    // renderer and/or the fallback widget.
    void syncAppearance();
    QWidget *fallbackWidget() const noexcept; // nullptr when native platform applied

  private:
    class FallbackWidget;

    qreal finalX() const { return static_cast<qreal>(m_timelineOrigin) + m_timelineX; }

    void synchronizeGeometry();
    void updateFallbackRegion();
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    class Platform;
    struct PlatformDeleter {
        void operator()(Platform *platform) const;
    };

    void initializePlatform(SongView &owner);
    void setPlatformLayout();
    void setPlatformImages();
    bool setPlatformPosition();
#endif
    void updatePlayhead();

    SongView &m_owner;
    TimelineBandLayout m_layout;
    QColor m_color;
    // Lazily created software-painting child of SongView; only alive while
    // the native platform renderer is not applied. QPointer because SongView
    // may outlive this overlay and destroys its widget children before its
    // QObject children.
    QPointer<FallbackWidget> m_fallback;

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
    bool m_platformApplied = false;
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    bool m_platformAttempted = false;
#endif
};

} // namespace songview
