#include "playheadoverlay.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include "nativelayerutils_macos_p.h"
#include "songview.h"

#include <QColor>
#include <QGuiApplication>
#include <QPoint>
#include <QRect>
#include <QRegion>
#include <QWidget>
#include <algorithm>
#include <array>
#include <memory>

#if __has_feature(objc_arc)
#error playheadrenderer_macos.mm must be compiled without ARC
#endif

namespace songview {

namespace {

using native_layer::DisabledActionTransaction;
using native_layer::RetainedCoreFoundation;
using native_layer::RetainedObject;
using native_layer::setLayerRect;

constexpr CGFloat kPlayheadOverlayZPosition = 1'000'000.0;

void setLayerColor(CALayer *layer, const QColor &color)
{
    auto nativeColor = RetainedCoreFoundation<CGColor>{
        CGColorCreateSRGB(color.redF(), color.greenF(), color.blueF(), color.alphaF())};
    layer.backgroundColor = nativeColor.get();
}

void setShapeColor(CAShapeLayer *layer, const QColor &color)
{
    auto nativeColor = RetainedCoreFoundation<CGColor>{
        CGColorCreateSRGB(color.redF(), color.greenF(), color.blueF(), color.alphaF())};
    layer.fillColor = nativeColor.get();
}

void setGradientColors(CAGradientLayer *left, CAGradientLayer *right, const QColor &color,
                       qreal peakAlpha)
{
    RetainedObject<NSMutableArray> colors{[[NSMutableArray alloc] initWithCapacity:9]};
    RetainedObject<NSMutableArray> locations{[[NSMutableArray alloc] initWithCapacity:9]};
    for (int index = 0; index <= 8; ++index) {
        const qreal t = qreal(index) / 8.0;
        auto stopColor = RetainedCoreFoundation<CGColor>{
            CGColorCreateSRGB(color.redF(), color.greenF(), color.blueF(), peakAlpha * t * t)};
        [colors.get() addObject:(id)stopColor.get()];
        [locations.get() addObject:@(t)];
    }
    left.colors = colors.get();
    left.locations = locations.get();
    right.colors = colors.get();
    right.locations = locations.get();
}

} // namespace

class PlayheadOverlay::Platform final
{
  public:
    explicit Platform(QWidget &owner) : m_owner(owner)
    {
        DisabledActionTransaction transaction;

        m_rootLayer.reset([CALayer new]);
        m_rootLayer.get().name = @"PorydawPlayheadLayer";
        m_rootLayer.get().zPosition = kPlayheadOverlayZPosition;

        m_bodyClipLayer.reset([CALayer new]);
        m_bodyMaskLayer.reset([CAShapeLayer new]);
        m_bodyLayer.reset([CALayer new]);
        m_leftGlowLayer.reset([CAGradientLayer new]);
        m_rightGlowLayer.reset([CAGradientLayer new]);
        m_coreLayer.reset([CALayer new]);

        m_triangleClipLayer.reset([CALayer new]);
        m_triangleMaskLayer.reset([CAShapeLayer new]);
        m_triangleLayer.reset([CAShapeLayer new]);

        const std::array<CALayer *, 10> layers = {
            m_rootLayer.get(),    m_bodyClipLayer.get(),     m_bodyMaskLayer.get(),
            m_bodyLayer.get(),    m_leftGlowLayer.get(),     m_rightGlowLayer.get(),
            m_coreLayer.get(),    m_triangleClipLayer.get(), m_triangleMaskLayer.get(),
            m_triangleLayer.get()};
        for (auto *layer : layers)
            layer.anchorPoint = CGPointZero;

        m_rootLayer.get().geometryFlipped = NO;
        m_rootLayer.get().hidden = YES;
        m_leftGlowLayer.get().startPoint = CGPointMake(0.0, 0.5);
        m_leftGlowLayer.get().endPoint = CGPointMake(1.0, 0.5);
        m_rightGlowLayer.get().startPoint = CGPointMake(1.0, 0.5);
        m_rightGlowLayer.get().endPoint = CGPointMake(0.0, 0.5);

        auto maskColor = RetainedCoreFoundation<CGColor>{CGColorCreateSRGB(1.0, 1.0, 1.0, 1.0)};
        m_bodyMaskLayer.get().fillColor = maskColor.get();
        m_triangleMaskLayer.get().fillColor = maskColor.get();

        m_bodyClipLayer.get().mask = m_bodyMaskLayer.get();
        m_triangleClipLayer.get().mask = m_triangleMaskLayer.get();

        [m_bodyLayer.get() addSublayer:m_leftGlowLayer.get()];
        [m_bodyLayer.get() addSublayer:m_rightGlowLayer.get()];
        [m_bodyLayer.get() addSublayer:m_coreLayer.get()];
        [m_bodyClipLayer.get() addSublayer:m_bodyLayer.get()];
        [m_triangleClipLayer.get() addSublayer:m_triangleLayer.get()];

        [m_rootLayer.get() addSublayer:m_bodyClipLayer.get()];
        [m_rootLayer.get() addSublayer:m_triangleClipLayer.get()];

        attachToNativeView();
    }

