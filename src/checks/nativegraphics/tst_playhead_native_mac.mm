#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QCoreApplication>
#include <QImage>
#include <QPixmap>
#include <QPlatformSurfaceEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QScopeGuard>
#include <QSizeF>

#include <algorithm>
#include <array>
#include <memory>
#include <optional>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"

namespace {

void processLayers()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

bool layerFrameMatches(CALayer *layer, const QRectF &expected)
{
    if (!layer)
        return false;
    const CGRect actual = layer.frame;
    return qAbs(actual.origin.x - expected.x()) <= 0.01 &&
           qAbs(actual.origin.y - expected.y()) <= 0.01 &&
           qAbs(actual.size.width - expected.width()) <= 0.01 &&
           qAbs(actual.size.height - expected.height()) <= 0.01;
}

QRectF timelineColumnInScene(const SongView &view, QQuickItem &root)
{
    const qreal split = view.timelineSplitX();
    const QRectF column{split, 0.0, std::max<qreal>(0.0, root.width() - split),
                        std::max<qreal>(0.0, root.height())};
    return root.mapRectToScene(column);
}

CALayer *directPlayheadLayer(CALayer *owner)
{
    for (CALayer *layer in owner.sublayers) {
        if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
            return layer;
    }
    return nil;
}

int directPlayheadCount(CALayer *owner)
{
    int count = 0;
    for (CALayer *layer in owner.sublayers) {
        if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
            ++count;
    }
    return count;
}

CALayer *findPlayheadRecursively(CALayer *layer)
{
    if ([layer.name isEqualToString:@"PorydawPlayheadLayer"])
        return layer;
    for (CALayer *child in layer.sublayers) {
        if (CALayer *found = findPlayheadRecursively(child))
            return found;
    }
    return nil;
}

CALayer *ownerLayer(QQuickWindow *window)
{
    // Reads the native view of an already-created platform surface only; the
    // handle guard never forces window creation.
    if (!window || !window->handle())
        return nil;
    NSView *nativeView = reinterpret_cast<NSView *>(window->winId());
    if (!nativeView || ![nativeView isKindOfClass:[NSView class]])
        return nil;
    return nativeView.layer;
}

bool hasRasterContents(CALayer *layer)
{
    if (layer.contents || (layer.mask && hasRasterContents(layer.mask)))
        return true;
    for (CALayer *child in layer.sublayers) {
        if (hasRasterContents(child))
            return true;
    }
    return false;
}

QImage renderLayer(CALayer *layer, qreal dpr)
{
    const CGSize logical = layer.bounds.size;
    const qreal scale = (std::max)(dpr, 1.0);
    const int width = qCeil(logical.width * scale);
    const int height = qCeil(logical.height * scale);
    if (width <= 0 || height <= 0)
        return {};
    QImage image{QSize{width, height}, QImage::Format_ARGB32_Premultiplied};
    image.fill(Qt::transparent);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context =
        colorSpace
            ? CGBitmapContextCreate(image.bits(), width, height, 8, image.bytesPerLine(),
                                    colorSpace,
                                    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host)
            : nullptr;
    if (colorSpace)
        CFRelease(colorSpace);
    if (!context)
        return {};
    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, scale, -scale);
    [layer renderInContext:context];
    CGContextRelease(context);
    image.setDevicePixelRatio(scale);
    return image;
}

bool visibleOutside(const QImage &image, const QRegion &allowed)
{
    const qreal dpr = image.devicePixelRatio();
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) < 32)
                continue;
            const QPoint point{qFloor((x + 0.5) / dpr), qFloor((y + 0.5) / dpr)};
            if (!allowed.contains(point))
                return true;
        }
    }
    return false;
}

bool hasVisiblePixel(const QImage &image)
{
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (qAlpha(image.pixel(x, y)) >= 32)
                return true;
        }
    }
    return false;
}

struct Layers {
    CALayer *root = nil;
    CALayer *bodyClip = nil;
    CALayer *triangleClip = nil;
    CALayer *body = nil;
    CAShapeLayer *triangle = nil;
    CAGradientLayer *leftGlow = nil;
    CAGradientLayer *rightGlow = nil;
    CALayer *core = nil;
};

