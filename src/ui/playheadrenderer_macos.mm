#include "playheadoverlay.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QColor>
#include <QGuiApplication>
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

} // namespace

class PlayheadOverlay::Platform final {
public:
  explicit Platform(QWidget &owner) : m_owner(owner) {
    DisabledActionTransaction transaction;

    m_rootLayer.reset([CALayer new]);
    m_rootLayer.get().name = @"PorydawPlayheadLayer";

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
        m_rootLayer.get(),         m_bodyClipLayer.get(),
        m_bodyMaskLayer.get(),     m_bodyLayer.get(),
        m_leftGlowLayer.get(),     m_rightGlowLayer.get(),
        m_coreLayer.get(),         m_triangleClipLayer.get(),
        m_triangleMaskLayer.get(), m_triangleLayer.get()};
    for (auto *layer : layers) {
      layer.anchorPoint = CGPointZero;
    }

    m_rootLayer.get().geometryFlipped = NO;
    m_rootLayer.get().hidden = YES;
    m_leftGlowLayer.get().startPoint = CGPointMake(0.0, 0.5);
    m_leftGlowLayer.get().endPoint = CGPointMake(1.0, 0.5);

    m_rightGlowLayer.get().startPoint = CGPointMake(1.0, 0.5);
    m_rightGlowLayer.get().endPoint = CGPointMake(0.0, 0.5);

    CGColorRef maskColor = CGColorCreateSRGB(1.0, 1.0, 1.0, 1.0);
    m_bodyMaskLayer.get().fillColor = maskColor;
    m_triangleMaskLayer.get().fillColor = maskColor;
    CGColorRelease(maskColor);

    m_bodyClipLayer.get().mask = m_bodyMaskLayer.get();
    m_triangleClipLayer.get().mask = m_triangleMaskLayer.get();

    [m_bodyLayer.get() addSublayer:m_leftGlowLayer.get()];
    [m_bodyLayer.get() addSublayer:m_rightGlowLayer.get()];
    [m_bodyLayer.get() addSublayer:m_coreLayer.get()];

    [m_bodyClipLayer.get() addSublayer:m_bodyLayer.get()];
    [m_triangleClipLayer.get() addSublayer:m_triangleLayer.get()];

    [m_rootLayer.get() addSublayer:m_bodyClipLayer.get()];
    [m_rootLayer.get() addSublayer:m_triangleClipLayer.get()];

