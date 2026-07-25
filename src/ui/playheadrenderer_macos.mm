#include "ui/playheadrenderer.hpp"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QEvent>
#include <QPlatformSurfaceEvent>
#include <QPointer>
#include <QWidget>
#include <QWindow>
#include <array>
#include <cassert>
#include <memory>
#include <utility>

#if __has_feature(objc_arc)
#error playheadrenderer_macos.mm must be compiled without ARC
#endif

@interface PorydawPlayheadLayerView : NSView
@end

@implementation PorydawPlayheadLayerView

- (NSView *)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)isOpaque {
  return NO;
}

@end

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
    CFRelease(object);
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
      @"colors" : disabled,
      @"endPoint" : disabled,
      @"fillColor" : disabled,
      @"hidden" : disabled,
      @"locations" : disabled,
      @"mask" : disabled,
      @"opacity" : disabled,
      @"path" : disabled,
      @"position" : disabled,
      @"startPoint" : disabled,
      @"sublayers" : disabled,
      @"transform" : disabled,
      @"zPosition" : disabled,
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

auto makeColor(const QColor &color, CGFloat alpha)
    -> RetainedCoreFoundation<CGColor> {
  return RetainedCoreFoundation<CGColor>{
      CGColorCreateSRGB(CGFloat(color.redF()), CGFloat(color.greenF()),
                        CGFloat(color.blueF()), alpha)};
}

auto makeGradientColors(const QColor &color, CGFloat peak)
    -> RetainedObject<NSMutableArray> {
  auto colors = RetainedObject<NSMutableArray>{
      [[NSMutableArray alloc] initWithCapacity:kPlayheadGradientStops.size()]};
  for (const auto &stop : kPlayheadGradientStops) {
    auto stopColor = makeColor(color, CGFloat(color.alphaF()) * peak *
                                          CGFloat(stop.alphaFactor));
    [colors.get() addObject:(id)stopColor.get()];
  }
  return colors;
}

auto makeTrianglePath(bool pointsUp) -> RetainedCoreFoundation<CGPath> {
  auto path = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
  const auto baseY = pointsUp ? CGFloat(kPlayheadTriangleHeight) : CGFloat{0.0};
  const auto pointY =
      pointsUp ? CGFloat{0.0} : CGFloat(kPlayheadTriangleHeight);
  CGPathMoveToPoint(path.get(), nullptr, 0.0, baseY);
  CGPathAddLineToPoint(path.get(), nullptr,
                       2.0 * CGFloat(kPlayheadTriangleHalfWidth), baseY);
  CGPathAddLineToPoint(path.get(), nullptr, CGFloat(kPlayheadTriangleHalfWidth),
                       pointY);
  CGPathCloseSubpath(path.get());
  return path;
}

} // namespace

