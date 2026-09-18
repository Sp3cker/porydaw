#include "grid_smoke.h"
#include "math_smoke.h"
#include "ui/songview/quick/swiftgrid/document_feed.h"

#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QFont>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointF>
#include <QPointer>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QString>
#include <QTimer>
#include <QVariant>
#include <QWheelEvent>
#include <QtQml/qqml.h>
#include <QtTest/QTest>
#include <algorithm>
#include <array>
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

int noteId(const QJsonObject &note)
{
    return note.value("id").toInt(-1);
}

QJsonArray musicalState(const QJsonArray &notes)
{
    QJsonArray result;
    for (const QJsonValue &value : notes) {
        const QJsonObject note = value.toObject();
        QJsonObject musical;
        for (const char *key : {"id", "tick", "duration", "pitch", "track", "velocity", "ghost"})
            musical.insert(QLatin1String(key), note.value(QLatin1String(key)));
        result.append(musical);
    }
    return result;
}

struct Scene {
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
    int snap = 0;

    QJsonArray notes() const
    {
        require(model, "grid model destroyed during smoke");
        const QJsonDocument document =
            QJsonDocument::fromJson(model->property("noteSummary").toString().toUtf8());
        require(document.isArray(), "noteSummary is not a JSON array");
        return document.array();
    }

    QJsonObject note(int id) const
    {
        for (const QJsonValue &value : notes()) {
            if (noteId(value.toObject()) == id)
                return value.toObject();
        }
        return {};
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

    void click(QPointF content) const
    {
        press(content);
        release(content);
    }

    void doubleClick(QPointF content) const
    {
        reveal(content);
        QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, windowPoint(content));
        QTest::qWait(50ms);
    }

    void cancel(QPointF content) const
    {
        QQuickItem *grabber = window->mouseGrabberItem();
        require(grabber, "pressed QML input item has no native mouse grab");
        grabber->ungrabMouse();
        awaitState([this] { return model->property("activeNoteId").toInt() == -1; },
                   "native mouse ungrab did not cancel the gesture");
        QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, windowPoint(content));
        QTest::qWait(30ms);
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

