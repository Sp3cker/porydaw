// Selection keyboard routing, window tier: lifecycle scenario. A/B tab
// switching, drawer hide/show, a primary-track change, and closing plus
// reopening a song tab leave routing bound to the live view, with no stale
// callback mutating a background document (plan 10). The song opens and closes
// run production's genuine clean lifecycle — the scenario undoes every edit
// through the real undo stack first, so no unsaved-changes prompt can mask a
// regression, and each gate that proves the clean state stays a real
// assertion.

#include "checks/selectionkey/tst_windowtier.h"

#include "ui/editordrawer/editordrawer.h"

#include <QPointer>
#include <QQuickWindow>

namespace {

constexpr int kTrack = 0;

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
    {
        selectionkey::DeclineModalsWithin guard(
            QStringLiteral("closing the clean second song tab"));
        workspace.requestCloseSelectedTab();
    }
    selectionkey::settle();
    QVERIFY2(workspace.songTabFor(*SongName::create(m_songB)) == nullptr && closingTab.isNull(),
             "the clean second tab did not close and destroy its session");
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
    viewR.selectionModel().setNoteSelection({pairR->ids[0], pairR->ids[1]});
    QVERIFY2(focusAutomationBand(viewR), "could not focus the reopened tab's automation band");
    selectionkey::deliverKey(windowR, Qt::Key_Right);
    QVERIFY2(!notePairUnchanged(documentR, *pairR),
             "the reopened tab's routing is stale or dead after document replacement");
    QVERIFY2(selectionkey::undoTabToClean(workspace, documentR,
                                          QStringLiteral("the reopened tab stayed dirty before "
                                                         "the window close"),
                                          &error),
             qUtf8Printable(error));
}
