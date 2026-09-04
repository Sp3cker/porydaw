#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include "rollcheckplayhead.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPixmap>
#include <QPoint>
#include <QRegion>
#include <QWidget>
#include <QtMath>

#include <algorithm>
#include <array>
#include <optional>

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

QImage renderLayerMap(CALayer *layer, qreal devicePixelRatio, QStringList &failures)
{
    const CGSize logicalSize = layer.bounds.size;
    const qreal dpr = std::max<qreal>(devicePixelRatio, 1.0);
    const int pixelWidth = qCeil(qreal(logicalSize.width) * dpr);
    const int pixelHeight = qCeil(qreal(logicalSize.height) * dpr);
    if (pixelWidth <= 0 || pixelHeight <= 0) {
        failures.append("macOS playhead rendered map has empty geometry");
        return {};
    }

    QImage image(pixelWidth, pixelHeight, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CoreFoundationGuard colorSpaceGuard{colorSpace};
    if (!colorSpace) {
        failures.append("could not create a macOS playhead rendered-map color space");
        return {};
    }
    CGContextRef context = CGBitmapContextCreate(
        image.bits(), pixelWidth, pixelHeight, 8, image.bytesPerLine(), colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CoreFoundationGuard contextGuard{context};
    if (!context) {
        failures.append("could not create a macOS playhead rendered-map context");
        return {};
    }

    CGContextTranslateCTM(context, 0.0, CGFloat(pixelHeight));
    CGContextScaleCTM(context, CGFloat(dpr), -CGFloat(dpr));
    [layer renderInContext:context];
    image.setDevicePixelRatio(dpr);
    return image;
}

bool renderedMapHasVisiblePixelOutside(const QImage &image, const QRegion &allowed)
{
    const qreal dpr = image.devicePixelRatio() > 0.0 ? image.devicePixelRatio() : 1.0;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) < 32)
                continue;
            const QPoint logicalPoint(qFloor((qreal(x) + 0.5) / dpr),
                                      qFloor((qreal(y) + 0.5) / dpr));
            if (!allowed.contains(logicalPoint))
                return true;
        }
    }
    return false;
}

bool renderedMapHasVisiblePixel(const QImage &image)
{
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) >= 32)
                return true;
        }
    }
    return false;
}

} // namespace

