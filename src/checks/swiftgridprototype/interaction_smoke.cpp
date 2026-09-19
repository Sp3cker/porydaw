#include "curve_session.h"
#include "grid_smoke.h"

#include <QCoreApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>

#include <algorithm>
#include <array>
#include <chrono>
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

bool hasTruncatedText(QQuickItem *parent)
{
    if (parent->property("truncated").toBool())
        return true;
    for (QQuickItem *child : parent->childItems()) {
        if (hasTruncatedText(child))
            return true;
    }
    return false;
}

QRectF sceneRect(QQuickItem *item)
{
    return item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
}

QPoint center(QQuickItem *item)
{
    require(item, "missing native interaction target");
    return sceneRect(item).center().toPoint();
}

QJsonArray notes(QObject *model)
{
    return QJsonDocument::fromJson(model->property("noteSummary").toString().toUtf8()).array();
}

int selectedCount(QObject *model)
{
    int count = 0;
    for (const QJsonValue value : notes(model)) {
        if (value.toObject().value("selected").toBool())
            ++count;
    }
    return count;
}

int colorCount(const QImage &image, QRectF logical, QRgb color)
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

void verifyCurveExport()
{
    constexpr std::array<SGCurveValue, 6> input{
        {{0, 0}, {6, 0}, {13, 0}, {14, 4096}, {18, 4096}, {24, 0}}};
    constexpr std::array<SGCurveValue, 4> expected{{{0, 0}, {13, 0}, {14, 4096}, {24, 0}}};
    auto *session = sgc_create(0, 0, 24, input.data(), input.size(), 0, {0, 0, 481, 129, 1, 2});
    std::array<SGCurveValue, input.size()> output;
    auto requireCanonical = [&] {
        const size_t count = sgc_copy_curve_points(session, output.data());
        require(count == expected.size(),
                "canonical curve export kept redundant plateaus or removed fine samples");
        for (size_t i = 0; i < count; ++i)
            require(output[i].tick == expected[i].tick && output[i].value == expected[i].value,
                    "canonical curve export changed an endpoint or fine interpolation anchor");
    };
    requireCanonical();
    pass("canonical-curve-export-preserves-fine-samples");
    sgc_press(session, sgc_x_at_tick(session, 13), sgc_y_at_value(session, 0), 0);
    sgc_move(session, sgc_x_at_tick(session, 16), sgc_y_at_value(session, 8191), 1);
    const size_t movedCount = sgc_copy_curve_points(session, output.data());
    require(std::any_of(
                output.begin(), output.begin() + movedCount,
                [](const SGCurveValue &point) { return point.tick == 16 && point.value == 8191; }),
            "vertex drag did not preview the moved controller event");
    sgc_cancel(session);
    requireCanonical();
    pass("cancelled-vertex-drag-restores-controller-curve");
    const SGCurveState beforeStroke = sgc_state(session);
    sgc_press(session, sgc_x_at_tick(session, 8), sgc_y_at_value(session, 0), 0);
    require(sgc_state(session).has_gesture && sgc_state(session).selected_tick == -1,
            "stroke press did not open a selection-free curve gesture");
    sgc_move(session, sgc_x_at_tick(session, 10), sgc_y_at_value(session, 8191), 0);
    require(sgc_state(session).live_value == 8191,
            "stroke move did not preview the live controller value");
    sgc_cancel(session);
    require(sgc_state(session).keyboard_tick == beforeStroke.keyboard_tick &&
                sgc_state(session).live_value == beforeStroke.live_value,
            "cancelled stroke did not restore the keyboard cursor and live value");
    requireCanonical();
    sgc_destroy(session);
    pass("cancelled-stroke-restores-cursor-and-curve");
}
} // namespace

