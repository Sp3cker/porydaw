#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <limits>
#include <utility>

#include <QCoreApplication>

#include "checks/quickpopupguard.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"

#include "checks/automation/automationquickmenu.h"

namespace {
constexpr uint8_t kLfoController = 21;
constexpr uint64_t kTempoCopyTick = 96;
constexpr uint64_t kCcCopyTick = 144;
using CanvasMenuAction = AutomationCanvas::CanvasMenuAction;

using automation_quick::AutomationMenu;
using automation_quick::waitForAutomationMenu;

} // namespace

void AutomationEditingTest::clipboardCrossLanePasteClamps()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    QVERIFY(expandTempo());
    const quick_popup::PromptGuard guard(songTab.view());

    songTab.document().applyTempoEdit(TempoEdit{
        .remove = songTab.document().tempoPoints(),
        .add = {{kTempoCopyTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(300)}}});
    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kTempoCopyTick, 96}});
    QCoreApplication::processEvents();

    const LaneHandle lfo = findRow({EditorAutomationRowKind::ControlChange, 0, kLfoController});
    QVERIFY(lfo.valid());
    const QRect tempoHeader = automationPage.canvas()->pinnedTempoRect();
    const QPointF tempoGutter{qreal(layout::space(layout::Space::One)),
                              qreal(tempoHeader.center().y())};
    const QPointF lfoGutter{qreal(layout::space(layout::Space::One)),
                            qreal(laneBody(lfo).center().y())};
    // Copy and Paste are typed rows; the pick closes the menu before action
    // activation, and the clipboard command then dispatches synchronously.
    const auto openLaneMenu = [&](const QPointF &gutter, QString why) {
        mousePress(Qt::RightButton, automationGutterWindowPoint(gutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(gutter));
        return waitForAutomationMenu(songTab.view(), std::move(why));
    };
    const auto clickRow = [](const AutomationMenu &menu, CanvasMenuAction action) {
        return quick_popup::clickMenuRow(*menu.session, menu.model->rowForId(int(action)));
    };

    const AutomationMenu copyTempo =
        openLaneMenu(tempoGutter, "the tempo right-press did not open the shared menu");
    QVERIFY2(copyTempo.session, qUtf8Printable(copyTempo.diagnostic));
    QVERIFY2(clickRow(copyTempo, CanvasMenuAction::Copy), "the Copy tempo row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!copyTempo.session->isOpen(), "the Copy tempo pick left the shared menu open");

    const AutomationMenu pasteCc =
        openLaneMenu(lfoGutter, "the CC lane right-press did not open the shared menu");
    QVERIFY2(pasteCc.session, qUtf8Printable(pasteCc.diagnostic));
    QVERIFY2(clickRow(pasteCc, CanvasMenuAction::Paste), "the Paste CC row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!pasteCc.session->isOpen(), "the Paste CC pick left the shared menu open");
    const auto clampedCc = songTab.document().lanePoints(0, kLfoController);
    QCOMPARE(clampedCc.size(), std::size_t{1});
    QCOMPARE(clampedCc.front().tick, kTempoCopyTick);
    QCOMPARE(clampedCc.front().value, 127);

    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kCcCopyTick, 0}});
    QCoreApplication::processEvents();

    const AutomationMenu copyCc =
        openLaneMenu(lfoGutter, "the CC lane right-press did not reopen the shared menu");
    QVERIFY2(copyCc.session, qUtf8Printable(copyCc.diagnostic));
    QVERIFY2(clickRow(copyCc, CanvasMenuAction::Copy), "the Copy CC row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!copyCc.session->isOpen(), "the Copy CC pick left the shared menu open");

    const AutomationMenu pasteTempo =
        openLaneMenu(tempoGutter, "the tempo right-press did not reopen the shared menu");
    QVERIFY2(pasteTempo.session, qUtf8Printable(pasteTempo.diagnostic));
    QVERIFY2(clickRow(pasteTempo, CanvasMenuAction::Paste),
             "the Paste tempo row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!pasteTempo.session->isOpen(), "the Paste tempo pick left the shared menu open");
    const auto clampedTempo = songTab.document().tempoPoints();
    QCOMPARE(clampedTempo.size(), std::size_t{1});
    QCOMPARE(clampedTempo.front().tick, kCcCopyTick);
    QCOMPARE(clampedTempo.front().microsecondsPerQuarterNote,
             CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(CoreTimeDefaults::kMinTempoBpm));
}
