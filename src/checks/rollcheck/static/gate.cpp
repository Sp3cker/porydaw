#include "checks/rollcheck/static/tst_pianorollstatic.h"

#include <QCoreApplication>
#include <QEnterEvent>
#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWheelEvent>
#include <QtTest>

#include <array>

#include "checks/rollcheck/static/fixtures.h"
#include "checks/support/eventsynth.h"
#include "core/smf.h"
#include "core/tracklimits.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/eventlistview.h"
#include "ui/songtab.h"
#include "ui/songview.h"
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
    if (!band)
        return;
    const QPointF point(view.camera().leadPadPx() + 140.0, band->rect.height() * 3.0 / 4.0);
    checks::events::sendMouse(input, QEvent::MouseButtonPress, point, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(input, QEvent::MouseButtonRelease, point, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
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
    checks::events::sendWheel(input, QPointF(80.0, 100.0), QPoint(), QPoint(0, 120), Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false);
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
        !fixture.horizontalScrollbar() || !fixture.eventList() || !fixture.drawer() ||
        !fixture.headers() || !fixture.headersInput() || !fixture.controls() ||
        !fixture.divisionControl() || !fixture.feelControl())
        return false;
    const auto *quick = fixture.view()->findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    if (!root || !fixture.view()->isEnabled() || !fixture.rollInput()->isEnabled() ||
        !fixture.rulerInput()->isEnabled() || !fixture.horizontalScrollbar()->isVisible() ||
        !fixture.horizontalScrollbar()->isEnabled() || !fixture.eventList()->isEnabled() ||
        fixture.headersInput()->interaction() != fixture.headers() ||
        !fixture.headersInput()->isEnabled() || !fixture.controls()->isEnabled() ||
        !fixture.divisionControl()->isEnabled() || !fixture.feelControl()->isEnabled())
        return false;
    const auto *verticalScrollbar =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRollScrollBar"));
    const auto *otherEvents =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineOtherEventsInput"));
    if (!verticalScrollbar || !verticalScrollbar->isVisible() || !verticalScrollbar->isEnabled() ||
        !otherEvents || !otherEvents->isEnabled())
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
    QVERIFY(fixture.view()->isEnabled());
    QVERIFY(fixture.rollInput()->isEnabled());
    QVERIFY(fixture.rulerInput()->isEnabled());
    QVERIFY(fixture.horizontalScrollbar()->isVisible());
    QVERIFY(fixture.horizontalScrollbar()->isEnabled());
    QVERIFY(fixture.eventList()->isEnabled());
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
    QVERIFY(verticalScrollbar);
    QVERIFY(verticalScrollbar->isVisible());
    QVERIFY(verticalScrollbar->isEnabled());
    QVERIFY(otherEvents);
    QVERIFY(otherEvents->isEnabled());
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
    QVERIFY(fixture.view()->isEnabled());
    QVERIFY(controlsMatchRuler(fixture));
    QVERIFY(allFixedSurfacesEnabled(fixture));
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
    QVERIFY(fixture.view()->isEnabled());
    QVERIFY(controlsMatchRuler(fixture));
    QVERIFY(allFixedSurfacesEnabled(fixture));
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
    auto *const control = division ? fixture.divisionControl() : fixture.feelControl();
    QVERIFY(control);
    auto *const root = control->window() ? control->window()->contentItem() : nullptr;
    QVERIFY(root);
    QQuickWindow *const window = control->window();
    const QPointF scene =
        control->mapToScene(QPointF(control->width() / 2.0, control->height() / 2.0));
    const QPointF global = window->mapToGlobal(scene.toPoint());
    QEnterEvent enter(scene, scene, global);
    QCoreApplication::sendEvent(window, &enter);
    QMouseEvent move(QEvent::MouseMove, scene, global, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &move);
    QCoreApplication::processEvents();
    QVERIFY(fixture.toolTip()->isVisible());
    const QRectF tooltip(fixture.toolTip()->mapToItem(root, QPointF()), fixture.toolTip()->size());
    const qreal rowBottom =
        fixture.controls()->mapToItem(root, QPointF()).y() + rulerBandHeight(*fixture.view());
    if (rowBottom + tooltip.height() <= root->height()) {
        QVERIFY(tooltip.top() >= rowBottom - 0.5);
        QVERIFY(tooltip.bottom() <= root->height() + 0.5);
        QVERIFY(tooltip.left() >= -0.5);
        QVERIFY(tooltip.right() <= root->width() + 0.5);
    }
    const QPointF away = root->mapToScene(QPointF(root->width() / 2.0, root->height() / 2.0));
    QMouseEvent leave(QEvent::MouseMove, away, window->mapToGlobal(away.toPoint()), Qt::NoButton,
                      Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &leave);
    QCoreApplication::processEvents();
    QVERIFY(!fixture.toolTip()->isVisible());
}

} // namespace checks::rollcheck::staticcheck