    if (m_owner.isVisible()) {
      attachToNativeView();
    }
  }

  ~Platform() { [m_rootLayer.get() removeFromSuperlayer]; }

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
    DisabledActionTransaction transaction;

    const auto rootBounds =
        CGRectMake(0.0, 0.0, overlaySize.width(), overlaySize.height());
    setLayerRect(m_rootLayer.get(), rootBounds);
    setLayerRect(m_bodyClipLayer.get(), rootBounds);
    setLayerRect(m_bodyMaskLayer.get(), rootBounds);
    setLayerRect(m_triangleClipLayer.get(), rootBounds);
    setLayerRect(m_triangleMaskLayer.get(), rootBounds);

    CGMutablePathRef surfacePath = CGPathCreateMutable();
    for (const QRect &rect : visibleSurfaces) {
      CGPathAddRect(
          surfacePath, nullptr,
          CGRectMake(rect.x(), rect.y(), rect.width(), rect.height()));
    }
    m_bodyMaskLayer.get().path = surfacePath;
    CGPathRelease(surfacePath);

    CGMutablePathRef trianglePath = CGPathCreateMutable();
    CGPathAddRect(trianglePath, nullptr,
                  CGRectMake(triangleClip.x(), triangleClip.y(),
                             triangleClip.width(), triangleClip.height()));
    m_triangleMaskLayer.get().path = trianglePath;
    CGPathRelease(trianglePath);

    m_overlaySize = overlaySize;
    m_visibleSurfaces = visibleSurfaces;
    m_triangleClip = triangleClip;
    m_hasLayout = true;
  }

  void setAppearance(const QColor &color, int height, bool playing,
                     bool trianglePointsUp, qreal dpr) {
    if (m_hasAppearance && m_cachedColor == color && m_cachedHeight == height &&
        m_cachedPlaying == playing &&
        m_cachedTrianglePointsUp == trianglePointsUp && m_cachedDpr == dpr) {
      return;
    }
    DisabledActionTransaction transaction;

    const CGFloat scale = static_cast<CGFloat>(dpr > 0.0 ? dpr : 1.0);
    const std::array<CALayer *, 10> drawableLayers = {
        m_rootLayer.get(),         m_bodyClipLayer.get(),
        m_bodyMaskLayer.get(),     m_bodyLayer.get(),
        m_leftGlowLayer.get(),     m_rightGlowLayer.get(),
        m_coreLayer.get(),         m_triangleClipLayer.get(),
        m_triangleMaskLayer.get(), m_triangleLayer.get()};
    for (auto *layer : drawableLayers) {
      layer.contentsScale = scale;
    }
    m_bodyLayer.get().rasterizationScale = scale;
    m_triangleLayer.get().rasterizationScale = scale;

    const qreal leftExtent = playheadGlowLeftExtent(playing);
    const qreal rightExtent = playheadGlowRightExtent(playing);
    m_bodyLeftExtent = leftExtent;

    const qreal bodyWidth = leftExtent + rightExtent;
    m_bodyLayer.get().bounds = CGRectMake(0.0, 0.0, bodyWidth, height);

    m_leftGlowLayer.get().bounds = CGRectMake(0.0, 0.0, leftExtent, height);
    m_leftGlowLayer.get().position = CGPointMake(0.0, 0.0);

    if (!playing && rightExtent > 0.0) {
      m_rightGlowLayer.get().hidden = NO;
      m_rightGlowLayer.get().bounds = CGRectMake(0.0, 0.0, rightExtent, height);
      m_rightGlowLayer.get().position = CGPointMake(leftExtent, 0.0);
    } else {
      m_rightGlowLayer.get().hidden = YES;
    }

    m_coreLayer.get().bounds = CGRectMake(0.0, 0.0, kPlayheadLineWidth, height);
    m_coreLayer.get().position =
        CGPointMake(leftExtent - kPlayheadLineWidth / 2.0, 0.0);

    const qreal r = color.redF();
    const qreal g = color.greenF();
    const qreal b = color.blueF();
    const qreal a = color.alphaF();

    CGColorRef cgColor = CGColorCreateSRGB(r, g, b, a);
    m_coreLayer.get().backgroundColor = cgColor;

    NSMutableArray *colors =
        [NSMutableArray arrayWithCapacity:kPlayheadGradientStops.size()];
    NSMutableArray *locations =
        [NSMutableArray arrayWithCapacity:kPlayheadGradientStops.size()];
    const qreal peakAlpha = playheadPeakAlpha(playing);
    for (const auto &stop : kPlayheadGradientStops) {
      const qreal alpha = peakAlpha * stop.alphaFactor;
      CGColorRef stopColor = CGColorCreateSRGB(r, g, b, alpha);
      [colors addObject:(id)stopColor];
      CGColorRelease(stopColor);
      [locations addObject:@(stop.position)];
    }

    m_leftGlowLayer.get().colors = colors;
    m_leftGlowLayer.get().locations = locations;
    m_rightGlowLayer.get().colors = colors;
    m_rightGlowLayer.get().locations = locations;

    const CGFloat triWidth =
        static_cast<CGFloat>(2.0 * kPlayheadTriangleHalfWidth);
    const CGFloat triHeight = static_cast<CGFloat>(kPlayheadTriangleHeight);
    const CGFloat triHalfWidth =
        static_cast<CGFloat>(kPlayheadTriangleHalfWidth);

    m_triangleLayer.get().bounds = CGRectMake(0.0, 0.0, triWidth, triHeight);
    m_triangleLayer.get().fillColor = cgColor;

    CGMutablePathRef triPath = CGPathCreateMutable();
    if (!trianglePointsUp) {
      CGPathMoveToPoint(triPath, nullptr, 0.0, 0.0);
      CGPathAddLineToPoint(triPath, nullptr, triWidth, 0.0);
      CGPathAddLineToPoint(triPath, nullptr, triHalfWidth, triHeight);
    } else {
      CGPathMoveToPoint(triPath, nullptr, 0.0, triHeight);
      CGPathAddLineToPoint(triPath, nullptr, triWidth, triHeight);
      CGPathAddLineToPoint(triPath, nullptr, triHalfWidth, 0.0);
    }
    CGPathCloseSubpath(triPath);
    m_triangleLayer.get().path = triPath;
    CGPathRelease(triPath);

    CGColorRelease(cgColor);

    m_cachedColor = color;
    m_cachedHeight = height;
    m_cachedPlaying = playing;
    m_cachedTrianglePointsUp = trianglePointsUp;
    m_cachedDpr = dpr;
    m_hasAppearance = true;
  }

  void setPosition(qreal finalX, int top, bool visible) {
    DisabledActionTransaction transaction;
    m_bodyLayer.get().position = CGPointMake(finalX - m_bodyLeftExtent, top);
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
  RetainedObject<CAGradientLayer> m_leftGlowLayer;
  RetainedObject<CAGradientLayer> m_rightGlowLayer;
  RetainedObject<CALayer> m_coreLayer;

  RetainedObject<CALayer> m_triangleClipLayer;
  RetainedObject<CAShapeLayer> m_triangleMaskLayer;
  RetainedObject<CAShapeLayer> m_triangleLayer;

  QSize m_overlaySize;
  QRegion m_visibleSurfaces;
  QRect m_triangleClip;
  bool m_hasLayout = false;

  QColor m_cachedColor;
  int m_cachedHeight = -1;
  bool m_cachedPlaying = false;
  bool m_cachedTrianglePointsUp = false;
  qreal m_cachedDpr = 0.0;
  bool m_hasAppearance = false;

  qreal m_bodyLeftExtent = 0.0;
};

