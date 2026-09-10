// Regression coverage for the automation canvas' CC-lane delete confirmation:
// the Quick form that replaced the nonempty-lane QMessageBox on the shared
// canvas popup session. Every scenario drives the real rendered surface — the
// parameter label right-press, the typed Delete-events row, and the form's own
// buttons and keys — and reads the document, the undo stack, and the
// parameter catalog as oracles. The confirmation invokables are never called
// directly.

#include "checks/automation/tst_automationediting.h"

#include <QtTest>

#include <algorithm>
#include <limits>
#include <utility>
#include <variant>
#include <vector>

#include "checks/automation/automationquickmenu.h"
#include "checks/quickpopupguard.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/timeruler.h"
#include <QCoreApplication>
#include <QPointer>
#include <QQuickItem>

namespace {

using automation_quick::AutomationMenu;
using automation_quick::waitForAutomationMenu;

using CanvasMenuAction = AutomationCanvas::CanvasMenuAction;

// The rendered parameter label for a catalog index, or null.
QQuickItem *parameterLabelItem(SongTab &songTab, int index)
{
    QQuickItem *const root = songTab.view().quickView()->rootObject();
    return root ? root->findChild<QQuickItem *>(
                      QStringLiteral("automationParameterTab%1").arg(index))
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
    const int index = canvas.parameterIndex(row);
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

// The fixture's pilot lane: CC 10 carries two points, and the pilot song's
// volume lane carries one point a delete of CC 10 must never touch.
constexpr uint8_t kController = 10;
constexpr uint64_t kFirstPointTick = 48;
constexpr uint64_t kSecondPointTick = 96;
constexpr int kFirstPointValue = 40;
constexpr int kSecondPointValue = 100;
constexpr uint64_t kVolumeTick = 192;
constexpr int kInterveningVolumeValue = 90;
// The stale-document rewrite: another writer replaces the lane's content while
// the confirmation is pending.
constexpr uint64_t kRewrittenTick = 288;
constexpr int kRewrittenValue = 77;

int volumeLaneValue(SongTab &songTab, uint64_t tick)
{
    DocLanePoint point;
    if (!songTab.document().findLanePoint(0, CoreTimeDefaults::kCcVolume, tick, &point))
        return -1;
    return point.value;
}

// The integer quantities the confirmation message advertises, parsed from the
// live bridge text: a wording-agnostic view of the displayed count.
std::vector<int> displayedQuantities(const QString &message)
{
    std::vector<int> quantities;
    int begin = -1;
    for (int index = 0; index <= message.size(); ++index) {
        const bool digit = index < message.size() && message.at(index).isDigit();
        if (digit && begin < 0)
            begin = index;
        if (!digit && begin >= 0) {
            quantities.push_back(message.mid(begin, index - begin).toInt());
            begin = -1;
        }
    }
    return quantities;
}

} // namespace

AutomationEditingTest::CcDeletePrompt
AutomationEditingTest::openCcDeletePrompt(const EditorAutomationRowId &row, QString diagnostic)
{
    CcDeletePrompt prompt;
    prompt.diagnostic = std::move(diagnostic);
    AutomationCanvas *const canvas = m_page ? page().canvas() : nullptr;
    if (!canvas)
        return prompt;

    const AutomationMenu menu = openLabelMenu(tab(), *canvas, row, prompt.diagnostic);
    if (!menu.session || !menu.model)
        return prompt;

    const int removeRow = menu.model->rowForId(int(CanvasMenuAction::RemoveLane));
    if (removeRow < 0) {
        prompt.diagnostic = QStringLiteral("the lane menu offered no RemoveLane row");
        return prompt;
    }
    if (!quick_popup::clickMenuRow(*menu.session, removeRow)) {
        prompt.diagnostic = QStringLiteral("the RemoveLane row did not receive a real click");
        return prompt;
    }

    // The pick closes the menu and opens the confirmation as the session's
    // form content; the wait only passes once the root and both named buttons
    // render on the live content.
    const QPointer<songview::QuickPopupSession> live{menu.session};
    if (!QTest::qWaitFor([&live, &prompt] {
            if (!live || !live->isOpen())
                return false;
            prompt.root = quick_popup::promptItem(*live, QLatin1String("ccDeleteConfirm"));
            prompt.acceptButton = quick_popup::promptItem(*live, QLatin1String("acceptButton"));
            prompt.cancelButton = quick_popup::promptItem(*live, QLatin1String("cancelButton"));
            return prompt.root && prompt.acceptButton && prompt.cancelButton;
        }))
        return prompt;
    prompt.session = live.data();
    prompt.diagnostic.clear();
    return prompt;
}

void AutomationEditingTest::ccDeletePromptAcceptDeletesOnlyTargetLaneAndUndoRestores()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    const EditorAutomationRowId volumeRow{EditorAutomationRowKind::ControlChange, 0,
                                          CoreTimeDefaults::kCcVolume};
    QVERIFY(findRow(ccRow).valid());
    QVERIFY(findRow(volumeRow).valid());

    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    const CcDeletePrompt opened = openCcDeletePrompt(
        ccRow, QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));

    // While the question is on screen nothing is written: both lane points and
    // the sibling volume point stay exact.
    QVERIFY(frozenDocumentState(documentChanged.count()) == frozen);
    QCOMPARE(laneValue(kFirstPointTick), kFirstPointValue);
    QCOMPARE(laneValue(kSecondPointTick), kSecondPointValue);
    QCOMPARE(volumeLaneValue(songTab, kVolumeTick),
             CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume));

    // Cancel holds the initial focus; accepting is a real click on Delete.
    QTRY_VERIFY2(quick_popup::inputHasActiveFocus(quickWindow(), QLatin1String("cancelButton")),
                 "the confirmation did not give Cancel the initial focus");
    QVERIFY2(quick_popup::clickPromptButton(*opened.session, QLatin1String("acceptButton")),
             "the Delete button never rendered in the confirmation form");

    // Exactly one transaction removes the intended lane's written events: one
    // revision and one undo step, and the parameter label stays.
    QCOMPARE(documentChanged.count(), frozen.documentChanges + 1);
    QCOMPARE(songTab.document().revision(), frozen.revision + 1);
    QCOMPARE(songTab.document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(songTab.document().undoStack()->index(), frozen.undoIndex + 1);
    QVERIFY(songTab.document().smf().write() != frozen.smf);
    DocLanePoint point;
    QVERIFY(!songTab.document().findLanePoint(0, kController, kFirstPointTick, &point));
    QVERIFY(!songTab.document().findLanePoint(0, kController, kSecondPointTick, &point));
    // The parameter label persists and stays selectable; only its written
    // events are gone.
    QVERIFY2(activateParameter(volumeRow), "the volume label was no longer selectable");
    QVERIFY2(activateParameter(ccRow), "the cleared lane parameter was no longer selectable");
    const LaneHandle retained = findRow(ccRow);
    QVERIFY(retained.valid());
    QVERIFY(!laneBody(retained).isEmpty());
    QVERIFY(findRow(volumeRow).valid());
    QVERIFY(songTab.document().findLanePoint(0, CoreTimeDefaults::kCcVolume, kVolumeTick, &point));
    QCOMPARE(point.value, CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume));

    // Accept consumed the prompt and returned the band focus.
    QTRY_VERIFY2(opened.session->contentItem() == nullptr,
                 "accepting left confirmation content on the session");
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "accepting did not return focus to the automation band");

    // Undo restores the deleted events exactly; the sibling never moved.
    QVERIFY(songTab.history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(songTab.history().requestUndo()));
    QCOMPARE(laneValue(kFirstPointTick), kFirstPointValue);
    QCOMPARE(laneValue(kSecondPointTick), kSecondPointValue);
    QCOMPARE(volumeLaneValue(songTab, kVolumeTick),
             CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume));
    QCOMPARE(songTab.document().smf().write(), frozen.smf);
}

