// Selection keyboard routing, window tier: lifecycle scenario. A/B tab
// switching, drawer hide/show, a primary-track change, and closing plus
// reopening a song tab leave routing bound to the live view, with no stale
// callback mutating a background document (plan 10). The song opens and closes
// run production's genuine clean lifecycle — the scenario undoes every edit
// through the real undo stack first, so no unsaved-changes prompt can mask a
// regression, and each gate that proves the clean state stays a real
// assertion.

#include "checks/selectionkey/tst_windowtier.h"

#include "checks/support/timelinequickcheck.h"
#include "ui/editordrawer/automationpage.h"

#include "ui/editordrawer/editordrawer.h"

#include <QPointer>
#include <QQuickWindow>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kPan = 10;
constexpr uint64_t kPanTick = 5760;

AutomationCanvas *automationCanvas(SongView &view)
{
    return view.editorDrawer()->automationPage()->canvas();
}

bool clickParameter(SongView &view, const EditorAutomationRowId &row)
{
    auto *const canvas = automationCanvas(view);
    auto *const quick = selectionkey::quickCanvas(view);
    const int index = checks::support::automationParameterIndex(*canvas, row);
    QPointer<QQuickItem> label;
    if (index < 0 || !quick || !QTest::qWaitFor([&] {
            label = checks::support::visualDescendant(
                quick->rootObject(), QStringLiteral("automationParameterTab%1").arg(index));
            return label && label->window() && label->isVisible() && label->isEnabled() &&
                   label->width() > 0 && label->height() > 0;
        }))
        return false;
    QTest::mouseClick(label->window(), Qt::LeftButton, Qt::NoModifier,
                      label->mapToScene(label->boundingRect().center()).toPoint());
    return QTest::qWaitFor([&] { return canvas->parameterRow(canvas->activeParameter()) == row; });
}

std::optional<LaneHandle> panLane(const AutomationCanvas &canvas, int track)
{
    const auto &rows = canvas.rows();
    for (size_t index = 0; index < rows.size(); ++index) {
        const auto &row = rows[index].id;
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == track &&
            row.controller == kPan)
            return LaneHandle{int(index) + 1};
    }
    return std::nullopt;
}

} // namespace

