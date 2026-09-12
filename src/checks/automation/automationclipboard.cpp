#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <limits>
#include <utility>

#include <QCoreApplication>
#include <QQuickItem>

#include "checks/quickpopupguard.h"
#include "checks/support/timelinequickcheck.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"

#include "checks/automation/automationquickmenu.h"

namespace {
constexpr uint8_t kLfoController = 21;
constexpr Tick kTempoCopyTick = 96;
constexpr Tick kCcCopyTick = 144;
using CanvasMenuAction = AutomationCanvas::CanvasMenuAction;

using automation_quick::AutomationMenu;
using automation_quick::waitForAutomationMenu;

// The rendered parameter label for a catalog index, or null.
QQuickItem *parameterLabelItem(SongTab &songTab, int index)
{
    QQuickItem *const root = songTab.view().quickView()->rootObject();
    return root ? checks::support::visualDescendant(
                      root, QStringLiteral("automationParameterTab%1").arg(index))
                : nullptr;
}

// Opens the shared lane menu through the real rendered parameter label: the
// label's context-menu route activates the target parameter first, then opens
// its menu at the label. Returns the diagnostic-bearing menu either way.
AutomationMenu openLabelMenu(SongTab &songTab, AutomationCanvas &canvas,
                             const EditorAutomationRowId &row, QString why)
{
    AutomationMenu menu;
    menu.diagnostic = std::move(why);
    const int index = checks::support::automationParameterIndex(canvas, row);
    QQuickItem *const label = index >= 0 ? parameterLabelItem(songTab, index) : nullptr;
    if (!label) {
        menu.diagnostic = QStringLiteral("the parameter label never rendered");
        return menu;
    }
    QTest::mouseClick(
        label->window(), Qt::RightButton, Qt::NoModifier,
        label->mapToScene(QPointF(label->width() / 2.0, label->height() / 2.0)).toPoint());
    return waitForAutomationMenu(songTab.view(), std::move(menu.diagnostic));
}

} // namespace

void AutomationEditingTest::clipboardCrossLanePasteClamps()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    AutomationCanvas *const canvas = automationPage.canvas();
    QVERIFY(canvas);
    QVERIFY(activateParameter({EditorAutomationRowKind::Tempo, 0, 0}));
    const quick_popup::PromptGuard guard(songTab.view());

    songTab.document().applyTempoEdit(TempoEdit{
        .remove = songTab.document().tempoPoints(),
        .add = {{kTempoCopyTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(300)}}});
    songTab.document().writeLanePoints(0, kLfoController, 0, CoreTimeDefaults::kNoTick,
                                       {{kTempoCopyTick, 96}});
    QCoreApplication::processEvents();

    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    const EditorAutomationRowId lfoRow{EditorAutomationRowKind::ControlChange, 0, kLfoController};
    // Copy and Paste are typed rows; the pick closes the menu before action
    // activation, and the clipboard command then dispatches synchronously.
    const auto clickRow = [](const AutomationMenu &menu, CanvasMenuAction action) {
        return quick_popup::clickMenuRow(*menu.session, menu.model->rowForId(int(action)));
    };

    const AutomationMenu copyTempo = openLabelMenu(
        songTab, *canvas, tempoRow, "the tempo label right-press did not open the shared menu");
    QVERIFY2(copyTempo.session, qUtf8Printable(copyTempo.diagnostic));
    QVERIFY2(clickRow(copyTempo, CanvasMenuAction::Copy), "the Copy tempo row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!copyTempo.session->isOpen(), "the Copy tempo pick left the shared menu open");

    const AutomationMenu pasteCc = openLabelMenu(
        songTab, *canvas, lfoRow, "the CC label right-press did not open the shared menu");
    QVERIFY2(clickRow(pasteCc, CanvasMenuAction::Paste), "the Paste CC row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!pasteCc.session->isOpen(), "the Paste CC pick left the shared menu open");
    const auto clampedCc = songTab.document().lanePoints(0, kLfoController);
    QCOMPARE(clampedCc.size(), std::size_t{1});
    QCOMPARE(clampedCc.front().tick, kTempoCopyTick);
    QCOMPARE(clampedCc.front().value, 127);

    songTab.document().writeLanePoints(0, kLfoController, 0, CoreTimeDefaults::kNoTick,
                                       {{kCcCopyTick, 0}});
    QCoreApplication::processEvents();

    const AutomationMenu copyCc = openLabelMenu(
        songTab, *canvas, lfoRow, "the CC label right-press did not reopen the shared menu");
    QVERIFY2(copyCc.session, qUtf8Printable(copyCc.diagnostic));
    QVERIFY2(clickRow(copyCc, CanvasMenuAction::Copy), "the Copy CC row was not clickable");
    QCoreApplication::processEvents();
    QVERIFY2(!copyCc.session->isOpen(), "the Copy CC pick left the shared menu open");

    const AutomationMenu pasteTempo = openLabelMenu(
        songTab, *canvas, tempoRow, "the tempo label right-press did not reopen the shared menu");
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
