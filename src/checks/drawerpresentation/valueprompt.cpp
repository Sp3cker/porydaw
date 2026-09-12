// Inline Quick value prompt coverage for the automation drawer (drawer plan
// Cleanup phase 4): the Tempo and CC prompt families behind NodeLane publish
// through DrawerChrome, both canvas entry points open without writing, Enter
// commits the displayed value through the stored offset, and Escape, focus
// loss, document change, window deactivation, page hide, and a late accept all
// resolve the pending edit without touching the song.

#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QtTest>

#include <algorithm>
#include <cmath>
#include <cstdint>

#include <QCoreApplication>
#include <QEvent>
#include <QKeySequence>
#include <QQuickItem>
#include <QQuickWindow>

#include "checks/automation/automationvalueprompt.h"
#include "checks/drawerpresentation/fixtures.h"
#include "checks/selectionkey/automationprobe.h"
#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

using namespace checks::drawerpresentation;

namespace {

constexpr uint8_t kController = 10;
constexpr Tick kNodeTick = 24;

Snapshot snapshot(SongDocument &document)
{
    return {document.smf().write(), document.revision(), document.undoStack()->index()};
}

AutomationCanvas *canvasOf(const DrawerFixture &fixture)
{
    return fixture.view->editorDrawer()->automationPage()->canvas();
}

songview::TimelineInputItem *automationInput(const DrawerFixture &fixture)
{
    return fixture.quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineAutomationInput"));
}

LaneHandle ccLaneHandle(const AutomationCanvas &canvas)
{
    const auto &rows = canvas.rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id ==
            EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, kController})
            return LaneHandle{index + 1};
    }
    return {};
}

// Parameter selection is a real click on the live visual label; node probes
// only project the already-active lane's geometry.
bool activateParameter(DrawerFixture &fixture, AutomationCanvas &canvas,
                       const EditorAutomationRowId &row)
{
    const int index = checks::support::automationParameterIndex(canvas, row);
    if (index < 0)
        return false;
    QQuickItem *const root = fixture.quickRoot;
    if (!root)
        return false;
    QQuickItem *label = nullptr;
    if (!QTest::qWaitFor([&root, &label, index] {
            label = checks::support::visualDescendant(
                root, QStringLiteral("automationParameterTab%1").arg(index));
            return label && label->isVisible() && label->isEnabled() && label->width() > 0.0 &&
                   label->height() > 0.0 && label->window();
        })) {
        return false;
    }
    QQuickWindow *const window = label->window();
    QQuickItem *const content = window ? window->contentItem() : nullptr;
    if (!content)
        return false;
    const QPointF point = content->mapFromScene(
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)));
    if (!content->boundingRect().contains(point))
        return false;
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, point.toPoint());
    return QTest::qWaitFor([&canvas, index] { return canvas.activeParameter() == index; });
}

const TempoPoint *tempoPointAt(const SongDocument &document, Tick tick)
{
    const auto &points = document.tempoPoints();
    const auto found = std::find_if(points.cbegin(), points.cend(),
                                    [tick](const TempoPoint &point) { return point.tick == tick; });
    return found == points.cend() ? nullptr : &*found;
}

int tempoBpmAt(const SongDocument &document, Tick tick)
{
    const TempoPoint *const point = tempoPointAt(document, tick);
    Q_ASSERT(point);
    return int(std::lround(CoreTimeDefaults::tempoBpm(point->microsecondsPerQuarterNote)));
}

// Opens the Set-Value prompt on an existing CC node and waits until the chrome
// publishes it.
bool openCcNodePrompt(DrawerFixture &fixture, LaneHandle cc, Tick tick, int storedValue)
{
    AutomationCanvas *const canvas = canvasOf(fixture);
    if (!canvas || !canvas->openValuePromptForNode(cc, NodePoint{tick, storedValue}))
        return false;
    DrawerChrome &chrome = fixture.chrome();
    return QTest::qWaitFor([&chrome] { return automation_valueprompt::promptVisible(chrome); });
}

} // namespace

