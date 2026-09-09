#pragma once

#include "songview/timelinebandlayout.h"

#include <QColor>
#include <QObject>
#include <QPointer>
#include <QRectF>
#include <QVector>
#include <memory>

class QQuickWindow;
class SongView;

namespace songview {
class QuickPopupSession;
class TimelineQuickView;

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

    // Platform-surface lifecycle: teardown drops the native attachment before
    // the surface dies; (re)creation or a show transition re-syncs geometry
    // and re-attaches.
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    songview::TimelineQuickView *quickView() const;
    QQuickWindow *quickWindow() const;
    void ensureWindowTracking();
    void clearNativeAttachment();

    QRectF canvasTimelineColumnRect() const;
    QRectF timelineColumnRect() const;
    bool effectiveVisible() const;

    void synchronizeGeometry();
#ifdef __APPLE__
    class Platform;
    struct PlatformDeleter {
        void operator()(Platform *platform) const;
    };

    void initializePlatform();
    void setPlatformLayout();
    void setPlatformImages();
    void detachPlatform();
    void setPlatformPosition();
#endif
    void updatePlayhead();

    SongView &m_owner;
    TimelineBandLayout m_layout;
    QColor m_color;

    // Quick window the overlay is anchored to: watched for platform-surface
    // teardown/recreate, and cleared via TimelineQuickView's detach signal.
    QPointer<QQuickWindow> m_filteredWindow;
    bool m_detachConnected = false;
    bool m_inputEligibilityConnected = false;

#ifdef __APPLE__
    QPointer<QuickPopupSession> m_popupSession;
#endif

#ifdef __APPLE__
    std::unique_ptr<Platform, PlatformDeleter> m_platform;
    QVector<QRectF> m_visibleSurfaceRects;
    QVector<QRectF> m_triangleClips;
    qreal m_triangleTop = 0.0;
    QRectF m_bodyGeometry;
#endif

    qreal m_timelineX = 0.0;
    bool m_visible = false;
    bool m_playing = false;
    bool m_trianglePointsUp = false;
#ifdef __APPLE__
    qreal m_devicePixelRatio = 1.0;
#endif
};

} // namespace songview
