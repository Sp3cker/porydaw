#include "checks/rollcheck/static/tst_pianorollstatic.h"

#include <QCoreApplication>
#include <QEnterEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWheelEvent>
#include <QWindow>
#include <QtTest>

#include <array>

#include "checks/rollcheck/static/fixtures.h"
#include "checks/support/eventsynth.h"
#include "core/smf.h"
#include "core/tracklimits.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"

namespace checks::rollcheck::staticcheck {
namespace {

bool bindMidiStage(GateFixture &fixture)
{
    SmfFile smf;
    SongInfo info;
    info.label = fixture.tab()->name().value();
    fixture.tab()->applyMidiStage(info, std::move(smf), track_limits::kHardwareCapacity);
    return fixture.tab()->presentationError().isEmpty();
}

bool bindVoicegroup(GateFixture &fixture)
{
    const auto identity =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/loading_probe.inc"), QString());
    if (!identity)
        return false;
    fixture.tab()->applyVoicegroupBound(*identity);
    return true;
}

void sendRulerClick(songview::TimelineInputItem &input, SongView &view)
{
    const auto band = view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    QQuickWindow *const window = input.window();
    if (!band || !window)
        return;
    const QPointF point(view.camera().leadPadPx() + 140.0, band->rect.height() * 3.0 / 4.0);
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, input.mapToScene(point).toPoint());
}

void sendScrollbarWheel(QQuickItem &bar)
{
    QQuickWindow *const window = bar.window();
    if (!window)
        return;
    const QPointF local(bar.width() / 2.0, bar.height() / 2.0);
    const QPointF scene = bar.mapToScene(local);
    QWheelEvent event(scene, window->mapToGlobal(scene.toPoint()), QPoint(), QPoint(0, -120),
                      Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(window, &event);
}

void sendRollWheel(songview::TimelineInputItem &input)
{
    QQuickWindow *const window = input.window();
    if (!window)
        return;
    const QPointF scene = input.mapToScene(QPointF(80.0, 100.0));
    QWheelEvent event(scene, window->mapToGlobal(scene.toPoint()), QPoint(), QPoint(0, 120),
                      Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(window, &event);
}

bool controlsMatchRuler(const GateFixture &fixture)
{
    const auto *ruler = fixture.ruler();
    const auto *division = fixture.divisionControl();
    const auto *feel = fixture.feelControl();
    return ruler && division && feel && ruler->gridControlsEnabled() &&
           division->property("controlText").toString() == ruler->divisionText() &&
           feel->property("controlText").toString() == ruler->feelText() &&
           division->property("controlToolTip").toString() == ruler->divisionToolTip() &&
           feel->property("controlToolTip").toString() == ruler->feelToolTip();
}
bool allFixedSurfacesEnabled(const GateFixture &fixture)
{
    if (!fixture.view() || !fixture.rollInput() || !fixture.rulerInput() ||
        !fixture.horizontalScrollbar() || !fixture.eventListController() || !fixture.drawer() ||
        !fixture.headers() || !fixture.headersInput() || !fixture.controls() ||
        !fixture.divisionControl() || !fixture.feelControl())
        return false;
    const auto *quick = fixture.view()->findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    if (!root || !fixture.rollInput()->isEnabled() || !fixture.rulerInput()->isEnabled() ||
        !fixture.horizontalScrollbar()->isVisible() ||
        !fixture.horizontalScrollbar()->isEnabled() ||
        fixture.headersInput()->interaction() != fixture.headers() ||
        !fixture.headersInput()->isEnabled() || !fixture.controls()->isEnabled() ||
        !fixture.divisionControl()->isEnabled() || !fixture.feelControl()->isEnabled())
        return false;
    const auto *verticalScrollbar =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRollScrollBar"));
    const auto *otherEvents =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineOtherEventsInput"));
    const auto *eventListInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineEventListInput"));
    if (!verticalScrollbar || !verticalScrollbar->isVisible() || !verticalScrollbar->isEnabled() ||
        !otherEvents || !otherEvents->isEnabled() || !eventListInput ||
        !eventListInput->isEnabled())
        return false;
    constexpr std::array drawerNames{
        "drawerVoiceChangesHandleInput",
        "drawerVelocityHandleInput",
        "drawerAutomationHandleInput",
        "drawerBarInput",
        "drawerDetentInput",
    };
    for (const char *name : drawerNames) {
        const auto *input =
            root->findChild<songview::TimelineInputItem *>(QString::fromLatin1(name));
        if (!input || !input->isEnabled())
            return false;
    }
    return true;
}

struct GridControlState {
    QString divisionText;
    QString feelText;
    QString divisionToolTip;
    QString feelToolTip;
    QString divisionControlText;
    QString feelControlText;
    QString divisionControlToolTip;
    QString feelControlToolTip;
    QVariantMap appearance;
    bool controlsEnabled = false;
    bool divisionEnabled = false;
    bool feelEnabled = false;
};

GridControlState gridControlState(const GateFixture &fixture)
{
    const auto *ruler = fixture.ruler();
    const auto *controls = fixture.controls();
    const auto *division = fixture.divisionControl();
    const auto *feel = fixture.feelControl();
    if (!ruler || !controls || !division || !feel)
        return {};
    return {ruler->divisionText(),
            ruler->feelText(),
            ruler->divisionToolTip(),
            ruler->feelToolTip(),
            division->property("controlText").toString(),
            feel->property("controlText").toString(),
            division->property("controlToolTip").toString(),
            feel->property("controlToolTip").toString(),
            ruler->gridControlAppearance(),
            controls->isEnabled(),
            division->isEnabled(),
            feel->isEnabled()};
}

bool unchangedGridControlState(const GateFixture &fixture, const GridControlState &before)
{
    const GridControlState after = gridControlState(fixture);
    return after.divisionText == before.divisionText && after.feelText == before.feelText &&
           after.divisionToolTip == before.divisionToolTip &&
           after.feelToolTip == before.feelToolTip &&
           after.divisionControlText == before.divisionControlText &&
           after.feelControlText == before.feelControlText &&
           after.divisionControlToolTip == before.divisionControlToolTip &&
           after.feelControlToolTip == before.feelControlToolTip &&
           after.appearance == before.appearance &&
           after.controlsEnabled == before.controlsEnabled &&
           after.divisionEnabled == before.divisionEnabled &&
           after.feelEnabled == before.feelEnabled;
}

} // namespace

void PianoRollStaticTest::freshTabStaysGated()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY(!fixture.tab()->isReady());
    QVERIFY(fixture.rollInput()->isEnabled());
    QVERIFY(fixture.rulerInput()->isEnabled());
    QVERIFY(fixture.horizontalScrollbar()->isVisible());
    QVERIFY(fixture.horizontalScrollbar()->isEnabled());
    QVERIFY(fixture.eventListController());
    QVERIFY(fixture.drawer());
    QVERIFY(fixture.headersInput()->isEnabled());
    QCOMPARE(fixture.headersInput()->interaction(), fixture.headers());
    QVERIFY(fixture.controls()->isEnabled());
    QVERIFY(fixture.divisionControl()->isEnabled());
    QVERIFY(fixture.feelControl()->isEnabled());
    QVERIFY(controlsMatchRuler(fixture));
    auto *const quick = fixture.view()->findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    QVERIFY(root);
    auto *const verticalScrollbar =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRollScrollBar"));
    auto *const otherEvents =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineOtherEventsInput"));
    auto *const eventListInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineEventListInput"));
    QVERIFY(verticalScrollbar);
    QVERIFY(verticalScrollbar->isVisible());
    QVERIFY(verticalScrollbar->isEnabled());
    QVERIFY(otherEvents);
    QVERIFY(otherEvents->isEnabled());
    QVERIFY(eventListInput);
    QVERIFY(eventListInput->isEnabled());
    constexpr std::array drawerNames{
        "drawerVoiceChangesHandleInput",
        "drawerVelocityHandleInput",
        "drawerAutomationHandleInput",
        "drawerBarInput",
        "drawerDetentInput",
    };
    for (const char *name : drawerNames) {
        auto *const input =
            root->findChild<songview::TimelineInputItem *>(QString::fromLatin1(name));
        QVERIFY2(input, name);
        QVERIFY(input->isEnabled());
    }
    fixture.view()->setEditCursorTick(96);
    QCOMPARE(fixture.view()->editCursorTick(), uint64_t(96));
    const uint64_t before = fixture.view()->editCursorTick();
    sendRulerClick(*fixture.rulerInput(), *fixture.view());
    QCOMPARE(fixture.view()->editCursorTick(), before);
    QVERIFY(!fixture.view()->userGestureActive());
    const double zoom = fixture.view()->camera().pxPerBeat();
    sendRollWheel(*fixture.rollInput());
    QVERIFY(qFuzzyCompare(fixture.view()->camera().pxPerBeat(), zoom));
}

void PianoRollStaticTest::midiStageStaysGated()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    QVERIFY(!fixture.tab()->isReady());
    QVERIFY(fixture.view()->timeline());
    QCOMPARE(fixture.view()->editCursorTick(), uint64_t(0));
    QVERIFY(controlsMatchRuler(fixture));
    QTRY_VERIFY(allFixedSurfacesEnabled(fixture));
    const uint64_t cursor = fixture.view()->editCursorTick();
    sendRulerClick(*fixture.rulerInput(), *fixture.view());
    QCOMPARE(fixture.view()->editCursorTick(), cursor);
    const double scroll = fixture.view()->camera().scrollX();
    sendScrollbarWheel(*fixture.horizontalScrollbar());
    QVERIFY(qFuzzyCompare(fixture.view()->camera().scrollX(), scroll));
    const double zoom = fixture.view()->camera().pxPerBeat();
    sendRollWheel(*fixture.rollInput());
    QVERIFY(qFuzzyCompare(fixture.view()->camera().pxPerBeat(), zoom));
}

