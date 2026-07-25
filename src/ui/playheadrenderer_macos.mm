#include "playheadoverlay.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QImage>
#include <QRegion>
#include <QWidget>
#include <array>
#include <memory>
#include <utility>

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

auto makeDisabledActions() -> RetainedObject<NSDictionary> {
  auto *disabled = [NSNull null];
  return RetainedObject<NSDictionary> {
    [@{
      @"anchorPoint" : disabled,
      @"backgroundColor" : disabled,
      @"bounds" : disabled,
      @"contents" : disabled,
      @"hidden" : disabled,
      @"mask" : disabled,
      @"position" : disabled,
      @"sublayers" : disabled,
      @"transform" : disabled,
    } retain]
  };
}

void configureLayer(CALayer *layer, NSDictionary *disabledActions) {
  layer.actions = disabledActions;
  layer.anchorPoint = CGPointZero;
}

void setLayerRect(CALayer *layer, const CGRect &rect) {
  layer.bounds = CGRectMake(0.0, 0.0, rect.size.width, rect.size.height);
  layer.position = rect.origin;
}

} // namespace

class PlayheadOverlay::Platform final {
public:
  explicit Platform(PlayheadOverlay &overlay) : m_overlay(overlay) {
    auto disabledActions = makeDisabledActions();

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
      configureLayer(layer, disabledActions.get());
    }

    m_rootLayer.get().geometryFlipped = YES;
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

