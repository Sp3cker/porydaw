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

NSView *findPlayheadLayerView(NSView *ownerView) {
  if (!ownerView)
    return nil;
  for (NSView *subview in ownerView.subviews) {
    if ([subview isKindOfClass:NSClassFromString(@"PorydawPlayheadLayerView")])
      return subview;
  }
  return nil;
}

int countPlayheadLayerViews(NSView *ownerView) {
  if (!ownerView)
    return 0;
  int count = 0;
  for (NSView *subview in ownerView.subviews) {
    if ([subview isKindOfClass:NSClassFromString(@"PorydawPlayheadLayerView")])
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

  WId winId1 = lifecycleView->winId();
  if (winId1 == 0) {
    failures.append("SongView winId is null after tab1 show");
    return;
  }
  NSView *ownerView1 = reinterpret_cast<NSView *>(winId1);
  if (!ownerView1) {
    failures.append("SongView NSView is null after tab1 show");
    return;
  }

  NSViewGuard ownerView1Guard{ownerView1};

  NSView *overlayView1 = findPlayheadLayerView(ownerView1);
  if (!overlayView1) {
    failures.append("macOS playhead overlay layer view not attached under tab1 "
                    "owner NSView");
  }
  if (countPlayheadLayerViews(ownerView1) != 1) {
    failures.append(
        "expected exactly 1 playhead overlay under tab1 owner NSView");
  }

  tab2.show();
  tab2.addTab(lifecycleView.get(), QStringLiteral("Tab 2"));
  processPaints();

  WId winId2 = lifecycleView->winId();
  NSView *ownerView2 = reinterpret_cast<NSView *>(winId2);
  if (!ownerView2) {
    failures.append("SongView NSView is null after tab2 reparent");
    return;
  }

  NSView *overlayView2 = findPlayheadLayerView(ownerView2);
  if (!overlayView2) {
    failures.append("macOS playhead overlay layer view not attached under tab2 "
                    "owner NSView");
  }
  if (countPlayheadLayerViews(ownerView2) != 1) {
    failures.append(
        "expected exactly 1 playhead overlay under tab2 owner NSView");
  }
  if (ownerView1 != ownerView2 && countPlayheadLayerViews(ownerView1) != 0) {
    failures.append(
        "stale playhead overlay left under old owner NSView after reparent");
  }

  QWindow *win = lifecycleView->windowHandle();
  if (!win) {
    failures.append(
        "SongView windowHandle is null before native surface recreation");
    return;
  }

  NSView *attachedOverlay = findPlayheadLayerView(ownerView2);
  if (!attachedOverlay) {
    failures.append("macOS playhead overlay layer view missing before platform "
                    "destruction");
    return;
  }
  NSViewGuard overlayGuard{attachedOverlay};

  win->destroy();
  processPaints();

  if (attachedOverlay.superview != nil) {
    failures.append("retained overlay view remained attached to superview "
                    "after platform destruction");
  }

  win->create();
  processPaints();

  lifecycleView->show();
  processPaints();

  WId winId3 = lifecycleView->winId();
  NSView *ownerView3 = reinterpret_cast<NSView *>(winId3);
  if (ownerView3) {
    NSView *overlayView3 = findPlayheadLayerView(ownerView3);
    if (!overlayView3) {
      failures.append("macOS playhead overlay layer view not attached after "
                      "native handle recreation");
    }
    if (countPlayheadLayerViews(ownerView3) != 1) {
      failures.append(
          "expected exactly 1 playhead overlay after native handle recreation");
    }
  } else {
    failures.append("SongView NSView is null after native handle recreation");
  }

  tab2.removeTab(tab2.indexOf(lifecycleView.get()));
  lifecycleView->setParent(nullptr);
}

QPixmap renderMacPlayheadOverlay(SongView &view, QStringList &failures) {
  assert([NSThread isMainThread]);
  auto *ownerView = reinterpret_cast<NSView *>(view.winId());
  if (!ownerView) {
    failures.append(
        "SongView NSView is null for macOS playhead bitmap rendering");
    return {};
  }

  NSView *overlayView = findPlayheadLayerView(ownerView);
  if (!overlayView || !overlayView.layer) {
    failures.append(
        "macOS playhead overlay is unavailable for bitmap rendering");
    return {};
  }

  const CGSize logicalSize = overlayView.layer.bounds.size;
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
  [overlayView.layer renderInContext:context];
  image.setDevicePixelRatio(devicePixelRatio);
  return QPixmap::fromImage(image);
}
