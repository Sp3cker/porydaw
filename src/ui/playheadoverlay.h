#pragma once

#include <QColor>
#include <QImage>
#include <QRect>
#include <QRegion>
#include <QWidget>
#include <array>
#include <cstddef>
#include <memory>

#include "timelinesurface.h"

class QEvent;
class QPaintEvent;

namespace songview {

constexpr int kPlayheadGlowRadius = 10;
constexpr int kPlayheadTriangleHalfWidth = 4;
constexpr int kPlayheadTriangleHeight = 8;
constexpr qreal kPlayheadLineWidth = 1.0;
constexpr qreal kPlayheadPeakPlaying = 0.13;
constexpr qreal kPlayheadPeakPaused = 0.06;

struct PlayheadGradientStop
{
    qreal position;    // 0.0 to 1.0
    qreal alphaFactor; // t * t
};

constexpr std::array<PlayheadGradientStop, 9> kPlayheadGradientStops = [] {
    std::array<PlayheadGradientStop, 9> stops{};
    for (int i = 0; i <= 8; ++i) {
        const qreal t = static_cast<qreal>(i) / 8.0;
        stops[static_cast<std::size_t>(i)] = PlayheadGradientStop{t, t * t};
    }
    return stops;
}();

inline constexpr qreal playheadGlowLeftExtent(bool playing)
{
    return playing ? static_cast<qreal>(kPlayheadGlowRadius - 1)
                   : static_cast<qreal>(kPlayheadGlowRadius);
}

inline constexpr qreal playheadGlowRightExtent(bool playing)
{
    return playing ? (kPlayheadLineWidth / 2.0)
                   : static_cast<qreal>(kPlayheadGlowRadius);
}

inline constexpr qreal playheadPeakAlpha(bool playing)
{
    return playing ? kPlayheadPeakPlaying : kPlayheadPeakPaused;
}

class PlayheadOverlay final : public QWidget
{
public:
    explicit PlayheadOverlay(QWidget *owner, TimelineSurfaces surfaces);
    void setPlayhead(qreal timelineX, bool visible, bool playing);
    ~PlayheadOverlay() override;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void changeEvent(QEvent *event) override;
    void paintEvent(QPaintEvent *event) override;

private:
    qreal finalX() const
    {
        return static_cast<qreal>(m_timelineOrigin) + m_timelineX;
    }

    QRect visibleSurfaceRect(const QWidget *surface, QWidget *owner,
                             int origin) const;
    void observeSurfaceGeometry();
    void synchronizeGeometry();
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    struct Platform;
    struct PlatformDeleter
    {
        void operator()(Platform *platform) const;
    };

    void initializePlatform(QWidget &owner);
    void setPlatformLayout();
    void setPlatformImages();
    bool setPlatformPosition();
#endif
    bool updateImages();
    void updatePlayhead();

    QRegion playheadRegion() const;
    void updatePaintRegion();

    TimelineSurfaces m_surfaces;
    QColor m_color;
    QImage m_bodyImage;
    qreal m_bodyImageLeftExtent = 0.0;
    QImage m_triangleImage;

    int m_cachedBodyHeight = -1;
    bool m_cachedBodyPlaying = false;
    qreal m_cachedBodyDpr = 0.0;
    QColor m_cachedBodyThemeColor;
    bool m_cachedBodyValid = false;

    bool m_cachedTrianglePointsUp = false;
    qreal m_cachedTriangleDpr = 0.0;
    QColor m_cachedTriangleThemeColor;
    bool m_cachedTriangleValid = false;

#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    std::unique_ptr<Platform, PlatformDeleter> m_platform;
#endif
    QRegion m_lastPaintedRegion;

    QRegion m_visibleSurfaceRegion;
    QRect m_playheadGeometry;
    QRect m_triangleClip;
    qreal m_timelineX = 0.0;
    int m_timelineOrigin = 0;
    bool m_visible = false;
    bool m_playing = false;

    bool m_trianglePointsUp = false;
    qreal m_devicePixelRatio = 1.0;
    bool m_platformApplied = false;
#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    bool m_platformAttempted = false;
#endif
};

} // namespace songview
