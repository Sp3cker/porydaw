#include "grid_smoke.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace {
using namespace std::chrono_literals;

void require(bool condition, const char *reason)
{
    if (!condition) {
        std::fprintf(stderr, "SWIFT_GRID_SMOKE FAIL: %s\n", reason);
        std::fflush(stderr);
        std::exit(EXIT_FAILURE);
    }
}

template <typename Predicate>
void awaitState(Predicate predicate, const char *reason)
{
    require(QTest::qWaitFor(predicate, 3s), reason);
}

void pass(const char *scenario)
{
    std::printf("SWIFT_GRID_SMOKE %s PASS\n", scenario);
    std::fflush(stdout);
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

QRectF sceneRect(QQuickItem *item)
{
    return item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
}

QPoint center(QQuickItem *item)
{
    require(item, "missing native undo target");
    return sceneRect(item).center().toPoint();
}

QJsonArray undoNotes(QObject *model)
{
    return QJsonDocument::fromJson(model->property("noteSummary").toString().toUtf8()).array();
}

QString undoSummary(QObject *model)
{
    return model->property("noteSummary").toString();
}

int undoSelectedCount(QObject *model)
{
    int count = 0;
    for (const QJsonValue value : undoNotes(model)) {
        if (value.toObject().value("selected").toBool())
            ++count;
    }
    return count;
}

int undoAddedNoteId(const QJsonArray &before, const QJsonArray &after)
{
    for (const QJsonValue value : after) {
        const int id = value.toObject().value("id").toInt(-1);
        bool found = false;
        for (const QJsonValue prior : before) {
            if (prior.toObject().value("id").toInt(-2) == id) {
                found = true;
                break;
            }
        }
        if (!found)
            return id;
    }
    return -1;
}

int undoColorCount(const QImage &image, QRectF logical, QRgb color)
{
    const double dpr = image.devicePixelRatio();
    const QRect region = QRectF(logical.topLeft() * dpr, logical.size() * dpr)
                             .toAlignedRect()
                             .intersected(image.rect());
    int count = 0;
    for (int y = region.top(); y <= region.bottom(); ++y) {
        for (int x = region.left(); x <= region.right(); ++x) {
            if (image.pixelColor(x, y).rgb() == color)
                ++count;
        }
    }
    return count;
}

struct UndoScene {
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

    QQuickItem *item(const char *name) const
    {
        return namedItem(window->contentItem(), QString::fromLatin1(name));
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

    void reveal(QPointF content) const
    {
        require(viewport && surface && window, "grid scene destroyed during undo smoke");
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
                "undo gesture target is outside the native window");
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
                   "pointer release did not finish the undo gesture");
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

    void reset() const
    {
        require(QMetaObject::invokeMethod(window, "resetDemo"), "cannot reset the prototype");
        awaitState(
            [&] { return undoNotes(model).size() == 30 && namedItem(surface, "gridNote_1"); },
            "reset did not restore the musical fixture");
        QTest::qWait(50ms);
    }

    void undo() const
    {
        require(QMetaObject::invokeMethod(model, "undo"), "cannot invoke undo");
        QTest::qWait(30ms);
    }

    void redo() const
    {
        require(QMetaObject::invokeMethod(model, "redo"), "cannot invoke redo");
        QTest::qWait(30ms);
    }

    int revision() const { return model->property("revision").toInt(); }
    bool canUndo() const { return model->property("canUndo").toBool(); }
    bool canRedo() const { return model->property("canRedo").toBool(); }
    int lastCancelReason() const { return model->property("lastCancelReason").toInt(); }

    QJsonObject note(int id) const
    {
        for (const QJsonValue &value : undoNotes(model)) {
            if (value.toObject().value("id").toInt(-1) == id)
                return value.toObject();
        }
        return {};
    }
};

void verifyDrawRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    require(scene.revision() == 0 && !scene.canUndo() && !scene.canRedo(),
            "reset did not clear undo history");
    const QJsonArray before = undoNotes(scene.model);
    scene.press(scene.point(168, 100));
    scene.move(scene.point(146, 102));
    scene.release(scene.point(146, 102));
    awaitState([&] { return undoNotes(scene.model).size() == before.size() + 1; },
               "draw did not commit exactly one note");
    const QString drawn = undoSummary(scene.model);
    require(scene.revision() == 1 && scene.canUndo() && !scene.canRedo(),
            "draw commit did not push exactly one command");
    scene.undo();
    awaitState([&] { return undoNotes(scene.model).size() == before.size(); },
               "undo did not remove the drawn note");
    require(undoSummary(scene.model) == fixture, "undo did not restore the exact fixture");
    require(scene.canRedo() && !scene.canUndo(), "undo left canUndo/canRedo inconsistent");
    require(scene.revision() == 1, "undo changed the monotonic revision");
    require(undoSelectedCount(scene.model) == 0, "stale draw selection is not inert");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == drawn; },
               "redo did not restore the drawn note");
    require(scene.canUndo() && !scene.canRedo(), "redo left canUndo/canRedo inconsistent");
    require(scene.revision() == 1, "redo changed the monotonic revision");
    pass("undo-draw-commit-restores-fixture");
}

