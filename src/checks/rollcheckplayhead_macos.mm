#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include "rollcheckplayhead.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPixmap>
#include <QWidget>
#include <QtMath>

#include <algorithm>

#include "ui/playheadoverlay.h"
#include "ui/songview.h"

namespace {

void processLayers()
{
    QCoreApplication::sendPostedEvents(nullptr, QEvent::UpdateRequest);
    QCoreApplication::processEvents();
}

CALayer *findPlayheadLayer(CALayer *ownerLayer)
{
    for (CALayer *layer in ownerLayer.sublayers) {
        if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
            return layer;
    }
    return nil;
}

int countPlayheadLayers(CALayer *ownerLayer)
{
    int count = 0;
    for (CALayer *layer in ownerLayer.sublayers) {
        if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
            ++count;
    }
    return count;
}

bool layerTreeHasContents(CALayer *layer)
{
    if (layer.contents)
        return true;
    if (layer.mask && layerTreeHasContents(layer.mask))
        return true;
    for (CALayer *child in layer.sublayers) {
        if (layerTreeHasContents(child))
            return true;
    }
    return false;
}

struct RetainedObjectGuard {
    id object = nil;

    explicit RetainedObjectGuard(id value) : object([value retain]) {}
    ~RetainedObjectGuard() { [object release]; }

    RetainedObjectGuard(const RetainedObjectGuard &) = delete;
    RetainedObjectGuard &operator=(const RetainedObjectGuard &) = delete;
};

struct RetainedPathGuard {
    CGPathRef path = nullptr;

    explicit RetainedPathGuard(CGPathRef value) : path(value ? CGPathRetain(value) : nullptr) {}
    ~RetainedPathGuard()
    {
        if (path)
            CGPathRelease(path);
    }

