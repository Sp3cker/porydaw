#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QApplication>
#include <QDateTime>
#include <QDial>
#include <QDir>
#include <QFile>
#include <QMessageBox>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSettings>
#include <QSize>
#include <QStatusBar>
#include <QTimer>
#include <cmath>
#include <optional>

#include <vector>

#include "checks/support/voicegroupbrowserdriver.h"
#include "mainwindow.h"
#include "ui/dragspinbox.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspacequick/workspacequickhost.h"
#include "ui/workspaceui.h"

namespace {

EditorViewState persistedEditorState()
{
    auto state = EditorViewState{};
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
    state.velocity = {true, 173};
    state.automation = {true, 91};
    state.voiceChanges = {true, 64};
    state.activePage = EditorDrawerPage::VoiceChanges;
    state.laneHeight = 88;
    state.laneHeights.emplace(lane, 57);
    state.laneRanges.emplace(lane, 100);
    state.emptyLanes.insert(lane);
    state.hideLane(lane);
    return state;
}

} // namespace

void WorkspaceTabsTest::persistenceRestoresTabs()
{
    const EditorViewState editorState = persistedEditorState();
    {
        MainWindow window;
        auto *workspace = window.m_workspace.get();
        QVERIFY(workspace);
        workspace->requestProjectOpenAt(m_project.root());
        QVERIFY(workspace_test::waitForProject(*workspace));
        SongTab *initialFirst = open(window, m_songA);
        QVERIFY(initialFirst);
        const SongView::ViewState firstCanonical = initialFirst->view().viewState();
        SongTab *second = open(window, m_songB);
        QVERIFY(second);
        QCOMPARE(workspace->openTabCount(), qsizetype(1));

        workspace->setEditorViewState(editorState);
        QCOMPARE(second->view().editorViewState(), editorState);
        SongTab *first = open(window, m_songA, true);
        QVERIFY(first);
        QCOMPARE(first->view().editorViewState(), editorState);

        const SongView::ViewState defaults;
        const SongView::ViewState fresh = first->view().viewState();
        QVERIFY(fresh.valid);
        QVERIFY(std::abs(fresh.pxPerBeat - defaults.pxPerBeat) < 0.5);
        QCOMPARE(fresh.keyHeight, defaults.keyHeight);
        QCOMPARE(fresh.scrollPx, -first->view().camera().leadPadPx());
        QCOMPARE(fresh.scrollY, firstCanonical.scrollY);
        QCOMPARE(fresh.selectedTrack, firstCanonical.selectedTrack);
        QCOMPARE(fresh.editCursorTick, uint64_t(0));
        QCOMPARE(fresh.gridMinDenom, 0);
        QVERIFY(!fresh.gridTriplet);
        QVERIFY(!fresh.eventList);
        QVERIFY(!first->view().eventListVisible());
        QVERIFY(first->timeline());
        QVERIFY(first->voicegroupLease());
        QCOMPARE(window.m_audio.timeline(), first->timeline().get());
        QCOMPARE(window.m_audio.voicegroup(), first->voicegroupLease().get());

        auto *host = workspace_test::quickHost(window);
        QVERIFY(host);
        QVERIFY2(workspace_test::exposeWorkspaceHost(window, *host, QSize(1280, 800)),
                 "the production workspace host did not expose its embedded Quick window");
        QQuickWindow *const quickWindow = host->window();
        QVERIFY(quickWindow);
        QQuickItem *tabA = nullptr;
        QQuickItem *tabB = nullptr;
        QTRY_VERIFY((tabA = workspace_test::quickItem(*quickWindow, QStringLiteral("songTab:") +
                                                                        m_songA)) != nullptr);
        QTRY_VERIFY((tabB = workspace_test::quickItem(*quickWindow, QStringLiteral("songTab:") +
                                                                        m_songB)) != nullptr);
        const double targetX =
            tabA->mapToScene(QPointF(tabA->width() * 0.75, tabA->height() / 2)).x();
        workspace_test::dragQuickItemHorizontally(*quickWindow, *tabB, targetX);
        const std::vector<SongTab *> reordered = workspace->tabsInDisplayOrder();
        QCOMPARE(reordered.size(), size_t(2));
        QCOMPARE(reordered[0], first);
        QCOMPARE(reordered[1], second);
        workspace->selectSongTab(second);
        QCOMPARE(workspace->selectedSongTab(), second);
        QCOMPARE(window.m_audio.timeline(), second->timeline().get());
        QCOMPARE(window.m_audio.voicegroup(), second->voicegroupLease().get());

        QSettings settings;
        const QStringList expectedOpenSongs{m_songA, m_songB};
        QCOMPARE(settings.value(QStringLiteral("lastOpenSongs")).toStringList(), expectedOpenSongs);
        QCOMPARE(settings.value(QStringLiteral("lastSongLabel")).toString(), m_songB);
        auto *outputDial = window.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
        QVERIFY(outputDial);
        outputDial->setValue(37);
        QCOMPARE(window.m_audio.outputVolume(), 37);
        const std::vector<SongTab *> tabs = workspace->tabsInDisplayOrder();
        QCOMPARE(tabs.size(), size_t(2));
        QCOMPARE(tabs[0], first);
        QCOMPARE(tabs[1], second);
        QCOMPARE(workspace->selectedSongTab(), second);
        window.close();
    }

    MainWindow restored;
    auto *workspace = restored.m_workspace.get();
    QVERIFY(workspace);
    QTRY_COMPARE(workspace->openTabCount(), qsizetype(2));
    const std::optional<SongName> firstName = workspace_test::songName(m_songA);
    const std::optional<SongName> secondName = workspace_test::songName(m_songB);
    QVERIFY(firstName);
    QVERIFY(secondName);
    SongTab *first = workspace->songTabFor(*firstName);
    SongTab *second = workspace->songTabFor(*secondName);
    QTRY_VERIFY(first && second && first->isReady() && second->isReady());
    const std::vector<SongTab *> tabs = workspace->tabsInDisplayOrder();
    QCOMPARE(tabs.size(), size_t(2));
    QCOMPARE(tabs[0], first);
    QCOMPARE(tabs[1], second);
    QCOMPARE(workspace->selectedSongTab(), second);
    QCOMPARE(restored.m_audio.timeline(), second->timeline().get());
    QCOMPARE(restored.m_audio.voicegroup(), second->voicegroupLease().get());
    QCOMPARE(first->view().editorViewState(), editorState);
    QCOMPARE(second->view().editorViewState(), editorState);
    auto *outputDial = restored.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
    QVERIFY(outputDial);
    QCOMPARE(outputDial->value(), 37);
}