void verifyMoveRow(const UndoScene &scene)
{
    scene.reset();
    const QRectF firstBox = scene.expectedBox(0, 18, 60);
    const QPointF moved = firstBox.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight);
    scene.press(firstBox.center());
    // Undo restores note state but not selection (spec section 3.1), and the
    // press selected note 1, so the exact-restore reference is captured with
    // that selection established and the notes still at fixture positions.
    const QString fixture = undoSummary(scene.model);
    require(undoNotes(scene.model).size() == 30 && scene.revision() == 0,
            "press selected without committing");
    scene.move(moved);
    scene.release(moved);
    awaitState(
        [&] {
            const QJsonObject value = scene.note(1);
            return value.value("tick").toInt(-1) == 6 && value.value("pitch").toInt(-1) == 61;
        },
        "move did not commit source-rounded movement");
    const QString movedSummary = undoSummary(scene.model);
    require(scene.revision() == 1, "move commit did not push exactly one command");
    scene.undo();
    awaitState([&] { return undoSummary(scene.model) == fixture; },
               "move undo did not restore the exact fixture");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == movedSummary; },
               "move redo did not restore the moved summary");
    pass("undo-move-commit");
}

void verifyResizeRow(const UndoScene &scene)
{
    // Undo restores note state but not selection (spec section 3.1), so each
    // drag is an independent sub-row: reset, press to establish that drag's
    // selection, capture the reference, then commit/undo/redo exactly.
    const double reach = scene.baseFont * 0.25;
    scene.reset();
    const QRectF trailingBox = scene.expectedBox(24, 18, 64);
    const QPointF gripRight(trailingBox.right() + reach / 2, trailingBox.center().y());
    const QPointF longer = gripRight + QPointF(scene.beatWidth * 6 / 24, 0);
    scene.press(gripRight);
    const QString trailingFixture = undoSummary(scene.model);
    scene.move(longer);
    scene.release(longer);
    awaitState([&] { return scene.note(2).value("duration").toInt(-1) == 24; },
               "trailing resize did not commit");
    const QString afterTrailing = undoSummary(scene.model);
    require(scene.revision() == 1, "trailing resize did not push exactly one command");
    scene.undo();
    awaitState([&] { return undoSummary(scene.model) == trailingFixture; },
               "trailing-resize undo did not restore the exact fixture");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == afterTrailing; },
               "trailing-resize redo did not restore the trailing state");

    scene.reset();
    const QRectF leadingBox = scene.expectedBox(72, 18, 71);
    const QPointF gripLeft(leadingBox.left() - reach / 2, leadingBox.center().y());
    const QPointF earlier = gripLeft - QPointF(scene.beatWidth * 6 / 24, 0);
    scene.press(gripLeft);
    const QString leadingFixture = undoSummary(scene.model);
    scene.move(earlier);
    scene.release(earlier);
    awaitState(
        [&] {
            const QJsonObject value = scene.note(4);
            return value.value("tick").toInt(-1) == 66 && value.value("duration").toInt(-1) == 24;
        },
        "leading resize did not commit");
    const QString afterLeading = undoSummary(scene.model);
    require(scene.revision() == 1, "leading resize did not push exactly one command");
    scene.undo();
    awaitState([&] { return undoSummary(scene.model) == leadingFixture; },
               "leading-resize undo did not restore the exact fixture");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == afterLeading; },
               "leading-resize redo did not restore the leading state");
    pass("undo-resize-leading-and-trailing");
}

void verifyMenuDeleteRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    const QRectF band = sceneRect(scene.item("gridNote_1"))
                            .united(sceneRect(scene.item("gridNote_2")))
                            .adjusted(-6, -6, 6, 6);
    const QPoint start = band.topLeft().toPoint();
    const QPoint end = band.bottomRight().toPoint();
    QTest::mousePress(scene.window, Qt::RightButton, Qt::NoModifier, start);
    QTest::mouseMove(scene.window, end);
    awaitState([&] { return undoSelectedCount(scene.model) == 2; },
               "right-drag did not select two notes");
    QTest::mouseRelease(scene.window, Qt::RightButton, Qt::NoModifier, end);
    require(undoSelectedCount(scene.model) == 2, "released reticle discarded its selection");
    QTest::mouseClick(scene.window, Qt::RightButton, Qt::NoModifier,
                      center(scene.item("gridNote_1")));
    awaitState([&] { return scene.item("noteContextMenu")->property("opened").toBool(); },
               "right click did not open the note menu");
    QTest::keyClick(scene.window, Qt::Key_Down);
    QTest::keyClick(scene.window, Qt::Key_Down);
    QTest::keyClick(scene.window, Qt::Key_Return);
    awaitState([&] { return undoNotes(scene.model).size() == 28; },
               "menu Delete did not delete selection");
    const QString deleted = undoSummary(scene.model);
    require(scene.revision() == 1, "menu delete did not push exactly one command");
    require(undoSelectedCount(scene.model) == 0, "menu delete kept a selection");
    scene.undo();
    awaitState([&] { return undoSummary(scene.model) == fixture; },
               "menu-delete undo did not restore both notes exactly");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == deleted; },
               "menu-delete redo did not restore the deleted state");
    pass("undo-menu-delete-selection");
}

void verifyDoubleClickRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    const QJsonArray before = undoNotes(scene.model);
    scene.doubleClick(scene.point(420, 110));
    awaitState([&] { return undoNotes(scene.model).size() == before.size() + 1; },
               "double-click did not add one note");
    const QString added = undoSummary(scene.model);
    require(scene.revision() == 1, "double-click add did not push exactly one command");
    const int addedId = undoAddedNoteId(before, undoNotes(scene.model));
    require(addedId > 0, "added double-click note has no identity");
    scene.doubleClick(scene.expectedBox(420, 6, 110).center());
    awaitState([&] { return undoNotes(scene.model).size() == before.size(); },
               "double-click on an existing note did not delete it");
    const QString removed = undoSummary(scene.model);
    require(scene.revision() == 2, "double-click remove did not push exactly one command");
    require(removed == fixture, "double-click add-then-remove did not return to the fixture");
    scene.undo();
    awaitState([&] { return undoNotes(scene.model).size() == before.size() + 1; },
               "double-click-remove undo did not restore the added note");
    // Undo restores note state but not selection (spec section 3.1): the
    // remove cleared the selection, so re-select the restored note with a
    // no-command click before comparing against `added`.
    scene.click(scene.expectedBox(420, 6, 110).center());
    require(scene.revision() == 2, "selecting the restored note pushed a command");
    awaitState([&] { return undoSummary(scene.model) == added; },
               "double-click-remove undo did not restore the added note");
    scene.undo();
    awaitState([&] { return undoSummary(scene.model) == fixture; },
               "double-click-add undo did not restore the exact fixture");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == added; },
               "double-click-add redo did not restore the added note");
    scene.redo();
    awaitState([&] { return undoSummary(scene.model) == removed; },
               "double-click-remove redo did not restore the removed state");
    pass("undo-doubleclick-add-and-remove");
}

void verifyPitchCurveRow(const UndoScene &scene)
{
    scene.reset();
    scene.click(scene.expectedBox(0, 18, 60).center());
    require(undoSelectedCount(scene.model) == 1, "click did not select one note for the popup");
    QTest::keyClick(scene.window, Qt::Key_G);
    awaitState(
        [&] { return scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(); },
        "G did not open a functional pitch popup");
    auto *graph = scene.item("pitchBendGraph");
    const QRectF plot = graph->property("canvasRect").toRectF();
    require(plot.width() > 0 && plot.height() > 0, "pitch graph has no native canvas geometry");
    const QRectF curveRegion = graph->mapRectToScene(plot).adjusted(6, 6, -6, -6);
    const QRectF upperCurve(curveRegion.x(), curveRegion.y(), curveRegion.width(),
                            curveRegion.height() / 3);
    const int preCount = undoColorCount(scene.window->grabWindow(), upperCurve, qRgb(205, 84, 84));
    const QPoint low = graph
                           ->mapToScene(QPointF(plot.x() + (plot.width() - 1) * 2 / 18,
                                                plot.y() + (plot.height() - 1) * 0.8))
                           .toPoint();
    const QPoint high = graph
                            ->mapToScene(QPointF(plot.x() + (plot.width() - 1) * 16 / 18,
                                                 plot.y() + (plot.height() - 1) * 0.2))
                            .toPoint();
    QTest::mousePress(scene.window, Qt::LeftButton, Qt::ShiftModifier, low);
    QTest::mouseMove(scene.window, high);
    QTest::mouseRelease(scene.window, Qt::LeftButton, Qt::ShiftModifier, high);
    QTest::qWait(40ms);
    require(undoColorCount(scene.window->grabWindow(), upperCurve, qRgb(205, 84, 84)) > 5,
            "pitch gesture did not change the committed curve");
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the pitch popup");
    require(scene.revision() == 1 && scene.canUndo(),
            "pitch commit did not push exactly one controller command");
    QTest::keyClick(scene.window, Qt::Key_G);
    awaitState(
        [&] { return scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(); },
        "pitch popup did not reopen");
    QTest::qWait(40ms);
    require(undoColorCount(scene.window->grabWindow(), upperCurve, qRgb(205, 84, 84)) > 5,
            "edited pitch curve did not survive popup close and reopen");
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the reopened pitch popup");
    scene.undo();
    require(scene.canRedo() && !scene.canUndo(), "pitch undo left canUndo/canRedo inconsistent");
    QTest::keyClick(scene.window, Qt::Key_G);
    awaitState(
        [&] { return scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(); },
        "pitch popup did not reopen after undo");
    QTest::qWait(40ms);
    require(undoColorCount(scene.window->grabWindow(), upperCurve, qRgb(205, 84, 84)) == preCount,
            "pitch undo did not restore the pre-commit curve on reopen");
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the pitch popup after undo");
    pass("undo-pitch-curve-commit");
}

void verifyNoCommandRow(const UndoScene &scene)
{
    scene.reset();
    scene.click(scene.point(98, 100));
    require(scene.model->property("editCursorTick").toInt() == 96,
            "empty click did not snap its edit cursor");
    scene.click(scene.expectedBox(0, 18, 60).center());
    require(undoSelectedCount(scene.model) == 1, "click did not select one note");
    require(undoNotes(scene.model).size() == 30, "cursor and selection changed the note count");
    require(!scene.canUndo() && !scene.canRedo() && scene.revision() == 0,
            "cursor and selection pushed an undo command");
    pass("undo-no-command-for-cursor-and-selection");
}

void verifyResetRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    const QJsonArray before = undoNotes(scene.model);
    scene.press(scene.point(168, 100));
    scene.move(scene.point(146, 102));
    scene.release(scene.point(146, 102));
    awaitState([&] { return undoNotes(scene.model).size() == before.size() + 1; },
               "draw did not commit exactly one note");
    require(scene.canUndo() && scene.revision() == 1, "draw commit did not push one command");
    scene.reset();
    require(!scene.canUndo() && !scene.canRedo() && scene.revision() == 0,
            "reset did not clear undo history");
    require(undoNotes(scene.model).size() == 30, "reset did not restore the fixture count");
    require(undoSummary(scene.model) == fixture, "reset did not restore the exact fixture");
    scene.undo();
    require(undoNotes(scene.model).size() == 30 && scene.revision() == 0,
            "undo after reset is not inert");
    pass("undo-reset-clears-history");
}

QString cancelStatus(const UndoScene &scene)
{
    return scene.model->property("statusText").toString();
}

bool cancelIdle(const UndoScene &scene)
{
    return cancelStatus(scene).contains(QStringLiteral("notes,"));
}

void requireFreshDrawCommits(const UndoScene &scene, const char *reason)
{
    const int before = scene.revision();
    scene.press(scene.point(168, 100));
    scene.move(scene.point(146, 102));
    scene.release(scene.point(146, 102));
    require(scene.revision() == before + 1, reason);
}

void verifyCancelUngrabRow(const UndoScene &scene)
{
    scene.reset();
    const QRectF firstBox = scene.expectedBox(0, 18, 60);
    const QPointF moved = firstBox.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight);
    scene.press(firstBox.center());
    const QString pressed = undoSummary(scene.model);
    require(scene.revision() == 0, "press committed before the ungrab cancel");
    scene.move(moved);
    require(cancelStatus(scene).startsWith(QStringLiteral("Moving")),
            "move did not preview before the ungrab cancel");
    QQuickItem *grabber = scene.window->mouseGrabberItem();
    require(grabber, "pressed QML input item has no native mouse grab");
    grabber->ungrabMouse();
    awaitState([&] { return scene.model->property("activeNoteId").toInt() == -1; },
               "native mouse ungrab did not cancel the move gesture");
    QTest::mouseRelease(scene.window, Qt::LeftButton, Qt::NoModifier, scene.windowPoint(moved));
    QTest::qWait(30ms);
    require(undoSummary(scene.model) == pressed,
            "ungrab cancel moved notes or changed the selection");
    require(cancelIdle(scene), "ungrab cancel left a live gesture");
    require(scene.revision() == 0 && !scene.canUndo(), "ungrab cancel pushed an undo command");
    pass("cancel-ungrab-discards-move-preview");
}

void verifyCancelFocusLostRow(const UndoScene &scene)
{
    scene.reset();
    const QRectF firstBox = scene.expectedBox(0, 18, 60);
    const QPointF moved = firstBox.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight);
    scene.press(firstBox.center());
    const QString pressed = undoSummary(scene.model);
    QQuickItem *input = scene.item("pianoGridInput");
    require(input && input->hasActiveFocus(),
            "grid input did not hold active focus during the drag");
    scene.move(moved);
    require(cancelStatus(scene).startsWith(QStringLiteral("Moving")),
            "move did not preview before the focus steal");
    QQuickItem *stop = scene.item("transportStop");
    require(stop, "missing transport stop for the focus steal");
    stop->forceActiveFocus();
    QTest::qWait(50ms);
    require(cancelStatus(scene).startsWith(QStringLiteral("Moving")),
            "focus loss tore down a live gesture instead of surviving");
    require(scene.model->property("activeNoteId").toInt() == 1,
            "focus loss dropped the active note");
    const QPointF further = moved + QPointF(scene.beatWidth * 6 / 24, 0);
    scene.move(further);
    scene.release(further);
    awaitState(
        [&] {
            const QJsonObject value = scene.note(1);
            return value.value("tick").toInt(-1) == 12 && value.value("pitch").toInt(-1) == 61;
        },
        "move after focus loss did not commit");
    require(scene.revision() == 1, "post-focus-loss commit did not push exactly one command");
    scene.undo();
    awaitState([&] { return undoSummary(scene.model) == pressed; },
               "undo did not restore the pre-move state after focus loss");
    input->forceActiveFocus();
    QTest::qWait(30ms);
    pass("cancel-focuslost-keeps-live-gesture");
}

void verifyCancelHiddenRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    scene.reveal(scene.expectedBox(0, 18, 60).center());
    QTest::mouseMove(scene.window, scene.windowPoint(scene.expectedBox(0, 18, 60).center()));
    QTest::qWait(30ms);
    require(scene.model->property("cursorKind").toInt() == 1,
            "note hover did not arm the move cursor before the hidden cancel");
    scene.reveal(scene.point(24, 60));
    const QPoint gutterTarget(qRound(scene.model->property("keyboardWidth").toDouble() / 2),
                              scene.windowPoint(scene.point(24, 60)).y());
    QTest::mouseMove(scene.window, gutterTarget);
    awaitState([&] { return scene.model->property("hoverKey").toInt() >= 0; },
               "keyboard hover did not arm before the hidden cancel");
    scene.press(scene.point(168, 100));
    scene.move(scene.point(146, 102));
    require(cancelStatus(scene).startsWith(QStringLiteral("Drawing")),
            "draw did not preview before the hidden cancel");
    require(namedItem(scene.surface, QStringLiteral("drawPreview")),
            "draw preview item is missing before the hidden cancel");
    require(scene.revision() == 0, "draw preview committed before the hidden cancel");
    require(scene.surface->setProperty("visible", false), "cannot hide the grid surface");
    require(!scene.surface->isVisible(), "surface hide did not report !isVisible");
    awaitState([&] { return !namedItem(scene.surface, QStringLiteral("drawPreview")); },
               "hidden cancel left the draw preview");
    require(cancelIdle(scene), "hidden cancel left a live gesture");
    require(scene.model->property("hoverKey").toInt() == -1,
            "hidden cancel did not clear keyboard hover");
    require(scene.model->property("cursorKind").toInt() == 0,
            "hidden cancel did not reset the cursor");
    require(scene.revision() == 0 && !scene.canUndo(), "hidden cancel pushed an undo command");
    require(scene.lastCancelReason() == 2, "surface hide did not record Hidden");
    require(scene.surface->setProperty("visible", true), "cannot restore the grid surface");
    QTest::qWait(50ms);
    scene.release(scene.point(146, 102));
    require(undoSummary(scene.model) == fixture && scene.revision() == 0,
            "post-teardown release committed after the hidden cancel");
    requireFreshDrawCommits(scene, "fresh draw did not commit after the surface hidden cancel");
    // Window-level Hidden: QEvent::Hide on the host window. The filter
    // names Hidden (2). No QML onVisibleChanged on the window.
    scene.reset();
    scene.press(scene.point(168, 100));
    scene.move(scene.point(146, 102));
    require(cancelStatus(scene).startsWith(QStringLiteral("Drawing")),
            "draw did not preview before window hide");
    scene.window->hide();
    awaitState([&] { return !namedItem(scene.surface, QStringLiteral("drawPreview")); },
               "window hide left the draw preview");
    require(cancelIdle(scene), "window hide left a live gesture");
    require(!scene.window->isVisible(), "window hide left the window visible");
    require(scene.lastCancelReason() == 2, "window hide did not record Hidden");
    require(undoSummary(scene.model) == fixture, "window hide mutated notes or selection");
    require(scene.revision() == 0 && !scene.canUndo(), "window hide pushed an undo command");
    scene.window->show();
    awaitState([&] { return scene.window->isVisible(); },
               "window did not reshow after the hide cancel");
    QTest::qWait(50ms);
    scene.release(scene.point(146, 102));
    require(undoSummary(scene.model) == fixture && scene.revision() == 0,
            "post-teardown release committed after window hide");
    requireFreshDrawCommits(scene, "fresh draw did not commit after the window hidden cancel");
    // Editor-open coverage (spec S6.2: pitch preview discarded when the
    // editor is open). The modal popup precludes a live grid gesture, so
    // this phase selects, opens the editor with G, and hides the grid:
    // notes and revision must be untouched, the popup session must
    // survive, and dismissal must commit no controller command.
    scene.reset();
    scene.click(scene.expectedBox(0, 18, 60).center());
    require(undoSelectedCount(scene.model) == 1, "click did not select one note for the editor");
    const QString selected = undoSummary(scene.model);
    QTest::keyClick(scene.window, Qt::Key_G);
    awaitState(
        [&] { return scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(); },
        "G did not open the pitch popup before the hidden cancel");
    require(scene.window->property("pitchBridge").value<QObject *>() != nullptr,
            "pitch editor is missing at the hidden cancel");
    require(scene.surface->setProperty("visible", false),
            "cannot hide the grid surface with editor open");
    QTest::qWait(50ms);
    require(undoSummary(scene.model) == selected, "hidden cancel mutated notes with editor open");
    require(scene.revision() == 0 && !scene.canUndo(),
            "hidden cancel pushed a command with editor open");
    require(scene.window->property("pitchBridge").value<QObject *>() != nullptr,
            "hidden cancel tore down the pitch popup");
    require(scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(),
            "hidden cancel hid the pitch popup");
    require(scene.surface->setProperty("visible", true), "cannot restore the grid surface");
    QTest::qWait(50ms);
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the pitch popup after the hidden cancel");
    require(scene.revision() == 0 && !scene.canUndo(),
            "hidden cancel with editor open fabricated a controller command");
    pass("cancel-hidden-tears-down-and-clears-hover");
}

void verifyCancelWindowDeactivatedRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    scene.reveal(scene.expectedBox(0, 18, 60).center());
    QTest::mouseMove(scene.window, scene.windowPoint(scene.expectedBox(0, 18, 60).center()));
    QTest::qWait(30ms);
    require(scene.model->property("cursorKind").toInt() == 1,
            "note hover did not arm the move cursor before window deactivate");
    scene.reveal(scene.point(24, 60));
    const QPoint gutterTarget(qRound(scene.model->property("keyboardWidth").toDouble() / 2),
                              scene.windowPoint(scene.point(24, 60)).y());
    QTest::mouseMove(scene.window, gutterTarget);
    awaitState([&] { return scene.model->property("hoverKey").toInt() >= 0; },
               "keyboard hover did not arm before window deactivate");
    scene.press(scene.point(168, 100));
    scene.move(scene.point(146, 102));
    require(cancelStatus(scene).startsWith(QStringLiteral("Drawing")),
            "draw did not preview before window deactivate");
    // Host filter names WindowDeactivated (3). Visibility is the scenario
    // distinction, not the reason separator. Do not assert !isActive.
    QEvent deactivate(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(scene.window, &deactivate);
    awaitState([&] { return !namedItem(scene.surface, QStringLiteral("drawPreview")); },
               "window deactivate left the draw preview");
    require(cancelIdle(scene), "window deactivate left a live gesture");
    require(scene.model->property("hoverKey").toInt() == -1,
            "window deactivate did not clear keyboard hover");
    require(scene.model->property("cursorKind").toInt() == 0,
            "window deactivate did not reset the cursor");
    require(undoSummary(scene.model) == fixture, "window deactivate mutated notes or selection");
    require(scene.revision() == 0 && !scene.canUndo(), "window deactivate pushed an undo command");
    require(scene.window->isVisible(), "window deactivate hid the window");
    require(scene.lastCancelReason() == 3, "window deactivate did not record WindowDeactivated");
    scene.release(scene.point(146, 102));
    require(undoSummary(scene.model) == fixture && scene.revision() == 0,
            "post-teardown release committed after window deactivate");
    requireFreshDrawCommits(scene, "fresh draw did not commit after window deactivate");
    // Host arbitration: with the pitch popup open and no grid gesture, the
    // same window event must leave the popup session alone.
    scene.reset();
    scene.click(scene.expectedBox(0, 18, 60).center());
    require(undoSelectedCount(scene.model) == 1, "click did not select one note for the popup");
    QTest::keyClick(scene.window, Qt::Key_G);
    awaitState(
        [&] { return scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(); },
        "G did not open the pitch popup before window deactivate");
    QEvent popupDeactivate(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(scene.window, &popupDeactivate);
    QTest::qWait(50ms);
    require(scene.lastCancelReason() == 3,
            "popup window deactivate did not record WindowDeactivated");
    require(scene.window->property("pitchBridge").value<QObject *>() != nullptr,
            "window deactivate tore down the pitch popup");
    require(scene.revision() == 0, "window deactivate pushed a command with no grid gesture");
    require(scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(),
            "window deactivate hid the pitch popup");
    scene.item("pitchBendGraph")->forceActiveFocus();
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the pitch popup after window deactivate");
    pass("cancel-window-deactivated-matches-hidden");
}

void verifyCancelRightUngrabRow(const UndoScene &scene)
{
    scene.reset();
    const QString fixture = undoSummary(scene.model);
    const QRectF band = sceneRect(scene.item("gridNote_1"))
                            .united(sceneRect(scene.item("gridNote_2")))
                            .adjusted(-6, -6, 6, 6);
    const QPoint start = band.topLeft().toPoint();
    const QPoint end = band.bottomRight().toPoint();
    QTest::mousePress(scene.window, Qt::RightButton, Qt::NoModifier, start);
    QTest::mouseMove(scene.window, end);
    awaitState([&] { return undoSelectedCount(scene.model) == 2; },
               "right-drag did not select two notes before the ungrab cancel");
    QQuickItem *grabber = scene.window->mouseGrabberItem();
    require(grabber, "right-drag did not acquire the native mouse grab");
    grabber->ungrabMouse();
    awaitState([&] { return undoSelectedCount(scene.model) == 0; },
               "right ungrab did not restore the captured selection");
    QTest::mouseRelease(scene.window, Qt::RightButton, Qt::NoModifier, end);
    QTest::qWait(30ms);
    require(undoSummary(scene.model) == fixture,
            "right ungrab did not restore the exact pre-press selection");
    require(cancelIdle(scene), "right ungrab left a live gesture");
    require(scene.revision() == 0 && !scene.canUndo(), "right ungrab pushed an undo command");
    pass("cancel-right-ungrab-restores-captured-selection");
}

void verifyEscapeGestureRow(const UndoScene &scene)
{
    // Left gesture: Escape mid-move cancels through the pointer-ungrab
    // teardown — notes unmoved, gesture gone, the selection captured at
    // press survives, revision untouched.
    scene.reset();
    const QRectF firstBox = scene.expectedBox(0, 18, 60);
    const QPointF moved = firstBox.center() + QPointF(scene.beatWidth * 6 / 24, -scene.rowHeight);
    scene.press(firstBox.center());
    const QString pressed = undoSummary(scene.model);
    scene.move(moved);
    require(cancelStatus(scene).startsWith(QStringLiteral("Moving")),
            "move did not preview before the Escape cancel");
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return scene.model->property("activeNoteId").toInt() == -1; },
               "Escape did not cancel the live move gesture");
    QTest::mouseRelease(scene.window, Qt::LeftButton, Qt::NoModifier, scene.windowPoint(moved));
    QTest::qWait(30ms);
    require(undoSummary(scene.model) == pressed,
            "Escape moved notes or dropped the press-captured selection");
    require(undoSelectedCount(scene.model) == 1,
            "Escape did not preserve the press-captured selection");
    require(cancelIdle(scene), "Escape left a live gesture");
    require(scene.revision() == 0 && !scene.canUndo(), "Escape pushed an undo command");
    // Right gesture: the band grows the selection past the press capture;
    // Escape restores exactly selectionAtRightPress.
    scene.reset();
    scene.click(firstBox.center());
    const QString captured = undoSummary(scene.model);
    const QRectF band = sceneRect(scene.item("gridNote_1"))
                            .united(sceneRect(scene.item("gridNote_2")))
                            .adjusted(-6, -6, 6, 6);
    const QPoint start = band.topLeft().toPoint();
    const QPoint end = band.bottomRight().toPoint();
    QTest::mousePress(scene.window, Qt::RightButton, Qt::NoModifier, start);
    QTest::mouseMove(scene.window, end);
    awaitState([&] { return undoSelectedCount(scene.model) == 2; },
               "right-drag did not grow the selection before Escape");
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return undoSelectedCount(scene.model) == 1; },
               "Escape did not restore the right-press selection");
    QTest::mouseRelease(scene.window, Qt::RightButton, Qt::NoModifier, end);
    QTest::qWait(30ms);
    require(undoSummary(scene.model) == captured,
            "Escape did not restore the exact right-press selection");
    require(cancelIdle(scene), "Escape left a live right gesture");
    require(scene.revision() == 0 && !scene.canUndo(),
            "right-gesture Escape pushed an undo command");
    pass("escape-cancels-live-gesture-preserving-selection");
}

