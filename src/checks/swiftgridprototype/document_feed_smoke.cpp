#include "document_feed_smoke.h"
#include "math_smoke.h"
#include "ui/songview/quick/swiftgrid/document_feed.h"

#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QFont>
#include <QImage>
#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QScopeGuard>
#include <QString>
#include <QVariant>
#include <QWheelEvent>
#include <QtTest/QTest>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <utility>
#include <vector>

namespace {
using namespace std::chrono_literals;

[[noreturn]] void fail(const char *reason)
{
    std::fprintf(stderr, "SWIFT_GRID_SMOKE FAIL: %s\n", reason);
    std::fflush(stderr);
    std::exit(EXIT_FAILURE);
}

void require(bool condition, const char *reason)
{
    if (!condition)
        fail(reason);
}

void pass(const char *scenario)
{
    std::printf("SWIFT_GRID_SMOKE %s PASS\n", scenario);
    std::fflush(stdout);
}

template <typename Predicate>
void awaitState(Predicate predicate, const char *reason)
{
    QDeadlineTimer deadline(3s);
    while (!predicate()) {
        if (deadline.hasExpired())
            fail(reason);
        QTest::qWait(10ms);
    }
}

QQuickItem *namedItem(QQuickItem *parent, const QString &name)
{
    if (parent->objectName() == name)
        return parent;
    for (QQuickItem *child : parent->childItems()) {
        if (auto *found = namedItem(child, name))
            return found;
    }
    return nullptr;
}

struct DocumentScene {
    QPointer<QQuickWindow> window;
    QPointer<QQuickItem> viewport;
    QPointer<QQuickItem> surface;
    QPointer<QObject> model;
    double baseFont = 0;
    double dpr = 1;
    double beatWidth = 0;
    double rowHeight = 0;
    double leadPad = 0;
    int ticksPerBeat = 0;

    DocumentScene(QQuickWindow *windowValue, QQuickItem *viewportValue, QQuickItem *surfaceValue,
                  QObject *modelValue)
        : window(windowValue)
        , viewport(viewportValue)
        , surface(surfaceValue)
        , model(modelValue)
    {
        baseFont = model->property("baseFontPx").toDouble();
        dpr = model->property("devicePixelRatio").toDouble();
        beatWidth = model->property("beatWidth").toDouble();
        rowHeight = model->property("rowHeight").toDouble();
        leadPad = model->property("leadPadWidth").toDouble();
        ticksPerBeat = model->property("ticksPerBeat").toInt();
    }

    QPointF point(double tick, int pitch) const
    {
        return {leadPad + tick * beatWidth / ticksPerBeat, (127.0 - pitch + 0.5) * rowHeight};
    }

    double pixelSnap(double value) const { return std::round(value * dpr) / dpr; }

    QRectF expectedBox(int tick, int duration, int pitch) const
    {
        const double pixel = 1.0 / dpr;
        const double x0 = pixelSnap(leadPad + tick * beatWidth / ticksPerBeat);
        const double x1 = pixelSnap(leadPad + (tick + duration) * beatWidth / ticksPerBeat);
        const double top = pixelSnap((127 - pitch) * rowHeight);
        const double bottom = pixelSnap((128 - pitch) * rowHeight);
        return {x0, top + pixel, qMax(std::round(baseFont / 6.0), x1 - x0),
                bottom - top - 2 * pixel};
    }

    QRectF itemRect(QQuickItem *item) const
    {
        return {item->mapToItem(surface, QPointF{}), item->size()};
    }

    void reveal(QPointF content) const
    {
        require(viewport && surface && window, "grid scene destroyed during smoke");
        const double maxX =
            qMax(0.0, viewport->property("contentWidth").toDouble() - viewport->width());
        const double maxY =
            qMax(0.0, viewport->property("contentHeight").toDouble() - viewport->height());
        require(viewport->setProperty("contentX",
                                      qBound(0.0, content.x() - viewport->width() / 2, maxX)),
                "cannot scroll horizontal viewport");
        require(viewport->setProperty("contentY",
                                      qBound(0.0, content.y() - viewport->height() / 2, maxY)),
                "cannot scroll vertical viewport");
        QTest::qWait(20ms);
        const QPointF scenePoint = surface->mapToScene(content);
        require(scenePoint.x() >= 0 && scenePoint.x() < window->width() && scenePoint.y() >= 0 &&
                    scenePoint.y() < window->height(),
                "gesture target is outside the native window");
    }