void WorkspaceTabsTest::voicegroupRefresh()
{
    QString phase = QStringLiteral("constructing the workspace window");
    QString modalFailure;
    QTimer modalWatchdog;
    modalWatchdog.setInterval(1);
    connect(&modalWatchdog, &QTimer::timeout, qApp, [&] {
        QWidget *const modal = QApplication::activeModalWidget();
        if (!modal)
            return;
        modalWatchdog.stop();
        if (auto *const box = qobject_cast<QMessageBox *>(modal)) {
            modalFailure = QStringLiteral("%1 opened an unexpected modal \"%2\": %3 %4")
                               .arg(phase, box->windowTitle(), box->text(), box->informativeText());
            box->reject();
            return;
        }
        modalFailure = QStringLiteral("%1 opened an unexpected modal of type %2")
                           .arg(phase, QString::fromLatin1(modal->metaObject()->className()));
        modal->close();
    });
    modalWatchdog.start();

    MainWindow window;
    QVERIFY2(modalFailure.isEmpty(), qPrintable(modalFailure));
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    phase = QStringLiteral("opening the fixture project");
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY2(workspace_test::waitForProject(*workspace), qPrintable(phase));
    phase = QStringLiteral("opening the source fixture song");
    SongTab *source = open(window, m_songA);
    QVERIFY2(source, qPrintable(phase));
    phase = QStringLiteral("opening the observer fixture song");
    SongTab *observer = open(window, m_songB, true);
    QVERIFY2(observer, qPrintable(phase));
    QVERIFY2(source->voicegroupId(), "source fixture song has no editable voicegroup identity");
    QVERIFY2(observer->voicegroupId(), "observer fixture song has no editable voicegroup identity");
    QCOMPARE(*source->voicegroupId(), *observer->voicegroupId());
    workspace->selectSongTab(source);

    checks::VoicegroupBrowserDriver driver(*workspace);
    QVERIFY2(driver.isAvailable(), "voicegroup browser is unavailable for the shared fixture bank");
    QVERIFY2(driver.selectedBankView(), "shared fixture bank did not reach the browser");
    QVERIFY2(driver.releaseSpinBox(), "shared fixture bank has no release editor");
    const VoicegroupLease sourceLease = source->voicegroupLease();
    const VoicegroupLease observerLease = observer->voicegroupLease();
    QVERIFY2(sourceLease, "source fixture song did not publish its shared voicegroup");
    QVERIFY2(observerLease, "observer fixture song did not publish its shared voicegroup");
    int directSoundSlot = -1;
    for (int index = 0; index < VOICEGROUP_SIZE; ++index) {
        const uint8_t type = sourceLease->voices[index].type;
        if (type == VOICE_DIRECTSOUND || type == VOICE_DIRECTSOUND_NO_RESAMPLE ||
            type == VOICE_DIRECTSOUND_ALT) {
            directSoundSlot = index;
            break;
        }
    }
    QVERIFY2(directSoundSlot >= 0, "shared fixture voicegroup has no direct-sound voice");

    const auto waitForPhase = [&](auto ready) {
        const auto result =
            checks::async_wait::waitUntil([&] { return modalFailure.isEmpty(); }, ready, 5000, 1);
        if (result == checks::async_wait::Result::Ready)
            return true;
        if (modalFailure.isEmpty()) {
            modalFailure = QStringLiteral("%1 did not settle within 5 seconds (status: %2)")
                               .arg(phase, window.statusBar()->currentMessage());
        }
        return false;
    };

    const uint8_t beforeRelease = sourceLease->voices[directSoundSlot].release;
    const uint8_t editedRelease = beforeRelease == 25 ? 26 : 25;
    const MidiTimeline *const observerTimeline = observer->timeline().get();
    driver.selectSlot(directSoundSlot);
    QCOMPARE(driver.releaseSpinBox()->value(), int(beforeRelease));
    phase = QStringLiteral("editing the shared voicegroup release");
    driver.releaseSpinBox()->setValue(editedRelease);
    const bool editSettled = waitForPhase([&] {
        return workspace->bankActionsEnabled() &&
               source->voicegroupLease().get() != sourceLease.get() &&
               observer->voicegroupLease().get() != observerLease.get() &&
               source->voicegroupLease()->voices[directSoundSlot].release == editedRelease &&
               observer->voicegroupLease()->voices[directSoundSlot].release == editedRelease;
    });
    QVERIFY2(editSettled, qPrintable(modalFailure));
    const VoicegroupLease editedObserverLease = observer->voicegroupLease();

    phase = QStringLiteral("saving the shared voicegroup");
    workspace->saveSelectedSong();
    const bool saveSettled = waitForPhase([&] {
        const LoadedBankView *const savedBank = driver.selectedBankView();
        return savedBank && !savedBank->dirty && !workspace->selectedSongDirty() &&
               observer->voicegroupLease().get() != editedObserverLease.get() &&
               observer->voicegroupLease()->voices[directSoundSlot].release == editedRelease;
    });
    QVERIFY2(saveSettled, qPrintable(modalFailure));
    QVERIFY(!observer->document().isDirty());
    QCOMPARE(observer->timeline().get(), observerTimeline);

    workspace->selectSongTab(observer);
    QVERIFY(!workspace->selectedSongDirty());
    const VoicegroupLease cachedLease = observer->voicegroupLease();
    phase = QStringLiteral("reloading the unchanged observer voicegroup");
    workspace->requestSongOpen(observer->name());
    const bool unchangedReloadSettled = waitForPhase([&] { return observer->isReady(); });
    QVERIFY2(unchangedReloadSettled, qPrintable(modalFailure));
    QCOMPARE(observer->voicegroupLease().get(), cachedLease.get());
    QVERIFY(!observer->document().isDirty());

    const QString voicegroupPath =
        QDir(m_project.root()).filePath(observer->voicegroupId()->sourceRelativePath());
    QFile file(voicegroupPath);
    QVERIFY2(file.open(QIODevice::ReadWrite), qPrintable(file.errorString()));
    QVERIFY2(file.setFileTime(QDateTime::currentDateTimeUtc().addSecs(2),
                              QFileDevice::FileModificationTime),
             qPrintable(file.errorString()));
    file.close();
    phase = QStringLiteral("reloading the touched observer voicegroup");
    workspace->requestSongOpen(observer->name());
    const bool touchedReloadSettled = waitForPhase([&] {
        return observer->isReady() && observer->voicegroupLease().get() != cachedLease.get();
    });
    QVERIFY2(touchedReloadSettled, qPrintable(modalFailure));
    QVERIFY(!observer->document().isDirty());
    modalWatchdog.stop();
}