    void expectBox(QQuickItem *item, const QRectF &expected, const char *reason) const
    {
        QPointer<QQuickItem> guarded = item;
        awaitState([&] { return boxMatches(guarded.data(), expected); }, reason);
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

    void expectPublished(int id, int tick, int duration, int pitch, const char *reason) const
    {
        const QRectF expected = expectedBox(tick, duration, pitch);
        reveal(expected.center());
        awaitState(
            [&] {
                const QJsonObject value = note(id);
                return value.value("tick").toInt(-1) == tick &&
                       value.value("duration").toInt(-1) == duration &&
                       value.value("pitch").toInt(-1) == pitch;
            },
            reason);
        expectNamedBox(QStringLiteral("gridNote_%1").arg(id), expected,
                       "scene note primitive does not follow published geometry");
    }

    void expectPreview(const QRectF &expected) const
    {
        expectNamedBox(QStringLiteral("drawPreview"), expected,
                       "draw preview geometry is not source projected");
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

int addedNoteId(const QJsonArray &before, const QJsonArray &after)
{
    for (const QJsonValue &candidate : after) {
        const int id = noteId(candidate.toObject());
        bool existed = false;
        for (const QJsonValue &old : before)
            existed = existed || noteId(old.toObject()) == id;
        if (!existed)
            return id;
    }
    return -1;
}

void verifyFixture(Scene &scene)
{
    static constexpr std::array<int, 15> leadPitches = {
        60, 64, 67, 71, 74, 71, 67, 64, 60, 64, 67, 71, 74, 71, 67,
    };
    static constexpr std::array<int, 15> ghostPitches = {
        48, 55, 52, 57, 50, 57, 52, 55, 48, 55, 52, 57, 50, 57, 52,
    };
    static constexpr std::array<int, 3> leadVelocities = {98, 104, 110};
    static constexpr std::array<int, 3> ghostVelocities = {86, 92, 98};

    const QJsonArray initial = scene.notes();
    require(initial.size() == 30, "fixture must publish exactly 30 notes");
    for (int i = 0; i < 30; ++i) {
        const bool ghost = i >= 15;
        const int local = ghost ? i - 15 : i;
        const int id = i + 1;
        const int tick = 24 * local + (ghost ? 12 : 0);
        const int pitch = ghost ? ghostPitches[local] : leadPitches[local];
        const int velocity = ghost ? ghostVelocities[local % 3] : leadVelocities[local % 3];
        const QJsonObject note = scene.note(id);
        require(note.value("track").toInt(-1) == (ghost ? 1 : 0) &&
                    note.value("velocity").toInt(-1) == velocity &&
                    note.value("ghost").toBool(!ghost) == ghost,
                "fixture track, velocity, or ghost role differs from source fixture");
        scene.expectPublished(id, tick, 18, pitch, "fixture note fields differ from source MIDI");
    }
    pass("source-fixture-and-projected-boxes");
}

void verifyRaster(Scene &scene)
{
    const auto capture = [&] {
        QTest::qWait(30ms);
        QImage image = scene.window->grabWindow();
        require(!image.isNull(), "native grid framebuffer is empty");
        return image;
    };
    const auto pixelAt = [&](const QImage &image, QPointF content) {
        const QPointF position = scene.surface->mapToScene(content) * image.devicePixelRatio();
        const QPoint pixel(qRound(position.x()), qRound(position.y()));
        require(image.rect().contains(pixel), "raster probe is outside the framebuffer");
        return image.pixelColor(pixel);
    };
    const auto isBlack = [](QColor color) {
        return color.red() <= 16 && color.green() <= 16 && color.blue() <= 16;
    };

    scene.reveal(scene.point(9, 60));
    QImage image = capture();
    require(pixelAt(image, scene.point(9, 62)) == QColor("#C9C1BB") &&
                pixelAt(image, scene.point(9, 61)) == QColor("#B4ACA6"),
            "natural and accidental row pixels differ from production colors");
    const QRectF note = scene.expectedBox(0, 18, 60);
    require(pixelAt(image, note.center()) == QColor("#C0625E"),
            "velocity-98 note face differs from production OKLab fill");
    const double pixel = 1.0 / scene.dpr;
    const int borderPixels = qRound(scene.dpr);
    for (int i = 0; i < borderPixels; ++i) {
        require(isBlack(pixelAt(image, {note.center().x(), note.top() + i * pixel})) &&
                    isBlack(pixelAt(image, {note.center().x(), note.bottom() - (i + 1) * pixel})),
                "unselected note lacks its display-scaled black border");
    }
    pass("production-row-colors-note-fill-and-border-raster");

    scene.click(note.center());
    image = capture();
    const int ringPixels = qMax(1, qRound(scene.baseFont / 8.0 * scene.dpr));
    const QColor ring("#B9E8EE");
    for (int i = 0; i < ringPixels; ++i) {
        require(pixelAt(image, {note.center().x(), note.top() + i * pixel}) == ring &&
                    pixelAt(image, {note.center().x(), note.bottom() - (i + 1) * pixel}) == ring,
                "selected note ring is not contiguous at its production weight");
    }
    for (int i = 0; i < borderPixels; ++i) {
        const double inset = (ringPixels + i) * pixel;
        require(isBlack(pixelAt(image, {note.center().x(), note.top() + inset})) &&
                    isBlack(pixelAt(image, {note.center().x(), note.bottom() - inset - pixel})) &&
                    isBlack(pixelAt(image, {note.left() + inset, note.center().y()})) &&
                    isBlack(pixelAt(image, {note.right() - inset - pixel, note.center().y()})),
                "selected note lacks its inset black frame");
    }
    require(pixelAt(image, note.center()) == QColor("#C0625E"),
            "selection frame swallowed the note face");
    pass("production-selected-note-frame-raster");

    const QRectF ghost = scene.expectedBox(12, 18, 48);
    scene.reveal(ghost.center());
    image = capture();
    const QColor ghostFace = pixelAt(image, ghost.center());
    require(!isBlack(ghostFace) && pixelAt(image, {ghost.center().x(), ghost.top()}) == ghostFace &&
                pixelAt(image, {ghost.center().x(), ghost.bottom() - pixel}) == ghostFace,
            "ghost note acquired an opaque border instead of an uninterrupted face");
    pass("production-ghost-note-edge-raster");
    require(QMetaObject::invokeMethod(scene.window, "resetDemo"),
            "cannot reset the demo after raster probes");
    QTest::qWait(30ms);
}

void verifyChromeRaster(Scene &scene)
{
    const auto capture = [&] {
        QTest::qWait(30ms);
        QImage image = scene.window->grabWindow();
        require(!image.isNull(), "native grid framebuffer is empty");
        return image;
    };
    const auto windowPixel = [](const QImage &image, QPointF scenePoint) {
        const QPoint pixel(qRound(scenePoint.x() * image.devicePixelRatio()),
                           qRound(scenePoint.y() * image.devicePixelRatio()));
        require(image.rect().contains(pixel), "chrome raster probe is outside the framebuffer");
        return image.pixelColor(pixel);
    };
    const auto gutterPoint = [&](QQuickItem *gutter, double x, double y) {
        return gutter->mapToScene(QPointF(x, y));
    };

    auto *rulerGutter =
        namedItem(scene.window->contentItem(), QStringLiteral("timelineQuickRulerGutter"));
    auto *rollGutter =
        namedItem(scene.window->contentItem(), QStringLiteral("timelineQuickRollGutter"));
    require(rulerGutter && rollGutter, "ruler or keyboard gutter is missing");

    // Read-only visual probe: preserve the flickable scroll position so later
    // gesture scenarios observe the same camera state verifyRaster left.
    const double priorContentX = scene.viewport->property("contentX").toDouble();
    const double priorContentY = scene.viewport->property("contentY").toDouble();
    const auto restoreScroll = qScopeGuard([&] {
        scene.viewport->setProperty("contentX", priorContentX);
        scene.viewport->setProperty("contentY", priorContentY);
    });

    scene.reveal(scene.point(9, 60));
    QImage image = capture();
    const double keyboardWidth = scene.model->property("keyboardWidth").toDouble();
    const double rulerHeight = scene.model->property("rulerHeight").toDouble();
    require(windowPixel(image, gutterPoint(rulerGutter, keyboardWidth / 2, rulerHeight / 2)) ==
                QColor("#BDB5AF"),
            "ruler gutter chrome diverged from the production chrome background");
    // The ruler separator is a 1-logical-pixel rect centered on rulerHeight
    // (GridScene.swift:351), clipped by the gutter item's own height. The
    // scene-graph rect has no antialiasing: a device row is filled when its
    // pixel center falls inside the mapped clipped span. Probe the first row
    // whose center is inside for the exact production color.
    {
        const double dpr = image.devicePixelRatio();
        const QPointF gutterOrigin = rulerGutter->mapToScene(QPointF{});
        const double clipBottom = std::min(rulerHeight + 0.5, rulerGutter->height());
        const double devTop = (gutterOrigin.y() + rulerHeight - 0.5) * dpr;
        const double devBottom = (gutterOrigin.y() + clipBottom) * dpr;
        const int row = int(std::ceil(devTop - 0.5));
        require(row + 0.5 < devBottom,
                "ruler gutter separator has no device row inside its clipped span");
        const QColor actual =
            windowPixel(image, QPointF(gutterOrigin.x() + keyboardWidth / 2, double(row) / dpr));
        if (actual != QColor("#5B5652"))
            std::fprintf(stderr,
                         "ruler separator actual=%s row=%d devSpan=[%g,%g] dpr=%g "
                         "gutterY=%g gutterH=%g\n",
                         qPrintable(actual.name()), row, devTop, devBottom, dpr, gutterOrigin.y(),
                         rulerGutter->height());
        require(actual == QColor("#5B5652"),
                "ruler gutter separator diverged from the production separator color");
    }
    // A scene-graph rect without antialiasing fills exactly the device rows
    // whose pixel centers fall inside its mapped span; returns that row.
    const auto rowInsideSpan = [](double originY, double localTop, double localBottom, double dpr) {
        const double devTop = (originY + localTop) * dpr;
        const double devBottom = (originY + localBottom) * dpr;
        const int row = int(std::ceil(devTop - 0.5));
        require(row + 0.5 < devBottom, "separator strip has no device row inside its mapped span");
        return row;
    };
    // rollBandContent already carries -contentY, so gutter-local y is the
    // content-space row coordinate directly.
    const auto keyboardY = [&](int pitch) { return (127.0 - pitch + 0.5) * scene.rowHeight; };
    require(windowPixel(image, gutterPoint(rollGutter, keyboardWidth / 2, keyboardY(60))) ==
                    QColor("#F4F4F4") &&
                windowPixel(image, gutterPoint(rollGutter, keyboardWidth / 2, keyboardY(61))) ==
                    QColor("#202224"),
            "keyboard natural/black key fills diverged from production colors");
    // The C-boundary separator is one physical pixel (m.pixel = 1/dpr) ending
    // at the snapped row edge; probe the device row whose center falls inside
    // its mapped span for the exact production color.
    const double cEdge = (127.0 - 60 + 1.0) * scene.rowHeight;
    const double pixel = 1.0 / scene.dpr;
    const QPointF rollOrigin = rollGutter->mapToScene(QPointF{});
    const int sepRow =
        rowInsideSpan(rollOrigin.y(), cEdge - pixel, cEdge, image.devicePixelRatio());
    require(windowPixel(image, QPointF(rollOrigin.x() + keyboardWidth / 2,
                                       double(sepRow) / image.devicePixelRatio())) ==
                QColor("#BCB4AF"),
            "keyboard C-boundary separator diverged from its production color");

    const auto pixelAt = [&](const QImage &frame, QPointF content) {
        const QPointF position = scene.surface->mapToScene(content) * frame.devicePixelRatio();
        const QPoint point(qRound(position.x()), qRound(position.y()));
        require(frame.rect().contains(point), "grid raster probe is outside the framebuffer");
        return frame.pixelColor(point);
    };
    const double probeY = scene.point(9, 62).y();
    // The first bar line sits at leadPad + 4 beats (tick 96); the leadPad edge
    // itself is a red start marker, not a bar line.
    const double barX = scene.leadPad + 4 * scene.beatWidth;
    const QColor rowBackground = pixelAt(image, {barX + 24, probeY});
    const QColor barLine = pixelAt(image, {barX, probeY});
    require(barLine != rowBackground && barLine.red() < rowBackground.red() &&
                barLine.green() < rowBackground.green() && barLine.blue() < rowBackground.blue(),
            "bar grid line is not a darkened overlay over the row background");
    const QPointF surfaceOrigin = scene.surface->mapToScene(QPointF{});
    const int gridSepRow =
        rowInsideSpan(surfaceOrigin.y(), cEdge - pixel, cEdge, image.devicePixelRatio());
    require(pixelAt(image, {barX + 24, double(gridSepRow) / image.devicePixelRatio() -
                                           surfaceOrigin.y()}) == QColor("#BCB4AF"),
            "grid C-row separator diverged from its production color");
    pass("production-grid-line-raster");
}

// Document rows deliberately reuse the shown prototype, its pointer host and
// production receiver. The standalone process has no production feed observer;
// this sole synthetic endpoint reserves the top token, away from host IDs.
void verifyDocumentNote(Scene &scene, int id, const SgdNote &note)
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

QVariantList documentNoteScene(const Scene &scene)
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

void verifyDocumentMarks(Scene &scene, const std::vector<SgdTimeSignature> &signatures,
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

void verifyReadOnlyInput(Scene &scene, const SgdNote &note)
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

void verifyDocumentFeed(Scene scene)
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
    std::vector<SgdNote> notes{{0, 60, 480, 240, 98},
                               {1, 64, 960, 480, 127},
                               {0, 67, 1440, 360, 110},
                               {0, 72, 48000, 480, 100},
                               {1, 72, 48000, 480, 100}};
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

void exercise(Scene scene)
{
    verifyGridAudio();
    scene.baseFont = scene.model->property("baseFontPx").toDouble();
    scene.dpr = scene.model->property("devicePixelRatio").toDouble();
    scene.beatWidth = scene.model->property("beatWidth").toDouble();
    scene.rowHeight = scene.model->property("rowHeight").toDouble();
    scene.leadPad = scene.model->property("leadPadWidth").toDouble();
    scene.ticksPerBeat = scene.model->property("ticksPerBeat").toInt();
    scene.snap = scene.model->property("snapTicks").toInt();
    require(scene.baseFont > 0 && scene.dpr > 0 && scene.beatWidth > 0 && scene.rowHeight > 0 &&
                scene.leadPad >= 48 && scene.ticksPerBeat == 24 && scene.snap == 6 &&
                scene.model->property("visibleGridTicks").toInt() == 12 &&
                scene.model->property("highestPitch").toInt() == 127 &&
                scene.model->property("lowestPitch").toInt() == 0,
            "grid metrics do not match the production 24 TPQN projection");
    verifyFixture(scene);
    verifyRaster(scene);
    verifyChromeRaster(scene);

    const QPointF pending = scene.point(98, 100);
    const QJsonArray beforePending = scene.notes();
    const int oldCursor = scene.model->property("editCursorTick").toInt();
    scene.press(pending);
    require(musicalState(scene.notes()) == musicalState(beforePending) &&
                !namedItem(scene.surface, QStringLiteral("drawPreview")) &&
                scene.model->property("editCursorTick").toInt() == oldCursor,
            "empty press committed a note, preview, or edit cursor before release");
    scene.release(pending);
    require(musicalState(scene.notes()) == musicalState(beforePending) &&
                scene.model->property("editCursorTick").toInt() == 96,
            "empty click did not remain pending and snap its edit cursor");
    pass("pending-empty-click");

    const QJsonArray beforeShortDrag = scene.notes();
    const QPointF shortDragStart = scene.point(120, 108);
    const QPointF shortDragEnd = shortDragStart + QPointF(2, 0);
    scene.press(shortDragStart);
    scene.move(shortDragEnd);
    scene.release(shortDragEnd);
    require(musicalState(scene.notes()) == musicalState(beforeShortDrag) &&
                !namedItem(scene.surface, QStringLiteral("drawPreview")),
            "subthreshold horizontal drag drew a note");
    pass("production-minimum-draw-distance");
    const QJsonArray beforeDraw = scene.notes();
    const QPointF drawAnchor = scene.point(168, 100);

    const QPointF drawLeft = scene.point(146, 102);
    scene.press(drawAnchor);
    require(musicalState(scene.notes()) == musicalState(beforeDraw),
            "draw press changed committed musical state");
    scene.move(drawLeft);
    require(musicalState(scene.notes()) == musicalState(beforeDraw),
            "draw preview leaked into committed musical state");
    scene.expectPreview(scene.expectedBox(144, 30, 102));
    scene.release(drawLeft);
    awaitState([&] { return scene.notes().size() == beforeDraw.size() + 1; },
               "leftward draw did not commit exactly one note");
    const int drawnId = addedNoteId(beforeDraw, scene.notes());
    require(drawnId >= 31, "draw did not publish a new note identity");
    scene.expectPublished(drawnId, 144, 30, 102,
                          "leftward draw span or pointer-following pitch is wrong");
    const QJsonObject drawn = scene.note(drawnId);
    require(drawn.value("track").toInt(-1) == 0 && drawn.value("velocity").toInt(-1) == 100 &&
                !drawn.value("ghost").toBool(true) && drawn.value("selected").toBool(),
            "drawn note did not publish active-track defaults or persistent selection");
    require(!namedItem(scene.surface, QStringLiteral("drawPreview")),
            "draw preview remained after commit");
    auto *borderLayer =
        namedItem(scene.surface, QStringLiteral("timelineQuickPianoNoteBordersAndSelection"));
    require(borderLayer &&
                hasSelectionRing(borderLayer, scene.surface, scene.expectedBox(144, 30, 102)),
            "selected ring is not published after gesture release");
    pass("leftward-preview-commit-and-selection");

    const QJsonArray beforeRightDraw = scene.notes();
    scene.press(scene.point(192, 96));
    scene.move(scene.point(200, 96));
    const QPointF drawRight = scene.point(213, 95);
    scene.move(drawRight);
    require(musicalState(scene.notes()) == musicalState(beforeRightDraw),
            "rightward draw preview changed committed musical state");
    scene.expectPreview(scene.expectedBox(192, 24, 95));
    scene.release(drawRight);
    awaitState([&] { return scene.notes().size() == beforeRightDraw.size() + 1; },
               "rightward draw did not commit exactly one note");
    scene.expectPublished(addedNoteId(beforeRightDraw, scene.notes()), 192, 24, 95,
                          "rightward draw span or pointer-following pitch is wrong");
    pass("rightward-preview-and-commit");

    const QJsonArray beforeMove = scene.notes();
    const QRectF firstBox = scene.expectedBox(0, 18, 60);
    scene.press(firstBox.center());
    const QJsonArray pressedMove = scene.notes();
    scene.move(firstBox.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight));
    require(musicalState(scene.notes()) == musicalState(pressedMove),
            "existing-note move changed committed JSON during preview");
    scene.expectBox(namedItem(scene.surface, QStringLiteral("gridNote_1")),
                    scene.expectedBox(6, 18, 61), "note body did not preview a move");
    scene.release(firstBox.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight));
    scene.expectPublished(1, 6, 18, 61, "note body did not commit source-rounded movement");
    require(beforeMove.size() == scene.notes().size(), "move changed note count");
    pass("body-move-preview-and-commit");

    const double reach = scene.baseFont * 0.25;
    const QRectF resizeBox = scene.expectedBox(24, 18, 64);
    const QPointF outsideRight(resizeBox.right() + reach / 2, resizeBox.center().y());
    scene.press(outsideRight);
    const QJsonArray beforeResizePreview = scene.notes();
    const QPointF longer = outsideRight + QPointF(scene.beatWidth * 6 / 24, 0);
    scene.move(longer);
    require(musicalState(scene.notes()) == musicalState(beforeResizePreview),
            "right-resize preview changed committed JSON");
    scene.expectBox(namedItem(scene.surface, QStringLiteral("gridNote_2")),
                    scene.expectedBox(24, 24, 64), "outside right grip did not resize");
    scene.release(longer);
    scene.expectPublished(2, 24, 24, 64, "right resize did not preserve the start");

    const QRectF leftBox = scene.expectedBox(72, 18, 71);
    const QPointF outsideLeft(leftBox.left() - reach / 2, leftBox.center().y());
    scene.press(outsideLeft);
    const QPointF earlier = outsideLeft - QPointF(scene.beatWidth * 6 / 24, 0);
    scene.move(earlier);
    scene.release(earlier);
    scene.expectPublished(4, 66, 24, 71, "outside left grip did not preserve the end");
    pass("outside-edge-resize-both-sides");

    const QRectF offsetBox = scene.expectedBox(48, 18, 67);
    const QPointF offsetGrip(offsetBox.right() + reach / 2, offsetBox.center().y());
    const QJsonArray beforeDeadband = scene.notes();
    scene.press(offsetGrip);
    scene.move(offsetGrip + QPointF(1, 0));
    require(musicalState(scene.notes()) == musicalState(beforeDeadband),
            "offset resize deadband changed committed JSON");
    scene.expectBox(namedItem(scene.surface, QStringLiteral("gridNote_3")), offsetBox,
                    "offset grip jumped before crossing resize deadband");
    scene.cancel(offsetGrip + QPointF(1, 0));
    scene.expectPublished(3, 48, 18, 67, "cancel after deadband changed fixture note");
    pass("offset-resize-deadband");

    const QRectF cancelBox = scene.expectedBox(96, 18, 74);
    const QJsonArray beforeCancel = scene.notes();
    scene.press(cancelBox.center());
    const QPointF cancelMoved =
        cancelBox.center() + QPointF(scene.beatWidth * 6 / 24, scene.rowHeight);
    scene.move(cancelMoved);
    require(musicalState(scene.notes()) == musicalState(beforeCancel),
            "existing-note cancel setup changed committed JSON");
    scene.expectBox(namedItem(scene.surface, QStringLiteral("gridNote_5")),
                    scene.expectedBox(102, 18, 73), "existing note did not preview before cancel");
    scene.cancel(cancelMoved);
    require(musicalState(scene.notes()) == musicalState(beforeCancel),
            "cancellation did not restore existing musical state");
    scene.expectPublished(5, 96, 18, 74, "cancelled existing delegate did not restore");

    const QPointF cancelDrawStart = scene.point(216, 105);
    const QPointF cancelDrawEnd = scene.point(226, 104);
    scene.press(cancelDrawStart);
    scene.move(cancelDrawEnd);
    require(musicalState(scene.notes()) == musicalState(beforeCancel),
            "cancelled draw preview entered committed JSON");
    scene.expectPreview(scene.expectedBox(216, 12, 104));
    scene.cancel(cancelDrawEnd);
    require(musicalState(scene.notes()) == musicalState(beforeCancel) &&
                !namedItem(scene.surface, QStringLiteral("drawPreview")),
            "cancelled draw did not retract its preview");
    pass("pointer-cancellation");

    const QJsonArray beforeGhost = scene.notes();
    const QPointF ghostPoint = scene.point(13, 48);
    scene.click(ghostPoint);
    require(musicalState(scene.notes()) == musicalState(beforeGhost) &&
                !scene.note(16).value("selected").toBool() &&
                scene.model->property("editCursorTick").toInt() == 12,
            "ghost note was editable instead of acting as empty active-track space");
    pass("ghost-is-not-editable");

    const QJsonArray beforeDouble = scene.notes();
    const QPointF beyondOldCeiling = scene.point(420, 110);
    scene.doubleClick(beyondOldCeiling);
    awaitState([&] { return scene.notes().size() == beforeDouble.size() + 1; },
               "double-click beyond 16 beats did not add one note");
    const int doubleId = addedNoteId(beforeDouble, scene.notes());
    scene.expectPublished(doubleId, 420, 6, 110,
                          "double-click did not add one snap cell beyond old ceiling");
    const QRectF narrow = scene.expectedBox(420, 6, 110);
    const QJsonObject doubled = scene.note(doubleId);
    require(doubled.value("track").toInt(-1) == 0 && !doubled.value("ghost").toBool(true),
            "double-click note was not created on the active track");
    scene.press(narrow.center());
    const QJsonArray narrowPressed = scene.notes();
    const QPointF narrowMoved =
        narrow.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight);
    scene.move(narrowMoved);
    require(musicalState(scene.notes()) == musicalState(narrowPressed),
            "narrow-note move changed committed JSON during preview");
    scene.release(narrowMoved);
    scene.expectPublished(doubleId, 426, 6, 111,
                          "protected narrow-note center resized instead of moving");
    scene.doubleClick(scene.expectedBox(426, 6, 111).center());
    awaitState([&] { return scene.notes().size() == beforeDouble.size(); },
               "double-click on an existing note did not delete it");
    require(scene.note(doubleId).isEmpty(), "deleted double-click note remains published");
    pass("double-click-add-move-delete-without-16-beat-clamp");

    const double oldWidth = scene.viewport->property("contentWidth").toDouble();
    const int extentTick =
        (int((oldWidth - scene.leadPad) / scene.beatWidth * scene.ticksPerBeat) / scene.snap - 2) *
        scene.snap;
    const QString addedBar =
        QString::number(int((oldWidth - scene.leadPad) / scene.beatWidth / 4) + 2);
    const QJsonArray beforeGrowth = scene.notes();
    scene.doubleClick(scene.point(extentTick + 1, 106));
    awaitState(
        [&] {
            auto *label = namedItem(scene.window->contentItem(), "rulerLabel_" + addedBar);
            return scene.viewport->property("contentWidth").toDouble() > oldWidth && label &&
                   label->width() >= label->property("contentWidth").toDouble();
        },
        "extending the song did not publish complete ruler metrics");
    scene.expectPublished(addedNoteId(beforeGrowth, scene.notes()), extentTick, scene.snap, 106,
                          "note creation at the old content edge failed");
    pass("content-growth-and-ruler-metrics");

    const QPointF hoverContent = scene.point(24, 60);
    scene.reveal(hoverContent);
    const QPoint hoverTarget(qRound(scene.model->property("keyboardWidth").toDouble() / 2),
                             scene.windowPoint(hoverContent).y());
    QTest::mouseMove(scene.window, hoverTarget);
    const QPointer<QQuickItem> chip =
        namedItem(scene.window->contentItem(), QStringLiteral("timelineQuickPianoHoverChip"));
    const bool hoverAligned = QTest::qWaitFor(
        [&] {
            return chip && chip->isVisible() &&
                   std::abs(chip->mapToScene(QPointF(0, chip->height() / 2)).y() -
                            hoverTarget.y()) <= 1.0;
        },
        3s);
    if (!hoverAligned) {
        auto *grabber = scene.window->mouseGrabberItem();
        std::fprintf(
            stderr, "hover target=%d chipCenter=%g visible=%d key=%d scroll=%g grabber=%s\n",
            hoverTarget.y(), chip ? chip->mapToScene(QPointF(0, chip->height() / 2)).y() : -1,
            chip && chip->isVisible(), scene.model->property("hoverKey").toInt(),
            scene.viewport->property("contentY").toDouble(),
            grabber ? grabber->metaObject()->className() : "none");
    }
    require(hoverAligned, "scrolled keyboard hover chip is not beside the hovered row");
    pass("scrolled-keyboard-hover-chip");
    verifyGridInteractions(scene.window, scene.model);
    verifyGridUndo(scene.window, scene.model);
    verifyGridCancel(scene.window, scene.model);
    verifyGridEscape(scene.window, scene.model);
    verifyDocumentFeed(scene);

    std::puts("SWIFT_GRID_SMOKE PASS");
    std::fflush(stdout);
    QCoreApplication::exit(EXIT_SUCCESS);
}

void startSmoke()
{
    auto *app = QCoreApplication::instance();
    require(app, "pre-routine ran without application");
    auto *poll = new QTimer(app);
    const auto checkReady = [poll] {
        for (QWindow *candidate : QGuiApplication::allWindows()) {
            auto *window = qobject_cast<QQuickWindow *>(candidate);
            if (!window || !window->isExposed())
                continue;
            auto *surface = namedItem(window->contentItem(), QStringLiteral("pianoGridSurface"));
            auto *viewport = namedItem(window->contentItem(), QStringLiteral("pianoGridViewport"));
            auto *model = window->property("gridModel").value<QObject *>();
            if (!surface || !viewport || !model || viewport->width() <= 0 ||
                model->property("noteSummary").toString().isEmpty() ||
                !namedItem(surface, QStringLiteral("gridNote_1")) ||
                !namedItem(window->contentItem(), QStringLiteral("rulerLabel_1")))
                continue;
            poll->stop();
            poll->deleteLater();
            exercise({window, viewport, surface, model});
            return;
        }
    };
    QObject::connect(poll, &QTimer::timeout, app, checkReady);
    poll->start(25ms);
    QTimer::singleShot(30s, app,
                       [] { fail("30-second wall timeout waiting for scene or gesture result"); });
}

void prepareSmoke()
{
    QTimer::singleShot(0ms, QCoreApplication::instance(), startSmoke);
}
} // namespace

extern "C" void installGridSmoke(void)
{
    if (qEnvironmentVariable("PORYDAW_SWIFT_GRID_SMOKE") != QStringLiteral("1"))
        return;
    qAddPreRoutine(prepareSmoke);
}
