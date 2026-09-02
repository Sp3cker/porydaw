#include <QApplication>
#include <QComboBox>
#include <QLineEdit>
#include <QListWidget>
#include <QSettings>
#include <QVariant>
#include <cstdio>
#include <map>
#include <vector>

#include "checks/support/asyncwait.h"
#include "mainwindow.h"
#include "ui/layout.h"
#include "ui/songlistpanel.h"
#include "ui/songtab.h"
#include "ui/songview.h"

namespace {

using SettingsSnapshot = std::map<QString, QVariant>;

SettingsSnapshot settingsSnapshot()
{
    QSettings settings;
    settings.sync();
    SettingsSnapshot snapshot;
    for (const QString &key : settings.allKeys())
        snapshot.emplace(key, settings.value(key));
    return snapshot;
}

template <typename Predicate>
bool waitFor(Predicate predicate)
{
    return checks::async_wait::waitUntil([] { return true; }, predicate, 30000, 1) ==
           checks::async_wait::Result::Ready;
}

} // namespace

// --sessioncheck <projectRoot> <song>: session-persistence check. Verifies
// that closing a window records the workspace, window geometry, editor state,
// and song-list filters, then a fresh window restores them without emitting
// false persistence changes. QSettings is redirected into a temp dir first,
// so the user's real session is never read or written.

