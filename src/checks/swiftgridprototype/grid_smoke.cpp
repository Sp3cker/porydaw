#include "grid_smoke.h"

#include <QColor>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QString>
#include <QTimer>
#include <QVariant>
#include <QtTest/QTest>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>

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

void exercise(Scene scene)
{
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
    const QJsonArray beforeGrowth = scene.notes();
    scene.doubleClick(scene.point(extentTick + 1, 106));
    awaitState(
        [&] {
            return scene.viewport->property("contentWidth").toDouble() > oldWidth &&
                   scene.model->property("metricsReady").toBool();
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
                !model->property("metricsReady").toBool() ||
                !namedItem(surface, QStringLiteral("gridNote_1")))
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
