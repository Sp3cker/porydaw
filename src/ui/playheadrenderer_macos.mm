#include "playheadoverlay.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QGuiApplication>
#include <QImage>
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

struct ReleaseObject {
  template <class T> void operator()(T *object) const noexcept {
    [object release];
  }
};

template <class T> using RetainedObject = std::unique_ptr<T, ReleaseObject>;

struct ReleaseCoreFoundation {
  template <class T> void operator()(T *object) const noexcept {
    if (object) {
      CFRelease(object);
    }
  }
};

template <class T>
using RetainedCoreFoundation = std::unique_ptr<T, ReleaseCoreFoundation>;

class DisabledActionTransaction final {
public:
  DisabledActionTransaction() {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
  }

  ~DisabledActionTransaction() { [CATransaction commit]; }

  DisabledActionTransaction(const DisabledActionTransaction &) = delete;
  DisabledActionTransaction(DisabledActionTransaction &&) = delete;
  DisabledActionTransaction &
  operator=(const DisabledActionTransaction &) = delete;
  DisabledActionTransaction &operator=(DisabledActionTransaction &&) = delete;
};

void setLayerRect(CALayer *layer, const CGRect &rect) {
  layer.bounds = CGRectMake(0.0, 0.0, rect.size.width, rect.size.height);
  layer.position = rect.origin;
}

void setLayerContents(CALayer *layer, const QImage &image) {
  if (image.isNull()) {
    layer.contents = nil;
    return;
  }

  auto imageRef = RetainedCoreFoundation<CGImage>{image.toCGImage()};
  layer.contents = (id)imageRef.get();

  const qreal dpr =
      image.devicePixelRatio() > 0.0 ? image.devicePixelRatio() : 1.0;
  const QSizeF logicalSize = image.deviceIndependentSize();
  layer.contentsScale = dpr;
  layer.bounds =
      CGRectMake(0.0, 0.0, logicalSize.width(), logicalSize.height());
}

} // namespace

class MacPlayheadBackend final : public PlayheadBackend {
public:
  explicit MacPlayheadBackend(QWidget &owner) : m_owner(owner) {
    DisabledActionTransaction transaction;

    m_rootLayer.reset([CALayer new]);
    m_rootLayer.get().name = @"PorydawPlayheadLayer";

    m_bodyClipLayer.reset([CALayer new]);
    m_bodyMaskLayer.reset([CAShapeLayer new]);
    m_bodyLayer.reset([CALayer new]);

    m_triangleClipLayer.reset([CALayer new]);
    m_triangleMaskLayer.reset([CAShapeLayer new]);
    m_triangleLayer.reset([CALayer new]);

    const std::array<CALayer *, 7> layers = {
        m_rootLayer.get(),         m_bodyClipLayer.get(),
        m_bodyMaskLayer.get(),     m_bodyLayer.get(),
        m_triangleClipLayer.get(), m_triangleMaskLayer.get(),
        m_triangleLayer.get()};
    for (auto *layer : layers) {
      layer.anchorPoint = CGPointZero;
    }

    m_rootLayer.get().geometryFlipped = NO;
    m_rootLayer.get().hidden = YES;

    auto maskColor =
        RetainedCoreFoundation<CGColor>{CGColorCreateSRGB(1.0, 1.0, 1.0, 1.0)};
    m_bodyMaskLayer.get().fillColor = maskColor.get();
    m_triangleMaskLayer.get().fillColor = maskColor.get();

    m_bodyClipLayer.get().mask = m_bodyMaskLayer.get();
    m_triangleClipLayer.get().mask = m_triangleMaskLayer.get();

    [m_bodyClipLayer.get() addSublayer:m_bodyLayer.get()];
    [m_triangleClipLayer.get() addSublayer:m_triangleLayer.get()];

    [m_rootLayer.get() addSublayer:m_bodyClipLayer.get()];
    [m_rootLayer.get() addSublayer:m_triangleClipLayer.get()];

    if (m_owner.isVisible()) {
      attachToNativeView();
    }
  }

  ~MacPlayheadBackend() override { [m_rootLayer.get() removeFromSuperlayer]; }