void AutomationEditingTest::ccDeletePromptCancelButtonLeavesDocumentUntouched()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    const CcDeletePrompt opened = openCcDeletePrompt(
        {EditorAutomationRowKind::ControlChange, 0, kController},
        QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));

    QVERIFY2(quick_popup::clickPromptButton(*opened.session, QLatin1String("cancelButton")),
             "the Cancel button never rendered in the confirmation form");
    QTRY_VERIFY2(!opened.session->isOpen(), "Cancel did not dismiss the confirmation");
    QTRY_VERIFY2(opened.session->contentItem() == nullptr,
                 "Cancel left confirmation content on the session");

    QVERIFY(frozenDocumentState(documentChanged.count()) == frozen);
    QCOMPARE(laneValue(kFirstPointTick), kFirstPointValue);
    QCOMPARE(laneValue(kSecondPointTick), kSecondPointValue);
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "Cancel did not restore the automation band focus");
}

void AutomationEditingTest::ccDeletePromptEscapeLeavesDocumentUntouched()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    const CcDeletePrompt opened = openCcDeletePrompt(
        {EditorAutomationRowKind::ControlChange, 0, kController},
        QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));

    keyClick(Qt::Key_Escape);
    QTRY_VERIFY2(!opened.session->isOpen(), "Escape did not dismiss the confirmation");
    QTRY_VERIFY2(opened.session->contentItem() == nullptr,
                 "Escape left confirmation content on the session");

    QVERIFY(frozenDocumentState(documentChanged.count()) == frozen);
    QCOMPARE(laneValue(kFirstPointTick), kFirstPointValue);
    QCOMPARE(laneValue(kSecondPointTick), kSecondPointValue);
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "Escape did not restore the automation band focus");
}

