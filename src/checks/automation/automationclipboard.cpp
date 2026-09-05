#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <limits>

#include <QCoreApplication>
#include <QMenu>

#include "checks/automation/automationmodalguard.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"

namespace {

constexpr uint8_t kLfoController = 21;
constexpr uint64_t kTempoCopyTick = 96;
constexpr uint64_t kCcCopyTick = 144;

using automation_modal::findMenuAction;
using automation_modal::MenuInteractionResult;
using automation_modal::scheduleMenuInteraction;

using TriggerResult = MenuInteractionResult;

} // namespace

void AutomationEditingTest::clipboardCrossLanePasteClamps()
{
    SongTab &songTab = tab();
    AutomationPage &automationPage = page();
    QVERIFY(expandTempo());

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

    TriggerResult copyTempo;
    {
        const auto interaction = scheduleMenuInteraction(
            copyTempo, [](QMenu &menu) { return findMenuAction(menu, QStringLiteral("Copy")); });
        mousePress(Qt::RightButton, automationGutterWindowPoint(tempoGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(tempoGutter));
    }
    QVERIFY2(copyTempo.opened, qPrintable(copyTempo.diagnostic));
    QCOMPARE(copyTempo.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(copyTempo.actionFound, qPrintable(copyTempo.diagnostic));
    QVERIFY2(copyTempo.actionEnabled, qPrintable(copyTempo.diagnostic));
    QVERIFY2(copyTempo.actionClicked, qPrintable(copyTempo.diagnostic));

    TriggerResult pasteCc;
    {
        const auto interaction = scheduleMenuInteraction(pasteCc, [](QMenu &menu) {
            return findMenuAction(menu, QStringLiteral("Paste CC lane (replace)"));
        });
        mousePress(Qt::RightButton, automationGutterWindowPoint(lfoGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(lfoGutter));
    }
    QVERIFY2(pasteCc.opened, qPrintable(pasteCc.diagnostic));
    QCOMPARE(pasteCc.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(pasteCc.actionFound, qPrintable(pasteCc.diagnostic));
    QVERIFY2(pasteCc.actionEnabled, qPrintable(pasteCc.diagnostic));
    QVERIFY2(pasteCc.actionClicked, qPrintable(pasteCc.diagnostic));
    const auto clampedCc = songTab.document().lanePoints(0, kLfoController);
    QCOMPARE(clampedCc.size(), std::size_t{1});
    QCOMPARE(clampedCc.front().tick, kTempoCopyTick);
    QCOMPARE(clampedCc.front().value, 127);

    songTab.document().writeLanePoints(0, kLfoController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kCcCopyTick, 0}});
    QCoreApplication::processEvents();

    TriggerResult copyCc;
    {
        const auto interaction = scheduleMenuInteraction(copyCc, [](QMenu &menu) {
            return findMenuAction(menu, QStringLiteral("Copy CC lane"));
        });
        mousePress(Qt::RightButton, automationGutterWindowPoint(lfoGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(lfoGutter));
    }
    QVERIFY2(copyCc.opened, qPrintable(copyCc.diagnostic));
    QCOMPARE(copyCc.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(copyCc.actionFound, qPrintable(copyCc.diagnostic));
    QVERIFY2(copyCc.actionEnabled, qPrintable(copyCc.diagnostic));
    QVERIFY2(copyCc.actionClicked, qPrintable(copyCc.diagnostic));

    TriggerResult pasteTempo;
    {
        const auto interaction = scheduleMenuInteraction(
            pasteTempo, [](QMenu &menu) { return findMenuAction(menu, QStringLiteral("Paste")); });
        mousePress(Qt::RightButton, automationGutterWindowPoint(tempoGutter));
        mouseRelease(Qt::RightButton, automationGutterWindowPoint(tempoGutter));
    }
    QVERIFY2(pasteTempo.opened, qPrintable(pasteTempo.diagnostic));
    QCOMPARE(pasteTempo.parentWidget, static_cast<QWidget *>(&songTab.view()));
    QVERIFY2(pasteTempo.actionFound, qPrintable(pasteTempo.diagnostic));
    QVERIFY2(pasteTempo.actionEnabled, qPrintable(pasteTempo.diagnostic));
    QVERIFY2(pasteTempo.actionClicked, qPrintable(pasteTempo.diagnostic));
    const auto clampedTempo = songTab.document().tempoPoints();
    QCOMPARE(clampedTempo.size(), std::size_t{1});
    QCOMPARE(clampedTempo.front().tick, kCcCopyTick);
    QCOMPARE(clampedTempo.front().microsecondsPerQuarterNote,
             CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(CoreTimeDefaults::kMinTempoBpm));
}