void PlayheadOverlay::initializePlatform(QWidget &owner) {
  if (QGuiApplication::platformName() == QLatin1String("cocoa")) {
    m_platform.reset(new Platform(owner));
  }
}

void PlayheadOverlay::attachPlatformToNativeView() {
  if (m_platform) {
    m_platform->attachToNativeView();
  }
}

void PlayheadOverlay::setPlatformLayout() {
  if (m_platform) {
    m_platform->setLayout(size(), m_visibleSurfaceRegion, m_triangleClip);
  }
}

void PlayheadOverlay::setPlatformAppearance() {
  if (m_platform) {
    m_platform->setAppearance(m_color, m_playheadGeometry.height(), m_playing,
                              m_trianglePointsUp, m_devicePixelRatio);
  }
}

void PlayheadOverlay::setPlatformPosition() {
  if (m_platform) {
    m_platform->setPosition(finalX(), m_playheadGeometry.top(), m_visible);
  }
}

void PlayheadOverlay::updatePlayhead(bool playingChanged) {
  if (m_platform) {
    if (playingChanged) {
      m_platform->setAppearance(m_color, m_playheadGeometry.height(), m_playing,
                                m_trianglePointsUp, m_devicePixelRatio);
    }
    m_platform->setPosition(finalX(), m_playheadGeometry.top(), m_visible);
  } else {
    updatePaintRegion();
  }
}

void PlayheadOverlay::PlatformDeleter::operator()(Platform *platform) const {
  delete platform;
}

PlayheadOverlay::~PlayheadOverlay() = default;

} // namespace songview