void AutomationEditingTest::ccDeletePromptOutsideRightPressClosesWithoutRetarget()
{
    SongTab &songTab = tab();
    AutomationCanvas *const canvas = page().canvas();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};
    const EditorAutomationRowId volumeRow{EditorAutomationRowKind::ControlChange, 0,
                                          CoreTimeDefaults::kCcVolume};

    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    const CcDeletePrompt opened =
        openCcDeletePrompt(ccRow, QStringLiteral("the RemoveLane pick did not open the delete "
                                                 "confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));

    // The witness sits on the volume parameter's label: a leaked or retargeted
    // press would open that label's menu right there.
    QQuickItem *const content = opened.session->contentItem();
    QVERIFY(content);
    QQuickItem *const volumeLabel = parameterLabelItem(songTab, canvas->parameterIndex(volumeRow));
    QVERIFY2(volumeLabel, "the volume label never rendered");
    const QPoint outside =
        volumeLabel->mapToScene(QPointF(volumeLabel->width() / 2.0, volumeLabel->height() / 2.0))
            .toPoint();
    QVERIFY2(!content->contains(content->mapFromScene(QPointF(outside))),
             "the outside witness did not reach the popup underlay");

    QTest::mousePress(m_quickWindow, Qt::RightButton, Qt::NoModifier, outside);
    QCoreApplication::processEvents();
    QVERIFY2(!opened.session->isOpen(), "an outside right press did not dismiss the confirmation");
    // Release over the plot, away from every label, so the release itself can
    // never open a replacement menu.
    const LaneHandle cc = findRow(ccRow);
    QVERIFY(cc.valid());
    QTRY_VERIFY2(!laneBody(cc).isEmpty(), "the lane plot never rendered");
    QTest::mouseRelease(m_quickWindow, Qt::RightButton, Qt::NoModifier,
                        automationWindowPoint(QPointF(laneBody(cc).center())));
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const session = quick_popup::popupSession(songTab.view());
    QVERIFY2(session && !session->isOpen(), "the swallowed outside right release opened a popup");
    checks::support::pumpQuick();
    QVERIFY2(!session->isOpen(), "the outside dismissal reopened or retargeted the lane menu");

    QVERIFY(frozenDocumentState(documentChanged.count()) == frozen);
    QCOMPARE(laneValue(kFirstPointTick), kFirstPointValue);
    QCOMPARE(laneValue(kSecondPointTick), kSecondPointValue);
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "the outside dismissal did not restore the automation band focus");
}