    ~Platform() { [m_rootLayer.get() removeFromSuperlayer]; }

    void setImages(const QColor &color)
    {
        if (m_color == color)
            return;

        DisabledActionTransaction transaction;
        m_color = color;
        updateColors();
    }

    void setLayout(const QRect &timelineColumn, const QRegion &visibleSurfaces,
                   const QRect &triangleClip, const QRect &bodyGeometry, qreal devicePixelRatio,
                   bool playing, bool trianglePointsUp)
    {
        attachToNativeView();
        const QPoint overlayOffset = m_owner.mapTo(m_owner.window(), QPoint(0, 0));
        const qreal dpr = std::max<qreal>(devicePixelRatio, 1.0);
        const bool clipLayoutChanged = !m_hasLayout || m_timelineColumn != timelineColumn ||
                                       m_overlayOffset != overlayOffset ||
                                       m_visibleSurfaces != visibleSurfaces ||
                                       m_triangleClip != triangleClip;
        const bool playingChanged = m_playing != playing;
        m_timelineColumn = timelineColumn;

        m_overlayOffset = overlayOffset;
        m_visibleSurfaces = visibleSurfaces;
        m_triangleClip = triangleClip;
        m_bodyTop = bodyGeometry.top();
        m_bodyHeight = bodyGeometry.height();
        m_triangleTop = triangleClip.top();
        m_devicePixelRatio = dpr;
        m_playing = playing;
        m_trianglePointsUp = trianglePointsUp;

        DisabledActionTransaction transaction;
        if (clipLayoutChanged) {
            const auto rootRect = CGRectMake(overlayOffset.x() + timelineColumn.x(),
                                             overlayOffset.y() + timelineColumn.y(),
                                             timelineColumn.width(), timelineColumn.height());
            const auto rootBounds =
                CGRectMake(0.0, 0.0, timelineColumn.width(), timelineColumn.height());
            setLayerRect(m_rootLayer.get(), rootRect);
            setLayerRect(m_bodyClipLayer.get(), rootBounds);
            setLayerRect(m_bodyMaskLayer.get(), rootBounds);
            setLayerRect(m_triangleClipLayer.get(), rootBounds);
            setLayerRect(m_triangleMaskLayer.get(), rootBounds);

            auto surfacePath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
            for (const QRect &rect : visibleSurfaces) {
                CGPathAddRect(surfacePath.get(), nullptr,
                              CGRectMake(rect.x(), rect.y(), rect.width(), rect.height()));
            }
            m_bodyMaskLayer.get().path = surfacePath.get();

            auto trianglePath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
            CGPathAddRect(trianglePath.get(), nullptr,
                          CGRectMake(triangleClip.x(), triangleClip.y(), triangleClip.width(),
                                     triangleClip.height()));
            m_triangleMaskLayer.get().path = trianglePath.get();
        }
        // Font-scaled metrics can change without changing the overlay's outer
        // geometry, so refresh native vector geometry on every layout sync.
        updateVisualGeometry();
        if (playingChanged)
            updateColors();
        m_hasLayout = true;
    }

    void setPosition(qreal localX, bool visible, bool playing, bool trianglePointsUp)
    {
        attachToNativeView();
        // With no attached native view the playhead silently renders nothing:
        // the position push is retried on the next frame and there is no
        // fallback renderer.

        const bool playingChanged = m_playing != playing;
        const bool visualGeometryChanged = playingChanged || m_trianglePointsUp != trianglePointsUp;
        m_playing = playing;
        m_trianglePointsUp = trianglePointsUp;

        DisabledActionTransaction transaction;
        if (visualGeometryChanged) {
            updateVisualGeometry();
            if (playingChanged)
                updateColors();
        }
        m_bodyLayer.get().position =
            CGPointMake(localX - playheadGlowLeftExtent(playing), m_bodyTop);
        m_triangleLayer.get().position =
            CGPointMake(localX - playheadTriangleHalfWidth(), m_triangleTop);
        m_rootLayer.get().hidden = visible ? NO : YES;
    }

  private:
    void updateColors()
    {
        setGradientColors(m_leftGlowLayer.get(), m_rightGlowLayer.get(), m_color,
                          playheadPeakAlpha(m_playing));
        setLayerColor(m_coreLayer.get(), m_color);
        setShapeColor(m_triangleLayer.get(), m_color);
    }