void DrawerPresentationTest::valuePromptTempoLimitsAcceptAndClamp()
{
    DrawerFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qUtf8Printable(error));
    DrawerChrome &chrome = fixture.chrome();
    AutomationCanvas *const canvas = canvasOf(fixture);
    QVERIFY(canvas);
    QQuickWindow *const window = fixture.quick->quickWindow();
    QVERIFY(window);
    auto *const input = automationInput(fixture);
    QVERIFY(input);
    SongDocument &document = fixture.tab->document();

    // The insertion entry point publishes the BPM domain with the displayed
    // insertion value and writes nothing by opening.
    const uint64_t revision = document.revision();
    const int undoIndex = document.undoStack()->index();
    QVERIFY(canvas->openValuePromptForInsertion(LaneHandle{0}, kNodeTick, 140));
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QCOMPARE(document.revision(), revision);
    QCOMPARE(document.undoStack()->index(), undoIndex);
    QCOMPARE(chrome.valuePromptTitle(), QStringLiteral("Set tempo"));
    QCOMPARE(chrome.valuePromptLabel(), QStringLiteral("BPM:"));
    QCOMPARE(chrome.valuePromptMinimum(), CoreTimeDefaults::kMinTempoBpm);
    QCOMPARE(chrome.valuePromptMaximum(), CoreTimeDefaults::kMaxTempoBpm);
    QCOMPARE(chrome.valuePromptInitialValue(), 140);

    // Enter commits the typed displayed value as the stored BPM and hands
    // focus back to the automation input.
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(*window);
    QVERIFY2(prompt, "the tempo prompt did not take active focus");
    QCOMPARE(prompt->property("selectedText").toString(), QStringLiteral("140"));
    QTest::keySequence(window, QKeySequence(Qt::Key_9, Qt::Key_0));
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(document.revision(), revision + 1);
    QCOMPARE(document.undoStack()->index(), undoIndex + 1);
    QCOMPARE(tempoBpmAt(document, kNodeTick), 90);
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(*window, *input));

    // Acceptance clamps out-of-domain displayed values into the lane limits.
    QVERIFY(canvas->openValuePromptForInsertion(LaneHandle{0}, kNodeTick + 8, 120));
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    canvas->acceptNodeValuePrompt(CoreTimeDefaults::kMaxTempoBpm + 1000);
    QVERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(tempoBpmAt(document, kNodeTick + 8), CoreTimeDefaults::kMaxTempoBpm);
    QVERIFY(canvas->openValuePromptForInsertion(LaneHandle{0}, kNodeTick + 16, 120));
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    canvas->acceptNodeValuePrompt(CoreTimeDefaults::kMinTempoBpm - 1000);
    QVERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(tempoBpmAt(document, kNodeTick + 16), CoreTimeDefaults::kMinTempoBpm);
    QCOMPARE(document.revision(), revision + 3);
    QCOMPARE(document.undoStack()->index(), undoIndex + 3);
}