void AutomationEditingTest::ccDeletePromptInitialReturnCancelsWithoutNavigation()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    const CcDeletePrompt opened = openCcDeletePrompt(
        {EditorAutomationRowKind::ControlChange, 0, kController},
        QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));
    QTRY_VERIFY2(quick_popup::inputHasActiveFocus(quickWindow(), QLatin1String("cancelButton")),
                 "the confirmation did not give Cancel the initial focus");

    // A bare Return on the untouched form must cancel it, not navigate.
    keyClick(Qt::Key_Return);
    QTRY_VERIFY2(!opened.session->isOpen(), "Return did not dismiss the confirmation");
    QTRY_VERIFY2(opened.session->contentItem() == nullptr,
                 "Return left confirmation content on the session");

    QVERIFY(frozenDocumentState(documentChanged.count()) == frozen);
    QCOMPARE(laneValue(kFirstPointTick), kFirstPointValue);
    QCOMPARE(laneValue(kSecondPointTick), kSecondPointValue);
    QTRY_VERIFY2(songTab.view().quickView()->focusedBand() == songview::TimelineBand::Automation,
                 "the Return cancellation did not restore the automation band focus");
}

void AutomationEditingTest::ccDeletePromptStaleDocumentCannotDeleteTarget()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());

    const CcDeletePrompt opened = openCcDeletePrompt(
        {EditorAutomationRowKind::ControlChange, 0, kController},
        QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));
    QTRY_VERIFY2(quick_popup::inputHasActiveFocus(quickWindow(), QLatin1String("cancelButton")),
                 "the confirmation did not give Cancel the initial focus");

    // Press the real Delete button and slip an external rewrite of the same
    // lane under the pressed pointer: the open-time snapshot goes stale, and
    // the synchronous rebuild may legitimately cancel the pending prompt
    // before the release arrives.
    QVERIFY(opened.acceptButton);
    const QPoint acceptCenter = quick_popup::itemCenter(*opened.acceptButton);
    QTest::mousePress(opened.session->window(), Qt::LeftButton, Qt::NoModifier, acceptCenter);
    QCoreApplication::processEvents();
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kRewrittenTick, kRewrittenValue}});
    songTab.document().writeLanePoints(0, CoreTimeDefaults::kCcVolume, 0,
                                       std::numeric_limits<uint64_t>::max(),
                                       {{kVolumeTick, kInterveningVolumeValue}});
    QCoreApplication::processEvents();
    const uint64_t revisionAfterWrite = songTab.document().revision();
    const int undoCountAfterWrite = songTab.document().undoStack()->count();
    const int undoIndexAfterWrite = songTab.document().undoStack()->index();
    const QByteArray smfAfterWrite = songTab.document().smf().write();

    QTest::mouseRelease(opened.session->window(), Qt::LeftButton, Qt::NoModifier, acceptCenter);
    QCoreApplication::processEvents();
    checks::support::pumpQuick();

    // Whether the rebuild cancelled the pending prompt or the release ran a
    // stale accept, the outcome is identical: the rewrite stands alone, and
    // neither the rewritten target nor the sibling loses content.
    QVERIFY2(!opened.session->isOpen(), "the stale request left a popup open");
    songview::QuickPopupSession *const session = quick_popup::popupSession(songTab.view());
    QVERIFY2(session && !session->isOpen(), "the stale request reopened a popup");
    QVERIFY(quick_popup::promptItem(*session, QLatin1String("ccDeleteConfirm")) == nullptr);
    QCOMPARE(songTab.document().revision(), revisionAfterWrite);
    QCOMPARE(songTab.document().undoStack()->count(), undoCountAfterWrite);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexAfterWrite);
    QCOMPARE(songTab.document().smf().write(), smfAfterWrite);
    QCOMPARE(laneValue(kRewrittenTick), kRewrittenValue);
    QCOMPARE(laneValue(kFirstPointTick), -1);
    QCOMPARE(laneValue(kSecondPointTick), -1);
    QCOMPARE(volumeLaneValue(songTab, kVolumeTick), kInterveningVolumeValue);
    QVERIFY(findRow({EditorAutomationRowKind::ControlChange, 0, kController}).valid());
    QVERIFY(
        findRow({EditorAutomationRowKind::ControlChange, 0, CoreTimeDefaults::kCcVolume}).valid());
}