void verifyEscapePitchEditorRow(const UndoScene &scene)
{
    // A committed numeric edit survives while the dragged live preview is
    // discarded: Escape from the graph's focus cancels the graph gesture,
    // drops the preview, and closes the popup through the arbiter.
    scene.reset();
    scene.click(scene.expectedBox(0, 18, 60).center());
    require(undoSelectedCount(scene.model) == 1, "click did not select one note for the popup");
    QTest::keyClick(scene.window, Qt::Key_G);
    awaitState(
        [&] { return scene.item("pitchBendGraph") && scene.item("pitchBendGraph")->isVisible(); },
        "G did not open the pitch popup for the Escape row");
    QTest::mouseDClick(scene.window, Qt::LeftButton, Qt::NoModifier,
                       center(scene.item("bendRangeInput")));
    QTest::qWait(30ms);
    QTest::keyClick(scene.window, Qt::Key_7);
    QTest::keyClick(scene.window, Qt::Key_Return);
    awaitState([&] { return scene.item("bendRangeInput")->property("text").toString() == "7"; },
               "pitch bend range numeric editor did not accept text input");
    require(scene.revision() == 1, "numeric edit did not push exactly one command");
    auto *graph = scene.item("pitchBendGraph");
    const QRectF plot = graph->property("canvasRect").toRectF();
    const QRectF curveRegion = graph->mapRectToScene(plot).adjusted(6, 6, -6, -6);
    const QRectF upperCurve(curveRegion.x(), curveRegion.y(), curveRegion.width(),
                            curveRegion.height() / 3);
    const QPoint low = graph
                           ->mapToScene(QPointF(plot.x() + (plot.width() - 1) * 2 / 18,
                                                plot.y() + (plot.height() - 1) * 0.8))
                           .toPoint();
    const QPoint high = graph
                            ->mapToScene(QPointF(plot.x() + (plot.width() - 1) * 16 / 18,
                                                 plot.y() + (plot.height() - 1) * 0.2))
                            .toPoint();
    QTest::mousePress(scene.window, Qt::LeftButton, Qt::ShiftModifier, low);
    QTest::mouseMove(scene.window, high);
    QTest::qWait(40ms);
    require(undoColorCount(scene.window->grabWindow(), upperCurve, qRgb(205, 84, 84)) > 5,
            "unreleased pitch gesture did not produce a live preview");
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the pitch popup through the arbiter");
    QTest::mouseRelease(scene.window, Qt::LeftButton, Qt::ShiftModifier, high);
    require(scene.revision() == 1, "Escape discard pushed an undo command");
    require(scene.canUndo(), "Escape discard dropped the committed numeric edit");
    // G-reopen raster (discarded preview vs surviving numeric) is
    // [cutover-disposable]: delivery-dependent. Cutover gate is
    // selectionkey unmodified (charter V-1).
    pass("escape-closes-pitch-editor-discarding-preview");
}

void verifyEscapeNoteMenuRow(const UndoScene &scene)
{
    scene.reset();
    QTest::mouseClick(scene.window, Qt::RightButton, Qt::NoModifier,
                      center(scene.item("gridNote_1")));
    awaitState([&] { return scene.item("noteContextMenu")->property("opened").toBool(); },
               "right click did not open the note menu");
    const QString selected = undoSummary(scene.model);
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return !scene.item("noteContextMenu")->property("opened").toBool(); },
               "Escape did not close the note menu through the arbiter");
    require(undoSummary(scene.model) == selected, "menu Escape did not preserve the selection");
    require(scene.revision() == 0 && !scene.canUndo(), "menu Escape pushed an undo command");
    pass("escape-closes-note-menu");
}