    QPoint windowPoint(QPointF content) const { return surface->mapToScene(content).toPoint(); }

    void press(QPointF content) const
    {
        reveal(content);
        QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, windowPoint(content));
        QTest::qWait(30ms);
    }

    void move(QPointF content) const
    {
        QTest::mouseMove(window, windowPoint(content));
        QTest::qWait(30ms);
    }

    void release(QPointF content) const
    {
        QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, windowPoint(content));
        awaitState([this] { return model->property("activeNoteId").toInt() == -1; },
                   "pointer release did not finish the gesture");
    }

    void doubleClick(QPointF content) const
    {
        reveal(content);
        QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, windowPoint(content));
        QTest::qWait(50ms);
    }

    bool boxMatches(QQuickItem *item, const QRectF &expected) const
    {
        if (!item || !item->isVisible())
            return false;
        const QRectF actual = itemRect(item);
        const double tolerance = 0.26 / dpr + 0.02;
        return std::abs(actual.x() - expected.x()) <= tolerance &&
               std::abs(actual.y() - expected.y()) <= tolerance &&
               std::abs(actual.width() - expected.width()) <= tolerance &&
               std::abs(actual.height() - expected.height()) <= tolerance;
    }

    void expectNamedBox(const QString &name, const QRectF &expected, const char *reason) const
    {
        if (QTest::qWaitFor([&] { return boxMatches(namedItem(surface, name), expected); }, 3s))
            return;
        auto *item = namedItem(surface, name);
        const QRectF actual = item ? itemRect(item) : QRectF{};
        std::fprintf(stderr, "%s actual=(%g,%g %gx%g) expected=(%g,%g %gx%g) visible=%d\n",
                     qPrintable(name), actual.x(), actual.y(), actual.width(), actual.height(),
                     expected.x(), expected.y(), expected.width(), expected.height(),
                     item && item->isVisible());
        fail(reason);
    }
};

bool hasSelectionRing(QQuickItem *root, QQuickItem *surface, const QRectF &noteBox)
{
    for (QQuickItem *child : root->childItems()) {
        const QColor color = child->property("color").value<QColor>();
        const QRectF rect(child->mapToItem(surface, QPointF{}), child->size());
        if (color == QColor(QStringLiteral("#B9E8EE")) &&
            rect.intersects(noteBox.adjusted(-8, -8, 8, 8)))
            return true;
        if (hasSelectionRing(child, surface, noteBox))
            return true;
    }
    return false;
}

// Document rows deliberately reuse the shown prototype, its pointer host and
// production receiver. The standalone process has no production feed observer;
// this sole synthetic endpoint reserves the top token, away from host IDs.
void verifyDocumentNote(DocumentScene &scene, int id, const SgdNote &note)
{
    const QRectF box = scene.expectedBox(int(note.onTick), int(note.durationTicks), note.key);
    scene.reveal(box.center());
    scene.expectNamedBox(QStringLiteral("gridNote_%1").arg(id), box,
                         "document note was re-quantized or projected with the demo timebase");
    QTest::qWait(30ms);
    const QImage image = scene.window->grabWindow();
    require(!image.isNull(), "document grid framebuffer is empty");
    auto *item = namedItem(scene.surface, QStringLiteral("gridNote_%1").arg(id));
    require(item, "document note vanished before its framebuffer probe");
    const QColor face = item->property("color").value<QColor>();
    const QRectF interior = box.adjusted(1, 1, -1, -1);
    const QRect deviceBox =
        QRectF(scene.surface->mapToScene(interior.topLeft()) * image.devicePixelRatio(),
               interior.size() * image.devicePixelRatio())
            .toAlignedRect();
    require(image.rect().contains(deviceBox), "document note raster probe is clipped");
    int facePixels = 0;
    for (int y = deviceBox.top(); y <= deviceBox.bottom(); ++y)
        for (int x = deviceBox.left(); x <= deviceBox.right(); ++x)
            facePixels += image.pixelColor(x, y) == face;
    require(facePixels >= deviceBox.width() * deviceBox.height() / 4,
            "document note face does not cover its native framebuffer bounds");
}