void AutomationEditingTest::ccDeletePromptInvalidationSparesForeignPopup()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId ccRow{EditorAutomationRowKind::ControlChange, 0, kController};

    const CcDeletePrompt opened = openCcDeletePrompt(
        ccRow, QStringLiteral("the RemoveLane pick did not open the delete confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));
    QTRY_VERIFY2(quick_popup::inputHasActiveFocus(quickWindow(), QLatin1String("cancelButton")),
                 "the confirmation did not give Cancel the initial focus");

    // The confirmation's underlay absorbs every press, so no user input can
    // hand the shared session to another owner while it is open. The ruler's
    // real production open method performs the takeover: the pending prompt
    // is invalidated and the foreign division menu publishes with real rows.
    QQuickItem *const root = songTab.view().quickView()->rootObject();
    QVERIFY(root);
    auto *const rulerInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    QVERIFY(rulerInput);
    auto *const ruler = dynamic_cast<songview::TimeRuler *>(rulerInput->interaction());
    QVERIFY(ruler);
    QQuickItem *const division =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    QVERIFY(division);
    ruler->openDivisionMenu(
        division->mapToScene(QPointF(division->width() / 2.0, division->height() / 2.0)));

    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(songTab.view())};
    QVERIFY(live);
    QVERIFY2(QTest::qWaitFor([&live] {
                 QQuickItem *const panel = quick_popup::menuPanel(*live);
                 return live->isOpen() && panel && quick_popup::menuModel(*panel) != nullptr;
             }),
             "the foreign ruler menu did not publish over the pending confirmation");
    QVERIFY(live->contentItem() == nullptr);
    QVERIFY(quick_popup::promptItem(*live, QLatin1String("ccDeleteConfirm")) == nullptr);

    // A canvas-only document rewrite must not disturb the foreign menu.
    songTab.document().writeLanePoints(0, kController, 0, std::numeric_limits<uint64_t>::max(),
                                       {{kRewrittenTick, kRewrittenValue}});
    QCoreApplication::processEvents();
    checks::support::pumpQuick();
    QVERIFY2(live->isOpen(), "the canvas rewrite cancelled the foreign ruler menu");
    QVERIFY(quick_popup::menuPanel(*live));
    const uint64_t revisionAfterWrite = songTab.document().revision();
    const int undoCountAfterWrite = songTab.document().undoStack()->count();
    const int undoIndexAfterWrite = songTab.document().undoStack()->index();
    const QByteArray smfAfterWrite = songTab.document().smf().write();

    // The foreign menu keeps working: a real row pick changes the grid.
    const int currentDenom = songTab.view().viewState().gridMinDenom;
    const int targetDenom = currentDenom == 8 ? 16 : 8;
    const int targetRow =
        quick_popup::menuModel(*quick_popup::menuPanel(*live))->rowForId(targetDenom);
    QVERIFY2(targetRow >= 0, "the foreign division menu omitted the chosen denominator");
    QVERIFY2(quick_popup::clickMenuRow(*live, targetRow),
             "the foreign division row did not receive a real click");
    QCoreApplication::processEvents();
    QVERIFY2(!live->isOpen(), "the foreign division pick left the shared menu open");
    QCOMPARE(songTab.view().viewState().gridMinDenom, targetDenom);

    // Focus belongs to the invoking ruler control, and its keyboard path
    // still works: Return reopens the foreign menu.
    QTRY_VERIFY2(division->hasActiveFocus(),
                 "the foreign pick did not return focus to the ruler control");
    keyClick(Qt::Key_Return);
    QVERIFY2(QTest::qWaitFor([&live] {
                 QQuickItem *const panel = quick_popup::menuPanel(*live);
                 return live->isOpen() && panel && quick_popup::menuModel(*panel) != nullptr;
             }),
             "Return on the focused ruler control did not reopen the foreign menu");

    // The takeover-invalidated prompt must never surface late or delete:
    // exactly the external rewrite happened.
    live->cancel();
    QCoreApplication::processEvents();
    QVERIFY(!live->isOpen());
    checks::support::pumpQuick();
    QVERIFY(!live->isOpen());
    QVERIFY(quick_popup::promptItem(*live, QLatin1String("ccDeleteConfirm")) == nullptr);
    QCOMPARE(songTab.document().revision(), revisionAfterWrite);
    QCOMPARE(songTab.document().undoStack()->count(), undoCountAfterWrite);
    QCOMPARE(songTab.document().undoStack()->index(), undoIndexAfterWrite);
    QCOMPARE(songTab.document().smf().write(), smfAfterWrite);
    QCOMPARE(laneValue(kRewrittenTick), kRewrittenValue);
    QCOMPARE(laneValue(kFirstPointTick), -1);
    QCOMPARE(laneValue(kSecondPointTick), -1);
    QCOMPARE(volumeLaneValue(songTab, kVolumeTick),
             CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume));
    QVERIFY(findRow(ccRow).valid());
}