class PlayheadLayerTree final {
public:
  PlayheadLayerTree()
      : m_rootLayer([CALayer new]), m_surfaceClipLayer([CALayer new]),
        m_surfaceMaskLayer([CAShapeLayer new]),
        m_playheadPositionLayer([CALayer new]),
        m_leftGlowLayer([CAGradientLayer new]),
        m_rightGlowLayer([CAGradientLayer new]), m_coreLayer([CALayer new]),
        m_triangleClipLayer([CALayer new]),
        m_triangleMaskLayer([CAShapeLayer new]),
        m_triangleLayer([CAShapeLayer new]) {
    assert([NSThread isMainThread]);
    auto disabledActions = makeDisabledActions();
    auto layers = std::array<CALayer *, 10>{
        m_rootLayer.get(),         m_surfaceClipLayer.get(),
        m_surfaceMaskLayer.get(),  m_playheadPositionLayer.get(),
        m_leftGlowLayer.get(),     m_rightGlowLayer.get(),
        m_coreLayer.get(),         m_triangleClipLayer.get(),
        m_triangleMaskLayer.get(), m_triangleLayer.get(),
    };
    for (auto *layer : layers)
      configureLayer(layer, disabledActions.get());

    m_rootLayer.get().geometryFlipped = YES;
    m_rootLayer.get().hidden = YES;
    m_leftGlowLayer.get().startPoint = CGPointMake(0.0, 0.5);
    m_leftGlowLayer.get().endPoint = CGPointMake(1.0, 0.5);
    m_rightGlowLayer.get().startPoint = CGPointMake(1.0, 0.5);
    m_rightGlowLayer.get().endPoint = CGPointMake(0.0, 0.5);

    auto locations = RetainedObject<NSMutableArray>{[[NSMutableArray alloc]
        initWithCapacity:kPlayheadGradientStops.size()]};
    for (const auto &stop : kPlayheadGradientStops)
      [locations.get() addObject:@(stop.position)];
    m_leftGlowLayer.get().locations = locations.get();
    m_rightGlowLayer.get().locations = locations.get();
    m_triangleLayer.get().allowsEdgeAntialiasing = YES;

    auto maskColor = makeColor(QColor(255, 255, 255, 255), 1.0);
    m_surfaceMaskLayer.get().fillColor = maskColor.get();
    m_triangleMaskLayer.get().fillColor = maskColor.get();
    m_surfaceClipLayer.get().mask = m_surfaceMaskLayer.get();
    m_triangleClipLayer.get().mask = m_triangleMaskLayer.get();

    [m_surfaceClipLayer.get() addSublayer:m_playheadPositionLayer.get()];
    [m_playheadPositionLayer.get() addSublayer:m_leftGlowLayer.get()];
    [m_playheadPositionLayer.get() addSublayer:m_rightGlowLayer.get()];
    [m_playheadPositionLayer.get() addSublayer:m_coreLayer.get()];
    [m_triangleClipLayer.get() addSublayer:m_triangleLayer.get()];
    [m_rootLayer.get() addSublayer:m_surfaceClipLayer.get()];
    [m_rootLayer.get() addSublayer:m_triangleClipLayer.get()];
  }

  PlayheadLayerTree(const PlayheadLayerTree &) = delete;
  PlayheadLayerTree(PlayheadLayerTree &&) = delete;
  PlayheadLayerTree &operator=(const PlayheadLayerTree &) = delete;
  PlayheadLayerTree &operator=(PlayheadLayerTree &&) = delete;

  void synchronize(const PlayheadPresentation &presentation) {
    const bool layoutChanged =
        !m_hasLayout || !(m_layout == presentation.layout);
    const bool appearanceChanged =
        !m_hasAppearance || !(m_appearance == presentation.appearance);
    const bool stateChanged = !m_hasState || !(m_state == presentation.state);
    if (!layoutChanged && !appearanceChanged && !stateChanged)
      return;

    assert([NSThread isMainThread]);
    auto transaction = DisabledActionTransaction{};
    if (layoutChanged)
      applyLayout(presentation.layout);
    if (layoutChanged || !m_hasAppearance ||
        m_appearance.playing != presentation.appearance.playing) {
      applyPlayheadGeometry(presentation.layout,
                            presentation.appearance.playing);
    }
    if (!m_hasAppearance ||
        m_appearance.themeColor != presentation.appearance.themeColor) {
      applySolidColor(presentation.appearance.themeColor);
    }
    if (!m_hasAppearance ||
        m_appearance.themeColor != presentation.appearance.themeColor ||
        m_appearance.playing != presentation.appearance.playing) {
      applyGradientColors(presentation.appearance);
    }
    if (!m_hasState || m_state.finalX != presentation.state.finalX) {
      applyPosition(presentation.state.finalX);
    }
    if (!m_hasState || m_state.visible != presentation.state.visible) {
      m_rootLayer.get().hidden = presentation.state.visible ? NO : YES;
    }

    if (layoutChanged) {
      m_layout = presentation.layout;
      m_hasLayout = true;
    }
    if (appearanceChanged) {
      m_appearance = presentation.appearance;
      m_hasAppearance = true;
    }
    if (stateChanged) {
      m_state = presentation.state;
      m_hasState = true;
    }
  }

  CALayer *rootLayer() const { return m_rootLayer.get(); }

private:
  static void setLayerBounds(CALayer *layer, CGFloat width, CGFloat height) {
    layer.bounds = CGRectMake(0.0, 0.0, width, height);
  }

