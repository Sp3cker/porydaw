#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPixmap>
#include <QTabWidget>
#include <QWidget>
#include <QWindow>
#include <QtGlobal>
#include <QtMath>

#include "rollcheckplayhead.h"
#include "ui/songview.h"
#include <cassert>
#include <memory>

namespace {

void processPaints() {
  QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
  QCoreApplication::processEvents();
}

CALayer *findPlayheadLayer(NSView *ownerView) {
  if (!ownerView || !ownerView.layer)
    return nil;
  for (CALayer *layer in ownerView.layer.sublayers) {
    if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
      return layer;
  }
  return nil;
}

int countPlayheadLayers(NSView *ownerView) {
  if (!ownerView || !ownerView.layer)
    return 0;
  int count = 0;
  for (CALayer *layer in ownerView.layer.sublayers) {
    if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
      count++;
  }
  return count;
}

struct LifecycleCleanupGuard {
  SongView *view = nullptr;
  QTabWidget *tab1 = nullptr;
  QTabWidget *tab2 = nullptr;

  ~LifecycleCleanupGuard() {
    if (view) {
      if (tab1) {
        const int idx = tab1->indexOf(view);
        if (idx != -1)
          tab1->removeTab(idx);
      }
      if (tab2) {
        const int idx = tab2->indexOf(view);
        if (idx != -1)
          tab2->removeTab(idx);
      }
      view->setParent(nullptr);
    }
  }
};

struct NSViewGuard {
  NSView *view = nil;
  explicit NSViewGuard(NSView *v) : view([v retain]) {}
  ~NSViewGuard() { [view release]; }
  NSViewGuard(const NSViewGuard &) = delete;
  NSViewGuard &operator=(const NSViewGuard &) = delete;
};

struct CoreFoundationGuard {
  CFTypeRef object = nullptr;

  explicit CoreFoundationGuard(CFTypeRef value) : object(value) {}

  ~CoreFoundationGuard() {
    if (object)
      CFRelease(object);
  }

  CoreFoundationGuard(const CoreFoundationGuard &) = delete;
  CoreFoundationGuard &operator=(const CoreFoundationGuard &) = delete;
};

} // namespace

void checkMacPlayheadLifecycle(QStringList &failures) {
  auto lifecycleView = std::make_unique<SongView>();

  QTabWidget tab1;
  QTabWidget tab2;
  tab1.setAttribute(Qt::WA_DontShowOnScreen);
  tab2.setAttribute(Qt::WA_DontShowOnScreen);

  LifecycleCleanupGuard cleanupGuard{lifecycleView.get(), &tab1, &tab2};

  tab1.addTab(lifecycleView.get(), QStringLiteral("Tab 1"));
  tab1.show();
  processPaints();

  // The renderer attaches its layer to the SongView's top-level window's
  // content NSView (Platform::attachToNativeView walks m_owner.window()),
  // NOT to any view of the SongView itself — the SongView stays an alien
  // widget with no native handle, exactly as in the app. Every layer probe
  // below therefore inspects the enclosing tab widget's window view.
  const WId winId1 = tab1.winId();
  if (winId1 == 0) {
    failures.append("tab1 winId is null after show");
    return;
  }
  NSView *windowView1 = reinterpret_cast<NSView *>(winId1);
  if (!windowView1) {
    failures.append("tab1 window NSView is null after show");
    return;
  }

  NSViewGuard windowView1Guard{windowView1};

  CALayer *overlayLayer1 = findPlayheadLayer(windowView1);
  if (!overlayLayer1) {
    failures.append("macOS playhead overlay layer not attached under tab1's "
                    "window NSView");
  }
  if (countPlayheadLayers(windowView1) != 1) {
    failures.append(
        "expected exactly 1 playhead overlay under tab1's window NSView");
  }
  if (lifecycleView->testAttribute(Qt::WA_NativeWindow)) {
    failures.append("attaching the playhead layer forced the SongView "
                    "native");
  }

  tab2.show();
  tab2.addTab(lifecycleView.get(), QStringLiteral("Tab 2"));
  processPaints();

  const WId winId2 = tab2.winId();
  NSView *windowView2 = reinterpret_cast<NSView *>(winId2);
  if (!windowView2) {
    failures.append("tab2 window NSView is null after reparent");
    return;
  }

  CALayer *overlayLayer2 = findPlayheadLayer(windowView2);
  if (!overlayLayer2) {
    failures.append("macOS playhead overlay layer not attached under tab2's "
                    "window NSView");
  }
  if (countPlayheadLayers(windowView2) != 1) {
    failures.append(
        "expected exactly 1 playhead overlay under tab2's window NSView");
  }
  if (windowView1 != windowView2 && countPlayheadLayers(windowView1) != 0) {
    failures.append(
        "stale playhead overlay left under old window NSView after reparent");
  }

  QWindow *win = tab2.windowHandle();
  if (!win) {
    failures.append(
        "tab2 windowHandle is null before native surface recreation");
    return;
  }

  CALayer *attachedOverlay = findPlayheadLayer(windowView2);
  if (!attachedOverlay) {
    failures.append("macOS playhead overlay layer missing before platform "
                    "destruction");
    return;
  }

  win->destroy();
  processPaints();
  win->create();
  processPaints();

  tab2.show();
  processPaints();

  const WId winId3 = tab2.winId();
  NSView *windowView3 = reinterpret_cast<NSView *>(winId3);
  if (windowView3) {
    CALayer *overlayLayer3 = findPlayheadLayer(windowView3);
    if (!overlayLayer3) {
      failures.append("macOS playhead overlay layer not attached after "
                      "native handle recreation");
    }
    if (countPlayheadLayers(windowView3) != 1) {
      failures.append(
          "expected exactly 1 playhead overlay after native handle recreation");
    }
  } else {
    failures.append("tab2 window NSView is null after native handle "
                    "recreation");
  }

  tab2.removeTab(tab2.indexOf(lifecycleView.get()));
  lifecycleView->setParent(nullptr);
}