    attachToNativeView();
  }

  ~Platform() { [m_rootLayer.get() removeFromSuperlayer]; }

  void attachToNativeView() {
    auto *parentWidget = m_overlay.parentWidget();
    if (!parentWidget) {
      if (m_attachedView) {
        [m_rootLayer.get() removeFromSuperlayer];
        m_attachedView = nullptr;
      }
      return;
    }
    WId parentWId = parentWidget->internalWinId();
    if (parentWId == 0 && parentWidget->isVisible()) {
      parentWId = parentWidget->winId();
    }
    auto *parentView =
        parentWId ? reinterpret_cast<NSView *>(parentWId) : nullptr;
    if (parentView != m_attachedView ||
        (parentView && m_rootLayer.get().superlayer != parentView.layer)) {
      if (m_attachedView && m_attachedView != parentView) {
        [m_rootLayer.get() removeFromSuperlayer];
        m_attachedView = nullptr;
      }
      if (parentView) {
        parentView.wantsLayer = YES;
        if (m_rootLayer.get().superlayer != parentView.layer) {
          [m_rootLayer.get() removeFromSuperlayer];
          [parentView.layer addSublayer:m_rootLayer.get()];
        }
        m_attachedView = parentView;
      }
    }
  }

  void synchronize() {
    attachToNativeView();

    const bool positionOnly =
        m_hasSynced &&
        m_lastVisibleSurfaceRegion == m_overlay.m_visibleSurfaceRegion &&
        m_lastTriangleClip == m_overlay.m_triangleClip &&
        m_lastOverlaySize == m_overlay.size() &&
        m_lastBodyImageCacheKey == m_overlay.m_bodyImage.cacheKey() &&
        m_lastTriangleImageCacheKey == m_overlay.m_triangleImage.cacheKey();

    DisabledActionTransaction transaction;

    if (!positionOnly) {
      const auto rootBounds =
          CGRectMake(0.0, 0.0, m_overlay.width(), m_overlay.height());
      setLayerRect(m_rootLayer.get(), rootBounds);
      setLayerRect(m_bodyClipLayer.get(), rootBounds);
      setLayerRect(m_bodyMaskLayer.get(), rootBounds);
      setLayerRect(m_triangleClipLayer.get(), rootBounds);
      setLayerRect(m_triangleMaskLayer.get(), rootBounds);

      if (!m_hasSynced ||
          m_lastVisibleSurfaceRegion != m_overlay.m_visibleSurfaceRegion) {
        auto surfacePath =
            RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
        for (const QRect &rect : m_overlay.m_visibleSurfaceRegion) {
          CGPathAddRect(
              surfacePath.get(), nullptr,
              CGRectMake(rect.x(), rect.y(), rect.width(), rect.height()));
        }
        m_bodyMaskLayer.get().path = surfacePath.get();
        m_lastVisibleSurfaceRegion = m_overlay.m_visibleSurfaceRegion;
      }

      if (!m_hasSynced || m_lastTriangleClip != m_overlay.m_triangleClip) {
        auto triangleMaskPath =
            RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
        CGPathAddRect(triangleMaskPath.get(), nullptr,
                      CGRectMake(m_overlay.m_triangleClip.x(),
                                 m_overlay.m_triangleClip.y(),
                                 m_overlay.m_triangleClip.width(),
                                 m_overlay.m_triangleClip.height()));
        m_triangleMaskLayer.get().path = triangleMaskPath.get();
        m_lastTriangleClip = m_overlay.m_triangleClip;
      }

      if (!m_hasSynced ||
          m_lastBodyImageCacheKey != m_overlay.m_bodyImage.cacheKey()) {
        if (!m_overlay.m_bodyImage.isNull()) {
          CGImageRef cgImg = m_overlay.m_bodyImage.toCGImage();
          m_bodyLayer.get().contents = (id)cgImg;
          CGImageRelease(cgImg);
          const qreal dpr = m_overlay.m_bodyImage.devicePixelRatio() > 0.0
                                ? m_overlay.m_bodyImage.devicePixelRatio()
                                : 1.0;
          m_bodyLayer.get().contentsScale = dpr;
          const CGFloat logicalW = m_overlay.m_bodyImage.width() / dpr;
          const CGFloat logicalH = m_overlay.m_bodyImage.height() / dpr;
          m_bodyLayer.get().bounds = CGRectMake(0.0, 0.0, logicalW, logicalH);
        } else {
          m_bodyLayer.get().contents = nil;
        }
        m_lastBodyImageCacheKey = m_overlay.m_bodyImage.cacheKey();
      }

      if (!m_hasSynced ||
          m_lastTriangleImageCacheKey != m_overlay.m_triangleImage.cacheKey()) {
        if (!m_overlay.m_triangleImage.isNull()) {
          QImage vertFlipped = m_overlay.m_triangleImage.flipped(Qt::Vertical);
          CGImageRef cgImg = vertFlipped.toCGImage();
          m_triangleLayer.get().contents = (id)cgImg;
          CGImageRelease(cgImg);
          const qreal dpr = m_overlay.m_triangleImage.devicePixelRatio() > 0.0
                                ? m_overlay.m_triangleImage.devicePixelRatio()
                                : 1.0;
          m_triangleLayer.get().contentsScale = dpr;
          const CGFloat logicalW = m_overlay.m_triangleImage.width() / dpr;
          const CGFloat logicalH = m_overlay.m_triangleImage.height() / dpr;
          m_triangleLayer.get().bounds =
              CGRectMake(0.0, 0.0, logicalW, logicalH);
        } else {
          m_triangleLayer.get().contents = nil;
        }
        m_lastTriangleImageCacheKey = m_overlay.m_triangleImage.cacheKey();
      }

      m_lastOverlaySize = m_overlay.size();
    }

    const qreal finalX = m_overlay.finalX();
    const CGFloat bodyX = finalX - m_overlay.m_bodyImageLeftExtent;
    const CGFloat bodyY = m_overlay.m_playheadGeometry.top();
    m_bodyLayer.get().position = CGPointMake(bodyX, bodyY);

    const CGFloat triX = finalX - kPlayheadTriangleHalfWidth;
    const CGFloat triY = m_overlay.m_playheadGeometry.top();
    m_triangleLayer.get().position = CGPointMake(triX, triY);

    m_rootLayer.get().hidden = m_overlay.m_visible ? NO : YES;
    m_hasSynced = true;
  }

  void paint(QPaintEvent *) {}

private:
  PlayheadOverlay &m_overlay;
  NSView *m_attachedView = nullptr;
  RetainedObject<CALayer> m_rootLayer;
  RetainedObject<CALayer> m_bodyClipLayer;
  RetainedObject<CAShapeLayer> m_bodyMaskLayer;
  RetainedObject<CALayer> m_bodyLayer;
  RetainedObject<CALayer> m_triangleClipLayer;
  RetainedObject<CAShapeLayer> m_triangleMaskLayer;
  RetainedObject<CALayer> m_triangleLayer;

  QRegion m_lastVisibleSurfaceRegion;
  QRect m_lastTriangleClip;
  QSize m_lastOverlaySize;
  qint64 m_lastBodyImageCacheKey = -1;
  qint64 m_lastTriangleImageCacheKey = -1;
  bool m_hasSynced = false;
};

void PlayheadOverlay::initializePlatform() {
  m_platform.reset(new Platform(*this));
}

void PlayheadOverlay::synchronizePlatform() {
  if (m_platform) {
    m_platform->synchronize();
  }
}

void PlayheadOverlay::paintPlatform(QPaintEvent *event) {
  if (m_platform) {
    m_platform->paint(event);
  }
}

void PlayheadOverlay::PlatformDeleter::operator()(Platform *platform) const {
  delete platform;
}
PlayheadOverlay::~PlayheadOverlay() = default;

} // namespace songview
