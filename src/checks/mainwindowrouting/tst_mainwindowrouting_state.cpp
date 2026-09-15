#include "mainwindowroutingfixture.h"

#include "checks/quickpopupguard.h"
#include "checks/trackheaders/trackheaderoracles.h"
#include "ui/mousehints/mousehints.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/theme/themeruntime.h"

#include <QQuickItem>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QStatusBar>

#include <QtTest>

namespace {

// The Edit menu's named command group with the given mnemonic-stripped
// title, or null when task 13's projection is absent.
QMenu *submenuWithTitle(QMenu &menu, const QString &title)
{
    for (QAction *menuAction : menu.actions()) {
        QMenu *sub = menuAction->menu();
        if (sub && QString(sub->title()).remove(QLatin1Char('&')) == title)
            return sub;
    }
    return nullptr;
}
} // namespace

namespace checks::mainwindowrouting {

class MainWindowRoutingStateTest final : public QObject, private MainWindowRoutingFixture
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MainWindowRoutingStateTest)

  public:
    MainWindowRoutingStateTest(QString projectRoot, QString songA, QString songB)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
    {}

  private slots:
    void drawerSeedProjection()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        QCOMPARE(window.m_automationDrawerAction->shortcut(), QKeySequence(Qt::Key_A));
        QCOMPARE(window.m_velocityDrawerAction->shortcut(), QKeySequence(Qt::Key_V));
        QCOMPARE(window.m_voiceChangesDrawerAction->shortcut(), QKeySequence(Qt::Key_P));
        QCOMPARE(window.m_voiceChangesDrawerAction->objectName(),
                 QStringLiteral("voiceChangesDrawerWindowAction"));
        for (QAction *action : {window.m_automationDrawerAction, window.m_velocityDrawerAction,
                                window.m_voiceChangesDrawerAction})
            QCOMPARE(action->shortcutContext(), Qt::WindowShortcut);
        QVERIFY(a.drawerSectionVisible(EditorDrawerPage::Velocity));
        QVERIFY(!a.drawerSectionVisible(EditorDrawerPage::Automations));
        QVERIFY(!a.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
        QCOMPARE(a.drawerActivePage(), EditorDrawerPage::Velocity);
        QCOMPARE(a.drawerSectionHeight(EditorDrawerPage::Velocity), 173);
        QCOMPARE(a.editorViewState().drawerState(), b.editorViewState().drawerState());
    }

    void drawerFanout()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        a.setDrawerSectionVisible(EditorDrawerPage::Automations, false);
        a.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
        a.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
        QVERIFY(!b.hasVisibleDrawerSection());
        sendKey(window, Qt::Key_A);
        QVERIFY(a.drawerSectionVisible(EditorDrawerPage::Automations));
        QVERIFY(b.drawerSectionVisible(EditorDrawerPage::Automations));
        QCOMPARE(a.drawerActivePage(), EditorDrawerPage::Automations);
        QCOMPARE(b.drawerActivePage(), EditorDrawerPage::Automations);
        sendKey(window, Qt::Key_A);
        QVERIFY(!a.drawerSectionVisible(EditorDrawerPage::Automations));
        QVERIFY(!b.drawerSectionVisible(EditorDrawerPage::Automations));
        sendKey(window, Qt::Key_V);
        QVERIFY(a.drawerSectionVisible(EditorDrawerPage::Velocity));
        QVERIFY(b.drawerSectionVisible(EditorDrawerPage::Velocity));
        QCOMPARE(a.drawerActivePage(), EditorDrawerPage::Velocity);
        QCOMPARE(b.drawerActivePage(), EditorDrawerPage::Velocity);
        sendKey(window, Qt::Key_P);
        QVERIFY(a.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
        QVERIFY(b.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
        QCOMPARE(a.drawerActivePage(), EditorDrawerPage::VoiceChanges);
        QCOMPARE(b.drawerActivePage(), EditorDrawerPage::VoiceChanges);
    }

    void eventListGating()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &b = session->b->view();
        b.setEventListVisible(true);
        QVERIFY(!window.m_automationDrawerAction->isEnabled());
        QVERIFY(!window.m_velocityDrawerAction->isEnabled());
        QVERIFY(!window.m_voiceChangesDrawerAction->isEnabled());
        const EditorViewState blocked = b.editorViewState();
        sendKey(window, Qt::Key_V);
        sendKey(window, Qt::Key_P);
        QCOMPARE(b.editorViewState(), blocked);
        b.setEventListVisible(false);
        QVERIFY(window.m_automationDrawerAction->isEnabled());
        QVERIFY(window.m_velocityDrawerAction->isEnabled());
        QVERIFY(window.m_voiceChangesDrawerAction->isEnabled());
    }

    void drawerFocusFollowsFallback()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &b = session->b->view();
        b.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        b.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        b.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
        b.focusTimelineBand(songview::TimelineBand::VoiceChanges, Qt::MouseFocusReason);
        QCoreApplication::processEvents();
        QCOMPARE(b.focusedTimelineBand(), songview::TimelineBand::VoiceChanges);
        window.m_voiceChangesDrawerAction->trigger();
        QVERIFY(!b.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
        QVERIFY(b.drawerSectionVisible(EditorDrawerPage::Velocity));
        QCOMPARE(b.focusedTimelineBand(), songview::TimelineBand::Velocity);
        b.focusTimelineBand(songview::TimelineBand::Velocity, Qt::MouseFocusReason);
        window.m_velocityDrawerAction->trigger();
        QVERIFY(!b.drawerSectionVisible(EditorDrawerPage::Velocity));
        QVERIFY(b.drawerSectionVisible(EditorDrawerPage::Automations));
        QCOMPARE(b.focusedTimelineBand(), songview::TimelineBand::Automation);
        b.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason);
        window.m_automationDrawerAction->trigger();
        QVERIFY(!b.hasVisibleDrawerSection());
        QCOMPARE(b.focusedTimelineBand(), songview::TimelineBand::Roll);
        QWidget *focus = QApplication::focusWidget();
        QVERIFY(focus);
        QVERIFY(focus == session->b || session->b->isAncestorOf(focus));
    }

    void hideRetains()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        b.setDrawerActivePage(EditorDrawerPage::Velocity);
        b.setDrawerSectionHeight(EditorDrawerPage::Velocity, 180);
        b.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 97);
        const int velocityHeight = b.drawerSectionHeight(EditorDrawerPage::Velocity);
        const int voiceHeight = b.drawerSectionHeight(EditorDrawerPage::VoiceChanges);
        b.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
        b.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
        QCOMPARE(b.drawerActivePage(), EditorDrawerPage::Velocity);
        QCOMPARE(b.drawerSectionHeight(EditorDrawerPage::Velocity), velocityHeight);
        QCOMPARE(b.drawerSectionHeight(EditorDrawerPage::VoiceChanges), voiceHeight);
        QCOMPARE(a.drawerActivePage(), EditorDrawerPage::Velocity);
        QCOMPARE(a.drawerSectionHeight(EditorDrawerPage::Velocity), velocityHeight);
        QCOMPARE(a.drawerSectionHeight(EditorDrawerPage::VoiceChanges), voiceHeight);
    }

    void tabSwitchRefocus()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        for (const EditorDrawerPage page :
             {EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
              EditorDrawerPage::VoiceChanges})
            b.setDrawerSectionVisible(page, false);
        QVERIFY(!a.hasVisibleDrawerSection());
        QVERIFY(!b.hasVisibleDrawerSection());
        window.m_workspace->selectSongTab(session->a);
        QCOMPARE(window.m_workspace->selectedSongTab(), session->a);
        QCoreApplication::processEvents();
        a.focusActiveSurface();
        QCoreApplication::processEvents();
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents();
        QCOMPARE(a.focusedTimelineBand(), songview::TimelineBand::Roll);
        QWidget *focus = QApplication::focusWidget();
        QVERIFY(focus);
        QVERIFY(focus == session->a || session->a->isAncestorOf(focus));

        window.m_workspace->selectSongTab(session->b);
        QCOMPARE(window.m_workspace->selectedSongTab(), session->b);
        QCoreApplication::processEvents();
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents();
        QCOMPARE(b.focusedTimelineBand(), songview::TimelineBand::Roll);
        focus = QApplication::focusWidget();
        QVERIFY(focus);
        QVERIFY(focus == session->b || session->b->isAncestorOf(focus));
    }

    void editActionProjectionAndIdentity()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab *a = session->a;
        SongTab *b = session->b;

        // The window commands are the canonical set's own objects, projected
        // into the native Edit groups — no duplicates, no per-entry handlers.
        QAction *copy = window.m_copyAction;
        QAction *solo = window.m_soloAction;
        QAction *insertTime = window.m_insertTimeAction;
        QAction *deleteTime = window.m_deleteTimeAction;
        QVERIFY(copy && solo && insertTime && deleteTime);
        QCOMPARE(copy, window.m_editActions->action(SongView::EditCommand::Copy));
        QCOMPARE(solo, window.m_editActions->action(SongView::EditCommand::SoloTracks));
        QCOMPARE(insertTime, window.m_editActions->action(SongView::EditCommand::InsertTime));
        QCOMPARE(deleteTime, window.m_editActions->action(SongView::EditCommand::DeleteTime));
        QMenu *edit = editMenu(window);
        QVERIFY(edit);
        QVERIFY(edit->actions().contains(copy));
        QMenu *timeMenu = submenuWithTitle(*edit, QStringLiteral("Time"));
        QMenu *tracksMenu = submenuWithTitle(*edit, QStringLiteral("Tracks"));
        QVERIFY(timeMenu);
        QVERIFY(tracksMenu);
        QVERIFY(timeMenu->actions().contains(insertTime));
        QVERIFY(timeMenu->actions().contains(deleteTime));
        QVERIFY(tracksMenu->actions().contains(solo));

        // Retargeting follows the selection; the projected objects do not.
        window.m_workspace->selectSongTab(a);
        QCOMPARE(window.m_editActions->target(), &a->view());
        window.m_workspace->selectSongTab(b);
        QCOMPARE(window.m_editActions->target(), &b->view());
        QCOMPARE(window.m_copyAction, copy);
        QCOMPARE(window.m_soloAction, solo);
        QCOMPARE(window.m_insertTimeAction, insertTime);
        QCOMPARE(window.m_deleteTimeAction, deleteTime);
        // A ready selected tab opens the readiness-gated commands; an
        // explicit unbind through the production seam disables everything
        // until the next real selection change retargets the set.
        QVERIFY(solo->isEnabled());
        window.m_editActions->rebind(nullptr);
        QVERIFY(!window.m_editActions->target());
        QVERIFY(!copy->isEnabled());
        QVERIFY(!solo->isEnabled());
        QVERIFY(!insertTime->isEnabled());
        QVERIFY(!deleteTime->isEnabled());
        window.m_workspace->selectSongTab(a);
        QCOMPARE(window.m_editActions->target(), &a->view());
        QVERIFY(solo->isEnabled());
    }

    void editActionsStartUnboundWithNoWorkspace()
    {
        // Without a saved workspace recipe there are no startup tabs at all:
        // the set constructs unbound and every projected command is
        // disabled — the null-target arm of the readiness predicate.
        const SettingsGuard settings;
        MainWindow window;
        QVERIFY(window.m_editActions);
        QVERIFY(!window.m_editActions->target());
        QVERIFY(!window.m_copyAction->isEnabled());
        QVERIFY(!window.m_soloAction->isEnabled());
        QVERIFY(!window.m_insertTimeAction->isEnabled());
        QVERIFY(!window.m_deleteTimeAction->isEnabled());
    }

    void nonSelectedOriginFansCompleteStateOutAndNoopsStaySilent()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
        const EditorAutomationRowId hiddenFirst{EditorAutomationRowKind::ControlChange, 1, 7};
        const EditorAutomationRowId hiddenSecond{EditorAutomationRowKind::ControlChange, 0, 80};
        window.m_workspace->selectSongTab(session->a);
        QSignalSpy origin(&b, &SongView::editorViewStateChanged);
        QSignalSpy projection(&a, &SongView::editorViewStateChanged);
        QSignalSpy hub(window.m_workspace.get(), &WorkspaceUi::editorViewStateChanged);
        QSignalSpy persisted(&window, &MainWindow::editorViewStatePersisted);
        const EditorViewState state = completeSeed();
        b.setEditorViewState(state);
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 1);
        QCOMPARE(projection.count(), 0);
        QCOMPARE(hub.count(), 1);
        QCOMPARE(persisted.count(), 1);
        QCOMPARE(a.editorViewState(), state);
        QCOMPARE(b.editorViewState(), state);
        QCOMPARE(loadEditorViewState(QSettings{}), state);
        QCOMPARE(b.editorViewState().hiddenLanes().size(), size_t{2});
        QCOMPARE(b.editorViewState().hiddenLanes().front(), hiddenFirst);
        QCOMPARE(b.editorViewState().hiddenLanes().back(), hiddenSecond);

        const int originBeforeRange = origin.count();
        const int hubBeforeRange = hub.count();
        const int projectionBeforeRange = projection.count();
        const int persistedBeforeRange = persisted.count();
        b.setLaneDisplayRange(0, 74, 80);
        QCOMPARE(origin.count(), originBeforeRange + 1);
        QCOMPARE(hub.count(), hubBeforeRange + 1);
        QCOMPARE(persisted.count(), persistedBeforeRange + 1);
        QCOMPARE(projection.count(), projectionBeforeRange);
        QCOMPARE(a.editorViewState().laneRanges.at(lane), uint8_t{80});
        QCOMPARE(b.editorViewState().laneRanges.at(lane), uint8_t{80});

        const int originBeforeNoop = origin.count();
        const int projectionBeforeNoop = projection.count();
        const int hubBeforeNoop = hub.count();
        const int persistedBeforeNoop = persisted.count();
        b.setLaneDisplayRange(0, 74, 80);
        EditorViewState unchanged = b.editorViewState();
        unchanged.emptyLanes.insert(lane);
        b.setEditorViewState(unchanged);
        unchanged.emptyLanes.erase({EditorAutomationRowKind::ControlChange, 3, 99});
        b.setEditorViewState(unchanged);
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), originBeforeNoop);
        QCOMPARE(projection.count(), projectionBeforeNoop);
        QCOMPARE(hub.count(), hubBeforeNoop);
        QCOMPARE(persisted.count(), persistedBeforeNoop);
    }

    void laneIdentityRemapPersistsAndQuietRemapStaysSilent()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        const EditorAutomationRowId hiddenFirst{EditorAutomationRowKind::ControlChange, 1, 7};
        const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
        b.setEditorViewState(completeSeed());
        window.m_workspace->selectSongTab(session->a);
        QSignalSpy projection(&a, &SongView::editorViewStateChanged);
        QSignalSpy origin(&b, &SongView::editorViewStateChanged);
        QSignalSpy hub(window.m_workspace.get(), &WorkspaceUi::editorViewStateChanged);
        QSignalSpy persisted(&window, &MainWindow::editorViewStatePersisted);
        const int tracks = b.document().engineTrackCount();
        QVERIFY(tracks >= 2);
        const int source = 1;
        const int target = source == tracks - 1 ? 0 : tracks - 1;
        const QByteArray midi = b.document().smf().write();
        const EditorViewState before = b.editorViewState();
        QVERIFY(b.document().moveTrack(source, target));
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 1);
        QCOMPARE(hub.count(), 1);
        QCOMPARE(persisted.count(), 1);
        const EditorViewState remapped = b.editorViewState();
        QVERIFY(remapped != before);
        QCOMPARE(projection.count(), 0);
        QVERIFY(!remapped.isLaneHidden(hiddenFirst));
        QCOMPARE(remapped.hiddenLanes().size(), size_t{2});
        QCOMPARE(remapped.hiddenLanes().front().controller, uint8_t{7});
        QVERIFY(remapped.hiddenLanes().front().track != uint8_t{1});
        QCOMPARE(remapped.hiddenLanes().back().controller, uint8_t{80});
        QCOMPARE(remapped.laneRanges.at(tempo), uint8_t{100});
        QCOMPARE(a.editorViewState(), remapped);
        QCOMPARE(loadEditorViewState(QSettings{}), remapped);
        b.document().undoStack()->undo();
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 2);
        QCOMPARE(hub.count(), 2);
        QCOMPARE(persisted.count(), 2);
        QCOMPARE(a.editorViewState(), before);
        QCOMPARE(b.editorViewState(), before);
        QCOMPARE(b.document().smf().write(), midi);
        QVERIFY(!b.document().isDirty());
        QCOMPARE(projection.count(), 0);

        EditorViewState reduced;
        reduced.velocity = {true, 173};
        reduced.automation = {true, 44};
        reduced.voiceChanges = {true, 55};
        reduced.activePage = EditorDrawerPage::Automations;
        b.setEditorViewState(reduced);
        projection.clear();
        origin.clear();
        hub.clear();
        persisted.clear();
        const QByteArray quietMidi = b.document().smf().write();
        QVERIFY(b.document().moveTrack(source, target));
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 0);
        QCOMPARE(hub.count(), 0);
        QCOMPARE(persisted.count(), 0);
        b.document().undoStack()->undo();
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 0);
        QCOMPARE(projection.count(), 0);
        QCOMPARE(hub.count(), 0);
        QCOMPARE(persisted.count(), 0);
        QCOMPARE(b.document().smf().write(), quietMidi);
        QVERIFY(!b.document().isDirty());
    }

    void viewOnlyLaneMutationsPersistWithoutDocumentMutation()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        b.setEditorViewState(completeSeed());
        const QByteArray midi = b.document().smf().write();
        const uint64_t revision = b.document().revision();
        const int undoCount = b.document().undoStack()->count();
        const auto snapshot = porydawSnapshot(session->fixture->root());
        QSignalSpy origin(&b, &SongView::editorViewStateChanged);
        QSignalSpy hub(window.m_workspace.get(), &WorkspaceUi::editorViewStateChanged);
        QSignalSpy persisted(&window, &MainWindow::editorViewStatePersisted);
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 2, 40};
        EditorViewState next = b.editorViewState();
        next.emptyLanes.insert(lane);
        b.setEditorViewState(next);
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 1);
        QCOMPARE(hub.count(), 1);
        QCOMPARE(persisted.count(), 1);
        QCOMPARE(a.editorViewState(), b.editorViewState());
        QCOMPARE(loadEditorViewState(QSettings{}), b.editorViewState());
        QCOMPARE(b.document().smf().write(), midi);
        QCOMPARE(b.document().revision(), revision);
        QCOMPARE(b.document().undoStack()->count(), undoCount);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        next = b.editorViewState();
        next.emptyLanes.erase(lane);
        b.setEditorViewState(next);
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 2);
        QCOMPARE(hub.count(), 2);
        QCOMPARE(persisted.count(), 2);
        QCOMPARE(b.document().smf().write(), midi);
        QCOMPARE(b.document().revision(), revision);
        QCOMPARE(b.document().undoStack()->count(), undoCount);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
    }

    void rejectedRemapIsTotalNoop()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        const EditorViewState beforeA = a.editorViewState();
        const EditorViewState beforeB = b.editorViewState();
        const QByteArray midi = b.document().smf().write();
        const uint64_t revision = b.document().revision();
        const EditorViewState settings = loadEditorViewState(QSettings{});
        const auto snapshot = porydawSnapshot(session->fixture->root());
        QSignalSpy origin(&b, &SongView::editorViewStateChanged);
        QSignalSpy hub(window.m_workspace.get(), &WorkspaceUi::editorViewStateChanged);
        QSignalSpy persisted(&window, &MainWindow::editorViewStatePersisted);
        TrackRemap rejected;
        rejected.engineTrackMap = {0, 0};
        rejected.newEngineTrackCount = 2;
        emit b.document().tracksRemapped(rejected);
        QCoreApplication::processEvents();
        QCOMPARE(a.editorViewState(), beforeA);
        QCOMPARE(b.editorViewState(), beforeB);
        QCOMPARE(b.document().smf().write(), midi);
        QCOMPARE(b.document().revision(), revision);
        QCOMPARE(loadEditorViewState(QSettings{}), settings);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QCOMPARE(origin.count(), 0);
        QCOMPARE(hub.count(), 0);
        QCOMPARE(persisted.count(), 0);
        EditorViewState valueCopy = completeSeed();
        const EditorViewState original = valueCopy;
        QVERIFY(!valueCopy.remapEngineTracks({0, 0}));
        QCOMPARE(valueCopy, original);
    }

    void mouseHintFollowsRealTargets()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        QQuickItem *const plot = quickItem(view, QLatin1String("timelineRollInput"));
        QQuickItem *const gutter = quickItem(view, QLatin1String("timelineRollGutterInput"));
        QQuickItem *const headers = quickItem(view, QLatin1String("timelineTrackHeadersInput"));
        QVERIFY(plot && gutter && headers);
        songview::TrackHeaderModel *const model = trackHeaders(view);
        QVERIFY(model);
        QVERIFY(model->rowCount() >= 1);

        // Ordinary hover through the real Quick delivery: each target's own
        // profile survives the move without any manual clear.
        QTest::mouseMove(canvas, plot->mapToScene(plot->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == plot);
        const QString plotProfile = hints.currentText();
        QVERIFY(!plotProfile.isEmpty());

        QTest::mouseMove(canvas, gutter->mapToScene(gutter->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == gutter);
        QVERIFY(!hints.currentText().isEmpty());

        const std::optional<QPointF> title = headerRowPoint(
            *headers, *model, 0,
            model->data(model->index(0, 0), songview::TrackHeaderModel::TitleRectRole).toRectF());
        QVERIFY(title.has_value());
        QTest::mouseMove(canvas, headers->mapToScene(*title).toPoint());
        QTRY_VERIFY(hints.currentSource() == headers);
        const QString rowProfile = hints.currentText();
        QVERIFY(!rowProfile.isEmpty());

        // The mute control is a no-hint target inside the same input item:
        // it claims an empty profile instead of leaking the row's.
        const std::optional<QPointF> mute =
            headerRowPoint(*headers, *model, 0, model->muteButtonRect());
        QVERIFY(mute.has_value());
        QTest::mouseMove(canvas, headers->mapToScene(*mute).toPoint());
        QTRY_VERIFY(hints.currentSource() == headers && hints.currentText().isEmpty());

        // Back on the row body the scope profile returns unchanged.
        QTest::mouseMove(canvas, headers->mapToScene(*title).toPoint());
        QTRY_VERIFY(hints.currentSource() == headers && hints.currentText() == rowProfile);

        // The Quick scrollbar is its own no-hint group: the covered band
        // profile must not leak through it.
        QQuickItem *const scrollbar = quickItem(view, QLatin1String("timelineRollScrollBar"));
        QVERIFY(scrollbar && scrollbar->isVisible());
        QTest::mouseMove(canvas,
                         scrollbar->mapToScene(scrollbar->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() != headers && hints.currentText().isEmpty());
    }

    void mouseHintMenuScopeKeepsRenameAndRestoresEditor()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        songview::TrackHeaderModel *const model = trackHeaders(view);
        QVERIFY(model);
        QVERIFY(model->rowCount() >= 2);
        QQuickItem *const headers = quickItem(view, QLatin1String("timelineTrackHeadersInput"));
        QVERIFY(headers);
        songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
        QVERIFY(popup);
        const quick_popup::PromptGuard guard(view);

        // A real double-click on the row title opens the in-band rename editor.
        const int track =
            model->data(model->index(0, 0), songview::TrackHeaderModel::TrackRole).toInt();
        const std::optional<QPointF> title = headerRowPoint(
            *headers, *model, 0,
            model->data(model->index(0, 0), songview::TrackHeaderModel::TitleRectRole).toRectF());
        QVERIFY(title.has_value());
        QTest::mouseDClick(canvas, Qt::LeftButton, Qt::NoModifier,
                           headers->mapToScene(*title).toPoint());
        QTRY_COMPARE(model->renamingTrack(), track);
        QQuickItem *const renameInput = quickItem(view, QLatin1String("timelineTrackHeaderRename"));
        QTRY_VERIFY(renameInput && renameInput->isVisible());
        QQuickItem *const editor = renameInput->parentItem();
        QVERIFY(editor);

        // Hovering the editor publishes its own profile, not the row's.
        hoverAt(*canvas, editor->mapToScene(editor->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == editor);
        QVERIFY(!hints.currentText().isEmpty());

        // The shared header menu suppresses every hint outside its own scope.
        const std::optional<QPointF> secondTitle = headerRowPoint(
            *headers, *model, 1,
            model->data(model->index(1, 0), songview::TrackHeaderModel::TitleRectRole).toRectF());
        QVERIFY(secondTitle.has_value());
        QTest::mouseClick(canvas, Qt::RightButton, Qt::NoModifier,
                          headers->mapToScene(*secondTitle).toPoint());
        QVERIFY2(
            QTest::qWaitFor([popup] { return popup->isOpen() && quick_popup::menuPanel(*popup); }),
            "the header right-press did not open the shared menu");
        QTRY_VERIFY(!hints.currentSource() || popup->owns(hints.currentSource()));
        QVERIFY(hints.currentText().isEmpty());

        // Opening the menu hands its panel popup focus, which commits the
        // in-progress rename through the editor's own focus-loss path.
        QTRY_COMPARE(model->renamingTrack(), -1);
        QTRY_VERIFY(!renameInput->isVisible());

        // The menu's own Rename row — the real path a user takes — reopens
        // the editor on the menu's track, and the editor's hint returns.
        const int menuTrack =
            model->data(model->index(1, 0), songview::TrackHeaderModel::TrackRole).toInt();
        QQuickItem *const panel = quick_popup::menuPanel(*popup);
        QVERIFY(panel);
        songview::QuickMenuModel *const menuModel = quick_popup::menuModel(*panel);
        QVERIFY(menuModel);
        int renameRow = -1;
        for (int row = 0; row < menuModel->rowCount(); ++row) {
            if (menuModel->data(menuModel->index(row, 0), songview::QuickMenuModel::IdRole)
                    .toInt() ==
                static_cast<int>(songview::TrackHeaderModel::HeaderMenuAction::RenameTrack)) {
                renameRow = row;
                break;
            }
        }
        QVERIFY(renameRow >= 0);
        QVERIFY2(quick_popup::clickMenuRow(*popup, renameRow),
                 "the menu's Rename track row did not render");
        QTRY_VERIFY(!popup->isOpen());
        QTRY_COMPARE(model->renamingTrack(), menuTrack);
        QTRY_VERIFY(renameInput->isVisible());
        hoverAt(*canvas, editor->mapToScene(editor->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == editor && !hints.currentText().isEmpty());

        // Cancelling the rename through the model's own finish path — the
        // same call the editor's Escape handler makes — ends the editor; the
        // row's profile returns under the unchanged cursor.
        model->finishRename(false, true);
        QTRY_COMPARE(model->renamingTrack(), -1);
        hoverAt(*canvas, headers->mapToScene(*title).toPoint());
        QTRY_VERIFY(hints.currentSource() == headers && !hints.currentText().isEmpty());
    }

    void mouseHintPopupScopeRestoresCoveredTarget()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        QQuickItem *const gutter = quickItem(view, QLatin1String("timelineRollGutterInput"));
        QVERIFY(gutter);
        songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
        QVERIFY(popup);
        const quick_popup::PromptGuard guard(view);

        hoverAt(*canvas, gutter->mapToScene(gutter->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == gutter);
        const QString gutterProfile = hints.currentText();
        QVERIFY(!gutterProfile.isEmpty());

        // The Insert Time action opens its canvas form; the session scope
        // suppresses the covered gutter hint.
        QVERIFY(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
        QVERIFY(window.m_insertTimeAction);
        window.m_insertTimeAction->trigger();
        QVERIFY2(QTest::qWaitFor([popup] {
                     return popup->isOpen() &&
                            quick_popup::promptItem(*popup, QLatin1String("insertTimePrompt"));
                 }),
                 "the Insert Time action did not open its canvas prompt");
        QTRY_VERIFY(!hints.currentSource() || popup->owns(hints.currentSource()));
        QVERIFY(hints.currentText().isEmpty());

        // Cancelling through the bridge entry point — the same call the
        // form's Escape handler makes — dismisses the form; the stationary
        // cursor's covered target republishes its own profile.
        view.cancelInsertTimePrompt();
        QTRY_VERIFY(!popup->isOpen());
        QTRY_VERIFY(hints.currentSource() == gutter && hints.currentText() == gutterProfile);
    }

    void mouseHintStatusLayoutStaysStable()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &view = session->b->view();
        ui::MouseHints &hints = mouseHints();
        QQuickWindow *const canvas = quickCanvas(view);
        QVERIFY(canvas);
        QQuickItem *const plot = quickItem(view, QLatin1String("timelineRollInput"));
        QQuickItem *const gutter = quickItem(view, QLatin1String("timelineRollGutterInput"));
        QVERIFY(plot && gutter);
        QStatusBar *const bar = window.statusBar();
        QVERIFY(bar);
        QWidget *caption = nullptr;
        for (QWidget *const child : bar->findChildren<QWidget *>())
            if (child->accessibleName() == QStringLiteral("Mouse hint"))
                caption = child;
        QVERIFY(caption);
        QWidget *const meter = window.m_polyMeter;
        QVERIFY(meter);

        const auto captionIsCentered = [&] {
            const QImage image = caption->grab().toImage();
            // The caption paints nothing but the hint text, so ink is
            // whatever differs from the untouched background. Neither ink
            // RGB nor coverage alone is portable: subpixel antialiasing
            // tints glyph pixels far from the pen color, and QWidget::grab
            // fills the unpainted area transparently or opaquely depending
            // on the platform. Corners stay clear of the centered text.
            const QColor bg = image.pixelColor(0, 0);
            int left = image.width();
            int right = -1;
            for (int y = 0; y < image.height(); ++y)
                for (int x = 0; x < image.width(); ++x)
                    if (image.pixelColor(x, y) != bg) {
                        left = qMin(left, x);
                        right = qMax(right, x);
                    }
            const qreal center = caption->mapTo(bar, QPoint()).x() +
                                 (left + right + 1) / (2.0 * image.devicePixelRatio());
            // Ink bounds differ from centered advance widths by glyph bearings.
            const qreal bearingAllowance = QFontMetrics(caption->font()).height() / 2.0;
            return right >= left && qAbs(center - bar->width() / 2.0) <= bearingAllowance;
        };

        hoverAt(*canvas, plot->mapToScene(plot->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == plot);
        const QString profile = hints.currentText();
        QVERIFY(!profile.isEmpty());
        QCoreApplication::processEvents();
        QCOMPARE(caption->accessibleDescription(), profile);
        const int barHeight = bar->height();
        QVERIFY2(captionIsCentered(), "Hint text must be centered on the status bar");

        // An operational message never displaces the hint text or the bar's
        // height; the caption's stretch absorbs the transient message's space.
        bar->showMessage(QStringLiteral("Operational message"), 2000);
        QCoreApplication::processEvents();
        QCOMPARE(hints.currentText(), profile);
        QCOMPARE(caption->accessibleDescription(), profile);
        QCOMPARE(bar->height(), barHeight);

        // Showing the permanent meter leaves the displayed hint and the bar's
        // height alone.
        meter->show();
        QCoreApplication::processEvents();
        const int meterX = meter->x();
        const int meteredHeight = bar->height();
        QCOMPARE(hints.currentText(), profile);
        QVERIFY2(captionIsCentered(), "Showing the meter must not shift the hint center");

        // A longer profile changes only the painted text: the full string
        // stays accessible and the meter does not move.
        hoverAt(*canvas, gutter->mapToScene(gutter->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == gutter);
        QCoreApplication::processEvents();
        QCOMPARE(caption->accessibleDescription(), hints.currentText());
        QCOMPARE(meter->x(), meterX);
        QCOMPARE(bar->height(), meteredHeight);
        QVERIFY2(captionIsCentered(), "Elided hints must retain the status-bar center");

        // An enlarged application font may grow the bar, but the hint text
        // still never drives its height or pushes the meter.
        const QFont originalFont = QApplication::font();
        const QScopeGuard fontRestore([&originalFont] { QApplication::setFont(originalFont); });
        QFont larger = originalFont;
        if (larger.pixelSize() > 0)
            larger.setPixelSize(qRound(larger.pixelSize() * 1.5));
        else
            larger.setPointSizeF(larger.pointSizeF() * 1.5);
        QApplication::setFont(larger);
        QCoreApplication::processEvents();
        const int enlargedHeight = bar->height();
        const int enlargedMeterX = meter->x();
        hoverAt(*canvas, plot->mapToScene(plot->boundingRect().center()).toPoint());
        QTRY_VERIFY(hints.currentSource() == plot);
        QCoreApplication::processEvents();
        QCOMPARE(caption->accessibleDescription(), hints.currentText());
        QCOMPARE(bar->height(), enlargedHeight);
        QCOMPARE(meter->x(), enlargedMeterX);
        QVERIFY2(captionIsCentered(), "Enlarging the font must not shift the hint center");
        meter->hide();
        QCoreApplication::processEvents();
        QVERIFY2(captionIsCentered(), "Hiding the meter must not shift the hint center");
    }

  private:
    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
};

int runMainWindowRoutingStateCheck(const QString &projectRoot, const QString &songA,
                                   const QString &songB, const QStringList &qtArguments)
{
    MainWindowRoutingStateTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("mainwindow-routing-state")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace checks::mainwindowrouting

#include "tst_mainwindowrouting_state.moc"