QPixmap renderMacPlayheadOverlay(SongView &view, QStringList &failures) {
  assert([NSThread isMainThread]);
  // The layer lives on the top-level window's content NSView (see
  // checkMacPlayheadLifecycle). In rollcheck the SongView is that top level,
  // but resolve through window() so the lookup mirrors the renderer.
  auto *ownerView = reinterpret_cast<NSView *>(view.window()->winId());
  if (!ownerView) {
    failures.append(
        "window NSView is null for macOS playhead bitmap rendering");
    return {};
  }

  CALayer *overlayLayer = findPlayheadLayer(ownerView);
  if (!overlayLayer) {
    failures.append(
        "macOS playhead overlay is unavailable for bitmap rendering");
    return {};
  }

  const CGSize logicalSize = overlayLayer.bounds.size;
  const qreal devicePixelRatio = view.devicePixelRatioF();
  const int pixelWidth = qCeil(qreal(logicalSize.width) * devicePixelRatio);
  const int pixelHeight = qCeil(qreal(logicalSize.height) * devicePixelRatio);
  if (pixelWidth <= 0 || pixelHeight <= 0) {
    failures.append("macOS playhead overlay bitmap has empty geometry");
    return {};
  }

  QImage image(pixelWidth, pixelHeight, QImage::Format_ARGB32_Premultiplied);
  image.fill(Qt::transparent);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CoreFoundationGuard colorSpaceGuard{colorSpace};
  if (!colorSpace) {
    failures.append("could not create color space for macOS playhead bitmap");
    return {};
  }

  CGContextRef context = CGBitmapContextCreate(
      image.bits(), pixelWidth, pixelHeight, 8, image.bytesPerLine(),
      colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CoreFoundationGuard contextGuard{context};
  if (!context) {
    failures.append("could not create context for macOS playhead bitmap");
    return {};
  }

  CGContextTranslateCTM(context, 0.0, CGFloat(pixelHeight));
  CGContextScaleCTM(context, CGFloat(devicePixelRatio),
                    -CGFloat(devicePixelRatio));
  [overlayLayer renderInContext:context];
  image.setDevicePixelRatio(devicePixelRatio);
  return QPixmap::fromImage(image);
}