void PianoRollStaticTest::voicegroupBoundReadiesTab()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    QVERIFY(bindVoicegroup(fixture));
    QVERIFY(fixture.tab()->isReady());
    QVERIFY(controlsMatchRuler(fixture));
    QTRY_VERIFY(allFixedSurfacesEnabled(fixture));
}

void PianoRollStaticTest::gridControlsDoNotRestyleAcrossReadiness()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    const GridControlState before = gridControlState(fixture);
    QVERIFY(!before.divisionText.isEmpty());
    QVERIFY(bindVoicegroup(fixture));
    QVERIFY(fixture.tab()->isReady());
    QVERIFY(unchangedGridControlState(fixture, before));
    QVERIFY(controlsMatchRuler(fixture));
}

void PianoRollStaticTest::gatedAndReadyRulerScrub()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    const uint64_t gated = fixture.view()->editCursorTick();
    sendRulerClick(*fixture.rulerInput(), *fixture.view());
    QCOMPARE(fixture.view()->editCursorTick(), gated);
    QVERIFY(!fixture.view()->userGestureActive());
    QVERIFY(bindVoicegroup(fixture));
    const uint64_t ready = fixture.view()->editCursorTick();
    sendRulerClick(*fixture.rulerInput(), *fixture.view());
    QVERIFY(fixture.view()->editCursorTick() != ready);
    QVERIFY(!fixture.view()->userGestureActive());
}

