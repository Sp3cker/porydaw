#include "playheadoverlay.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include "nativelayerutils_macos_p.h"

#include <QGuiApplication>
#include <QImage>
#include <QPoint>
#include <QRect>
#include <QRegion>
#include <QSize>
#include <QWidget>
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

void setLayerContents(CALayer *layer, const QImage &image)
{
    if (image.isNull()) {
        layer.contents = nil;
        return;
    }

    auto imageRef = RetainedCoreFoundation<CGImage>{image.toCGImage()};
    layer.contents = (id)imageRef.get();

    const qreal dpr = image.devicePixelRatio() > 0.0 ? image.devicePixelRatio() : 1.0;
    const QSizeF logicalSize = image.deviceIndependentSize();
    layer.contentsScale = dpr;
    layer.bounds = CGRectMake(0.0, 0.0, logicalSize.width(), logicalSize.height());
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

        m_triangleClipLayer.reset([CALayer new]);
        m_triangleMaskLayer.reset([CAShapeLayer new]);
        m_triangleLayer.reset([CALayer new]);

        const std::array<CALayer *, 7> layers = {
            m_rootLayer.get(),    m_bodyClipLayer.get(),     m_bodyMaskLayer.get(),
            m_bodyLayer.get(),    m_triangleClipLayer.get(), m_triangleMaskLayer.get(),
            m_triangleLayer.get()};
        for (auto *layer : layers) {
            layer.anchorPoint = CGPointZero;
        }

        m_rootLayer.get().geometryFlipped = NO;
        m_rootLayer.get().hidden = YES;

        auto maskColor = RetainedCoreFoundation<CGColor>{CGColorCreateSRGB(1.0, 1.0, 1.0, 1.0)};
        m_bodyMaskLayer.get().fillColor = maskColor.get();
        m_triangleMaskLayer.get().fillColor = maskColor.get();

        m_bodyClipLayer.get().mask = m_bodyMaskLayer.get();
        m_triangleClipLayer.get().mask = m_triangleMaskLayer.get();

        [m_bodyClipLayer.get() addSublayer:m_bodyLayer.get()];
        [m_triangleClipLayer.get() addSublayer:m_triangleLayer.get()];

        [m_rootLayer.get() addSublayer:m_bodyClipLayer.get()];
        [m_rootLayer.get() addSublayer:m_triangleClipLayer.get()];

        attachToNativeView();
    }

    ~Platform() { [m_rootLayer.get() removeFromSuperlayer]; }

    void setLayout(const QSize &overlaySize, const QRegion &visibleSurfaces,
                   const QRect &triangleClip)
    {
        attachToNativeView();
        const QPoint overlayOffset = m_owner.mapTo(m_owner.window(), QPoint(0, 0));
        if (m_hasLayout && m_overlaySize == overlaySize && m_overlayOffset == overlayOffset &&
            m_visibleSurfaces == visibleSurfaces && m_triangleClip == triangleClip) {
            return;
        }

        DisabledActionTransaction transaction;
        const auto rootRect = CGRectMake(overlayOffset.x(), overlayOffset.y(), overlaySize.width(),
                                         overlaySize.height());
        const auto rootBounds = CGRectMake(0.0, 0.0, overlaySize.width(), overlaySize.height());
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

        m_overlaySize = overlaySize;
        m_overlayOffset = overlayOffset;
        m_visibleSurfaces = visibleSurfaces;
        m_triangleClip = triangleClip;
        m_hasLayout = true;
    }

    void setImages(const QImage &bodyImage, qreal bodyImageLeftExtent, const QImage &triangleImage)
    {
        DisabledActionTransaction transaction;
        const auto bodyImageCacheKey = bodyImage.cacheKey();
        if (m_bodyImageCacheKey != bodyImageCacheKey) {
            setLayerContents(m_bodyLayer.get(), bodyImage);
            m_bodyImageLeftExtent = bodyImageLeftExtent;
            m_bodyImageCacheKey = bodyImageCacheKey;
        }

        const auto triangleImageCacheKey = triangleImage.cacheKey();
        if (m_triangleImageCacheKey != triangleImageCacheKey) {
            setLayerContents(m_triangleLayer.get(), triangleImage);
            m_triangleImageCacheKey = triangleImageCacheKey;
        }
    }

    bool setPosition(qreal finalX, int bodyTop, int triangleTop, bool visible)
    {
        attachToNativeView();
        if (!m_attachedView || m_rootLayer.get().superlayer != m_attachedView.layer)
            return false;

        DisabledActionTransaction transaction;
        m_bodyLayer.get().position = CGPointMake(finalX - m_bodyImageLeftExtent, bodyTop);
        m_triangleLayer.get().position =
            CGPointMake(finalX - playheadTriangleHalfWidth(), triangleTop);
        m_rootLayer.get().hidden = visible ? NO : YES;
        return true;
    }

  private:
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

    RetainedObject<CALayer> m_triangleClipLayer;
    RetainedObject<CAShapeLayer> m_triangleMaskLayer;
    RetainedObject<CALayer> m_triangleLayer;

    QSize m_overlaySize;
    QPoint m_overlayOffset;
    QRegion m_visibleSurfaces;
    QRect m_triangleClip;
    bool m_hasLayout = false;

    qint64 m_bodyImageCacheKey = -1;
    qint64 m_triangleImageCacheKey = -1;
    qreal m_bodyImageLeftExtent = 0.0;
};

void PlayheadOverlay::initializePlatform(QWidget &owner)
{
    if (QGuiApplication::platformName() != QLatin1String("cocoa"))
        return;

    m_platform.reset(new Platform(owner));
}

void PlayheadOverlay::setPlatformLayout()
{
    Q_ASSERT(m_platform);
    m_platform->setLayout(size(), m_visibleSurfaceRegion, m_triangleClip);
}

void PlayheadOverlay::setPlatformImages()
{
    Q_ASSERT(m_platform);
    m_platform->setImages(m_bodyImage, m_bodyImageLeftExtent, m_triangleImage);
}

bool PlayheadOverlay::setPlatformPosition()
{
    Q_ASSERT(m_platform);
    return m_platform->setPosition(finalX(), m_bodyGeometry.top(), m_triangleClip.top(), m_visible);
}

void PlayheadOverlay::PlatformDeleter::operator()(Platform *platform) const
{
    delete platform;
}

} // namespace songview
