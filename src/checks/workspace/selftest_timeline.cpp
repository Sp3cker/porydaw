#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QSettings>

#include <cmath>

#include "core/miditimeline.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

WorkspaceTimelineSelfTest::WorkspaceTimelineSelfTest(QString projectRoot, QString songLabel)
    : m_songLabel(std::move(songLabel))
    , m_project(std::move(projectRoot))
{}

void WorkspaceTimelineSelfTest::init()
{
    QSettings settings;
    settings.clear();
    settings.sync();
    QString error;
    QVERIFY2(m_project.reset(error), qPrintable(error));
}

void WorkspaceTimelineSelfTest::cleanup()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

SongTab *WorkspaceTimelineSelfTest::openNull(MainWindow &window, SongView *&view)
{
    window.m_persistSession = false;
    if (!window.m_audioOk || !window.m_audio.usingNullBackend() ||
        window.m_audio.backendName() != QStringLiteral("Null"))
        return nullptr;
    auto *workspace = window.m_workspace.get();
    workspace->requestProjectOpenAt(m_project.root());
    if (!workspace_test::waitForProject(*workspace))
        return nullptr;
    const std::optional<SongName> name = workspace_test::songName(m_songLabel);
    if (!name)
        return nullptr;
    SongTab *tab = workspace_test::openReady(*workspace, *name);
    if (!tab || !window.m_audio.songLoaded())
        return nullptr;
    view = &tab->view();
    return tab;
}

bool WorkspaceTimelineSelfTest::startObserved(MainWindow &window, SongTab &tab, SongView &view,
                                              uint64_t samplePosition)
{
    window.stopPlayback();
    if (checks::async_wait::waitUntil(
            [&window, &tab] { return window.m_workspace->songTabFor(tab.name()) == &tab; },
            [&window] {
                return window.m_audio.transport() == Transport::Stopped &&
                       window.m_audio.playheadSamples() == 0;
            },
            2000) != checks::async_wait::Result::Ready)
        return false;
    const uint64_t tick =
        uint64_t(std::llround(window.m_audio.timeline()->tickForSample(samplePosition)));
    view.commitEditCursor(tick);
    const uint64_t before = window.m_audio.playheadSamples();
    window.startPlayback();
    return checks::async_wait::waitUntil(
               [&window, &tab] { return window.m_workspace->songTabFor(tab.name()) == &tab; },
               [&window, before] {
                   return window.m_audio.transport() == Transport::Playing &&
                          window.m_audio.playheadSamples() > before;
               },
               3000) == checks::async_wait::Result::Ready;
}

void WorkspaceTimelineSelfTest::liveTimelineSwapAndUndo()
{
    MainWindow window;
    SongView *view = nullptr;
    SongTab *tab = openNull(window, view);
    QVERIFY(tab);
    QVERIFY(view);
    QVERIFY(startObserved(window, *tab, *view));
    const int track = view->selectionModel().primaryTrack();
    const MidiTimeline *const beforeEdit = tab->timeline().get();
    const uint64_t sampleBeforeEdit = window.m_audio.playheadSamples();
    view->document()->addNote(track, 0, 60, 24, 100);
    view->document()->addLanePoint(track, 7, 0, 100);
    QVERIFY(tab->document().isDirty());
    QTRY_VERIFY(tab->timeline().get() != beforeEdit &&
                window.m_audio.timeline() == tab->timeline().get() &&
                window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() > sampleBeforeEdit);

    DocNote note;
    QVERIFY(tab->document().findNote(track, 0, 60, &note));
    QVERIFY(startObserved(window, *tab, *view));
    const MidiTimeline *const beforeMove = tab->timeline().get();
    const uint64_t sampleBeforeMove = window.m_audio.playheadSamples();
    tab->document().moveNotes({note}, 24, 1);
    QTRY_VERIFY(tab->timeline().get() != beforeMove &&
                window.m_audio.timeline() == tab->timeline().get() &&
                window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() > sampleBeforeMove);
    DocNote moved;

    QVERIFY(tab->document().findNote(track, 24, 61, &moved));
    const uint64_t sampleBeforeUndo = window.m_audio.playheadSamples();
    window.m_workspace->requestUndo();
    window.m_workspace->requestUndo();
    window.m_workspace->requestUndo();
    QTRY_VERIFY(!tab->document().isDirty() && window.m_audio.timeline() == tab->timeline().get() &&
                window.m_audio.transport() == Transport::Playing &&
                window.m_audio.playheadSamples() > sampleBeforeUndo);

    QVERIFY(startObserved(window, *tab, *view));
    const uint64_t sampleBeforePreview = window.m_audio.playheadSamples();
    window.m_audio.previewVoice(0, 60, 112);
    QTest::qWait(300);
    window.m_audio.previewVoice(0, 60, 0);
    QCOMPARE(window.m_audio.transport(), Transport::Playing);
    QVERIFY(window.m_audio.playheadSamples() > sampleBeforePreview);

    window.stopPlayback();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Stopped);
    const SongName name = tab->name();
    window.m_workspace->requestCloseSelectedTab();
    QTRY_VERIFY(!window.m_workspace->songTabFor(name));
    QCOMPARE(window.m_workspace->openTabCount(), qsizetype(0));
}

void WorkspaceTimelineSelfTest::previewWhileStoppedDoesNotStartTransport()
{
    MainWindow window;
    SongView *view = nullptr;
    SongTab *tab = openNull(window, view);
    QVERIFY(tab);
    QVERIFY(view);
    window.stopPlayback();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Stopped);
    window.m_audio.previewVoice(0, 60, 0);
    QCOMPARE(window.m_audio.transport(), Transport::Stopped);
}