QVariantList documentNoteScene(const DocumentScene &scene)
{
    auto *fills = namedItem(scene.surface, QStringLiteral("timelineQuickPianoNoteFills"));
    require(fills, "document note fill layer is missing");
    QVariantList result;
    for (auto *item : fills->childItems()) {
        if (item->objectName().startsWith(QStringLiteral("gridNote_")))
            result.append(QVariant::fromValue(
                QVariantList{item->objectName(), scene.itemRect(item), item->property("color")}));
    }
    return result;
}

void verifyDocumentMarks(DocumentScene &scene, const std::vector<SgdTimeSignature> &signatures,
                         uint32_t begin, uint32_t end, bool checkLabels)
{
    scene.reveal(scene.point((double(begin) + end) / 2, 62));
    std::vector<SGSigPoint> oracleSignatures;
    for (const auto &signature : signatures)
        oracleSignatures.push_back({signature.startTick, signature.numerator, signature.denomPow2});
    const SGTimeMapFixture map{uint32_t(scene.ticksPerBeat), end, 0, end, oracleSignatures.data(),
                               oracleSignatures.size()};
    std::vector<SGGridLine> lines(sgm_timeaxis_grid_lines(&map, begin, end, nullptr, 0));
    require(sgm_timeaxis_grid_lines(&map, begin, end, lines.data(), lines.size()) == lines.size(),
            "production TimeAxis oracle changed within one synchronous query");
    require(!lines.empty(), "document signature probe has no oracle grid lines");
    auto *time = namedItem(scene.surface, QStringLiteral("timelineQuickPianoGridTime"));
    auto *marks = namedItem(scene.window->contentItem(), QStringLiteral("timelineQuickRulerMarks"));
    auto *palette = scene.model->property("palette").value<QObject *>();
    require(time && marks && palette, "document time/ruler scene or palette is missing");
    const QColor barColor(palette->property("gridLineBar").toString());
    const QColor beatColor(palette->property("gridLineBeat").toString());
    const QColor fineBeatColor(palette->property("gridLineBeatFine").toString());
    const auto hasLine = [&](QQuickItem *layer, double x, const QColor &color) {
        for (auto *item : layer->childItems()) {
            const QRectF rect = scene.itemRect(item);
            if (item->isVisible() && rect.height() > rect.width() &&
                std::abs(rect.center().x() - x) < 0.26 / scene.dpr + 0.02 &&
                item->property("color").value<QColor>() == color)
                return true;
        }
        return false;
    };
    for (const auto &line : lines) {
        const double x = scene.pixelSnap(scene.point(line.tick, 62).x());
        // TimeAxis determines musical role; density emphasis is local to each
        // governing segment, not the tick-zero visibleGridTicks output.
        awaitState(
            [&] {
                return line.isBar ? hasLine(time, x, barColor)
                                  : hasLine(time, x, beatColor) || hasLine(time, x, fineBeatColor);
            },
            "rendered grid mark disagrees with production TimeAxis signature semantics");
        if (checkLabels && line.isBar) {
            auto *label = namedItem(scene.window->contentItem(),
                                    QStringLiteral("rulerLabel_%1").arg(line.bar));
            require(label && label->isVisible() &&
                        std::abs(scene.itemRect(label).left() -
                                 (x + std::round(scene.baseFont * 0.125))) < 0.3,
                    "document ruler bar number/position disagrees with production TimeAxis");
            require(hasLine(marks, x, QColor(palette->property("gridLine").toString())),
                    "document ruler lacks the production TimeAxis bar mark");
        }
    }
    // Reject extra bar marks too: coincident-event first-wins would otherwise
    // be able to draw the required bars plus incorrect ones.
    size_t renderedBars = 0;
    for (auto *item : time->childItems()) {
        if (item->property("color").value<QColor>() != barColor)
            continue;
        const double x = scene.itemRect(item).center().x();
        if (x < scene.pixelSnap(scene.point(begin, 62).x()) - 0.01 ||
            x >= scene.pixelSnap(scene.point(end, 62).x()) - 0.01)
            continue;
        ++renderedBars;
        require(std::any_of(lines.begin(), lines.end(),
                            [&](const SGGridLine &line) {
                                return line.isBar &&
                                       std::abs(x - scene.pixelSnap(
                                                        scene.point(line.tick, 62).x())) < 0.3;
                            }),
                "document scene contains a bar rejected by production TimeAxis");
    }
    require(renderedBars ==
                size_t(std::count_if(lines.begin(), lines.end(),
                                     [](const SGGridLine &line) { return line.isBar; })),
            "document scene lost or duplicated production TimeAxis bar marks");
    const auto rasterLine = std::find_if(lines.begin(), lines.end(),
                                         [](const SGGridLine &line) { return line.tick != 0; });
    require(rasterLine != lines.end(), "signature raster probe overlaps the start playhead");
    scene.reveal(scene.point(rasterLine->tick, 62));
    QTest::qWait(30ms);
    const QImage image = scene.window->grabWindow();
    require(!image.isNull(), "signature framebuffer is empty");
    const QPoint probe =
        (scene.surface->mapToScene(scene.point(rasterLine->tick, 62)) * image.devicePixelRatio())
            .toPoint();
    require(image.rect().contains(probe), "document time raster probe is clipped");
    const QColor pixel = image.pixelColor(probe);
    require(pixel.red() < 0xC9 && pixel.green() < 0xC1 && pixel.blue() < 0xBB,
            "document time mark does not darken the actual framebuffer row");
}