  static void setLayerPositionX(CALayer *layer, CGFloat x) {
    auto position = layer.position;
    position.x = x;
    layer.position = position;
  }

  static void setLayerPositionY(CALayer *layer, CGFloat y) {
    auto position = layer.position;
    position.y = y;
    layer.position = position;
  }

  void applyLayout(const PlayheadLayout &layout) {
    const auto rootBounds =
        CGRectMake(0.0, 0.0, CGFloat(layout.overlayFrame.width()),
                   CGFloat(layout.overlayFrame.height()));
    setLayerRect(m_rootLayer.get(), rootBounds);
    setLayerRect(m_surfaceClipLayer.get(), rootBounds);
    setLayerRect(m_surfaceMaskLayer.get(), rootBounds);
    setLayerRect(m_triangleClipLayer.get(), rootBounds);
    setLayerRect(m_triangleMaskLayer.get(), rootBounds);

    auto surfacePath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
    for (const QRect &rect : layout.visibleSurfaceRegion) {
      CGPathAddRect(
          surfacePath.get(), nullptr,
          CGRectMake(rect.x(), rect.y(), rect.width(), rect.height()));
    }
    m_surfaceMaskLayer.get().path = surfacePath.get();

    auto triangleMaskPath =
        RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
    CGPathAddRect(triangleMaskPath.get(), nullptr,
                  CGRectMake(layout.triangleClip.x(), layout.triangleClip.y(),
                             layout.triangleClip.width(),
                             layout.triangleClip.height()));
    m_triangleMaskLayer.get().path = triangleMaskPath.get();

    auto trianglePath = makeTrianglePath(layout.trianglePointsUp);
    m_triangleLayer.get().path = trianglePath.get();

    setLayerBounds(m_playheadPositionLayer.get(),
                   2.0 * CGFloat(kPlayheadGlowRadius),
                   CGFloat(layout.overlayFrame.height()));
    setLayerPositionY(m_playheadPositionLayer.get(), 0.0);
    setLayerBounds(m_triangleLayer.get(),
                   2.0 * CGFloat(kPlayheadTriangleHalfWidth),
                   CGFloat(kPlayheadTriangleHeight));
    setLayerPositionY(m_triangleLayer.get(),
                      CGFloat(layout.playheadGeometry.top()));
    updateContentsScale(CGFloat(layout.contentsScale));
  }

  void applyPlayheadGeometry(const PlayheadLayout &layout, bool playing) {
    const auto playheadTop = CGFloat(layout.playheadGeometry.top());
    const auto playheadHeight = CGFloat(layout.playheadGeometry.height());
    const auto leftExtent = CGFloat(playheadGlowLeftExtent(playing));
    const auto rightExtent = CGFloat(playheadGlowRightExtent(playing));
    setLayerRect(m_leftGlowLayer.get(),
                 CGRectMake(CGFloat(kPlayheadGlowRadius) - leftExtent,
                            playheadTop, leftExtent, playheadHeight));
    setLayerRect(m_rightGlowLayer.get(),
                 CGRectMake(CGFloat(kPlayheadGlowRadius), playheadTop,
                            rightExtent, playheadHeight));
    m_rightGlowLayer.get().hidden = rightExtent == 0.0 ? YES : NO;
    setLayerRect(
        m_coreLayer.get(),
        CGRectMake(CGFloat(kPlayheadGlowRadius) - kPlayheadLineWidth / 2.0,
                   playheadTop, kPlayheadLineWidth, playheadHeight));
  }

  void applySolidColor(const QColor &themeColor) {
    auto solidColor = makeColor(themeColor, CGFloat(themeColor.alphaF()));
    m_coreLayer.get().backgroundColor = solidColor.get();
    m_triangleLayer.get().fillColor = solidColor.get();
  }

  void applyGradientColors(const PlayheadAppearance &appearance) {
    const auto peak = CGFloat(playheadPeakAlpha(appearance.playing));
    auto colors = makeGradientColors(appearance.themeColor, peak);
    m_leftGlowLayer.get().colors = colors.get();
    m_rightGlowLayer.get().colors = colors.get();
  }