std::optional<Layers> resolveLayers(CALayer *owner)
{
    CALayer *root = directPlayheadLayer(owner);
    if (!root || root.sublayers.count != 2)
        return std::nullopt;
    CALayer *bodyClip = root.sublayers[0];
    CALayer *triangleClip = root.sublayers[1];
    CALayer *body = bodyClip.sublayers.firstObject;
    CAShapeLayer *triangle = [triangleClip.sublayers.firstObject isKindOfClass:[CAShapeLayer class]]
                                 ? static_cast<CAShapeLayer *>(triangleClip.sublayers.firstObject)
                                 : nil;
    if (!body || !triangle || body.sublayers.count != 3)
        return std::nullopt;
    CAGradientLayer *left = [body.sublayers[0] isKindOfClass:[CAGradientLayer class]]
                                ? static_cast<CAGradientLayer *>(body.sublayers[0])
                                : nil;
    CAGradientLayer *right = [body.sublayers[1] isKindOfClass:[CAGradientLayer class]]
                                 ? static_cast<CAGradientLayer *>(body.sublayers[1])
                                 : nil;
    if (!left || !right)
        return std::nullopt;
    return Layers{root, bodyClip, triangleClip, body, triangle, left, right, body.sublayers[2]};
}

std::unique_ptr<checks::nativegraphics::Rig> macRig(const QString &projectRoot,
                                                    const QString &songLabel)
{
    QString error;
    std::unique_ptr<checks::nativegraphics::Rig> rig =
        checks::nativegraphics::makeRig(projectRoot, songLabel, QSize{1280, 800}, error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

} // namespace

void RenderingPlayheadTest::nativeLayerLifecycle()
{
    QVERIFY([NSThread isMainThread]);
    std::unique_ptr<checks::nativegraphics::Rig> rig = macRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *overlay = view.findChild<songview::PlayheadOverlay *>();
    QVERIFY(overlay);
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject() && quick->quickWindow());
    QQuickItem *root = quick->rootObject();
    QQuickWindow *quickWindow = quick->quickWindow();
    QTRY_VERIFY(quickWindow->isExposed());
    processLayers();
    CALayer *owner = ownerLayer(quickWindow);
    QVERIFY(owner);
    QVERIFY(findPlayheadRecursively(owner));
    QVERIFY(directPlayheadCount(owner) == 1);
    const std::optional<Layers> resolved = resolveLayers(owner);
    QVERIFY(resolved);
    const Layers layers = *resolved;
    QVERIFY(layers.root.superlayer == owner);
    QVERIFY(layers.root.zPosition >= 1'000'000.0);
    const int split = view.timelineSplitX();
    // The baseline host fills the Quick window, but the expectation is
    // deliberately mapped through the canvas root so composition offsets and
    // fractional page extents use the same native coordinate contract.
    QVERIFY(layerFrameMatches(layers.root, timelineColumnInScene(view, *root)));
    QVERIFY([layers.bodyClip.mask isKindOfClass:[CAShapeLayer class]]);
    QVERIFY([layers.triangleClip.mask isKindOfClass:[CAShapeLayer class]]);
    QVERIFY(![layers.core isKindOfClass:[CAGradientLayer class]]);

    QRegion bodyPlots;
    constexpr std::array bodyBands{
        songview::TimelineBand::Ruler,       songview::TimelineBand::Roll,
        songview::TimelineBand::OtherEvents, songview::TimelineBand::Automation,
        songview::TimelineBand::Velocity,    songview::TimelineBand::VoiceChanges};
    for (songview::TimelineBand band : bodyBands) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            view.timelineBandLayout().geometry(band);
        if (geometry)
            bodyPlots += geometry->plotRect.translated(-split, 0);
    }
    const std::optional<songview::TimelineBandGeometry> &ruler =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    QVERIFY(ruler);
    const QRegion rulerPlot = QRegion{ruler->plotRect.translated(-split, 0)};
    const uint64_t tick = uint64_t((std::max)(0.0, view.camera().tickAtContentX(100.0)));
    const qreal baseX = view.camera().contentX(tick);
    overlay->setPlayhead(baseX, true, false);
    processLayers();
    QVERIFY(!hasRasterContents(layers.root));
    const CGRect pausedBounds = layers.body.bounds;
    NSArray *pausedColors = [layers.leftGlow.colors copy];
    const auto releasePausedColors = qScopeGuard([pausedColors] { [pausedColors release]; });
    overlay->setPlayhead(baseX, true, true);
    processLayers();
    QVERIFY(!CGRectEqualToRect(layers.body.bounds, pausedBounds));
    QVERIFY(![layers.leftGlow.colors isEqual:pausedColors]);
    QVERIFY(!hasRasterContents(layers.root));

    const auto renderCore = [&] {
        const BOOL leftHidden = layers.leftGlow.hidden;
        const BOOL rightHidden = layers.rightGlow.hidden;
        const BOOL triangleHidden = layers.triangleClip.hidden;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layers.leftGlow.hidden = YES;
        layers.rightGlow.hidden = YES;
        layers.triangleClip.hidden = YES;
        QImage image = renderLayer(layers.root, quickWindow->effectiveDevicePixelRatio());
        layers.leftGlow.hidden = leftHidden;
        layers.rightGlow.hidden = rightHidden;
        layers.triangleClip.hidden = triangleHidden;
        [CATransaction commit];
        return image;
    };
    const auto renderTriangle = [&] {
        const BOOL bodyHidden = layers.bodyClip.hidden;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layers.bodyClip.hidden = YES;
        QImage image = renderLayer(layers.root, quickWindow->effectiveDevicePixelRatio());
        layers.bodyClip.hidden = bodyHidden;
        [CATransaction commit];
        return image;
    };
    const QImage coreMap = renderCore();
    QVERIFY(!visibleOutside(coreMap, bodyPlots));
    const QColor playheadColor = themes::color(themes::Role::song_view_playhead);
    for (songview::TimelineBand band : bodyBands) {
        const std::optional<songview::TimelineBandGeometry> &geometry =
            view.timelineBandLayout().geometry(band);
        if (!geometry)
            continue;
        const QRect localPlot = geometry->plotRect.translated(-split, 0);
        const QRect coreProbe{qRound(baseX) - layout::singlePixel(), localPlot.center().y(),
                              2 * layout::singlePixel() + 1, layout::singlePixel()};
        QVERIFY2(checks::support::hasSolidPlayheadPixel(coreMap, coreProbe, playheadColor),
                 "native core must be present in each visible plot");
    }
    QVERIFY(!visibleOutside(renderTriangle(), rulerPlot));

    overlay->setPlayhead(0.0, true, false);
    processLayers();
    QCOMPARE(layers.triangle.position.x, -qreal(songview::playheadTriangleHalfWidth()));
    QVERIFY(!layers.root.hidden);
    const QImage tickZeroTriangle = renderTriangle();
    const QRect localRuler = ruler->plotRect.translated(-split, 0);
    const int triangleTop =
        localRuler.bottom() - songview::playheadTriangleHeight() + layout::singlePixel();
    const QRect rightWing{0, triangleTop, songview::playheadTriangleHalfWidth(),
                          songview::playheadTriangleHeight()};
    QVERIFY(checks::support::hasSolidPlayheadPixel(tickZeroTriangle, rightWing, playheadColor));
    const int downTop = checks::support::playheadWidthAt(
        tickZeroTriangle, triangleTop + layout::singlePixel(), 0.0, playheadColor);
    const int downBottom = checks::support::playheadWidthAt(
        tickZeroTriangle, triangleTop + songview::playheadTriangleHeight() - layout::singlePixel(),
        0.0, playheadColor);
    QVERIFY(downTop > downBottom);
    const qreal columnWidth = quickWindow->width() - split;
    overlay->setPlayhead(columnWidth, true, true);
    processLayers();
    QVERIFY(layers.root.hidden);

    const songview::TimelineBandLayout savedLayout = view.timelineBandLayout();
    songview::TimelineBandLayout rulerless = savedLayout;
    rulerless.geometry(songview::TimelineBand::Ruler).reset();
    overlay->updateBands(rulerless);
    overlay->setPlayhead(0.0, true, false);
    processLayers();
    QVERIFY(layers.root.hidden);
    overlay->updateBands(savedLayout);
    view.setEventListVisible(true);
    overlay->setPlayhead(0.0, true, false);
    checks::support::pumpQuick();
    const QImage eventListTriangle = renderTriangle();
    const int upTop = checks::support::playheadWidthAt(
        eventListTriangle, triangleTop + layout::singlePixel(), 0.0, playheadColor);
    const int upBottom = checks::support::playheadWidthAt(
        eventListTriangle, triangleTop + songview::playheadTriangleHeight() - layout::singlePixel(),
        0.0, playheadColor);
    QVERIFY(upBottom > upTop);
    view.setEventListVisible(false);

    const songview::TimelineBandLayout canonicalBeforeLifecycle = view.timelineBandLayout();
    // Platform-surface teardown: the overlay must drop its layers while the
    // surface goes away, then re-attach once it returns.
    CALayer *attachedOwner = ownerLayer(quickWindow);
    QVERIFY(attachedOwner);
    QPlatformSurfaceEvent aboutToDetach{QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed};
    QCoreApplication::sendEvent(quickWindow, &aboutToDetach);
    processLayers();
    QVERIFY(directPlayheadCount(attachedOwner) == 0);
    QPlatformSurfaceEvent recreated{QPlatformSurfaceEvent::SurfaceCreated};
    QCoreApplication::sendEvent(quickWindow, &recreated);
    processLayers();
    QVERIFY(directPlayheadCount(attachedOwner) == 1);

    QEvent densityChange{QEvent::DevicePixelRatioChange};
    QCoreApplication::sendEvent(quickWindow, &densityChange);
    processLayers();
    quickWindow->hide();
    processLayers();
    quickWindow->show();
    QTRY_VERIFY(quickWindow->isExposed());
    processLayers();
    owner = ownerLayer(quickWindow);
    QVERIFY(owner);
    QVERIFY(layers.root.superlayer == owner);
    QVERIFY(directPlayheadCount(owner) == 1);
    QVERIFY(view.timelineBandLayout() == canonicalBeforeLifecycle);
    QVERIFY(!visibleOutside(renderCore(), bodyPlots));
    checks::support::pumpQuick();
    overlay->setPlayhead(-1.0, true, true);
    processLayers();
    QVERIFY(layers.root.hidden);
    QVERIFY(!hasVisiblePixel(renderCore()));
    QVERIFY(!hasVisiblePixel(renderTriangle()));

    overlay->setPlayhead(baseX, true, true);
    processLayers();
    NSArray *colorsBeforeMoves = [layers.leftGlow.colors copy];
    CGPathRef bodyPath = CGPathRetain(static_cast<CAShapeLayer *>(layers.bodyClip.mask).path);
    CGPathRef trianglePath = CGPathRetain(layers.triangle.path);
    const auto releasePaths = qScopeGuard([colorsBeforeMoves, bodyPath, trianglePath] {
        [colorsBeforeMoves release];
        if (bodyPath)
            CGPathRelease(bodyPath);
        if (trianglePath)
            CGPathRelease(trianglePath);
    });
    const CGRect bodyBounds = layers.body.bounds;
    constexpr qreal finalMove = 128.0 / 3.0;
    for (int move = 1; move <= 128; ++move)
        overlay->setPlayhead(baseX + qreal(move) / 3.0, true, true);
    processLayers();
    QVERIFY(!hasRasterContents(layers.root));
    QVERIFY([layers.leftGlow.colors isEqual:colorsBeforeMoves]);
    QVERIFY(CGPathEqualToPath(static_cast<CAShapeLayer *>(layers.bodyClip.mask).path, bodyPath));
    QVERIFY(CGPathEqualToPath(layers.triangle.path, trianglePath));
    QVERIFY(CGRectEqualToRect(layers.body.bounds, bodyBounds));
    QVERIFY(qAbs(layers.body.position.x -
                 (baseX + finalMove - songview::playheadGlowLeftExtent(true))) <= 0.01);

    CALayer *fakeQuick = [CALayer layer];
    fakeQuick.zPosition = 999'999.0;
    [owner addSublayer:fakeQuick];
    const auto removeFake = qScopeGuard([fakeQuick] { [fakeQuick removeFromSuperlayer]; });
    overlay->setPlayhead(baseX + 50.0, true, true);
    processLayers();
    QVERIFY(layers.root.superlayer == owner);
    QVERIFY(layers.root.zPosition > fakeQuick.zPosition);
    CALayer *decoy = [CALayer layer];
    [decoy addSublayer:layers.root];
    overlay->setPlayhead(baseX + 51.0, true, true);
    processLayers();
    QVERIFY(layers.root.superlayer == owner);
    QVERIFY(directPlayheadCount(owner) == 1);
    [decoy removeFromSuperlayer];
    QVERIFY(decoy.superlayer == nil);

    overlay->setPlayhead(0.0, false, false);
    processLayers();
    QVERIFY(layers.root.hidden);
    overlay->setPlayhead(baseX, true, true);
    processLayers();

    // Composition maps a page-sized canvas through its ancestors, rather
    // than assuming the Quick window is the timeline viewport.
    {
        const QPointF originalRootPosition = root->position();
        const QSizeF originalRootSize = root->size();
        const QSize originalWindowSize = quickWindow->size();
        root->setPosition(originalRootPosition + QPointF{31.5, 23.25});
        root->setSize(QSizeF{originalRootSize.width() - 87.5, originalRootSize.height() - 61.25});
        checks::support::pumpQuick();
        processLayers();
        // Moving the canvas republishes the transport's live playhead via
        // viewportChanged/refreshViewportLayout/syncTimelineIndicators,
        // overwriting the injected probe; re-assert the probe as the
        // authoritative semantic input so the mapping below is verified
        // against live state rather than a stale cache.
        overlay->setPlayhead(baseX, true, true);
        processLayers();
        const QRectF translatedColumn = timelineColumnInScene(view, *root);
        QCOMPARE(quickWindow->size(), originalWindowSize);
        QTRY_VERIFY(layerFrameMatches(layers.root, translatedColumn));
        const QPointF expectedNativePoint =
            root->mapToScene(QPointF(view.timelineSplitX() + baseX, 0.0));
        QVERIFY(qAbs(layers.root.frame.origin.x + layers.body.position.x +
                     songview::playheadGlowLeftExtent(true) - expectedNativePoint.x()) <= 0.01);

        // A hidden background page has no native content despite sharing its
        // window with the selected canvas.
        root->setVisible(false);
        checks::support::pumpQuick();
        QTRY_VERIFY(layers.root.hidden);
        QVERIFY(!hasVisiblePixel(renderCore()));
        root->setVisible(true);
        checks::support::pumpQuick();
        QTRY_VERIFY(!layers.root.hidden);

        // The real shared ruler menu exposes a page-bounded content rectangle.
        // Its native layer must cut the playhead out of that rectangle while
        // leaving the same column visible again after close.
        auto *rulerInput =
            root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
        QVERIFY(rulerInput);
        QVERIFY(rulerInput->width() > 4.0 && rulerInput->height() > 4.0);
        const QPointF menuPoint{std::clamp(baseX, 2.0, rulerInput->width() - 2.0),
                                rulerInput->height() / 4.0};
        checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, menuPoint, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, menuPoint,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        songview::QuickPopupSession *const popup = quick->popupSession();
        QVERIFY(popup);
        QTRY_VERIFY(popup->isOpen() && !popup->contentRectInScene().isEmpty());
        // Menu layout can settle across frames after open; converge the
        // snapshot with the mask's occlusion source before probing it.
        checks::support::pumpQuick();
        processLayers();
        QVERIFY(popup->isOpen() && !popup->contentRectInScene().isEmpty());
        const QRectF popupScene = popup->contentRectInScene();
        QRectF occludedPlot;
        for (songview::TimelineBand band : bodyBands) {
            const std::optional<songview::TimelineBandGeometry> &geometry =
                view.timelineBandLayout().geometry(band);
            if (!geometry)
                continue;
            const QRectF overlap =
                popupScene.intersected(root->mapRectToScene(QRectF(geometry->plotRect)));
            if (!overlap.isEmpty()) {
                occludedPlot = overlap;
                break;
            }
        }
        QVERIFY(!occludedPlot.isEmpty());
        const QPointF occludedCanvasPoint = root->mapFromScene(occludedPlot.center());
        const qreal occludedTimelineX = occludedCanvasPoint.x() - view.timelineSplitX();
        QVERIFY(occludedTimelineX >= 0.0 &&
                occludedTimelineX < root->width() - view.timelineSplitX());
        overlay->setPlayhead(occludedTimelineX, true, true);
        processLayers();
        // The translated column sits on fractional offsets, so the enclosing
        // integer rect would sweep legitimately visible fringe into the probe
        // while the mask stays fractionally exact; test only pixels wholly
        // inside the true occluded overlap (still containing the core, which
        // sits at the overlap center, for both the absence and reappearance
        // checks below).
        const QRectF occludedLocal = occludedPlot.translated(-translatedColumn.topLeft());
        const int probeLeft = qCeil(occludedLocal.left());
        const int probeTop = qCeil(occludedLocal.top());
        const QRect occludedProbe{probeLeft, probeTop,
                                  std::max(0, qFloor(occludedLocal.right()) - probeLeft),
                                  std::max(0, qFloor(occludedLocal.bottom()) - probeTop)};
        QVERIFY(!occludedProbe.isEmpty());
        QVERIFY(
            !checks::support::hasSolidPlayheadPixel(renderCore(), occludedProbe, playheadColor));
        popup->cancel(false);
        QTRY_VERIFY(!popup->isOpen());
        processLayers();
        QVERIFY(checks::support::hasSolidPlayheadPixel(renderCore(), occludedProbe, playheadColor));

        // Canvas-only resizing leaves the enclosing Quick window untouched
        // while moving native layer geometry to the resized page extent.
        overlay->setPlayhead(baseX, true, true);
        const QSizeF viewportOnlySize{root->width() - 37.5, root->height() - 29.25};
        root->setSize(viewportOnlySize);
        checks::support::pumpQuick();
        processLayers();
        const QRectF viewportOnlyColumn = timelineColumnInScene(view, *root);
        QCOMPARE(quickWindow->size(), originalWindowSize);
        QTRY_VERIFY(layerFrameMatches(layers.root, viewportOnlyColumn));

        // A surface loss drops the mapped attachment before native handles
        // die; recreation reuses the existing layer tree at the page's live
        // translated viewport without rebuilding the Quick scene.
        QPlatformSurfaceEvent composedSurfaceLoss{QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed};
        QCoreApplication::sendEvent(quickWindow, &composedSurfaceLoss);
        processLayers();
        QCOMPARE(directPlayheadCount(owner), 0);
        QPlatformSurfaceEvent composedSurfaceCreated{QPlatformSurfaceEvent::SurfaceCreated};
        QCoreApplication::sendEvent(quickWindow, &composedSurfaceCreated);
        processLayers();
        QTRY_COMPARE(directPlayheadCount(owner), 1);
        QVERIFY(layerFrameMatches(layers.root, viewportOnlyColumn));

        root->setSize(originalRootSize);
        root->setPosition(originalRootPosition);
        checks::support::pumpQuick();
        processLayers();
        QTRY_VERIFY(layerFrameMatches(layers.root, timelineColumnInScene(view, *root)));
    }
    const QPixmap bitmap =
        QPixmap::fromImage(renderLayer(layers.root, quickWindow->effectiveDevicePixelRatio()));
    QVERIFY(!bitmap.isNull());

    // windowAboutToDetach clears the native attachment while the borrowed
    // host window is valid. Detaching the scene leaves that host window and
    // its CALayer alive for sibling scenes.
    QPointer<QQuickWindow> borrowedWindow = quickWindow;
    CALayer *detachOwner = ownerLayer(quickWindow);
    QVERIFY(detachOwner);
    bool detachObserved = false;
    QObject::connect(quick, &songview::TimelineQuickView::windowAboutToDetach, this, [&] {
        detachObserved = true;
        QVERIFY(quick->quickWindow() == quickWindow);
        QCOMPARE(directPlayheadCount(detachOwner), 0);
    });
    quick->detachScene();
    QVERIFY(detachObserved);
    QVERIFY(borrowedWindow);
    QCOMPARE(borrowedWindow.data(), quickWindow);
    QCOMPARE(directPlayheadCount(detachOwner), 0);
    QVERIFY(!quick->quickWindow());
    // Post-detach pushes are silent no-ops: no crash, no stale-layer writes.
    overlay->setPlayhead(baseX, true, true);
    processLayers();
    QCOMPARE(directPlayheadCount(detachOwner), 0);
}
