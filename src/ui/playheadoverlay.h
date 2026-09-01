#pragma once

#include <QColor>
#include <QPainterPath>
#include <QPointer>
#include <QRect>
#include <QRegion>
#include <QSize>
#include <QWidget>
#include <memory>
#include <vector>
#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
#include <QImage>
#endif

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

struct PlayheadBand {
    QWidget &widget;
    int timelineOrigin;
};

/// Whether the platform-native playhead renderer is enabled for this process.
bool platformPlayheadRendererEnabled();

class PlayheadOverlay final : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PlayheadOverlay)

  public:
    explicit PlayheadOverlay(QWidget &owner, PlayheadBand rulerBand, QWidget &rollBand,
                             std::vector<PlayheadBand> clipBands);
    ~PlayheadOverlay() override;

    void setPlayhead(qreal timelineX, bool visible, bool playing);
    void updateBands(PlayheadBand rulerBand, QWidget &rollBand,
                     std::vector<PlayheadBand> clipBands);

  protected:
    void paintEvent(QPaintEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;
    void changeEvent(QEvent *event) override;

  private:
    qreal finalX() const { return static_cast<qreal>(m_timelineOrigin) + m_timelineX; }

    QRect visibleSurfaceRect(const QWidget *surface, QWidget *owner, int origin) const;
    QRegion fallbackPaintRegion() const;
    const QPainterPath &playheadTrianglePath();
    void removeObservedSurfaceFilters();
    void observeSurfaceGeometry();
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
#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
    bool updateImages();
#endif
#endif
    void updatePlayhead();

    PlayheadBand m_rulerBand;
    QWidget &m_rollBand;
    std::vector<PlayheadBand> m_clipBands;
    QColor m_color;
    QPainterPath m_playheadTrianglePath;
    QSize m_playheadTrianglePathSize;

#ifdef PORYDAW_USE_MACOS_PLAYHEAD_IMAGES
    // Pre-rendered strips are used only by the CALayer renderer. DirectComposition
    // paints its own D2D surfaces, and the QWidget fallback allocates no images.
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
    QSize m_cachedTriangleSize;
    bool m_cachedTriangleValid = false;
#endif

#ifdef PORYDAW_USE_DIRECT_PLAYHEAD
    std::unique_ptr<Platform, PlatformDeleter> m_platform;
#endif
    std::vector<QPointer<QWidget>> m_observedSurfaceChain;
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