    void updateVisualGeometry()
    {
        const qreal leftExtent = playheadGlowLeftExtent(m_playing);
        const qreal rightExtent = playheadGlowRightExtent(m_playing);
        const qreal bodyWidth = leftExtent + rightExtent;
        const qreal lineWidth = playheadLineWidth();
        m_bodyLayer.get().bounds = CGRectMake(0.0, 0.0, bodyWidth, m_bodyHeight);
        setLayerRect(m_leftGlowLayer.get(), CGRectMake(0.0, 0.0, leftExtent, m_bodyHeight));
        setLayerRect(m_rightGlowLayer.get(),
                     CGRectMake(leftExtent, 0.0, rightExtent, m_bodyHeight));
        setLayerRect(m_coreLayer.get(),
                     CGRectMake(leftExtent - lineWidth / 2.0, 0.0, lineWidth, m_bodyHeight));

        const qreal triangleWidth = 2.0 * playheadTriangleHalfWidth();
        const qreal triangleHeight = playheadTriangleHeight();
        m_triangleLayer.get().bounds = CGRectMake(0.0, 0.0, triangleWidth, triangleHeight);
        auto trianglePath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
        const qreal baseY = m_trianglePointsUp ? triangleHeight : 0.0;
        const qreal tipY = m_trianglePointsUp ? 0.0 : triangleHeight;
        CGPathMoveToPoint(trianglePath.get(), nullptr, 0.0, baseY);
        CGPathAddLineToPoint(trianglePath.get(), nullptr, triangleWidth, baseY);
        CGPathAddLineToPoint(trianglePath.get(), nullptr, triangleWidth / 2.0, tipY);
        CGPathCloseSubpath(trianglePath.get());
        m_triangleLayer.get().path = trianglePath.get();

        const CGFloat contentsScale = m_devicePixelRatio;
        m_bodyMaskLayer.get().contentsScale = contentsScale;
        m_triangleMaskLayer.get().contentsScale = contentsScale;
        m_triangleLayer.get().contentsScale = contentsScale;
    }

    void attachToNativeView()
    {
        QWidget *topLevel = m_owner.window();
        WId topLevelWId = topLevel ? topLevel->internalWinId() : 0;
        if (topLevelWId == 0 && topLevel && topLevel->isVisible())
            topLevelWId = topLevel->winId();
        auto *ownerView = topLevelWId ? reinterpret_cast<NSView *>(topLevelWId) : nullptr;
        CALayer *ownerLayer = ownerView ? ownerView.layer : nil;
        if (ownerView == m_attachedView &&
            (!ownerView || m_rootLayer.get().superlayer == ownerLayer)) {
            if (m_rootLayer.get().zPosition != kPlayheadOverlayZPosition)
                m_rootLayer.get().zPosition = kPlayheadOverlayZPosition;
            return;
        }

        [m_rootLayer.get() removeFromSuperlayer];
        m_attachedView = nullptr;
        if (ownerLayer) {
            [ownerLayer addSublayer:m_rootLayer.get()];
            m_rootLayer.get().zPosition = kPlayheadOverlayZPosition;
            m_attachedView = ownerView;
        }
    }

    QWidget &m_owner;
    NSView *m_attachedView = nullptr;

    RetainedObject<CALayer> m_rootLayer;
    RetainedObject<CALayer> m_bodyClipLayer;
    RetainedObject<CAShapeLayer> m_bodyMaskLayer;
    RetainedObject<CALayer> m_bodyLayer;
    RetainedObject<CAGradientLayer> m_leftGlowLayer;
    RetainedObject<CAGradientLayer> m_rightGlowLayer;
    RetainedObject<CALayer> m_coreLayer;

    RetainedObject<CALayer> m_triangleClipLayer;
    RetainedObject<CAShapeLayer> m_triangleMaskLayer;
    RetainedObject<CAShapeLayer> m_triangleLayer;

    QRect m_timelineColumn;
    QPoint m_overlayOffset;
    QRegion m_visibleSurfaces;
    QRect m_triangleClip;
    QColor m_color;
    int m_bodyTop = 0;
    int m_bodyHeight = 0;
    int m_triangleTop = 0;
    qreal m_devicePixelRatio = 1.0;
    bool m_playing = false;
    bool m_trianglePointsUp = false;
    bool m_hasLayout = false;
};

void PlayheadOverlay::initializePlatform(SongView &owner)
{
    // No Platform off-cocoa (offscreen/CI): the overlay stays silent and
    // retries next frame. Offscreen WIds are not NSViews, so construction —
    // not a pointer check at attach time — is the correct gate.
    if (QGuiApplication::platformName() != QLatin1String("cocoa"))
        return;

    m_platform.reset(new Platform(owner));
}

void PlayheadOverlay::setPlatformLayout()
{
    Q_ASSERT(m_platform);
    m_platform->setLayout(timelineColumnRect(), m_visibleSurfaceRegion, m_triangleClip,
                          m_bodyGeometry, m_devicePixelRatio, m_playing, m_trianglePointsUp);
}

void PlayheadOverlay::setPlatformImages()
{
    Q_ASSERT(m_platform);
    m_platform->setImages(m_color);
}

void PlayheadOverlay::setPlatformPosition()
{
    Q_ASSERT(m_platform);
    m_platform->setPosition(m_timelineX, effectiveVisible(), m_playing, m_trianglePointsUp);
}

void PlayheadOverlay::PlatformDeleter::operator()(Platform *platform) const
{
    delete platform;
}

} // namespace songview
