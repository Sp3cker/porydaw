#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QCoreApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QImage>
#include <QQuickWidget>
#include <QWidget>
#include <QWindow>
#include <QtMath>

#include "ui/activity/trackactivitypresentation.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <memory>

namespace {

void processPaints()
{
    QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
    QCoreApplication::processEvents();
}

CALayer *findActivityLayer(NSView *ownerView)
{
    if (!ownerView || !ownerView.layer)
        return nil;
    for (CALayer *layer in ownerView.layer.sublayers) {
        if ([layer.name isEqualToString:@"PorydawTrackActivityLayer"])
            return layer;
    }
    return nil;
}

int countActivityLayers(NSView *ownerView)
{
    if (!ownerView || !ownerView.layer)
        return 0;
    int count = 0;
    for (CALayer *layer in ownerView.layer.sublayers) {
        if ([layer.name isEqualToString:@"PorydawTrackActivityLayer"])
            ++count;
    }
    return count;
}

CALayer *findSublayer(CALayer *owner, NSString *name)
{
    if (!owner)
        return nil;
    for (CALayer *layer in owner.sublayers) {
        if ([layer.name isEqualToString:name])
            return layer;
    }
    return nil;
}

class PaintCounter final : public QObject
{
  public:
    int paints = 0;
    int updates = 0;

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::Paint)
            ++paints;
        else if (event->type() == QEvent::UpdateRequest)
            ++updates;
        return false;
    }
};

struct CoreFoundationGuard {
    CFTypeRef object = nullptr;

    explicit CoreFoundationGuard(CFTypeRef value) : object(value) {}
    ~CoreFoundationGuard()
    {
        if (object)
            CFRelease(object);
    }

    CoreFoundationGuard(const CoreFoundationGuard &) = delete;
    CoreFoundationGuard &operator=(const CoreFoundationGuard &) = delete;
};