    RetainedPathGuard(const RetainedPathGuard &) = delete;
    RetainedPathGuard &operator=(const RetainedPathGuard &) = delete;
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

CALayer *currentOwnerLayer(SongView &view, QStringList &failures)
{
    QWidget *const topLevel = view.window();
    if (!topLevel) {
        failures.append("macOS playhead owner has no top-level widget");
        return nil;
    }
    const WId windowId = topLevel->winId();
    NSView *const ownerView = windowId ? reinterpret_cast<NSView *>(windowId) : nil;
    if (!ownerView || !ownerView.layer) {
        failures.append("macOS playhead owner has no current backing layer");
        return nil;
    }
    return ownerView.layer;
}

} // namespace

void checkMacPlayheadLifecycle(SongView &view, songview::PlayheadOverlay &overlay,
                               QStringList &failures)
{
    if (!songview::platformPlayheadRendererEnabled())
        return;
    if (![NSThread isMainThread]) {
        failures.append("macOS playhead layer check did not run on the GUI thread");
        return;
    }

    processLayers();
    CALayer *ownerLayer = currentOwnerLayer(view, failures);
    if (!ownerLayer)
        return;
    CALayer *root = findPlayheadLayer(ownerLayer);
    if (!root) {
        failures.append("macOS playhead is not attached to the actual current backing layer");
        return;
    }
    if (countPlayheadLayers(ownerLayer) != 1)
        failures.append("macOS host retained more than one native playhead layer");
    if (root.superlayer != ownerLayer)
        failures.append("macOS playhead was reparented away from the current backing layer");
    if (root.zPosition < 1'000'000.0)
        failures.append("macOS playhead does not have explicit z-order above retained Quick");
    if (root.sublayers.count != 2) {
        failures.append("macOS playhead layer does not expose body and triangle clips");
        return;
    }

    CALayer *const bodyClip = root.sublayers[0];
    CALayer *const triangleClip = root.sublayers[1];
    CALayer *const body = bodyClip.sublayers.firstObject;
    CALayer *const triangle = triangleClip.sublayers.firstObject;
    if (!body || ![triangle isKindOfClass:[CAShapeLayer class]] ||
        ![bodyClip.mask isKindOfClass:[CAShapeLayer class]] ||
        ![triangleClip.mask isKindOfClass:[CAShapeLayer class]] || body.sublayers.count != 3) {
        failures.append("macOS playhead native layer tree is incomplete");
        return;
    }
    CAGradientLayer *const leftGlow = (CAGradientLayer *)body.sublayers[0];
    CAGradientLayer *const rightGlow = (CAGradientLayer *)body.sublayers[1];
    CALayer *const core = body.sublayers[2];
    if (![leftGlow isKindOfClass:[CAGradientLayer class]] ||
        ![rightGlow isKindOfClass:[CAGradientLayer class]] ||
        [core isKindOfClass:[CAGradientLayer class]]) {
        failures.append("macOS playhead body does not use native gradient and core layers");
        return;
    }
    CAShapeLayer *const resolvedTriangle = (CAShapeLayer *)triangle;
    CAShapeLayer *const resolvedBodyMask = (CAShapeLayer *)bodyClip.mask;
    CAShapeLayer *const resolvedTriangleMask = (CAShapeLayer *)triangleClip.mask;

    const qreal baseX = view.camera().contentX(view.playheadTick());
    overlay.setPlayhead(baseX, true, false);
    processLayers();
    if (layerTreeHasContents(root))
        failures.append("paused macOS playhead retained raster layer contents");
    const CGRect pausedBodyBounds = body.bounds;
    RetainedObjectGuard pausedLeftColors{leftGlow.colors};

    overlay.setPlayhead(baseX, true, true);
    processLayers();
    if (CGRectEqualToRect(body.bounds, pausedBodyBounds) ||
        leftGlow.colors == pausedLeftColors.object) {
        failures.append("macOS play/pause did not update native glow layers");
    }
    if (layerTreeHasContents(root))
        failures.append("playing macOS playhead retained raster layer contents");

    RetainedObjectGuard movingLeftColors{leftGlow.colors};
    RetainedObjectGuard movingRightColors{rightGlow.colors};
    RetainedPathGuard bodyPath{resolvedBodyMask.path};
    RetainedPathGuard triangleClipPath{resolvedTriangleMask.path};
    RetainedPathGuard trianglePath{resolvedTriangle.path};
    const CGRect rootBounds = root.bounds;
    const CGRect bodyClipBounds = bodyClip.bounds;
    const CGRect bodyBounds = body.bounds;
    const CGRect leftGlowBounds = leftGlow.bounds;
    const CGRect rightGlowBounds = rightGlow.bounds;
    const CGRect coreBounds = core.bounds;
    const CGRect triangleClipBounds = triangleClip.bounds;
    const CGRect triangleBounds = triangle.bounds;
    const CGPoint startingBodyPosition = body.position;

    for (int move = 1; move <= 128; ++move)
        overlay.setPlayhead(baseX + qreal(move) / 3.0, true, true);
    processLayers();
    if (layerTreeHasContents(root)) {
        failures.append("position-only macOS updates introduced raster layer contents");
    }
    if (leftGlow.colors != movingLeftColors.object ||
        rightGlow.colors != movingRightColors.object || resolvedBodyMask.path != bodyPath.path ||
        resolvedTriangleMask.path != triangleClipPath.path ||
        resolvedTriangle.path != trianglePath.path || !CGRectEqualToRect(root.bounds, rootBounds) ||
        !CGRectEqualToRect(bodyClip.bounds, bodyClipBounds) ||
        !CGRectEqualToRect(body.bounds, bodyBounds) ||
        !CGRectEqualToRect(leftGlow.bounds, leftGlowBounds) ||
        !CGRectEqualToRect(rightGlow.bounds, rightGlowBounds) ||
        !CGRectEqualToRect(core.bounds, coreBounds) ||
        !CGRectEqualToRect(triangleClip.bounds, triangleClipBounds) ||
        !CGRectEqualToRect(triangle.bounds, triangleBounds)) {
        failures.append("position-only macOS updates regenerated native playhead geometry");
    }
    if (CGPointEqualToPoint(body.position, startingBodyPosition))
        failures.append("position-only macOS updates did not move the native playhead");

    CALayer *fakeQuickLayer = [CALayer layer];
    fakeQuickLayer.name = @"PorydawPlayheadCheckQuickLayer";
    fakeQuickLayer.zPosition = 999'999.0;
    [ownerLayer addSublayer:fakeQuickLayer];
    overlay.setPlayhead(baseX + 50.0, true, true);
    processLayers();
    ownerLayer = currentOwnerLayer(view, failures);
    if (!ownerLayer || root.superlayer != ownerLayer ||
        root.zPosition <= fakeQuickLayer.zPosition) {
        failures.append("macOS playhead did not remain above newer retained Quick layers");
    }

    CALayer *decoyLayer = [CALayer layer];
    [decoyLayer addSublayer:root];
    overlay.setPlayhead(baseX + 51.0, true, true);
    processLayers();
    ownerLayer = currentOwnerLayer(view, failures);
    if (!ownerLayer || root.superlayer != ownerLayer || countPlayheadLayers(ownerLayer) != 1) {
        failures.append("macOS playhead did not reattach after native layer churn");
    }
    [fakeQuickLayer removeFromSuperlayer];

    overlay.setPlayhead(0.0, false, false);
    processLayers();
    if (!root.hidden)
        failures.append("hidden macOS playhead presentation left its native layer visible");
}

QPixmap renderMacPlayheadOverlay(SongView &view, QStringList &failures)
{
    if (![NSThread isMainThread]) {
        failures.append("macOS playhead rendering did not run on the GUI thread");
        return {};
    }
    CALayer *const ownerLayer = currentOwnerLayer(view, failures);
    CALayer *const overlayLayer = ownerLayer ? findPlayheadLayer(ownerLayer) : nil;
    if (!overlayLayer) {
        failures.append("macOS playhead layer is unavailable for bitmap rendering");
        return {};
    }

    const CGSize logicalSize = overlayLayer.bounds.size;
    const qreal devicePixelRatio = std::max<qreal>(view.devicePixelRatioF(), 1.0);
    const int pixelWidth = qCeil(qreal(logicalSize.width) * devicePixelRatio);
    const int pixelHeight = qCeil(qreal(logicalSize.height) * devicePixelRatio);
    if (pixelWidth <= 0 || pixelHeight <= 0) {
        failures.append("macOS playhead layer has empty bitmap geometry");
        return {};
    }

    QImage image(pixelWidth, pixelHeight, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CoreFoundationGuard colorSpaceGuard{colorSpace};
    if (!colorSpace) {
        failures.append("could not create a macOS playhead color space");
        return {};
    }
    CGContextRef context = CGBitmapContextCreate(
        image.bits(), pixelWidth, pixelHeight, 8, image.bytesPerLine(), colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CoreFoundationGuard contextGuard{context};
    if (!context) {
        failures.append("could not create a macOS playhead bitmap context");
        return {};
    }

    CGContextTranslateCTM(context, 0.0, CGFloat(pixelHeight));
    CGContextScaleCTM(context, CGFloat(devicePixelRatio), -CGFloat(devicePixelRatio));
    [overlayLayer renderInContext:context];
    image.setDevicePixelRatio(devicePixelRatio);
    return QPixmap::fromImage(image);
}