void verifyReadOnlyInput(DocumentScene &scene, const SgdNote &note)
{
    const QVariantList before = documentNoteScene(scene);
    const QVariant revision = scene.model->property("revision");
    const QVariant applied = scene.model->property("appliedRevisionText");
    const QVariant canUndo = scene.model->property("canUndo");
    const QVariant canRedo = scene.model->property("canRedo");
    const QVariant cursor = scene.model->property("editCursorTick");
    const QRectF box = scene.expectedBox(int(note.onTick), int(note.durationTicks), note.key);
    const auto inert = [&] {
        auto *borders = namedItem(scene.surface, "timelineQuickPianoNoteBordersAndSelection");
        auto *menu = namedItem(scene.window->contentItem(), "noteContextMenu");
        require(documentNoteScene(scene) == before && borders && menu &&
                    !hasSelectionRing(borders, scene.surface, box) &&
                    !namedItem(scene.surface, "drawPreview") &&
                    !menu->property("opened").toBool() &&
                    !scene.window->property("pitchBridge").value<QObject *>() &&
                    scene.model->property("activeNoteId").toInt() == -1 &&
                    scene.model->property("revision") == revision &&
                    scene.model->property("appliedRevisionText") == applied &&
                    scene.model->property("canUndo") == canUndo &&
                    scene.model->property("canRedo") == canRedo &&
                    scene.model->property("editCursorTick") == cursor,
                "read-only input changed notes, selection, edit state, undo or revision");
    };
    // Real pointer presses, movement and release: draw, move, both resize
    // grips, double-click add/delete, right-band selection and note menu.
    for (const QPointF start :
         {scene.point(1200, 70), box.center(), QPointF(box.left(), box.center().y()),
          QPointF(box.right(), box.center().y())}) {
        const QPointF end = start + QPointF(scene.beatWidth, -scene.rowHeight);
        scene.press(start);
        scene.move(end);
        inert();
        scene.release(end);
        inert();
    }
    scene.doubleClick(scene.point(1200, 70));
    inert();
    scene.doubleClick(box.center());
    inert();
    scene.reveal(box.center());
    const QPoint rightStart = scene.windowPoint(box.topLeft() - QPointF(4, 4));
    const QPoint rightEnd = scene.windowPoint(box.bottomRight() + QPointF(4, 4));
    QTest::mousePress(scene.window, Qt::RightButton, Qt::NoModifier, rightStart);
    QTest::mouseMove(scene.window, rightEnd);
    QTest::qWait(30ms);
    inert();
    QTest::mouseRelease(scene.window, Qt::RightButton, Qt::NoModifier, rightEnd);
    QTest::mouseClick(scene.window, Qt::RightButton, Qt::NoModifier,
                      scene.windowPoint(box.center()));
    QTest::qWait(30ms);
    inert();
    for (const char *method : {"deleteSelection", "undo", "redo", "resetDemo", "previewPitchCurves",
                               "commitPitchCurves", "cancelPitchCurves", "closePitchEditor"}) {
        require(QMetaObject::invokeMethod(scene.model, method),
                "cannot invoke read-only semantic mutation entry");
        inert();
    }
    // A typed null must overwrite the sentinel; an invalid QVariant must not
    // pass merely because the caller already initialized its result to null.
    QObject *editor = scene.model.data();
    require(QMetaObject::invokeMethod(scene.model, "makePitchEditor", qReturnArg(editor), 20.0,
                                      16.0, QStringLiteral("Helvetica"), QStringLiteral("Menlo")) &&
                !editor,
            "read-only semantic pitch-editor entry opened an edit session");
    int escapeAction = -1;
    require(
        QMetaObject::invokeMethod(scene.model, "escapePressed", qReturnArg(escapeAction), false) &&
            escapeAction == 0,
        "read-only Escape found an edit session to resolve");
    inert();
    pass("document-read-only-pointer-and-semantic-mutation-inertness");
}

