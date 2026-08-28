#include <QApplication>
#include <QComboBox>
#include <QDir>
#include <QLineEdit>
#include <QListWidget>
#include <QSettings>
#include <QStatusBar>
#include <cstdio>

#include "checks/support/asyncwait.h"
#include "mainwindow.h"
#include "ui/songlistpanel.h"

namespace {

template <typename Predicate>
bool waitFor(Predicate predicate)
{
    return checks::async_wait::waitUntil([] { return true; }, predicate, 30000, 1) ==
           checks::async_wait::Result::Ready;
}

} // namespace

// --sessioncheck <projectRoot> <song>: session-persistence check. Verifies
// that restoreSession() reopens the remembered project (and song), is a
// no-op when nothing (or a vanished directory) is remembered, that closing
// a window records the session — window geometry and the song list's
// filter state (search text, sort, category) included — and that a fresh
// window comes back at the saved geometry with the filters reapplied.
// QSettings is redirected into a temp dir first, so the user's real
// session is never read or written. Run against a scratch copy — closing
// writes view sidecars into the project.

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

    // 1. Nothing remembered: restore is a no-op.
    {
        MainWindow window;
        window.restoreSession();
        check(window.windowTitle() == QStringLiteral("porydaw"),
              "restore with no remembered project opened something");
    }

    // 2. The remembered project directory vanished: still a no-op.
    {
        QSettings settings;
        settings.setValue(QStringLiteral("lastProjectDir"), projectRoot + QStringLiteral("/gone"));
        settings.setValue(QStringLiteral("lastSongLabel"), songLabel);
        settings.sync();
        MainWindow window;
        window.restoreSession();
        check(waitFor([&] { return window.windowTitle() == QStringLiteral("porydaw"); }),
              "failed startup open did not tear down its placeholder");
    }

    // 3. Project remembered but no song: the project opens (titled after its
    // directory), nothing loads.
    {
        QSettings settings;
        settings.setValue(QStringLiteral("lastProjectDir"), projectRoot);
        settings.remove(QStringLiteral("lastSongLabel"));
        settings.remove(QStringLiteral("lastOpenSongs"));
        settings.sync();
        MainWindow window;
        window.restoreSession();
        const QString expectedTitle =
            QStringLiteral("%1 — porydaw").arg(QDir(projectRoot).dirName());
        check(waitFor([&] { return window.windowTitle() == expectedTitle; }),
              "remembered project open timed out");
        check(window.statusBar()->currentMessage().startsWith(QStringLiteral("Opened")),
              "remembered project did not open");
        check(window.windowTitle() == expectedTitle,
              "title is not the project name (or a song loaded unasked)");
    }

    // 4. Project + song remembered: both come back; closing at a distinctive
    // size records the geometry, the song list's filter state, and
    // re-records the session. Only lastSongLabel is set here — the pre-tabs
    // session format — so this also proves the single-label fallback
    // restores as one tab; the close then records the tab-list format that
    // block 5 restores from.
    QString filterCategory;
    {
        QSettings().setValue(QStringLiteral("lastSongLabel"), songLabel);
        MainWindow window;
        window.restoreSession();
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
        // Distinctive filter state — search text, A–Z sort, a real
        // category — for block 5 to find again after the relaunch.
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
        // window would come back shrunk and block 5 would fail.
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

    // 5. Relaunch: geometry, session, and song-list filters all come back.
    // The category can only reapply once the project's songs populate the
    // combo, so it's checked after restoreSession().
    {
        MainWindow window;
        check(window.size() == QSize(777, 505), "new window did not restore the saved geometry");
        window.restoreSession();
        auto *search = window.findChild<QLineEdit *>(QStringLiteral("songListSearch"));
        auto *sort = window.findChild<QComboBox *>(QStringLiteral("songListSort"));
        auto *category = window.findChild<QComboBox *>(QStringLiteral("songListCategory"));
        check(waitFor([&] {
                  return window.windowTitle().startsWith(songLabel) && category &&
                         category->currentData().toString() == filterCategory;
              }),
              "relaunch project open timed out");
        check(window.windowTitle().startsWith(songLabel),
              "relaunch did not restore project and song");
        check(search && search->text() == QStringLiteral("filterme"),
              "relaunch did not restore the song filter text");
        check(sort && sort->currentIndex() == 1, "relaunch did not restore the song sort order");
        check(category && category->currentData().toString() == filterCategory,
              "relaunch did not restore the song category filter");
    }

    if (failures == 0)
        std::printf("sessioncheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
