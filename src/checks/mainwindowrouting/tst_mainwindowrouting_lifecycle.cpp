#include "checks/support/support.h"
#include "mainwindowroutingfixture.h"
#include "ui/songview.h"

#include <QCloseEvent>

#include <QtTest>

namespace checks::mainwindowrouting {

class MainWindowRoutingLifecycleTest final : public QObject, private MainWindowRoutingFixture
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MainWindowRoutingLifecycleTest)

  public:
    MainWindowRoutingLifecycleTest(QString projectRoot, QString songA, QString songB)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
    {}

  private slots:
    void closeAndReopenProjectsGlobalState()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        const EditorViewState state = completeSeed();
        session->b->view().setEditorViewState(state);
        const auto snapshot = porydawSnapshot(session->fixture->root());
        window.m_workspace->selectSongTab(session->b);
        const SongName name = session->b->name();
        window.m_workspace->requestCloseSelectedTab();
        QCOMPARE(window.m_workspace->openTabCount(), qsizetype{1});
        QVERIFY(window.m_workspace->songTabFor(name) == nullptr);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        window.m_workspace->requestSongOpen(name, true);
        SongTab *reopened = window.m_workspace->selectedSongTab();
        QVERIFY(reopened);
        QVERIFY(waitForTabReady(*window.m_workspace, reopened));
        QCOMPARE(reopened->view().editorViewState(), state);
        QVERIFY(reopened->timeline());
        QVERIFY(hasCanonicalFreshViewState(reopened->view(), *reopened->timeline()));
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
    }

    void readyReloadPreservesTransients()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab *reopened = session->b;
        SongView &view = reopened->view();
        const SongView::ViewState before = view.viewState();
        int alternateTrack = -1;
        for (int track = 0; track < 16; ++track) {
            if (reopened->timeline()->tracks[track].used && track != before.selectedTrack) {
                alternateTrack = track;
                break;
            }
        }
        QVERIFY(alternateTrack >= 0);
        SongView::ViewState requested;
        requested.valid = true;
        requested.pxPerBeat = before.pxPerBeat * 2.0;
        requested.keyHeight = before.keyHeight * 1.5;
        requested.scrollPx = (std::numeric_limits<double>::max)();
        requested.scrollY = (std::numeric_limits<double>::max)();
        requested.selectedTrack = alternateTrack;
        requested.editCursorTick =
            before.editCursorTick == 0 ? reopened->timeline()->ticksPerBeat : 0;
        requested.gridMinDenom = 16;
        requested.gridTriplet = true;
        requested.eventList = true;
        view.applyViewState(requested);
        SongView::ViewState seeded = view.viewState();
        if (seeded.scrollPx == before.scrollPx || seeded.scrollY == before.scrollY) {
            if (seeded.scrollPx == before.scrollPx)
                requested.scrollPx = 0.0;
            if (seeded.scrollY == before.scrollY)
                requested.scrollY = 0.0;
            view.applyViewState(requested);
            seeded = view.viewState();
        }
        QVERIFY(seeded.scrollPx != before.scrollPx);
        QVERIFY(seeded.scrollY != before.scrollY);
        QCOMPARE(seeded.selectedTrack, alternateTrack);
        QCOMPARE(seeded.gridMinDenom, 16);
        QVERIFY(seeded.gridTriplet);
        QVERIFY(seeded.eventList);
        QTabBar *tabBar = window.findChild<QTabBar *>();
        QVERIFY(tabBar);
        tabBar->setFocusPolicy(Qt::StrongFocus);
        tabBar->setFocus(Qt::OtherFocusReason);
        QCOMPARE(QApplication::focusWidget(), tabBar);
        QSignalSpy eventListTraffic(&view, &SongView::eventListVisibilityChanged);
        view.applyViewState(seeded);
        QCOMPARE(QApplication::focusWidget(), tabBar);
        eventListTraffic.clear();
        const MidiTimeline *beforeReload = reopened->timeline().get();
        const SongName name = reopened->name();
        const auto snapshot = porydawSnapshot(session->fixture->root());
        window.m_workspace->requestSongOpen(name);
        QVERIFY(!reopened->isReady());
        QCOMPARE(reopened->timeline().get(), beforeReload);
        bool stateDropped = false;
        const auto reload = checks::async_wait::waitUntil(
            [&window, reopened, &name] { return window.m_workspace->songTabFor(name) == reopened; },
            [&] {
                if (!reopened->isReady()) {
                    stateDropped =
                        stateDropped || !sameViewState(reopened->view().viewState(), seeded);
                    return false;
                }
                return reopened->timeline().get() != beforeReload;
            },
            30000, 1);
        QCOMPARE(reload, checks::async_wait::Result::Ready);
        QVERIFY(!stateDropped);
        QVERIFY(reopened->isReady());
        QVERIFY(reopened->timeline().get() != beforeReload);
        QVERIFY(sameViewState(reopened->view().viewState(), seeded));
        QCOMPARE(eventListTraffic.count(), 0);
        QCOMPARE(QApplication::focusWidget(), tabBar);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
    }

    void freshBind()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        const SongName name = session->b->name();
        const auto &songs = workspace.projectState().snapshot.songs();
        const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
            return info.label == name.value();
        });
        QVERIFY(song != songs.cend());
        QVERIFY(session->b->voicegroupId());
        SmfFile stage;
        QString error;
        QVERIFY(SmfFile::readFile(song->midPath, &stage, &error));
        LoadedVoiceGroup bank = {};
        SongTab probe(name);
        const EditorViewState global = completeSeed();
        probe.view().applyEditorViewState(global);
        QSignalSpy ready(&probe, &SongTab::readinessChanged);
        QVERIFY(!probe.isReady());
        probe.applyMidiStage(*song, std::move(stage),
                             workspace.projectState().snapshot.trackBudgetFor(*song));
        QVERIFY(!probe.isReady());
        QVERIFY(probe.timeline());
        QCOMPARE(probe.view().document(), &probe.document());
        QCOMPARE(probe.view().editorViewState(), global);
        QVERIFY(hasCanonicalFreshViewState(probe.view(), *probe.timeline()));
        QCOMPARE(ready.count(), 0);
        probe.applyBankView(
            LoadedBankView{*session->b->voicegroupId(), borrowVoicegroupLease(&bank), QString()});
        QCOMPARE(ready.count(), 0);
        probe.applyVoicegroupBound(*session->b->voicegroupId());
        QVERIFY(probe.isReady());
        checks::support::bindEditActionsForTest(probe.view());
        QCOMPARE(ready.count(), 1);
    }

    void stagedReload()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        const SongName name = session->b->name();
        const auto &songs = workspace.projectState().snapshot.songs();
        const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
            return info.label == name.value();
        });
        QVERIFY(song != songs.cend());
        QVERIFY(session->b->voicegroupId());
        QString error;
        SmfFile initial;
        SmfFile replacement;
        QVERIFY(SmfFile::readFile(song->midPath, &initial, &error));
        QVERIFY(SmfFile::readFile(song->midPath, &replacement, &error));
        const VoicegroupId identity = *session->b->voicegroupId();
        LoadedVoiceGroup bank = {};
        SongTab probe(name);
        const int budget = workspace.projectState().snapshot.trackBudgetFor(*song);
        probe.applyMidiStage(*song, std::move(initial), budget);
        probe.applyBankView(LoadedBankView{identity, borrowVoicegroupLease(&bank), QString()});
        probe.applyVoicegroupBound(identity);
        checks::support::bindEditActionsForTest(probe.view());
        QVERIFY(probe.isReady());
        const MidiTimeline *bound = probe.timeline().get();
        SongView::ViewState state = probe.view().viewState();
        state.valid = true;
        state.pxPerBeat *= 2.0;
        state.keyHeight *= 1.5;
        state.editCursorTick = probe.timeline()->ticksPerBeat * 4;
        state.gridMinDenom = 16;
        state.gridTriplet = true;
        probe.view().applyViewState(state);
        const SongView::ViewState retained = probe.view().viewState();
        QSignalSpy ready(&probe, &SongTab::readinessChanged);
        probe.beginMidiReload();
        QVERIFY(!probe.isReady());
        QCOMPARE(probe.timeline().get(), bound);
        QVERIFY(sameViewState(probe.view().viewState(), retained));
        QCOMPARE(ready.count(), 1);
        probe.applyMidiStage(*song, std::move(replacement), budget);
        QVERIFY(!probe.isReady());
        QVERIFY(probe.timeline().get() != bound);
        QVERIFY(sameViewState(probe.view().viewState(), retained));
        QCOMPARE(ready.count(), 1);
        probe.applyVoicegroupBound(identity);
        QVERIFY(probe.isReady());
        QVERIFY(sameViewState(probe.view().viewState(), retained));
        QCOMPARE(ready.count(), 2);
    }

    void bankRebind()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        WorkspaceUi &workspace = *session->window->m_workspace;
        const SongName name = session->b->name();
        const auto &songs = workspace.projectState().snapshot.songs();
        const auto song = std::find_if(songs.cbegin(), songs.cend(), [&name](const SongInfo &info) {
            return info.label == name.value();
        });
        QVERIFY(song != songs.cend());
        QVERIFY(session->b->voicegroupId());
        SmfFile stage;
        QString error;
        QVERIFY(SmfFile::readFile(song->midPath, &stage, &error));
        const VoicegroupId identity = *session->b->voicegroupId();
        LoadedVoiceGroup initial;
        LoadedVoiceGroup replacement;
        SongTab probe(name);
        probe.applyMidiStage(*song, std::move(stage),
                             workspace.projectState().snapshot.trackBudgetFor(*song));
        probe.applyBankView(LoadedBankView{identity, borrowVoicegroupLease(&initial), QString()});
        probe.applyVoicegroupBound(identity);
        checks::support::bindEditActionsForTest(probe.view());
        QVERIFY(probe.isReady());
        const MidiTimeline *timeline = probe.timeline().get();
        const SongView::ViewState state = probe.view().viewState();
        QSignalSpy ready(&probe, &SongTab::readinessChanged);
        probe.applyBankView(
            LoadedBankView{identity, borrowVoicegroupLease(&replacement), QString()});
        probe.applyVoicegroupBound(identity);
        QVERIFY(probe.isReady());
        QCOMPARE(probe.timeline().get(), timeline);
        QCOMPARE(probe.voicegroupLease().get(), &replacement);
        QVERIFY(sameViewState(probe.view().viewState(), state));
        QCOMPARE(ready.count(), 0);
    }

    void failedOpenPreservesLiveTab()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        WorkspaceUi &workspace = *window.m_workspace;
        const EditorViewState state = completeSeed();
        session->b->view().setEditorViewState(state);
        const auto snapshot = porydawSnapshot(session->fixture->root());
        SongTab *old = session->b;
        const qsizetype count = workspace.openTabCount();
        const QString label = old->document().label();
        QVERIFY(!old->document().isDirty());
        workspace.requestSongOpen(old->name());
        workspace.requestProjectOpenAt(session->fixture->root() +
                                       QStringLiteral("/missing-project"));
        const auto failed = [&workspace] {
            if (QPointer<QMessageBox> box =
                    qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
                box && !box->property("dismissalQueued").toBool()) {
                box->setProperty("dismissalQueued", true);
                QTimer::singleShot(0, box, [box] { box->reject(); });
            }
            return workspace.projectState().state == ProjectOpenState::Failed;
        };
        QCOMPARE(checks::async_wait::waitUntil([] { return true; }, failed, 30000, 1),
                 checks::async_wait::Result::Ready);
        QCOMPARE(workspace.selectedSongTab(), old);
        QCOMPARE(workspace.openTabCount(), count);
        QCOMPARE(workspace.projectState().snapshot.root(), session->fixture->root());
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QVERIFY(waitForTabReady(workspace, old));
        QCOMPARE(old->document().label(), label);
    }

    void projectSwitchAndQuitPreserveState()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        WorkspaceUi &workspace = *window.m_workspace;
        const EditorViewState state = completeSeed();
        session->b->view().setEditorViewState(state);
        const auto snapshot = porydawSnapshot(session->fixture->root());
        const QByteArray midiA = session->a->document().smf().write();
        const QByteArray midiB = session->b->document().smf().write();
        const int undoA = session->a->document().undoStack()->count();
        const int undoB = session->b->document().undoStack()->count();
        workspace.requestProjectOpenAt(session->fixture->root());
        QVERIFY(waitForProjectReady(workspace));
        QCOMPARE(workspace.openTabCount(), qsizetype{0});
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QCOMPARE(loadEditorViewState(QSettings{}), state);
        const auto aName = SongName::create(m_songA);
        const auto bName = SongName::create(m_songB);
        QVERIFY(aName);
        QVERIFY(bName);
        workspace.requestSongOpen(*aName);
        SongTab *reopenedA = workspace.selectedSongTab();
        QVERIFY(waitForTabReady(workspace, reopenedA));
        QCOMPARE(reopenedA->view().editorViewState(), state);
        QCOMPARE(reopenedA->document().smf().write(), midiA);
        QCOMPARE(reopenedA->document().undoStack()->count(), undoA);
        workspace.requestSongOpen(*bName, true);
        SongTab *reopenedB = workspace.selectedSongTab();
        QVERIFY(waitForTabReady(workspace, reopenedB));
        QCOMPARE(reopenedB->view().editorViewState(), state);
        QCOMPARE(reopenedB->document().smf().write(), midiB);
        QCOMPARE(reopenedB->document().undoStack()->count(), undoB);
        QCloseEvent close;
        QApplication::sendEvent(&window, &close);
        QVERIFY(close.isAccepted());
        QVERIFY(window.m_closeAccepted);
        window.close();
        QCOMPARE(checks::async_wait::waitUntil(
                     [] { return true; }, [&window] { return window.m_closeAccepted; }, 30000, 1),
                 checks::async_wait::Result::Ready);
        QVERIFY(porydawSnapshot(session->fixture->root()) == snapshot);
        QCOMPARE(loadEditorViewState(QSettings{}), state);
    }

  private:
    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
};

int runMainWindowRoutingLifecycleCheck(const QString &projectRoot, const QString &songA,
                                       const QString &songB, const QStringList &qtArguments)
{
    MainWindowRoutingLifecycleTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("mainwindow-routing-lifecycle")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace checks::mainwindowrouting

#include "tst_mainwindowrouting_lifecycle.moc"