void verifyGridInteractions(QQuickWindow *window, QObject *model)
{
    verifyCurveExport();
    auto item = [window](const char *name) {
        return namedItem(window->contentItem(), QString::fromLatin1(name));
    };
    auto reset = [&] {
        require(QMetaObject::invokeMethod(window, "resetDemo"), "cannot reset the prototype");
        awaitState([&] { return notes(model).size() == 30 && item("gridNote_1"); },
                   "reset did not restore the musical fixture");
        QTest::qWait(50ms);
    };
    auto click = [&](const char *name) {
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center(item(name)));
        QTest::qWait(30ms);
    };

    reset();

    const QRectF band =
        sceneRect(item("gridNote_1")).united(sceneRect(item("gridNote_2"))).adjusted(-6, -6, 6, 6);
    const QPoint start = band.topLeft().toPoint();
    const QPoint end = band.bottomRight().toPoint();
    auto beginBand = [&] {
        QTest::mousePress(window, Qt::RightButton, Qt::NoModifier, start);
        QTest::mouseMove(window, end);
        awaitState([&] { return selectedCount(model) == 2; },
                   "right-drag did not select intersecting editable notes live");
    };
    beginBand();
    QTest::qWait(30ms);
    require(colorCount(window->grabWindow(), band.adjusted(-2, -2, 2, 2), qRgb(0, 202, 219)) > 8,
            "right-drag reticle does not render the production cyan dash frame");
    auto *grabber = window->mouseGrabberItem();
    require(grabber, "right-drag did not acquire the native mouse grab");
    grabber->ungrabMouse();
    QTest::mouseRelease(window, Qt::RightButton, Qt::NoModifier, end);
    awaitState([&] { return selectedCount(model) == 0; },
               "cancelled reticle did not restore the previous selection");
    beginBand();
    QTest::mouseRelease(window, Qt::RightButton, Qt::NoModifier, end);
    require(selectedCount(model) == 2, "released reticle discarded its selection");
    pass("right-reticle-raster-live-selection-and-cancel");

    QTest::mouseClick(window, Qt::RightButton, Qt::NoModifier, center(item("gridNote_1")));
    awaitState([&] { return item("noteContextMenu")->property("opened").toBool(); },
               "right click did not open the note menu");
    require(selectedCount(model) == 2, "note menu destroyed an existing multi-selection");
    QTest::qWait(30ms);
    require(!hasTruncatedText(item("noteContextMenu")),
            "note menu clips an action or shortcut label");
    QTest::keyClick(window, Qt::Key_Down);
    QTest::keyClick(window, Qt::Key_Down);
    QTest::keyClick(window, Qt::Key_Return);
    awaitState([&] { return notes(model).size() == 28; }, "menu Delete did not delete selection");
    for (const QJsonValue value : notes(model)) {
        const int id = value.toObject().value("id").toInt();
        require(id != 1 && id != 2, "menu Delete removed the wrong notes");
    }
    pass("note-menu-keyboard-delete-preserves-target-selection");

    reset();
    click("transportPlayPause");
    auto *audio = window->property("audio").value<QObject *>();
    require(audio, "missing audio session");
    awaitState(
        [&] {
            return audio->property("playing").toBool() &&
                   audio->property("playheadTick").toDouble() > 0;
        },
        "Play did not advance the real poryaaaa transport");
    require(item("gridPlayhead")->isVisible() && item("rulerPlayheadTriangle")->isVisible(),
            "playing transport has no grid and ruler playheads");
    click("transportPlayPause");
    require(!audio->property("playing").toBool(), "Pause did not pause playback");
    const double paused = audio->property("playheadTick").toDouble();
    QTest::qWait(100ms);
    require(audio->property("playheadTick").toDouble() == paused, "paused playhead kept moving");
    click("transportStop");
    require(audio->property("playheadTick").toDouble() == 0, "Stop did not return to song start");
    pass("real-audio-play-pause-stop-and-playhead");
    // Premise: a focused persistent Quick control plus an active window.
    // The Stop click focused the button, but window deactivation clears
    // active focus, so both halves are pinned here rather than inherited.
    ensureSmokeWindowActive(window);
    item("transportStop")->forceActiveFocus();
    QTest::keyClick(window, Qt::Key_Space);
    const bool spaceStarted =
        QTest::qWaitFor([&] { return audio->property("playing").toBool(); }, 3s);
    if (!spaceStarted) {
        QQuickItem *focus = window->activeFocusItem();
        QObject *currentPage = window->property("currentPage").value<QObject *>();
        QObject *rootAudio = window->property("audio").value<QObject *>();
        QObject *songTabs = window->property("songTabs").value<QObject *>();
        const QString focusName = focus ? focus->objectName() : QStringLiteral("<null>");
        const QString pageName = currentPage ? currentPage->objectName() : QStringLiteral("<null>");
        std::fprintf(stderr,
                     "Space transport diagnostic: windowActive=%d windowVisible=%d "
                     "activeFocusItem='%s' gridShortcutsEnabled=%d currentPage='%s' "
                     "noteMenuOpen=%d pitchEditorOpen=%d rootAudioMatches=%d selectedId=%d "
                     "selectedIndex=%d audioPlaying=%d\n",
                     window->isActive(), window->isVisible(), qPrintable(focusName),
                     window->property("gridShortcutsEnabled").toBool(), qPrintable(pageName),
                     currentPage && currentPage->property("noteMenuOpen").toBool(),
                     currentPage && currentPage->property("pitchEditorOpen").toBool(),
                     rootAudio == audio, songTabs ? songTabs->property("selectedId").toInt() : -1,
                     songTabs ? songTabs->property("selectedIndex").toInt() : -1,
                     audio->property("playing").toBool());
        std::fflush(stderr);
    }
    require(spaceStarted, "focused Stop button stole Space from the window transport command");
    QTest::keyClick(window, Qt::Key_Return);
    require(!audio->property("playing").toBool() && audio->property("playheadTick").toDouble() == 0,
            "Enter did not activate the focused Stop button");
    pass("transport-space-priority-and-local-enter");

    click("gridNote_1");
    ensureSmokeWindowActive(window);
    QTest::keyClick(window, Qt::Key_G);
    awaitState([&] { return item("pitchBendGraph") && item("pitchBendGraph")->isVisible(); },
               "G did not open a functional pitch popup");
    auto *popup = item("pitchBendPopup");
    require(popup && window->contentItem()->boundingRect().contains(sceneRect(popup)),
            "pitch popup is not clamped inside the application window");
    auto *graph = item("pitchBendGraph");
    const QRectF plot = graph->property("canvasRect").toRectF();
    require(plot.width() > 0 && plot.height() > 0, "pitch graph has no native canvas geometry");
    const QPoint low = graph
                           ->mapToScene(QPointF(plot.x() + (plot.width() - 1) * 2 / 18,
                                                plot.y() + (plot.height() - 1) * 0.8))
                           .toPoint();
    const QPoint high = graph
                            ->mapToScene(QPointF(plot.x() + (plot.width() - 1) * 16 / 18,
                                                 plot.y() + (plot.height() - 1) * 0.2))
                            .toPoint();
    QTest::mousePress(window, Qt::LeftButton, Qt::ShiftModifier, low);
    QTest::mouseMove(window, high);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::ShiftModifier, high);
    QTest::qWait(40ms);
    const QRectF curveRegion = graph->mapRectToScene(plot).adjusted(6, 6, -6, -6);
    require(colorCount(window->grabWindow(), curveRegion, qRgb(205, 84, 84)) > 30,
            "pitch gesture did not render the production track-colored curve");
    const QImage drawn = window->grabWindow();
    QTest::keyClick(window, Qt::Key_Escape);
    awaitState([&] { return !window->property("pitchBridge").value<QObject *>(); },
               "Escape did not dismiss the pitch popup");
    ensureSmokeWindowActive(window);
    QTest::keyClick(window, Qt::Key_G);
    awaitState([&] { return item("pitchBendGraph") && item("pitchBendGraph")->isVisible(); },
               "pitch popup did not reopen");
    QTest::qWait(40ms);
    const QImage reopened = window->grabWindow();
    const QRectF upperCurve(curveRegion.x(), curveRegion.y(), curveRegion.width(),
                            curveRegion.height() / 3);
    const int upperPixels = colorCount(drawn, upperCurve, qRgb(205, 84, 84));
    require(upperPixels > 5 && colorCount(reopened, upperCurve, qRgb(205, 84, 84)) > 5,
            "edited pitch curve did not survive popup close and reopen");
    pass("native-pitch-curve-raster-and-committed-reopen");

    QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, center(item("bendRangeInput")));
    QTest::qWait(30ms);
    QTest::keyClick(window, Qt::Key_7);
    QTest::keyClick(window, Qt::Key_Return);
    awaitState([&] { return item("bendRangeInput")->property("text").toString() == "7"; },
               "pitch bend range numeric editor did not accept text input");
    click("pitchBendReset");
    QTest::qWait(40ms);
    require(colorCount(window->grabWindow(), upperCurve, qRgb(205, 84, 84)) == 0,
            "Reset did not restore the zero pitch curve");
    QTest::keyClick(window, Qt::Key_Escape);
    awaitState([&] { return !window->property("pitchBridge").value<QObject *>(); },
               "pitch popup did not close after numeric editing");
    ensureSmokeWindowActive(window);
    QTest::keyClick(window, Qt::Key_G);
    awaitState(
        [&] {
            return item("bendRangeInput") &&
                   item("bendRangeInput")->property("text").toString() == "7";
        },
        "pitch bend range did not survive popup reopen");
    pass("pitch-popup-numeric-range-reset-and-persistence");

    auto previewCurve = [&] {
        QTest::mousePress(window, Qt::LeftButton, Qt::ShiftModifier, low);
        QTest::mouseMove(window, high);
        QTest::qWait(40ms);
        require(colorCount(window->grabWindow(), upperCurve, qRgb(205, 84, 84)) > 5,
                "unreleased pitch gesture did not produce a live preview");
    };
    previewCurve();
    auto *pitchGrabber = window->mouseGrabberItem();
    require(pitchGrabber, "pitch gesture did not acquire the native mouse grab");
    pitchGrabber->ungrabMouse();
    QTest::mouseRelease(window, Qt::LeftButton, Qt::ShiftModifier, high);
    QTest::qWait(40ms);
    require(colorCount(window->grabWindow(), upperCurve, qRgb(205, 84, 84)) == 0,
            "aborted pitch gesture did not restore the committed curve");
    for (const char *focusTarget : std::array{"pitchBendGraph", "pitchBendPopup"}) {
        previewCurve();
        item(focusTarget)->forceActiveFocus();
        QTest::keyClick(window, Qt::Key_Escape);
        awaitState([&] { return !window->property("pitchBridge").value<QObject *>(); },
                   "Escape did not dismiss an active pitch gesture");
        QTest::mouseRelease(window, Qt::LeftButton, Qt::ShiftModifier, high);
        ensureSmokeWindowActive(window);
        QTest::keyClick(window, Qt::Key_G);
        awaitState([&] { return item("pitchBendGraph") && item("pitchBendGraph")->isVisible(); },
                   "pitch popup did not reopen after cancelling a live gesture");
        QTest::qWait(40ms);
        require(colorCount(window->grabWindow(), upperCurve, qRgb(205, 84, 84)) == 0 &&
                    item("bendRangeInput")->property("text").toString() == "7",
                "Escape persisted a live preview or discarded a previously committed numeric edit");
    }
    pass("pitch-abort-and-escape-discard-live-preview");
    graph = item("modWheelGraph");
    const QRectF modPlot = graph->property("canvasRect").toRectF();
    const QPoint modLow = graph
                              ->mapToScene(QPointF(modPlot.x() + (modPlot.width() - 1) * 2 / 18,
                                                   modPlot.y() + (modPlot.height() - 1) * 0.8))
                              .toPoint();
    const QPoint modHigh = graph
                               ->mapToScene(QPointF(modPlot.x() + (modPlot.width() - 1) * 16 / 18,
                                                    modPlot.y() + (modPlot.height() - 1) * 0.2))
                               .toPoint();
    QTest::mousePress(window, Qt::LeftButton, Qt::AltModifier, modLow);
    QTest::mouseMove(window, modHigh);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::AltModifier, modHigh);
    QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, center(item("lfoSpeedInput")));
    QTest::qWait(30ms);
    QTest::keyClick(window, Qt::Key_5);
    QTest::keyClick(window, Qt::Key_Return);
    const QRectF modUpper =
        graph->mapRectToScene(modPlot).adjusted(6, 6, -6, -modPlot.height() * 2 / 3);
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, QPoint(window->width() - 10, 100));
    awaitState([&] { return !window->property("pitchBridge").value<QObject *>(); },
               "outside click did not dismiss the pitch popup");
    ensureSmokeWindowActive(window);
    QTest::keyClick(window, Qt::Key_G);
    awaitState(
        [&] {
            return item("lfoSpeedInput") &&
                   item("lfoSpeedInput")->property("text").toString() == "5";
        },
        "LFO speed did not survive popup reopen");
    QTest::qWait(40ms);
    const QImage modReopened = window->grabWindow();
    require(colorCount(modReopened, modUpper, qRgb(205, 84, 84)) > 5 &&
                colorCount(modReopened, upperCurve, qRgb(205, 84, 84)) == 0,
            "modulation editing did not persist independently of pitch editing");
    pass("modulation-lfo-and-outside-dismiss-persistence");
    QTest::keyClick(window, Qt::Key_Escape);
}