void PianoRollStaticTest::gatedAndReadyScrollbarWheel()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    const double gated = fixture.view()->camera().scrollX();
    sendScrollbarWheel(*fixture.horizontalScrollbar());
    QVERIFY(qFuzzyCompare(fixture.view()->camera().scrollX(), gated));
    QVERIFY(bindVoicegroup(fixture));
    const double ready = fixture.view()->camera().scrollX();
    sendScrollbarWheel(*fixture.horizontalScrollbar());
    QVERIFY(!qFuzzyCompare(fixture.view()->camera().scrollX(), ready));
}

void PianoRollStaticTest::gatedAndReadyRollZoom()
{
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    const double gated = fixture.view()->camera().pxPerBeat();
    sendRollWheel(*fixture.rollInput());
    QVERIFY(qFuzzyCompare(fixture.view()->camera().pxPerBeat(), gated));
    QVERIFY(bindVoicegroup(fixture));
    const double ready = fixture.view()->camera().pxPerBeat();
    sendRollWheel(*fixture.rollInput());
    QVERIFY(!qFuzzyCompare(fixture.view()->camera().pxPerBeat(), ready));
}

void PianoRollStaticTest::tooltipFloatsBelowRuler_data()
{
    QTest::addColumn<bool>("division");
    QTest::newRow("division") << true;
    QTest::newRow("feel") << false;
}