// A volume lane showing only the synthetic engine-default node carries no
// written events: its Delete pick dispatches nothing — no confirmation and
// no write — and the parameter label stays.
void AutomationEditingTest::ccDeletePromptSyntheticOnlyVolumeSkipsConfirmation()
{
    SongTab &songTab = tab();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId volumeRow{EditorAutomationRowKind::ControlChange, 0,
                                          CoreTimeDefaults::kCcVolume};
    QVERIFY(findRow(volumeRow).valid());

    // Clearing the staged written point leaves the default-visible row with
    // just its synthetic tick-0 node.
    songTab.document().writeLanePoints(0, CoreTimeDefaults::kCcVolume, 0,
                                       std::numeric_limits<uint64_t>::max(), {});
    QCoreApplication::processEvents();
    QVERIFY(songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume).empty());
    const LaneHandle volume = findRow(volumeRow);
    QVERIFY(volume.valid());
    QVERIFY(!laneBody(volume).isEmpty());

    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    AutomationCanvas *const canvas = page().canvas();
    const AutomationMenu menu =
        openLabelMenu(songTab, *canvas, volumeRow,
                      QStringLiteral("the volume label right-press did not open the shared menu"));
    QVERIFY2(menu.session && menu.model, qUtf8Printable(menu.diagnostic));
    const int removeRow = menu.model->rowForId(int(CanvasMenuAction::RemoveLane));
    QVERIFY2(removeRow >= 0, "the synthetic-only volume menu offered no RemoveLane row");
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, removeRow),
             "the RemoveLane row did not receive a real click");
    QCoreApplication::processEvents();

    // The empty dispatch closes the pick without a question and without a
    // write; the parameter label stays.
    QVERIFY2(!menu.session->isOpen(), "the synthetic-only volume pick left a popup open");
    checks::support::pumpQuick();
    songview::QuickPopupSession *const session = quick_popup::popupSession(songTab.view());
    QVERIFY2(session && !session->isOpen(),
             "the synthetic-only volume pick opened a delete confirmation");
    QVERIFY2(quick_popup::promptItem(*session, QLatin1String("ccDeleteConfirm")) == nullptr,
             "the synthetic-only volume pick rendered a delete confirmation");
    QVERIFY(findRow(volumeRow).valid());
    QVERIFY(!laneBody(findRow(volumeRow)).isEmpty());
    QVERIFY(frozenDocumentState(documentChanged.count()) == frozen);
    QVERIFY(songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume).empty());
}