void checkMacPlayheadLifecycle(SongView &view, songview::PlayheadOverlay &overlay,
                               QStringList &failures)
{
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
        failures.append("macOS host retained more than one playhead layer");
    if (root.superlayer != ownerLayer)
        failures.append("macOS playhead was reparented away from the current backing layer");
    if (root.zPosition < 1'000'000.0)
        failures.append("macOS playhead does not have explicit z-order above retained Quick");

    const int timelineSplitX = view.timelineSplitX();
    const QRect timelineColumn(timelineSplitX, 0, std::max(0, view.width() - timelineSplitX),
                               view.height());
    const QPoint rootOffset = view.mapTo(view.window(), QPoint(0, 0));
    const CGRect expectedRootFrame = CGRectMake(rootOffset.x() + timelineColumn.x(), rootOffset.y(),
                                                timelineColumn.width(), timelineColumn.height());
    if (!CGRectEqualToRect(root.frame, expectedRootFrame))
        failures.append("macOS playhead root does not frame the canonical timeline column");
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

    QRegion expectedBodyPixels;
    constexpr std::array bodyBands{
        songview::TimelineBand::Ruler,       songview::TimelineBand::Roll,
        songview::TimelineBand::OtherEvents, songview::TimelineBand::Automation,
        songview::TimelineBand::Velocity,    songview::TimelineBand::VoiceChanges,
    };
    for (const songview::TimelineBand band : bodyBands) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            view.timelineBandLayout().geometry(band);
        if (!geometry)
            continue;
        const QRect expectedPlotRect =
            geometry->plotRect.intersected(view.rect()).translated(-timelineSplitX, 0);
        if (!expectedPlotRect.isEmpty())
            expectedBodyPixels += expectedPlotRect;
    }
    QRegion expectedTrianglePixels;
    if (const std::optional<songview::TimelineBandGeometry> &ruler =
            view.timelineBandLayout().geometry(songview::TimelineBand::Ruler)) {
        const QRect expectedPlotRect =
            ruler->plotRect.intersected(view.rect()).translated(-timelineSplitX, 0);
        if (!expectedPlotRect.isEmpty())
            expectedTrianglePixels += expectedPlotRect;
    }

    const auto renderCoreMap = [&] {
        const BOOL leftGlowWasHidden = leftGlow.hidden;
        const BOOL rightGlowWasHidden = rightGlow.hidden;
        const BOOL triangleWasHidden = triangleClip.hidden;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        leftGlow.hidden = YES;
        rightGlow.hidden = YES;
        triangleClip.hidden = YES;
        QImage image = renderLayerMap(root, view.devicePixelRatioF(), failures);
        leftGlow.hidden = leftGlowWasHidden;
        rightGlow.hidden = rightGlowWasHidden;
        triangleClip.hidden = triangleWasHidden;
        [CATransaction commit];
        return image;
    };
    const auto renderTriangleMap = [&] {
        const BOOL bodyWasHidden = bodyClip.hidden;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        bodyClip.hidden = YES;
        QImage image = renderLayerMap(root, view.devicePixelRatioF(), failures);
        bodyClip.hidden = bodyWasHidden;
        [CATransaction commit];
        return image;
    };
    const auto checkRenderedPixelContract = [&](const char *state, bool allowTickZeroOverhang) {
        const QImage coreMap = renderCoreMap();
        if (!coreMap.isNull() && renderedMapHasVisiblePixelOutside(coreMap, expectedBodyPixels)) {
            failures.append(QStringLiteral("%1 native playhead core painted outside the timeline "
                                           "plot strips")
                                .arg(QString::fromLatin1(state)));
        }

        QRegion allowedTrianglePixels = expectedTrianglePixels;
        if (allowTickZeroOverhang) {
            const QRect rulerBounds = expectedTrianglePixels.boundingRect();
            const int halfWidth = songview::playheadTriangleHalfWidth();
            allowedTrianglePixels +=
                QRect(-halfWidth, rulerBounds.top(), halfWidth, rulerBounds.height());
        }
        const QImage triangleMap = renderTriangleMap();
        if (!triangleMap.isNull() &&
            renderedMapHasVisiblePixelOutside(triangleMap, allowedTrianglePixels)) {
            failures.append(
                QStringLiteral("%1 native ruler triangle painted outside its plot or exceeded "
                               "the permitted tick-zero left-wing overhang")
                    .arg(QString::fromLatin1(state)));
        }
    };

    const qreal baseX = view.camera().contentX(view.playheadTick());
    overlay.setPlayhead(baseX, true, false);
    processLayers();
    if (layerTreeHasContents(root))
        failures.append("paused macOS playhead retained raster layer contents");
    checkRenderedPixelContract("paused", false);
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
    checkRenderedPixelContract("playing", false);

    const auto checkTickZeroTriangleCenter = [&](const char *state) {
        const qreal expectedLeft = -qreal(songview::playheadTriangleHalfWidth());
        if (!qFuzzyIsNull(triangle.position.x - expectedLeft)) {
            failures.append(QStringLiteral("%1 native ruler triangle is not centered at tick zero")
                                .arg(QString::fromLatin1(state)));
        }
        if (root.hidden) {
            failures.append(QStringLiteral("%1 native playhead was hidden at timeline-local zero")
                                .arg(QString::fromLatin1(state)));
        }
    };
    overlay.setPlayhead(0.0, true, false);
    processLayers();
    checkRenderedPixelContract("paused tick-zero", true);
    checkTickZeroTriangleCenter("paused");
    overlay.setPlayhead(0.0, true, true);
    processLayers();
    checkRenderedPixelContract("playing tick-zero", true);
    checkTickZeroTriangleCenter("playing");
    const auto checkOutOfRangeRight = [&](const char *state, bool playing) {
        overlay.setPlayhead(qreal(timelineColumn.width()), true, playing);
        processLayers();
        if (!root.hidden) {
            failures.append(
                QStringLiteral("%1 native playhead remained visible at the timeline right edge")
                    .arg(QString::fromLatin1(state)));
        }
    };
    checkOutOfRangeRight("paused", false);
    checkOutOfRangeRight("playing", true);

    const songview::TimelineBandLayout layout = view.timelineBandLayout();
    songview::TimelineBandLayout rulerlessLayout = layout;
    rulerlessLayout.geometry(songview::TimelineBand::Ruler).reset();
    overlay.updateBands(rulerlessLayout);
    overlay.setPlayhead(0.0, true, false);
    processLayers();
    if (!root.hidden)
        failures.append("native playhead remained visible without a ruler plot");
    overlay.updateBands(layout);

    const qreal offscreenPlayheadTick = view.camera().tickAtContentX(-1.0);
    const qreal offscreenContentX = view.camera().contentX(offscreenPlayheadTick);
    if (offscreenContentX >= 0.0) {
        failures.append(
            "native playhead offscreen fixture did not produce negative camera content X");
    } else {
        const auto checkOffscreenLeft = [&](const char *state, bool playing) {
            overlay.setPlayhead(offscreenContentX, true, playing);
            processLayers();
            if (!root.hidden) {
                failures.append(
                    QStringLiteral("%1 native playhead root remained visible for negative camera "
                                   "content X")
                        .arg(QString::fromLatin1(state)));
            }
            const QImage coreMap = renderCoreMap();
            if (!coreMap.isNull() && renderedMapHasVisiblePixel(coreMap)) {
                failures.append(
                    QStringLiteral("%1 native playhead core remained visible for negative camera "
                                   "content X")
                        .arg(QString::fromLatin1(state)));
            }
            const QImage triangleMap = renderTriangleMap();
            if (!triangleMap.isNull() && renderedMapHasVisiblePixel(triangleMap)) {
                failures.append(
                    QStringLiteral("%1 native ruler triangle remained visible for negative camera "
                                   "content X")
                        .arg(QString::fromLatin1(state)));
            }
        };
        checkOffscreenLeft("paused", false);
        checkOffscreenLeft("playing", true);
    }

    overlay.setPlayhead(baseX, true, true);
    processLayers();

    RetainedObjectGuard movingLeftColors{leftGlow.colors};
    RetainedObjectGuard movingRightColors{rightGlow.colors};
    RetainedPathGuard bodyPath{resolvedBodyMask.path};
    RetainedPathGuard triangleClipPath{resolvedTriangleMask.path};
    RetainedPathGuard trianglePath{resolvedTriangle.path};
    const CGRect rootBounds = root.bounds;
    const CGRect rootFrame = root.frame;
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
        !CGRectEqualToRect(root.frame, rootFrame) ||
        !CGRectEqualToRect(bodyClip.bounds, bodyClipBounds) ||
        !CGRectEqualToRect(body.bounds, bodyBounds) ||
        !CGRectEqualToRect(leftGlow.bounds, leftGlowBounds) ||
        !CGRectEqualToRect(rightGlow.bounds, rightGlowBounds) ||
        !CGRectEqualToRect(core.bounds, coreBounds) ||
        !CGRectEqualToRect(triangleClip.bounds, triangleClipBounds) ||
        !CGRectEqualToRect(triangle.bounds, triangleBounds)) {
        failures.append("position-only macOS updates regenerated playhead geometry");
    }
    if (CGPointEqualToPoint(body.position, startingBodyPosition))
        failures.append("position-only macOS updates did not move the playhead");

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

    overlay.setPlayhead(view.camera().contentX(view.playheadTick()), true, true);
    processLayers();
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

    return QPixmap::fromImage(renderLayerMap(overlayLayer, view.devicePixelRatioF(), failures));
}