QImage renderActivityLayer(CALayer *layer, qreal devicePixelRatio)
{
    if (!layer)
        return {};
    const int pixelWidth = qCeil(qreal(layer.bounds.size.width) * devicePixelRatio);
    const int pixelHeight = qCeil(qreal(layer.bounds.size.height) * devicePixelRatio);
    if (pixelWidth <= 0 || pixelHeight <= 0)
        return {};
    QImage image(pixelWidth, pixelHeight, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    auto colorSpace = CGColorSpaceCreateDeviceRGB();
    CoreFoundationGuard colorSpaceGuard{colorSpace};
    if (!colorSpace)
        return {};
    auto context = CGBitmapContextCreate(
        image.bits(), pixelWidth, pixelHeight, 8, image.bytesPerLine(), colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CoreFoundationGuard contextGuard{context};
    if (!context)
        return {};
    CGContextTranslateCTM(context, 0.0, CGFloat(pixelHeight));
    CGContextScaleCTM(context, CGFloat(devicePixelRatio), -CGFloat(devicePixelRatio));
    [layer renderInContext:context];
    image.setDevicePixelRatio(devicePixelRatio);
    return image;
}

bool isOpaque(const QImage &image)
{
    if (image.isNull())
        return false;
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            if (image.pixelColor(x, y).alpha() != 255)
                return false;
    return true;
}

struct NSViewGuard {
    NSView *view = nil;

    explicit NSViewGuard(NSView *source) : view([source retain]) {}
    ~NSViewGuard() { [view release]; }

    NSViewGuard(const NSViewGuard &) = delete;
    NSViewGuard &operator=(const NSViewGuard &) = delete;
};

} // namespace

int runMacTrackActivityPresentationCheck()
{
    if (QGuiApplication::platformName() != QLatin1String("cocoa"))
        return 0;
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "trackactivitymetercheck: FAIL: %s\n", message);
            ++failures;
        }
    };

    QWidget window1;
    QWidget window2;
    window1.setAttribute(Qt::WA_DontShowOnScreen);
    window2.setAttribute(Qt::WA_DontShowOnScreen);
    window1.resize(160, 120);
    window2.resize(160, 120);
    auto owner = std::make_unique<QWidget>(&window1);
    owner->setGeometry(12, 18, 80, 64);
    auto presentation = std::make_unique<TrackActivityPresentation>(*owner);

    constexpr int track = 3;
    constexpr int secondTrack = 7;
    constexpr int stride = 32;
    constexpr int meterHeight = 31;
    const std::array definitions{
        TrackActivityPresentation::TrackDefinition{track, QColor(Qt::red)},
        TrackActivityPresentation::TrackDefinition{secondTrack, QColor(Qt::blue)},
    };
    TrackActivity fullActivity;
    fullActivity.resetPaused();
    presentation->setTracks(definitions, {stride, meterHeight});
    presentation->present(fullActivity, false);

    window1.show();
    owner->show();
    processPaints();
    const WId winId1 = window1.winId();
    auto *windowView1 = winId1 ? reinterpret_cast<NSView *>(winId1) : nullptr;
    check(windowView1 != nil, "macOS activity window NSView is unavailable");
    if (!windowView1)
        return failures;
    NSViewGuard windowView1Guard{windowView1};
    CALayer *root = findActivityLayer(windowView1);
    check(root != nil, "macOS activity layer did not attach to the top-level NSView");
    check(countActivityLayers(windowView1) == 1,
          "macOS activity presentation attached more than one root layer");
    check(!owner->testAttribute(Qt::WA_NativeWindow),
          "macOS activity presentation forced its owner QWidget native");
    check(owner->findChildren<QQuickWidget *>().isEmpty(),
          "macOS native activity presentation instantiated a QQuickWidget");
    if (!root)
        return failures;

    check(root.sublayers.count == 2, "macOS activity layer did not create one layer per row");
    CALayer *firstRow = root.sublayers.count > 0 ? root.sublayers[0] : nil;
    CALayer *left = findSublayer(firstRow, @"PorydawTrackActivityLeft");
    CALayer *right = findSublayer(firstRow, @"PorydawTrackActivityRight");
    check(firstRow && left && right, "macOS activity row is missing stereo layers");
    check(std::abs(firstRow.bounds.size.height - meterHeight) < 0.001,
          "macOS activity row height does not match the presentation geometry");

    PaintCounter paintCounter;
    owner->installEventFilter(&paintCounter);
    window1.installEventFilter(&paintCounter);
    QWindow *const backingStoreWindow = window1.windowHandle();
    check(backingStoreWindow != nullptr,
          "macOS activity top-level QWindow is unavailable for repaint observation");
    if (backingStoreWindow)
        backingStoreWindow->installEventFilter(&paintCounter);
    processPaints();
    paintCounter.paints = 0;
    paintCounter.updates = 0;
    TrackActivity stereoActivity;
    TrackActivityLevels levels{};
    levels[track] = {255, 64};
    stereoActivity.advance(levels, 1.0f, true);
    presentation->present(stereoActivity, true);
    processPaints();
    check(paintCounter.paints == 0 && paintCounter.updates == 0,
          "native activity presentation dirtied the QWidget backing store");

    left = findSublayer(firstRow, @"PorydawTrackActivityLeft");
    right = findSublayer(firstRow, @"PorydawTrackActivityRight");
    if (left && right) {
        check(left.bounds.size.height > right.bounds.size.height,
              "macOS activity stereo heights did not update independently");
        check(std::abs(left.position.y + left.bounds.size.height - meterHeight) < 0.001 &&
                  std::abs(right.position.y + right.bounds.size.height - meterHeight) < 0.001,
              "macOS activity bars are not bottom-anchored");
        const qreal dpr = owner->devicePixelRatioF();
        const qreal physicalLeft = qreal(left.bounds.size.height) * dpr;
        const qreal physicalRight = qreal(right.bounds.size.height) * dpr;
        check(std::abs(physicalLeft - std::round(physicalLeft)) < 0.001 &&
                  std::abs(physicalRight - std::round(physicalRight)) < 0.001,
              "macOS activity heights are not snapped to physical pixels");
    }

    const qreal frameDpr = owner->devicePixelRatioF();
    const QImage nativeFrame = renderActivityLayer(root, frameDpr);
    check(!nativeFrame.isNull(), "macOS activity CALayer did not render into a bitmap");
    check(isOpaque(nativeFrame), "macOS activity CALayer left transparent pixels in the strip");
    if (!nativeFrame.isNull()) {
        const int leftX = nativeFrame.width() / 4;
        const int rightX = nativeFrame.width() * 3 / 4;
        const int firstRowY = std::min(nativeFrame.height() - 1, qRound(4.0 * frameDpr));
        const int secondRowY =
            std::min(nativeFrame.height() - 1, qRound((stride + 4.0) * frameDpr));
        check(nativeFrame.pixelColor(leftX, firstRowY) != nativeFrame.pixelColor(rightX, firstRowY),
              "macOS activity CALayer did not render independent stereo colors");
        check(nativeFrame.pixelColor(rightX, firstRowY) !=
                  nativeFrame.pixelColor(rightX, secondRowY),
              "macOS activity CALayer did not preserve independent row colors");
    }

    owner->move(24, 30);
    processPaints();
    root = findActivityLayer(windowView1);
    check(root && std::abs(root.position.x - 24.0) < 0.001 &&
              std::abs(root.position.y - 30.0) < 0.001,
          "macOS activity layer did not follow owner geometry");
    owner->hide();
    processPaints();
    check(root && root.hidden, "macOS activity layer remained visible with its owner hidden");
    owner->show();
    processPaints();
    check(root && !root.hidden, "macOS activity layer did not return with its owner");

    window2.show();
    owner->setParent(&window2);
    owner->show();
    processPaints();
    const WId winId2 = window2.winId();
    auto *windowView2 = winId2 ? reinterpret_cast<NSView *>(winId2) : nullptr;
    check(windowView2 && findActivityLayer(windowView2),
          "macOS activity layer did not attach after reparenting");
    check(windowView1 == windowView2 || countActivityLayers(windowView1) == 0,
          "macOS activity layer remained attached to the old window");

    // After reparenting, a Move delivered to the former ancestor window must
    // not resynchronize the layer: only the current ancestor chain filters.
    CALayer *staleRoot = findActivityLayer(windowView2);
    check(staleRoot != nil, "macOS activity root is missing for the stale filter probe");
    if (staleRoot) {
        const CGPoint staleProbe = CGPointMake(97.0, 89.0);
        staleRoot.position = staleProbe;
        QMoveEvent formerMove(window1.pos(), window1.pos());
        QCoreApplication::sendEvent(&window1, &formerMove);
        check(std::abs(staleRoot.position.x - staleProbe.x) < 0.001 &&
                  std::abs(staleRoot.position.y - staleProbe.y) < 0.001,
              "macOS activity layer was resynchronized by a former ancestor filter");
    }

    QWindow *const nativeWindow = window2.windowHandle();
    check(nativeWindow != nullptr, "macOS activity test window has no QWindow");
    if (nativeWindow) {
        nativeWindow->destroy();
        processPaints();
        nativeWindow->create();
        window2.show();
        owner->show();
        processPaints();
        const WId recreatedWinId = window2.winId();
        auto *recreatedView = recreatedWinId ? reinterpret_cast<NSView *>(recreatedWinId) : nullptr;
        check(recreatedView && findActivityLayer(recreatedView),
              "macOS activity layer did not recover after native handle recreation");
        check(recreatedView && countActivityLayers(recreatedView) == 1,
              "macOS activity recreation produced duplicate root layers");
    }

    presentation.reset();
    processPaints();
    const WId finalWinId = window2.winId();
    auto *finalView = finalWinId ? reinterpret_cast<NSView *>(finalWinId) : nullptr;
    check(!finalView || countActivityLayers(finalView) == 0,
          "macOS activity layer survived presentation destruction");
    owner->setParent(nullptr);
    return failures;
}