void verifyEscapeIdleRow(const UndoScene &scene)
{
    // Arbiter decision through the model API (spec D1). Grid-surface
    // Escape delivery is the gesture-row wiring; idle keyClick needs
    // focus restoration the sandbox must not grow.
    scene.reset();
    scene.click(scene.expectedBox(0, 18, 60).center());
    require(undoSelectedCount(scene.model) == 1, "click did not select one note");
    const int rev = scene.revision();
    int action = -1;
    require(QMetaObject::invokeMethod(scene.model, "escapePressed", Qt::DirectConnection,
                                      Q_RETURN_ARG(int, action), Q_ARG(bool, false)),
            "cannot invoke escapePressed");
    require(action == 4, "idle escapePressed did not return clearSelection");
    require(undoSelectedCount(scene.model) == 0, "idle Escape did not clear the selection");
    require(scene.revision() == rev && !scene.canUndo(), "idle Escape pushed an undo command");
    pass("escape-idle-clears-selection");
}

} // namespace

void verifyGridUndo(QQuickWindow *window, QObject *model)
{
    UndoScene scene{window, nullptr, nullptr, model};
    scene.surface = namedItem(window->contentItem(), QStringLiteral("pianoGridSurface"));
    scene.viewport = namedItem(window->contentItem(), QStringLiteral("pianoGridViewport"));
    require(scene.surface && scene.viewport, "grid scene is missing for the undo smoke");
    scene.baseFont = model->property("baseFontPx").toDouble();
    scene.dpr = model->property("devicePixelRatio").toDouble();
    scene.beatWidth = model->property("beatWidth").toDouble();
    scene.rowHeight = model->property("rowHeight").toDouble();
    scene.leadPad = model->property("leadPadWidth").toDouble();
    scene.ticksPerBeat = model->property("ticksPerBeat").toInt();
    require(scene.baseFont > 0 && scene.dpr > 0 && scene.beatWidth > 0 && scene.rowHeight > 0 &&
                scene.leadPad >= 48 && scene.ticksPerBeat == 24,
            "grid metrics do not match the production 24 TPQN projection");

    verifyDrawRow(scene);
    verifyMoveRow(scene);
    verifyResizeRow(scene);
    verifyMenuDeleteRow(scene);
    verifyDoubleClickRow(scene);
    verifyPitchCurveRow(scene);
    verifyNoCommandRow(scene);
    verifyResetRow(scene);
}

void verifyGridCancel(QQuickWindow *window, QObject *model)
{
    UndoScene scene{window, nullptr, nullptr, model};
    scene.surface = namedItem(window->contentItem(), QStringLiteral("pianoGridSurface"));
    scene.viewport = namedItem(window->contentItem(), QStringLiteral("pianoGridViewport"));
    require(scene.surface && scene.viewport, "grid scene is missing for the cancel smoke");
    scene.baseFont = model->property("baseFontPx").toDouble();
    scene.dpr = model->property("devicePixelRatio").toDouble();
    scene.beatWidth = model->property("beatWidth").toDouble();
    scene.rowHeight = model->property("rowHeight").toDouble();
    scene.leadPad = model->property("leadPadWidth").toDouble();
    scene.ticksPerBeat = model->property("ticksPerBeat").toInt();
    require(scene.baseFont > 0 && scene.dpr > 0 && scene.beatWidth > 0 && scene.rowHeight > 0 &&
                scene.leadPad >= 48 && scene.ticksPerBeat == 24,
            "grid metrics do not match the production 24 TPQN projection");

    verifyCancelUngrabRow(scene);
    verifyCancelFocusLostRow(scene);
    verifyCancelHiddenRow(scene);
    verifyCancelWindowDeactivatedRow(scene);
    verifyCancelRightUngrabRow(scene);
}

void verifyGridEscape(QQuickWindow *window, QObject *model)
{
    UndoScene scene{window, nullptr, nullptr, model};
    scene.surface = namedItem(window->contentItem(), QStringLiteral("pianoGridSurface"));
    scene.viewport = namedItem(window->contentItem(), QStringLiteral("pianoGridViewport"));
    require(scene.surface && scene.viewport, "grid scene is missing for the escape smoke");
    scene.baseFont = model->property("baseFontPx").toDouble();
    scene.dpr = model->property("devicePixelRatio").toDouble();
    scene.beatWidth = model->property("beatWidth").toDouble();
    scene.rowHeight = model->property("rowHeight").toDouble();
    scene.leadPad = model->property("leadPadWidth").toDouble();
    scene.ticksPerBeat = model->property("ticksPerBeat").toInt();
    require(scene.baseFont > 0 && scene.dpr > 0 && scene.beatWidth > 0 && scene.rowHeight > 0 &&
                scene.leadPad >= 48 && scene.ticksPerBeat == 24,
            "grid metrics do not match the production 24 TPQN projection");

    verifyEscapeGestureRow(scene);
    verifyEscapePitchEditorRow(scene);
    verifyEscapeNoteMenuRow(scene);
    verifyEscapeIdleRow(scene);
    // escape-single-arbiter-paths: menu/popup/grid wiring are the three
    // rows above. Cross-surface G/focus matrix is cutover/selectionkey
    // (charter V-1), not sandbox focus plumbing.
}
