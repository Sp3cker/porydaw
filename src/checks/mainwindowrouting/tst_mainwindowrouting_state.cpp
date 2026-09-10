#include "mainwindowroutingfixture.h"

#include <QtTest>

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
        const int tracks = b.document()->engineTrackCount();
        QVERIFY(tracks >= 2);
        const int source = 1;
        const int target = source == tracks - 1 ? 0 : tracks - 1;
        const QByteArray midi = b.document()->smf().write();
        const EditorViewState before = b.editorViewState();
        QVERIFY(b.document()->moveTrack(source, target));
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
        b.document()->undoStack()->undo();
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 2);
        QCOMPARE(hub.count(), 2);
        QCOMPARE(persisted.count(), 2);
        QCOMPARE(a.editorViewState(), before);
        QCOMPARE(b.editorViewState(), before);
        QCOMPARE(b.document()->smf().write(), midi);
        QVERIFY(!b.document()->isDirty());
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
        const QByteArray quietMidi = b.document()->smf().write();
        QVERIFY(b.document()->moveTrack(source, target));
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 0);
        QCOMPARE(hub.count(), 0);
        QCOMPARE(persisted.count(), 0);
        b.document()->undoStack()->undo();
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 0);
        QCOMPARE(projection.count(), 0);
        QCOMPARE(hub.count(), 0);
        QCOMPARE(persisted.count(), 0);
        QCOMPARE(b.document()->smf().write(), quietMidi);
        QVERIFY(!b.document()->isDirty());
    }

    void viewOnlyLaneMutationsPersistWithoutDocumentMutation()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &a = session->a->view();
        SongView &b = session->b->view();
        b.setEditorViewState(completeSeed());
        const QByteArray midi = b.document()->smf().write();
        const uint64_t revision = b.document()->revision();
        const int undoCount = b.document()->undoStack()->count();
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
        QCOMPARE(b.document()->smf().write(), midi);
        QCOMPARE(b.document()->revision(), revision);
        QCOMPARE(b.document()->undoStack()->count(), undoCount);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        next = b.editorViewState();
        next.emptyLanes.erase(lane);
        b.setEditorViewState(next);
        QCoreApplication::processEvents();
        QCOMPARE(origin.count(), 2);
        QCOMPARE(hub.count(), 2);
        QCOMPARE(persisted.count(), 2);
        QCOMPARE(b.document()->smf().write(), midi);
        QCOMPARE(b.document()->revision(), revision);
        QCOMPARE(b.document()->undoStack()->count(), undoCount);
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
        const QByteArray midi = b.document()->smf().write();
        const uint64_t revision = b.document()->revision();
        const EditorViewState settings = loadEditorViewState(QSettings{});
        const auto snapshot = porydawSnapshot(session->fixture->root());
        QSignalSpy origin(&b, &SongView::editorViewStateChanged);
        QSignalSpy hub(window.m_workspace.get(), &WorkspaceUi::editorViewStateChanged);
        QSignalSpy persisted(&window, &MainWindow::editorViewStatePersisted);
        TrackRemap rejected;
        rejected.engineTrackMap = {0, 0};
        rejected.newEngineTrackCount = 2;
        emit b.document()->tracksRemapped(rejected);
        QCoreApplication::processEvents();
        QCOMPARE(a.editorViewState(), beforeA);
        QCOMPARE(b.editorViewState(), beforeB);
        QCOMPARE(b.document()->smf().write(), midi);
        QCOMPARE(b.document()->revision(), revision);
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