// The confirmation advertises document-written events only. The staged volume
// parameter carries one written point beside its synthetic tick-0 node, so
// the displayed count must be the written count; a real delete then removes
// the written events while the parameter stays available, and undo restores
// them.
void AutomationEditingTest::ccDeletePromptDefaultLaneWrittenCountExcludesSynthetic()
{
    SongTab &songTab = tab();
    AutomationCanvas *const canvas = page().canvas();
    const quick_popup::PromptGuard guard(songTab.view());
    const EditorAutomationRowId volumeRow{EditorAutomationRowKind::ControlChange, 0,
                                          CoreTimeDefaults::kCcVolume};
    QVERIFY(findRow(volumeRow).valid());

    // One written volume point; the synthetic default node is projection only.
    const int writtenCount =
        int(songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume).size());
    QCOMPARE(writtenCount, 1);
    QSignalSpy documentChanged(&songTab.document(), &SongDocument::documentChanged);
    QVERIFY(documentChanged.isValid());
    const FrozenDocumentState frozen = frozenDocumentState(documentChanged.count());

    const CcDeletePrompt opened = openCcDeletePrompt(
        volumeRow, QStringLiteral("the volume pick did not open the confirmation"));
    QVERIFY2(opened.session && opened.root && opened.cancelButton,
             qUtf8Printable(opened.diagnostic));
    QTRY_VERIFY2(quick_popup::inputHasActiveFocus(quickWindow(), QLatin1String("cancelButton")),
                 "the confirmation did not give Cancel the initial focus");

    // The displayed quantity is the written-event count: it excludes the
    // synthetic node without pinning the message wording.
    const std::vector<int> advertised =
        displayedQuantities(canvas->property("ccDeletePromptMessage").toString());
    QVERIFY2(std::find(advertised.cbegin(), advertised.cend(), writtenCount) != advertised.cend(),
             "the confirmation did not advertise the written-event count");
    QVERIFY2(std::find(advertised.cbegin(), advertised.cend(), writtenCount + 1) ==
                 advertised.cend(),
             "the confirmation count includes the synthetic default node");

    QVERIFY2(quick_popup::clickPromptButton(*opened.session, QLatin1String("acceptButton")),
             "the Delete button never rendered in the confirmation form");

    // The written events go; the default-visible row stays on screen.
    QCOMPARE(documentChanged.count(), frozen.documentChanges + 1);
    QCOMPARE(songTab.document().revision(), frozen.revision + 1);
    QCOMPARE(songTab.document().undoStack()->count(), frozen.undoCount + 1);
    QCOMPARE(songTab.document().undoStack()->index(), frozen.undoIndex + 1);
    QVERIFY(songTab.document().smf().write() != frozen.smf);
    QVERIFY(songTab.document().lanePoints(0, CoreTimeDefaults::kCcVolume).empty());
    const LaneHandle retained = findRow(volumeRow);
    QVERIFY(retained.valid());
    QVERIFY(!laneBody(retained).isEmpty());

    // Undo restores the written events into the still-visible row.
    QVERIFY(songTab.history().canUndo());
    QVERIFY(std::holds_alternative<DocumentHistoryApplied>(songTab.history().requestUndo()));
    QCOMPARE(songTab.document().smf().write(), frozen.smf);
    DocLanePoint point;
    QVERIFY(songTab.document().findLanePoint(0, CoreTimeDefaults::kCcVolume, kVolumeTick, &point));
    QCOMPARE(point.value, CoreTimeDefaults::controllerDefault(CoreTimeDefaults::kCcVolume));
    QVERIFY(findRow(volumeRow).valid());
    QVERIFY(!laneBody(findRow(volumeRow)).isEmpty());
}