void verifyDocumentFeedImpl(DocumentScene scene)
{
    constexpr uint64_t token = std::numeric_limits<uint64_t>::max();
    constexpr uint64_t firstRevision = (uint64_t(1) << 63) + 17;
    SgdDelivery delivery{};
    sgd_register_feed(token, &delivery);
    const auto unregister = qScopeGuard([&] {
        sgd_clear_delivery(token);
        sgd_unregister_feed(token);
    });
    require(scene.model->setProperty("readOnly", true) &&
                scene.model->setProperty("documentTrack", 0) &&
                QMetaObject::invokeMethod(scene.model, "bindDocument", QString::number(token)),
            "cannot bind the existing shown grid to a read-only document");
    require(delivery.fn && delivery.context, "production receiver did not bind the endpoint");
    scene.ticksPerBeat = 480;
    std::vector<SgdNote> notes{{1, 0, 60, 480, 240, 98},
                               {2, 1, 64, 960, 480, 127},
                               {3, 0, 67, 1440, 360, 110},
                               {4, 0, 72, 48000, 480, 100},
                               {5, 1, 72, 48000, 480, 100}};
    std::vector<SgdTimeSignature> signatures{{480, 3, 2}, {1920, 7, 3}, {1920, 5, 3}};
    const auto push = [&](uint64_t revision, int tracks = 2) {
        const SgdDocumentHeader header{
            token, revision, 480, tracks, int32_t(notes.size()), int32_t(signatures.size())};
        // Vectors and header outlive this synchronous callback only. The real
        // Swift receiver must own accepted values after it returns.
        delivery.fn(&header, notes.empty() ? nullptr : notes.data(),
                    signatures.empty() ? nullptr : signatures.data(), delivery.context);
        QTest::qWait(30ms);
    };
    const auto expectCount = [&](int count, uint64_t revision) {
        awaitState(
            [&] {
                return scene.model->property("renderedNoteCount").toInt() == count &&
                       documentNoteScene(scene).size() == count &&
                       scene.model->property("appliedRevisionText").toString() ==
                           QString::number(revision);
            },
            "document track/revision outputs disagree with the rendered scene");
    };
    push(firstRevision);
    expectCount(3, firstRevision);
    require(scene.model->property("ticksPerBeat").toInt() == 480,
            "document division did not replace the demo timebase");
    verifyDocumentNote(scene, 1, notes[0]);
    verifyDocumentNote(scene, 3, notes[2]);
    verifyDocumentMarks(scene, signatures, 0, 3600, true);
    for (const auto &signature : {std::pair{"3/4", 480}, std::pair{"5/8", 1920}}) {
        auto *label =
            namedItem(scene.window->contentItem(), QStringLiteral("rulerLabel_") + signature.first);
        require(label && label->isVisible() &&
                    std::abs(scene.itemRect(label).left() -
                             (scene.pixelSnap(scene.point(signature.second, 62).x()) +
                              std::round(scene.baseFont * 0.125))) < 0.3,
                "document signature label did not follow its real tick");
    }
    require(!namedItem(scene.window->contentItem(), "rulerLabel_7/8"),
            "overwritten coincident signature remains in the ruler");
    verifyReadOnlyInput(scene, notes[0]);

    // Exercise the real wheel host, then its writable FontInfo scale authority.
    // Direct model configuration would be overwritten by host layout updates.
    scene.reveal(scene.point(4800, 60));
    const double oldX = scene.viewport->property("contentX").toDouble();
    const double oldY = scene.viewport->property("contentY").toDouble();
    const QPoint wheelPoint = scene.windowPoint(scene.point(4800, 60));
    QWheelEvent wheel(wheelPoint, scene.window->mapToGlobal(wheelPoint), {}, {-120, -120},
                      Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(scene.window, &wheel);
    awaitState(
        [&] {
            return scene.viewport->property("contentY").toDouble() > oldY &&
                   scene.viewport->property("contentX").toDouble() > oldX;
        },
        "read-only horizontal/vertical wheel pan is inert");
    const double previousBeatWidth = scene.beatWidth;
    auto *context = qmlContext(scene.window);
    const QPointer<QObject> fontInfo =
        context ? context->objectForName(QStringLiteral("appFontInfo")) : nullptr;
    require(fontInfo, "the existing appFontInfo QML id is inaccessible from the window context");
    const QFont originalFont = fontInfo->property("font").value<QFont>();
    const auto restoreFont = qScopeGuard([fontInfo, originalFont] {
        if (fontInfo)
            fontInfo->setProperty("font", originalFont);
    });
    QFont scaledFont = originalFont;
    const int scaledPixelSize = qRound(scene.baseFont * 1.5);
    scaledFont.setPixelSize(scaledPixelSize);
    require(fontInfo->setProperty("font", scaledFont),
            "cannot configure the existing host FontInfo font property");
    awaitState([&] { return scene.window->property("baseFontPx").toDouble() == scaledPixelSize; },
               "host FontInfo scale did not update the authoritative root metric");
    QTest::qWait(30ms);
    require(QMetaObject::invokeMethod(scene.window, "configureViewport"),
            "cannot apply the existing host viewport configuration");
    awaitState([&] { return scene.model->property("baseFontPx").toDouble() == scaledPixelSize; },
               "host viewport configuration did not publish the requested metric scale");
    QTest::qWait(30ms);
    scene.baseFont = scene.model->property("baseFontPx").toDouble();
    scene.beatWidth = scene.model->property("beatWidth").toDouble();
    scene.rowHeight = scene.model->property("rowHeight").toDouble();
    scene.leadPad = scene.model->property("leadPadWidth").toDouble();
    require(scene.beatWidth > previousBeatWidth, "host metric scale did not change projection");
    verifyDocumentNote(scene, 1, notes[0]);
    const QPoint hoverTarget(qRound(scene.model->property("keyboardWidth").toDouble() / 2),
                             scene.windowPoint(scene.point(600, 60)).y());
    QTest::mouseMove(scene.window, hoverTarget);
    awaitState(
        [&] {
            auto *chip = namedItem(scene.window->contentItem(), "timelineQuickPianoHoverChip");
            return chip && chip->isVisible() &&
                   std::abs(chip->mapToScene({0, chip->height() / 2}).y() - hoverTarget.y()) <= 1;
        },
        "read-only keyboard hover preview is not live after host pan/metric-scale changes");
    expectCount(3, firstRevision);
    pass("document-read-only-live-pan-metric-scale-and-hover");

    scene.reveal(scene.point(24000, 60));
    const double savedX = scene.viewport->property("contentX").toDouble();
    const double savedY = scene.viewport->property("contentY").toDouble();
    const auto viewUnchanged = [&] {
        require(scene.viewport->property("contentX").toDouble() == savedX &&
                    scene.viewport->property("contentY").toDouble() == savedY &&
                    scene.model->property("beatWidth").toDouble() == scene.beatWidth &&
                    scene.model->property("rowHeight").toDouble() == scene.rowHeight,
                "document refresh or track selection reset the viewport");
    };
    require(scene.model->setProperty("documentTrack", 1), "cannot select document track");
    expectCount(2, firstRevision);
    viewUnchanged();
    verifyDocumentNote(scene, 2, notes[1]);
    require(!namedItem(scene.surface, "gridNote_1") && !namedItem(scene.surface, "gridNote_3"),
            "selected document track leaked another track's notes");
    notes[1].onTick = 1200;
    notes[1].durationTicks = 240;
    notes[1].key = 65;
    scene.reveal(scene.point(24000, 60));
    const double refreshX = scene.viewport->property("contentX").toDouble();
    const double refreshY = scene.viewport->property("contentY").toDouble();
    push(firstRevision + 1);
    expectCount(2, firstRevision + 1);
    require(scene.viewport->property("contentX").toDouble() == refreshX &&
                scene.viewport->property("contentY").toDouble() == refreshY,
            "higher revision changed the current scroll");
    verifyDocumentNote(scene, 2, notes[1]);
    const QVariantList accepted = documentNoteScene(scene);
    notes[1].key = 80;
    push(firstRevision);
    expectCount(2, firstRevision + 1);
    require(documentNoteScene(scene) == accepted,
            "track switch reset the revision guard and accepted a stale snapshot");
    scene.reveal(scene.point(24000, 60));
    for (int track : {-1, 2}) {
        require(scene.model->setProperty("documentTrack", track), "cannot select invalid track");
        expectCount(0, firstRevision + 1);
        viewUnchanged();
    }
    require(scene.model->setProperty("documentTrack", 1), "cannot restore document track");
    expectCount(2, firstRevision + 1);
    require(documentNoteScene(scene) == accepted,
            "invalid track lost the retained accepted snapshot");
    pass("document-track-filter-refresh-stale-guard-and-invalid-track");

    // Bound the pathological segment to ten ticks. Its raw numerator zero
    // and exponent 255 go through production TimeAxis, not copied shift math.
    signatures = {{480, 3, 2}, {1920, 7, 3}, {1920, 5, 3}, {3840, 0, 255}, {3850, 4, 2}};
    notes.clear();
    push(firstRevision + 2);
    expectCount(0, firstRevision + 2);
    verifyDocumentMarks(scene, signatures, 3820, 4000, false);
    signatures.clear();
    push(firstRevision + 3, 0);
    expectCount(0, firstRevision + 3);
    verifyDocumentMarks(scene, signatures, 0, 1920, true);
    pass("document-raw-signatures-production-oracle-and-empty-snapshot");
}

} // namespace

void verifyDocumentFeed(QQuickWindow *window, QQuickItem *viewport, QQuickItem *surface,
                        QObject *model)
{
    verifyDocumentFeedImpl(DocumentScene(window, viewport, surface, model));
}