void DrawerPresentationTest::valuePromptCcCenterOffsetInsertionCommit()
{
    DrawerFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qUtf8Printable(error));
    DrawerChrome &chrome = fixture.chrome();
    AutomationCanvas *const canvas = canvasOf(fixture);
    QVERIFY(canvas);
    QQuickWindow *const window = fixture.quick->quickWindow();
    QVERIFY(window);
    SongDocument &document = fixture.tab->document();
    document.addLanePoint(0, kController, kNodeTick, 64);
    pump();
    QVERIFY2(activateParameter(fixture, *canvas,
                               {EditorAutomationRowKind::ControlChange, 0, kController}),
             "the Pan parameter label did not activate");
    const LaneHandle cc = ccLaneHandle(*canvas);
    QVERIFY(cc.valid());

    // Entry point B: a real double click on an empty CC-10 plot spot opens the
    // insertion prompt in displayed (stored-64) units and writes nothing.
    auto *const input = automationInput(fixture);
    QVERIFY(input);
    QString diagnostics;
    const auto probe =
        selectionkey::AutomationProbe::locate(*fixture.view, input, 0, kController, &diagnostics);
    QVERIFY2(probe.has_value(), qUtf8Printable(diagnostics));
    QPoint scene;
    QVERIFY2(probe->emptyNodePoint(96, scene, &diagnostics), qUtf8Printable(diagnostics));

    const uint64_t revision = document.revision();
    const int undoIndex = document.undoStack()->index();
    QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, scene);
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QCOMPARE(document.revision(), revision);
    QCOMPARE(chrome.valuePromptMinimum(), -64);
    QCOMPARE(chrome.valuePromptMaximum(), 63);

    // Displayed 0 commits as the stored center 64 on the new insertion tick.
    QTest::keySequence(window, QKeySequence(Qt::Key_0));
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(document.revision(), revision + 1);
    QCOMPARE(document.undoStack()->index(), undoIndex + 1);
    const auto points = document.lanePoints(0, kController);
    QCOMPARE(points.size(), std::size_t{2});
    const DocLanePoint &inserted = points[0].tick == kNodeTick ? points[1] : points[0];
    QCOMPARE(inserted.value, 64);

    // The Set-Value entry point shows the same node in displayed units, and
    // the typed bounds round-trip through the stored offset on both ends.
    QVERIFY(openCcNodePrompt(fixture, cc, inserted.tick, 64));
    QCOMPARE(chrome.valuePromptInitialValue(), 0);
    QTest::keySequence(window, QKeySequence(Qt::Key_Minus, Qt::Key_6, Qt::Key_4));
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    DocLanePoint point;
    QVERIFY(document.findLanePoint(0, kController, inserted.tick, &point));
    QCOMPARE(point.value, 0);
    QVERIFY(openCcNodePrompt(fixture, cc, inserted.tick, 0));
    QCOMPARE(chrome.valuePromptInitialValue(), -64);
    QTest::keySequence(window, QKeySequence(Qt::Key_6, Qt::Key_3));
    QTest::keyClick(window, Qt::Key_Return);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QVERIFY(document.findLanePoint(0, kController, inserted.tick, &point));
    QCOMPARE(point.value, 127);
    QCOMPARE(document.revision(), revision + 3);
    QCOMPARE(document.undoStack()->index(), undoIndex + 3);
}

void DrawerPresentationTest::valuePromptEscapeCancelsAndReturnsFocus()
{
    DrawerFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qUtf8Printable(error));
    DrawerChrome &chrome = fixture.chrome();
    QQuickWindow *const window = fixture.quick->quickWindow();
    QVERIFY(window);
    auto *const input = automationInput(fixture);
    QVERIFY(input);
    SongDocument &document = fixture.tab->document();
    document.addLanePoint(0, kController, kNodeTick, 64);
    pump();

    auto *const canvas = canvasOf(fixture);
    QVERIFY(canvas);
    QVERIFY2(activateParameter(fixture, *canvas,
                               {EditorAutomationRowKind::ControlChange, 0, kController}),
             "the Pan parameter label did not activate");
    QString diagnostics;
    const auto probe =
        selectionkey::AutomationProbe::locate(*fixture.view, input, 0, kController, &diagnostics);
    QVERIFY2(probe.has_value(), qUtf8Printable(diagnostics));
    QPoint scene;
    QVERIFY2(probe->emptyNodePoint(96, scene, &diagnostics), qUtf8Printable(diagnostics));

    const Snapshot before = snapshot(document);
    QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, scene);
    QTRY_VERIFY(automation_valueprompt::promptVisible(chrome));
    QQuickItem *const prompt = automation_valueprompt::focusedTextInput(*window);
    QVERIFY2(prompt, "the insertion prompt did not take active focus");

    QTest::keyClick(window, Qt::Key_Escape);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(snapshot(document), before);
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(*window, *input));
}