  void applyPosition(qreal finalX) {
    setLayerPositionX(m_playheadPositionLayer.get(),
                      CGFloat(finalX) - CGFloat(kPlayheadGlowRadius));
    setLayerPositionX(m_triangleLayer.get(),
                      CGFloat(finalX) - CGFloat(kPlayheadTriangleHalfWidth));
  }

  void updateContentsScale(CGFloat contentsScale) {
    auto layers = std::array<CALayer *, 10>{
        m_rootLayer.get(),         m_surfaceClipLayer.get(),
        m_surfaceMaskLayer.get(),  m_playheadPositionLayer.get(),
        m_leftGlowLayer.get(),     m_rightGlowLayer.get(),
        m_coreLayer.get(),         m_triangleClipLayer.get(),
        m_triangleMaskLayer.get(), m_triangleLayer.get(),
    };
    for (auto *layer : layers)
      layer.contentsScale = contentsScale;
  }

  RetainedObject<CALayer> m_rootLayer;
  RetainedObject<CALayer> m_surfaceClipLayer;
  RetainedObject<CAShapeLayer> m_surfaceMaskLayer;
  RetainedObject<CALayer> m_playheadPositionLayer;
  RetainedObject<CAGradientLayer> m_leftGlowLayer;
  RetainedObject<CAGradientLayer> m_rightGlowLayer;
  RetainedObject<CALayer> m_coreLayer;
  RetainedObject<CALayer> m_triangleClipLayer;
  RetainedObject<CAShapeLayer> m_triangleMaskLayer;
  RetainedObject<CAShapeLayer> m_triangleLayer;
  PlayheadLayout m_layout;
  PlayheadAppearance m_appearance;
  PlayheadState m_state;
  bool m_hasLayout = false;
  bool m_hasAppearance = false;
  bool m_hasState = false;
};

class NativeOverlayHost final : public QObject {
public:
  NativeOverlayHost(QWidget &owner, CALayer *rootLayer)
      : m_owner(owner), m_overlayView([[PorydawPlayheadLayerView alloc]
                            initWithFrame:NSZeroRect]) {
    assert([NSThread isMainThread]);
    {
      auto transaction = DisabledActionTransaction{};
      [m_overlayView.get() setLayer:rootLayer];
      [m_overlayView.get() setWantsLayer:YES];
    }
    m_owner.installEventFilter(this);
    updateWatchedWindow();
  }

  ~NativeOverlayHost() override {
    assert([NSThread isMainThread]);
    m_owner.removeEventFilter(this);
    if (m_watchedWindow) {
      m_watchedWindow->removeEventFilter(this);
      m_watchedWindow = nullptr;
    }
    detach();
    auto transaction = DisabledActionTransaction{};
    [m_overlayView.get() setWantsLayer:NO];
    [m_overlayView.get() setLayer:nil];
  }

  NativeOverlayHost(const NativeOverlayHost &) = delete;
  NativeOverlayHost(NativeOverlayHost &&) = delete;
  NativeOverlayHost &operator=(const NativeOverlayHost &) = delete;
  NativeOverlayHost &operator=(NativeOverlayHost &&) = delete;