void PianoRollStaticTest::tooltipFloatsBelowRuler()
{
    QFETCH(bool, division);
    GateFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qPrintable(error));
    QVERIFY2(bindMidiStage(fixture), qPrintable(fixture.tab()->presentationError()));
    QVERIFY(bindVoicegroup(fixture));
    auto *const quick = fixture.view()->findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    const QPointer<songview::TimelineQuickView> guardedQuick = quick;
    const QPointer<QQuickItem> guardedCanvasRoot = quick ? quick->rootObject() : nullptr;
    const QPointer<QQuickWindow> guardedQuickWindow = quick ? quick->quickWindow() : nullptr;
    const QPointer<QWindow> guardedHostWindow = fixture.tab()->windowHandle();
    const QPointer<QQuickItem> guardedControls = fixture.controls();
    const QPointer<QQuickItem> guardedDivisionControl = fixture.divisionControl();
    const QPointer<QQuickItem> guardedFeelControl = fixture.feelControl();
    const QPointer<QQuickItem> guardedToolTip = fixture.toolTip();
    const auto sceneReady = [&] {
        return guardedQuick && guardedCanvasRoot && guardedQuickWindow && guardedHostWindow &&
               guardedControls && guardedDivisionControl && guardedFeelControl && guardedToolTip &&
               fixture.tab()->isVisible() && fixture.tab()->windowHandle() == guardedHostWindow &&
               guardedHostWindow->isExposed() && guardedQuickWindow->isVisible() &&
               guardedQuickWindow->isExposed() && guardedCanvasRoot->isVisible() &&
               guardedCanvasRoot->width() > 0.0 && guardedCanvasRoot->height() > 0.0 &&
               guardedToolTip->window() == guardedQuickWindow;
    };
    const auto usableControl = [&sceneReady,
                                &guardedQuickWindow](const QPointer<QQuickItem> &control) {
        return sceneReady() && control->isVisible() && control->isEnabled() &&
               control->width() > 0.0 && control->height() > 0.0 &&
               control->window() == guardedQuickWindow;
    };
    if (!QTest::qWaitFor([&] {
            return usableControl(guardedDivisionControl) && usableControl(guardedFeelControl);
        })) {
        QFAIL("ready ruler tooltip Quick surface did not become input-ready");
    }
    const QPointer<QQuickItem> guardedControl =
        division ? guardedDivisionControl : guardedFeelControl;
    bool windowEntered = false;
    const auto setHover = [&guardedCanvasRoot, &guardedQuickWindow,
                           &windowEntered](const QPointer<QQuickItem> &control, bool entering) {
        if (!guardedCanvasRoot || !guardedQuickWindow || !control)
            return false;
        QQuickItem *const canvasRoot = guardedCanvasRoot.data();
        QQuickWindow *const quickWindow = guardedQuickWindow.data();
        const QPoint windowPosition =
            (entering
                 ? control->mapToScene(QPointF(control->width() / 2.0, control->height() / 2.0))
                 : canvasRoot->mapToScene(
                       QPointF(canvasRoot->width() / 2.0, canvasRoot->height() / 2.0)))
                .toPoint();
        if (entering) {
            if (!windowEntered) {
                const QPointF point(windowPosition);
                QEnterEvent enter(point, point, QPointF(quickWindow->mapToGlobal(windowPosition)));
                QCoreApplication::sendEvent(quickWindow, &enter);
                windowEntered = true;
            }
            if (!checks::events::primeMouseMove(*quickWindow, *control, windowPosition))
                return false;
        }
        QTest::mouseMove(quickWindow, windowPosition);
        return true;
    };
    const auto hoverDiagnostic = [&sceneReady, &guardedQuickWindow,
                                  &guardedToolTip](const QPointer<QQuickItem> &control) {
        return QObject::tr(
                   "ruler tooltip did not appear while hovering the %1 control "
                   "(scene-ready=%2 hovered=%3 visible=%4 enabled=%5 size=%6x%7 window=%8 "
                   "tooltip-visibleForControl=%9 tooltip-text-empty=%10 tooltip-size=%11x%12)")
            .arg(control ? control->objectName() : QStringLiteral("<destroyed>"))
            .arg(sceneReady())
            .arg(control && control->property("hovered").toBool())
            .arg(control && control->isVisible())
            .arg(control && control->isEnabled())
            .arg(control ? control->width() : 0.0)
            .arg(control ? control->height() : 0.0)
            .arg(control && control->window() == guardedQuickWindow)
            .arg(guardedToolTip && guardedToolTip->property("visibleForControl").toBool())
            .arg(guardedToolTip && guardedToolTip->property("toolTipText").toString().isEmpty())
            .arg(guardedToolTip ? guardedToolTip->width() : 0.0)
            .arg(guardedToolTip ? guardedToolTip->height() : 0.0);
    };

    if (!usableControl(guardedControl)) {
        QFAIL("ready ruler tooltip Quick control was destroyed before hover delivery");
    }
    if (!setHover(guardedControl, true)) {
        setHover(guardedControl, false);
        QFAIL(qUtf8Printable(QObject::tr("could not deliver ruler hover to the %1 control")
                                 .arg(guardedControl->objectName())));
    }
    if (!QTest::qWaitFor(
            [&] { return sceneReady() && guardedControl && guardedToolTip->isVisible(); })) {
        setHover(guardedControl, false);
        QFAIL(qUtf8Printable(hoverDiagnostic(guardedControl)));
    }
    if (!sceneReady() || !guardedControl || !guardedToolTip->isVisible()) {
        QFAIL("ready ruler tooltip Quick scene was destroyed after hover delivery");
    }
    const QRectF tooltipRect(guardedToolTip->mapToItem(guardedCanvasRoot, QPointF(0, 0)),
                             guardedToolTip->size());
    const qreal rowBottom = guardedControls->mapToItem(guardedCanvasRoot, QPointF(0, 0)).y() +
                            rulerBandHeight(*fixture.view());
    // Room below the row exists, so the tooltip must float there instead
    // of covering the row or spilling past the canvas.
    if (rowBottom + tooltipRect.height() <= guardedCanvasRoot->height()) {
        if (tooltipRect.top() < rowBottom - 0.5) {
            setHover(guardedControl, false);
            QFAIL("ruler tooltip covered the ruler row instead of floating below it");
        }
        if (tooltipRect.bottom() > guardedCanvasRoot->height() + 0.5) {
            setHover(guardedControl, false);
            QFAIL("ruler tooltip spilled past the Quick canvas below the ruler row");
        }
        if (tooltipRect.left() < -0.5 || tooltipRect.right() > guardedCanvasRoot->width() + 0.5) {
            setHover(guardedControl, false);
            QFAIL("ruler tooltip left the Quick canvas while floating below the row");
        }
    }
    if (!setHover(guardedControl, false)) {
        QFAIL(qUtf8Printable(QObject::tr("could not deliver ruler hover leave from the %1 control")
                                 .arg(guardedControl->objectName())));
    }
    if (!QTest::qWaitFor(
            [&] { return sceneReady() && guardedControl && !guardedToolTip->isVisible(); })) {
        if (!sceneReady() || !guardedControl || !guardedToolTip) {
            QFAIL("ready ruler tooltip Quick scene was destroyed while awaiting hover leave");
        } else {
            QFAIL("ruler tooltip stayed visible after the hover left the control");
        }
    }
}

} // namespace checks::rollcheck::staticcheck