  PlayheadSyncResult synchronize(const PlayheadFrame &frame) override {
    attachToNativeView();
    if (!m_attachedView || m_rootLayer.get().superlayer != m_attachedView.layer)
      return {PlayheadSyncState::Deferred, {}};

    DisabledActionTransaction transaction;
    if (!m_hasStaticGeneration ||
        m_cachedStaticGeneration != frame.staticGeneration) {
      setLayout(frame.overlaySize, frame.bodyClip, frame.triangleClip);
      m_cachedStaticGeneration = frame.staticGeneration;
      m_hasStaticGeneration = true;
    }
    setImages(frame.bodyImage, frame.bodyImageLeftExtent, frame.triangleImage);
    setPosition(frame.x, frame.playheadGeometry.top(), frame.visible);
    return {PlayheadSyncState::Applied, {}};
  }

  void attachToNativeView() {
    WId ownerWId = m_owner.internalWinId();
    if (ownerWId == 0 && m_owner.isVisible()) {
      ownerWId = m_owner.winId();
    }
    auto *ownerView = ownerWId ? reinterpret_cast<NSView *>(ownerWId) : nullptr;
    if (ownerView == m_attachedView &&
        (!ownerView || m_rootLayer.get().superlayer == ownerView.layer)) {
      return;
    }

    [m_rootLayer.get() removeFromSuperlayer];
    m_attachedView = nullptr;
    if (ownerView) {
      ownerView.wantsLayer = YES;
      [ownerView.layer addSublayer:m_rootLayer.get()];
      m_attachedView = ownerView;
    }
  }

  void setLayout(const QSize &overlaySize, const QRegion &visibleSurfaces,
                 const QRect &triangleClip) {
    if (m_hasLayout && m_overlaySize == overlaySize &&
        m_visibleSurfaces == visibleSurfaces &&
        m_triangleClip == triangleClip) {
      return;
    }
    const auto rootBounds =
        CGRectMake(0.0, 0.0, overlaySize.width(), overlaySize.height());
    setLayerRect(m_rootLayer.get(), rootBounds);
    setLayerRect(m_bodyClipLayer.get(), rootBounds);
    setLayerRect(m_bodyMaskLayer.get(), rootBounds);
    setLayerRect(m_triangleClipLayer.get(), rootBounds);
    setLayerRect(m_triangleMaskLayer.get(), rootBounds);

    auto surfacePath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
    for (const QRect &rect : visibleSurfaces) {
      CGPathAddRect(
          surfacePath.get(), nullptr,
          CGRectMake(rect.x(), rect.y(), rect.width(), rect.height()));
    }
    m_bodyMaskLayer.get().path = surfacePath.get();

    auto trianglePath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
    CGPathAddRect(trianglePath.get(), nullptr,
                  CGRectMake(triangleClip.x(), triangleClip.y(),
                             triangleClip.width(), triangleClip.height()));
    m_triangleMaskLayer.get().path = trianglePath.get();

    m_overlaySize = overlaySize;
    m_visibleSurfaces = visibleSurfaces;
    m_triangleClip = triangleClip;
    m_hasLayout = true;
  }

  void setImages(const QImage &bodyImage, qreal bodyImageLeftExtent,
                 const QImage &triangleImage) {
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

  void setPosition(qreal finalX, int top, bool visible) {
    m_bodyLayer.get().position =
        CGPointMake(finalX - m_bodyImageLeftExtent, top);
    m_triangleLayer.get().position =
        CGPointMake(finalX - kPlayheadTriangleHalfWidth, top);
    m_rootLayer.get().hidden = visible ? NO : YES;
  }

private:
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
  QRegion m_visibleSurfaces;
  QRect m_triangleClip;
  bool m_hasLayout = false;
  quint64 m_cachedStaticGeneration = 0;
  bool m_hasStaticGeneration = false;

  qint64 m_bodyImageCacheKey = -1;
  qint64 m_triangleImageCacheKey = -1;
  qreal m_bodyImageLeftExtent = 0.0;
};

std::unique_ptr<PlayheadBackend> createPlayheadBackend(QWidget &owner) {
  if (QGuiApplication::platformName() != QLatin1String("cocoa"))
    return {};
  return std::make_unique<MacPlayheadBackend>(owner);
}

} // namespace songview