void DrawerPresentationTest::valuePromptFocusLossDocumentChangeAndPageHideCancel()
{
    DrawerFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qUtf8Printable(error));
    DrawerChrome &chrome = fixture.chrome();
    QQuickWindow *const window = fixture.quick->quickWindow();
    QVERIFY(window);
    auto *const input = automationInput(fixture);
    QVERIFY(input);
    SongDocument &document = fixture.tab->document();
    document.addLanePoint(0, kController, kNodeTick, 64);
    pump();
    const LaneHandle cc = ccLaneHandle(*canvasOf(fixture));
    QVERIFY(cc.valid());
    const Snapshot before = snapshot(document);

    // Focus loss cancels: forcing the roll band to take active focus closes
    // the pending prompt without a write.
    QVERIFY(openCcNodePrompt(fixture, cc, kNodeTick, 64));
    auto *const roll = fixture.quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineRollInput"));
    QVERIFY(roll);
    roll->forceActiveFocus(Qt::OtherFocusReason);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(snapshot(document), before);

    // A document change during the prompt cancels it: the only document delta
    // is the added point, and the pending node edit never commits.
    QVERIFY(openCcNodePrompt(fixture, cc, kNodeTick, 64));
    document.addLanePoint(0, kController, kNodeTick + 24, 32);
    pump();
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    DocLanePoint point;
    QVERIFY(document.findLanePoint(0, kController, kNodeTick, &point));
    QCOMPARE(point.value, 64);
    QVERIFY(document.findLanePoint(0, kController, kNodeTick + 24, &point));
    QCOMPARE(point.value, 32);
    QCOMPARE(document.lanePoints(0, kController).size(), std::size_t{2});
    QCOMPARE(document.revision(), before.revision + 1);
    QCOMPARE(document.undoStack()->index(), before.undoIndex + 1);
    const Snapshot afterLaneGrew = snapshot(document);

    // Quick-window deactivation cancels without a write.
    QVERIFY(openCcNodePrompt(fixture, cc, kNodeTick, 64));
    QEvent deactivation(QEvent::WindowDeactivate);
    QCoreApplication::sendEvent(window, &deactivation);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(snapshot(document), afterLaneGrew);

    // Hiding the automations page cancels without a write.
    QVERIFY(openCcNodePrompt(fixture, cc, kNodeTick, 64));
    fixture.view->setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(snapshot(document), afterLaneGrew);
}

void DrawerPresentationTest::valuePromptCancelAndLateAcceptWriteNothing()
{
    DrawerFixture fixture;
    QString error;
    QVERIFY2(fixture.create(error), qUtf8Printable(error));
    DrawerChrome &chrome = fixture.chrome();
    QQuickWindow *const window = fixture.quick->quickWindow();
    QVERIFY(window);
    auto *const input = automationInput(fixture);
    QVERIFY(input);
    SongDocument &document = fixture.tab->document();
    document.addLanePoint(0, kController, kNodeTick, 64);
    pump();
    const LaneHandle cc = ccLaneHandle(*canvasOf(fixture));
    QVERIFY(cc.valid());
    const Snapshot before = snapshot(document);

    // The chrome cancel invokable - the Escape path's entry point - clears the
    // pending edit, writes nothing, and returns focus to the automation input.
    QVERIFY(openCcNodePrompt(fixture, cc, kNodeTick, 64));
    QMetaObject::invokeMethod(&chrome, "cancelNodeValuePrompt");
    QTRY_VERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(snapshot(document), before);
    QTRY_VERIFY(automation_valueprompt::inputOwnsFocus(*window, *input));

    // A late accept with no pending edit is a no-op: no write and the prompt
    // stays closed.
    AutomationCanvas *const canvas = canvasOf(fixture);
    QVERIFY(canvas);
    canvas->acceptNodeValuePrompt(50);
    QVERIFY(!automation_valueprompt::promptVisible(chrome));
    QCOMPARE(snapshot(document), before);
}