void SelectionWindowTierTest::tabsDocumentsAndPrimaryTrackLifetime()
{
    WorkspaceUi &workspace = *m_session.workspace;
    QVERIFY2(m_tab, "the first song tab is missing");
    SongTab *const tabA = workspace.songTabFor(*SongName::create(m_songA));
    QCOMPARE(tabA, m_tab.data());
    SongView &viewA = tabA->view();
    SongDocument &documentA = tabA->document();
    viewA.selectTrack(kTrack);
    viewA.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songview::TimelineQuickView *const quickA = selectionkey::quickCanvas(viewA);
    QQuickWindow *const windowA = quickA ? quickA->quickWindow() : nullptr;
    QVERIFY2(windowA, "the first tab Quick window is missing");
    AutomationCanvas *const canvasA = automationCanvas(viewA);
    const EditorAutomationRowId panA{EditorAutomationRowKind::ControlChange, kTrack, kPan};
    QVERIFY(clickParameter(viewA, panA));

    // The per-case scenarios each roll their own edits back, and the explicit
    // undo-to-clean gate keeps this case self-sufficient, so the second-song
    // open runs production's genuine clean lifecycle (a dirty tab here is what
    // turns the open into an unsaved-changes prompt). The clean bytes then
    // double as the cross-tab mutation baseline.
    QString error;
    QVERIFY2(selectionkey::undoTabToClean(workspace, documentA,
                                          QStringLiteral("the first tab stayed dirty before the "
                                                         "second-song open"),
                                          &error),
             qUtf8Printable(error));
    const int tabCountBeforeSecondOpen = workspace.openTabCount();
    const QByteArray documentAClean = documentA.smf().write();
    const auto laneA = panLane(*canvasA, kTrack);
    QVERIFY(laneA.has_value());
    QVERIFY(canvasA->openValuePromptForInsertion(*laneA, kPanTick, 64));

    SongTab *const tabB = selectionkey::openSongTab(m_session, m_songB, true, error);
    QVERIFY2(tabB, qUtf8Printable(error));
    QVERIFY2(workspace.selectedSongTab() == tabB &&
                 workspace.openTabCount() == tabCountBeforeSecondOpen + 1 &&
                 workspace.songTabFor(tabA->name()) == tabA,
             "opening the second song did not add and select a distinct tab while retaining "
             "the first");
    SongView &viewB = tabB->view();
    SongDocument &documentB = tabB->document();
    viewB.selectTrack(kTrack);
    viewB.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    const std::optional<NotePair> pairB = addNotePair(documentB, kTrack, 960);
    QVERIFY2(pairB.has_value(),
             "the reserved tick-960 note pair could not be inserted on the second tab");
    songview::TimelineQuickView *const quickB = selectionkey::quickCanvas(viewB);
    QQuickWindow *const windowB = quickB ? quickB->quickWindow() : nullptr;
    QVERIFY2(windowB, "the second tab Quick window is missing");
    AutomationCanvas *const canvasB = automationCanvas(viewB);
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    QVERIFY(clickParameter(viewB, tempo));
    QVERIFY(!canvasA->valuePromptVisible());
    canvasA->acceptNodeValuePrompt(96);
    QCOMPARE(documentA.smf().write(), documentAClean);
    viewB.selectionModel().setNoteSelection({pairB->ids[0], pairB->ids[1]});
    QVERIFY2(focusAutomationBand(viewB), "could not focus the second tab's automation band");
    selectionkey::deliverKey(windowB, Qt::Key_Right);
    QVERIFY2(!notePairUnchanged(documentB, *pairB),
             "arrows did not move the selected notes on the second tab");
    QVERIFY2(documentA.smf().write() == documentAClean,
             "key delivery to the second tab mutated the first tab's document");
    const QByteArray documentBAfterMove = documentB.smf().write();

    workspace.selectSongTab(tabA);
    selectionkey::settle();
    QCOMPARE(workspace.selectedSongTab(), tabA);
    QCOMPARE(canvasA->parameterRow(canvasA->activeParameter()), std::optional{panA});
    QCOMPARE(canvasB->parameterRow(canvasB->activeParameter()), std::optional{tempo});
    const std::optional<NotePair> pairA = addNotePair(documentA, kTrack, 3840);
    QVERIFY2(pairA.has_value(),
             "the reserved tick-3840 note pair could not be inserted on the first tab");
    viewA.selectionModel().setNoteSelection({pairA->ids[0], pairA->ids[1]});
    QVERIFY2(focusAutomationBand(viewA),
             "could not focus the first tab's automation band after reselecting it");
    selectionkey::deliverKey(windowA, Qt::Key_Up);
    DocNote noteA;
    QVERIFY2(documentA.findNote(pairA->ids[0], &noteA) &&
                 noteA.key == uint8_t(pairA->notes[0].key + 1),
             "the Up arrow did not transpose the first tab's selection after reselecting it");
    QVERIFY2(documentB.smf().write() == documentBAfterMove,
             "key delivery to the first tab mutated the second tab's document");

    viewA.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
    selectionkey::settle();
    viewA.selectionModel().setNoteSelection({pairA->ids[0], pairA->ids[1]});
    const std::optional<DocNote> beforeHide = selectionkey::noteById(documentA, pairA->ids[0]);
    QVERIFY2(beforeHide.has_value(),
             "the first selected note vanished before the hidden-drawer baseline");
    selectionkey::deliverKey(windowA, Qt::Key_Right);
    QVERIFY2(documentA.findNote(pairA->ids[0], &noteA) && noteA.tick != beforeHide->tick,
             "note arrows stopped routing while the drawer was hidden");
    viewA.setDrawerSectionVisible(EditorDrawerPage::Automations, true);

    // The primary-track change clears the selection and retargets routing.
    QVERIFY2(documentA.engineTrackCount() > 1,
             "the rich fixture needs a second track for primary-track routing");
    const std::optional<NotePair> pairT1 = addNotePair(documentA, 1, 960);
    QVERIFY2(pairT1.has_value(), "the reserved track-1 tick-960 note pair could not be inserted");
    viewA.selectTrack(1);
    QVERIFY2(viewA.selectionModel().noteSelection().empty(),
             "the primary-track change did not clear the note selection");
    const EditorAutomationRowId panTrackOne{EditorAutomationRowKind::ControlChange, 1, kPan};
    QCOMPARE(canvasA->parameterRow(canvasA->activeParameter()), std::optional{panTrackOne});
    const auto laneTrackOne = panLane(*canvasA, 1);
    QVERIFY(laneTrackOne.has_value());
    QVERIFY(!canvasA->laneBody(*laneTrackOne).isEmpty());
    DocLanePoint panPoint;
    QVERIFY(!documentA.findLanePoint(1, kPan, kPanTick, &panPoint));
    const auto originalTrackPan = documentA.lanePoints(kTrack, kPan);
    QVERIFY(canvasA->openValuePromptForInsertion(*laneTrackOne, kPanTick, 64));
    canvasA->acceptNodeValuePrompt(96);
    QVERIFY(documentA.findLanePoint(1, kPan, kPanTick, &panPoint));
    QCOMPARE(panPoint.value, 96);
    const auto originalTrackPanAfter = documentA.lanePoints(kTrack, kPan);
    QCOMPARE(originalTrackPanAfter.size(), originalTrackPan.size());
    for (size_t index = 0; index < originalTrackPan.size(); ++index) {
        QCOMPARE(originalTrackPanAfter[index].tick, originalTrackPan[index].tick);
        QCOMPARE(originalTrackPanAfter[index].value, originalTrackPan[index].value);
    }
    QCOMPARE(documentB.smf().write(), documentBAfterMove);
    viewA.selectionModel().setNoteSelection({pairT1->ids[0], pairT1->ids[1]});
    QVERIFY2(focusAutomationBand(viewA),
             "could not focus the automation band on the new primary track");
    selectionkey::deliverKey(windowA, Qt::Key_Up);
    DocNote trackOneNote;
    QVERIFY2(documentA.findNote(pairT1->ids[0], &trackOneNote) &&
                 trackOneNote.key == uint8_t(pairT1->notes[0].key + 1),
             "the Up arrow did not transpose the new primary track's selection");

    // Return both tabs to their saved state so the close, the reopen, and the
    // final window close take production's genuine clean lifecycle instead of
    // blocking in an unsaved-changes prompt.
    QVERIFY2(selectionkey::undoTabToClean(workspace, documentA,
                                          QStringLiteral("the first tab stayed dirty before "
                                                         "closing the second tab"),
                                          &error),
             qUtf8Printable(error));
    workspace.selectSongTab(tabB);
    selectionkey::settle();
    QVERIFY2(selectionkey::undoTabToClean(workspace, documentB,
                                          QStringLiteral("the second tab stayed dirty before "
                                                         "its close"),
                                          &error),
             qUtf8Printable(error));
    const QPointer<SongTab> closingTab = tabB;
    const QPointer<AutomationCanvas> closingCanvas = canvasB;
    {
        selectionkey::DeclineModalsWithin guard(
            QStringLiteral("closing the clean second song tab"));
        workspace.requestCloseSelectedTab();
    }
    selectionkey::settle();
    QVERIFY2(workspace.songTabFor(*SongName::create(m_songB)) == nullptr && closingTab.isNull(),
             "the clean second tab did not close and destroy its session");
    QVERIFY(closingCanvas.isNull());
    const QByteArray documentABeforeReopen = documentA.smf().write();
    const int tabCountBeforeReopen = workspace.openTabCount();
    SongTab *const reopened = selectionkey::openSongTab(m_session, m_songB, true, error);
    QVERIFY2(reopened, qUtf8Printable(error));
    QVERIFY2(workspace.selectedSongTab() == reopened &&
                 workspace.openTabCount() == tabCountBeforeReopen + 1 &&
                 workspace.songTabFor(tabA->name()) == tabA,
             "reopening the second song did not create and select its replacement while "
             "retaining the first tab");
    SongView &viewR = reopened->view();
    SongDocument &documentR = reopened->document();
    viewR.selectTrack(kTrack);
    viewR.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    const std::optional<NotePair> pairR = addNotePair(documentR, kTrack, 960);
    QVERIFY2(pairR.has_value(),
             "the reserved tick-960 note pair could not be inserted on the reopened tab");
    songview::TimelineQuickView *const quickR = selectionkey::quickCanvas(viewR);
    QQuickWindow *const windowR = quickR ? quickR->quickWindow() : nullptr;
    QVERIFY2(windowR, "the reopened tab Quick window is missing");
    AutomationCanvas *const canvasR = automationCanvas(viewR);
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, kTrack, 7};
    QCOMPARE(canvasR->parameterRow(canvasR->activeParameter()), std::optional{volume});
    viewR.selectionModel().setNoteSelection({pairR->ids[0], pairR->ids[1]});
    QVERIFY2(focusAutomationBand(viewR), "could not focus the reopened tab's automation band");
    selectionkey::deliverKey(windowR, Qt::Key_Right);
    QVERIFY2(!notePairUnchanged(documentR, *pairR),
             "the reopened tab's routing is stale or dead after document replacement");
    QCOMPARE(documentA.smf().write(), documentABeforeReopen);
    QVERIFY2(selectionkey::undoTabToClean(workspace, documentR,
                                          QStringLiteral("the reopened tab stayed dirty before "
                                                         "the window close"),
                                          &error),
             qUtf8Printable(error));
}