int runSessionCheck(const QString &projectRoot, const QString &songLabel)
{
    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "sessioncheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };

    // 1. Project + song remembered: both come back; closing at a distinctive
    // size records the geometry, the song list's filter state, and
    // re-records the session. Only lastSongLabel is set here — the pre-tabs
    // session format — so this also proves the single-label fallback
    // restores as one tab; the close then records the tab-list format that
    // the relaunch restores from.
    QString filterCategory;

    const EditorViewState completeEditorState = [] {
        const EditorAutomationRowId lane0{EditorAutomationRowKind::ControlChange, 0, 74};
        const EditorAutomationRowId hiddenFirst{EditorAutomationRowKind::ControlChange, 1, 7};
        const EditorAutomationRowId hiddenSecond{EditorAutomationRowKind::ControlChange, 0, 80};
        const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
        const int laneHeightFloor = layout::fontPx(7.0 / 3.0);
        const int laneHeightCeiling = layout::fontPx(32.0 / 3.0);
        EditorViewState state;
        state.velocity = {false, 131};
        state.automation = {true, 143};
        state.voiceChanges = {true, 157};
        state.activePage = EditorDrawerPage::VoiceChanges;
        state.laneHeight = (laneHeightFloor + laneHeightCeiling) / 2;
        state.laneHeights = {{lane0, laneHeightFloor + 3}, {hiddenFirst, laneHeightFloor + 5}};
        state.laneRanges = {{lane0, 90}, {tempoRow, 100}};
        state.emptyLanes.insert(lane0);
        state.hideLane(hiddenFirst);
        state.hideLane(hiddenSecond);
        return state;
    }();
    SettingsSnapshot settingsBoundary;
    {
        QSettings startupSettings;
        startupSettings.setValue(QStringLiteral("lastProjectDir"), projectRoot);
        startupSettings.setValue(QStringLiteral("lastSongLabel"), songLabel);
        MainWindow window;
        // Resolve the Songs dock's list rather than any drawer-owned list.
        auto *panel = window.findChild<SongListPanel *>();
        auto *list = panel ? panel->findChild<QListWidget *>() : nullptr;
        check(waitFor([&] {
                  return window.windowTitle().startsWith(songLabel) && list &&
                         list->currentItem() && list->currentItem()->text().startsWith(songLabel);
              }),
              "remembered song project open timed out");
        check(window.windowTitle().startsWith(songLabel), "remembered song did not load");
        check(list && list->currentItem() && list->currentItem()->text().startsWith(songLabel),
              "restored song is not selected in the song list");
        WorkspaceUi *const workspace = window.findChild<WorkspaceUi *>();
        check(workspace != nullptr,
              "initial session could not discover WorkspaceUi through MainWindow");
        int persistedCompletions = 0;
        const QMetaObject::Connection persistenceSpy = QObject::connect(
            &window, &MainWindow::editorViewStatePersisted, &window,
            [&persistedCompletions](const EditorViewState &) { ++persistedCompletions; });
        if (workspace)
            workspace->setEditorViewState(completeEditorState);
        check(persistedCompletions == 1,
              "setting the complete editor state did not complete one public persistence");
        bool projected = workspace != nullptr;
        if (workspace) {
            const auto tabs = workspace->tabsInDisplayOrder();
            projected = !tabs.empty();
            for (SongTab *tab : tabs)
                projected =
                    projected && tab && tab->view().editorViewState() == completeEditorState;
        }
        check(projected, "the complete editor state did not project to the open tab");
        QSettings editorStateSettings;
        check(loadEditorViewState(editorStateSettings) == completeEditorState,
              "the complete editor state was not readable through QSettings");
        QObject::disconnect(persistenceSpy);
        // Distinctive filter state — search text, A–Z sort, a real
        // category — for the next window to find again after the relaunch.
        auto *search = window.findChild<QLineEdit *>(QStringLiteral("songListSearch"));
        auto *category = window.findChild<QComboBox *>(QStringLiteral("songListCategory"));
        auto *sort = window.findChild<QComboBox *>(QStringLiteral("songListSort"));
        if (check(search && category && sort, "song list filter widgets not found")) {
            if (category->count() > 1)
                category->setCurrentIndex(1);
            filterCategory = category->currentData().toString();
            sort->setCurrentIndex(1);
            search->setText(QStringLiteral("filterme"));
        }
        // Must fit the offscreen platform's 800x600 virtual screen: newer Qt
        // clamps restoreGeometry() to the available screen, so an oversized
        // window would come back shrunk and the relaunch check would fail.
        window.resize(777, 505);
        window.close();
        check(
            waitFor([&] {
                QSettings settings;
                return !settings.value(QStringLiteral("windowGeometry")).toByteArray().isEmpty() &&
                       settings.value(QStringLiteral("lastSongLabel")).toString() == songLabel &&
                       settings.value(QStringLiteral("lastOpenSongs")).toStringList() ==
                           QStringList(songLabel);
            }),
            "close was refused");
        QSettings settings;
        check(!settings.value(QStringLiteral("windowGeometry")).toByteArray().isEmpty(),
              "close did not save window geometry");
        check(settings.value(QStringLiteral("lastProjectDir")).toString() == projectRoot,
              "close lost the remembered project");
        check(settings.value(QStringLiteral("lastSongLabel")).toString() == songLabel,
              "close lost the remembered song");
        check(settings.value(QStringLiteral("lastOpenSongs")).toStringList() ==
                  QStringList(songLabel),
              "close did not record the open tab list");
        check(settings.value(QStringLiteral("songFilterText")).toString() ==
                  QStringLiteral("filterme"),
              "close did not save the song filter text");
    }
    // Capture every redirected QSettings value after the close, including
    // the complete editor-view codec entries.
    settingsBoundary = settingsSnapshot();

    // 2. Relaunch: geometry, session, and song-list filters all come back.
    // The category can only reapply once the project's songs populate the
    // combo, so it is checked after asynchronous startup restoration.
    {
        MainWindow window;
        WorkspaceUi *const workspace = window.findChild<WorkspaceUi *>();
        const auto startupTabs =
            workspace ? workspace->tabsInDisplayOrder() : std::vector<SongTab *>{};
        bool constructorInjected = workspace != nullptr && !startupTabs.empty();
        for (SongTab *tab : startupTabs)
            constructorInjected =
                constructorInjected && tab && tab->view().editorViewState() == completeEditorState;
        check(constructorInjected,
              "fresh MainWindow did not inject the complete editor state before startup restore");
        check(settingsSnapshot() == settingsBoundary,
              "fresh MainWindow constructor wrote the redirected settings");

        int persistedDuringRestore = 0;
        int hubChangesDuringRestore = 0;
        const QMetaObject::Connection persistenceSpy = QObject::connect(
            &window, &MainWindow::editorViewStatePersisted, &window,
            [&persistedDuringRestore](const EditorViewState &) { ++persistedDuringRestore; });
        QMetaObject::Connection hubSpy;
        if (workspace) {
            hubSpy = QObject::connect(
                workspace, &WorkspaceUi::editorViewStateChanged, &window,
                [&hubChangesDuringRestore](const EditorViewState &) { ++hubChangesDuringRestore; });
        }

        auto *search = window.findChild<QLineEdit *>(QStringLiteral("songListSearch"));
        auto *sort = window.findChild<QComboBox *>(QStringLiteral("songListSort"));
        auto *category = window.findChild<QComboBox *>(QStringLiteral("songListCategory"));
        SongTab *restoredTab = nullptr;
        const bool restoredReady = waitFor([&] {
            restoredTab = workspace ? workspace->selectedSongTab() : nullptr;
            return window.windowTitle().startsWith(songLabel) && category &&
                   category->currentData().toString() == filterCategory && restoredTab &&
                   restoredTab->isReady();
        });
        check(restoredReady, "relaunch project or selected tab readiness timed out");
        check(window.windowTitle().startsWith(songLabel),
              "relaunch did not restore project and song");
        check(search && search->text() == QStringLiteral("filterme"),
              "relaunch did not restore the song filter text");
        check(sort && sort->currentIndex() == 1, "relaunch did not restore the song sort order");
        check(category && category->currentData().toString() == filterCategory,
              "relaunch did not restore the song category filter");
        check(restoredTab && workspace && workspace->selectedSongTab() == restoredTab &&
                  restoredTab->isReady() &&
                  restoredTab->view().editorViewState() == completeEditorState &&
                  restoredTab->view().editorViewState().hiddenLanes() ==
                      completeEditorState.hiddenLanes(),
              "startup restore did not silently project the complete editor state and hidden-lane "
              "order");
        check(persistedDuringRestore == 0 && hubChangesDuringRestore == 0,
              "startup restore emitted an editor-state origin or persistence completion");
        QObject::disconnect(persistenceSpy);
        if (workspace)
            QObject::disconnect(hubSpy);
    }

    if (failures == 0)
        std::printf("sessioncheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