  void synchronize(const PlayheadLayout &layout) {
    if (!m_hasFrame || m_frame != layout.overlayFrame) {
      assert([NSThread isMainThread]);
      auto transaction = DisabledActionTransaction{};
      [m_overlayView.get()
          setFrame:CGRectMake(CGFloat(layout.overlayFrame.x()),
                              CGFloat(layout.overlayFrame.y()),
                              CGFloat(layout.overlayFrame.width()),
                              CGFloat(layout.overlayFrame.height()))];
      m_frame = layout.overlayFrame;
      m_hasFrame = true;
    }
    attachIfNeeded(NativeHandlePolicy::CreateIfNeeded);
    updateWatchedWindow();
  }

protected:
  bool eventFilter(QObject *watched, QEvent *event) override {
    if (watched == &m_owner) {
      switch (event->type()) {
      case QEvent::Show:
        attachIfNeeded(NativeHandlePolicy::CreateIfNeeded);
        updateWatchedWindow();
        break;
      case QEvent::ParentChange:
        detach();
        updateWatchedWindow();
        attachIfNeeded(NativeHandlePolicy::ExistingOnly);
        break;
      case QEvent::WinIdChange:
        if (!m_acquiringNativeHandle) {
          detach();
          updateWatchedWindow();
          attachIfNeeded(NativeHandlePolicy::ExistingOnly);
        }
        break;
      default:
        break;
      }
    } else if (m_watchedWindow && watched == m_watchedWindow.data()) {
      if (event->type() == QEvent::PlatformSurface) {
        auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
        if (surfaceEvent->surfaceEventType() ==
            QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) {
          detach();
        } else if (surfaceEvent->surfaceEventType() ==
                   QPlatformSurfaceEvent::SurfaceCreated) {
          attachIfNeeded(NativeHandlePolicy::ExistingOnly);
          updateWatchedWindow();
        }
      }
    }
    return QObject::eventFilter(watched, event);
  }

private:
  enum class NativeHandlePolicy {
    ExistingOnly,
    CreateIfNeeded,
  };

  void updateWatchedWindow() {
    QWindow *currentWindow = m_owner.windowHandle();
    if (m_watchedWindow.data() == currentWindow)
      return;
    if (m_watchedWindow)
      m_watchedWindow->removeEventFilter(this);
    m_watchedWindow = currentWindow;
    if (m_watchedWindow)
      m_watchedWindow->installEventFilter(this);
  }

  void attachIfNeeded(NativeHandlePolicy handlePolicy) {
    if ([m_overlayView.get() superview] || m_acquiringNativeHandle ||
        !m_owner.isVisible()) {
      return;
    }
    if (handlePolicy == NativeHandlePolicy::ExistingOnly &&
        m_owner.internalWinId() == 0) {
      return;
    }

    m_acquiringNativeHandle = true;
    const WId wid = m_owner.winId();
    m_acquiringNativeHandle = false;
    auto *ownerView = reinterpret_cast<NSView *>(wid);
    if (!ownerView)
      return;

    assert([NSThread isMainThread]);
    auto transaction = DisabledActionTransaction{};
    [ownerView addSubview:m_overlayView.get()
               positioned:NSWindowAbove
               relativeTo:nil];
  }

  void detach() {
    if (![m_overlayView.get() superview])
      return;
    assert([NSThread isMainThread]);
    auto transaction = DisabledActionTransaction{};
    [m_overlayView.get() removeFromSuperview];
  }

  QWidget &m_owner;
  QPointer<QWindow> m_watchedWindow;
  RetainedObject<PorydawPlayheadLayerView> m_overlayView;
  QRect m_frame;
  bool m_hasFrame = false;
  bool m_acquiringNativeHandle = false;
};

class PlayheadRenderer::Impl final {
public:
  explicit Impl(QWidget &overlay)
      : m_layerTree(), m_host(requiredOwner(overlay), m_layerTree.rootLayer()) {
  }

  void synchronize(const PlayheadPresentation &presentation) {
    m_layerTree.synchronize(presentation);
    m_host.synchronize(presentation.layout);
  }

  void paint(QPaintEvent *event) { (void)event; }

private:
  static QWidget &requiredOwner(QWidget &overlay) {
    QWidget *owner = overlay.parentWidget();
    Q_ASSERT(owner);
    return *owner;
  }

  PlayheadLayerTree m_layerTree;
  NativeOverlayHost m_host;
};

PlayheadRenderer::PlayheadRenderer(QWidget &overlay)
    : m_impl(std::make_unique<Impl>(overlay)) {}

PlayheadRenderer::~PlayheadRenderer() = default;

void PlayheadRenderer::synchronize(const PlayheadPresentation &presentation) {
  m_impl->synchronize(presentation);
}

void PlayheadRenderer::paint(QPaintEvent *event) { m_impl->paint(event); }

} // namespace songview
