#include "checks/support/loadedshell.h"

#include "checks/support/asyncwait.h"
#include "mainwindow.h"
#include "project/decompproject.h"
#include "project/projectidentity.h"
#include "project/projectworkspace.h"
#include "ui/songlistpanel.h"
#include "ui/songtab.h"
#include "ui/workspaceui.h"

#include <QApplication>
#include <QFileInfo>
#include <QMetaObject>
#include <QString>

namespace checks::support {
namespace {

// The staged decomp fixture's first song; the loaded-shell baselines freeze the
// shell with this song open.
constexpr char kLoadedSong[] = "mus_route101";
constexpr int kOpenTimeoutMs = 30000;

bool waitForProjectReady(const WorkspaceUi &workspace)
{
    return checks::async_wait::waitUntil(
               [] { return true; },
               [&workspace] { return workspace.projectState().state == ProjectOpenState::Ready; },
               kOpenTimeoutMs, 1) == checks::async_wait::Result::Ready;
}

bool waitForTabReady(WorkspaceUi &workspace, SongTab *tab)
{
    return tab && checks::async_wait::waitUntil(
                      [&workspace, tab] { return workspace.songTabFor(tab->name()) == tab; },
                      [tab] { return tab->isReady(); }, kOpenTimeoutMs,
                      1) == checks::async_wait::Result::Ready;
}

} // namespace

LoadedShell openLoadedShell(const QString &projectRoot, QString *error)
{
    const auto fail = [error](const QString &message) {
        if (error)
            *error = message;
        return LoadedShell{};
    };
    if (projectRoot.isEmpty()) {
        return fail(QStringLiteral(
            "PORYDAW_VISUAL_PROJECT_ROOT must point at a staged decomp project fixture root (the "
            "check catalog stages decompProjectFiles + decompMidiFiles into {scratch} and exports "
            "this variable); the loaded-shell baseline cannot be captured without a real project"));
    }
    if (!QFileInfo(projectRoot).isDir())
        return fail(QStringLiteral("project root '%1' is not a directory").arg(projectRoot));
    if (error)
        error->clear();

    LoadedShell shell;
    shell.window = std::make_unique<MainWindow>();
    auto *workspace = shell.window->findChild<WorkspaceUi *>();
    if (!workspace)
        return fail(QStringLiteral("the production shell has no WorkspaceUi"));
    workspace->requestProjectOpenAt(projectRoot);
    if (!waitForProjectReady(*workspace))
        return fail(QStringLiteral("project '%1' never reached its ready state").arg(projectRoot));

    const auto song = SongName::create(QString::fromLatin1(kLoadedSong));
    if (!song)
        return fail(
            QStringLiteral("'%1' is not a valid song name").arg(QLatin1String(kLoadedSong)));
    workspace->requestSongOpen(*song);
    SongTab *tab = workspace->songTabFor(*song);
    if (!tab)
        return fail(QStringLiteral("opening '%1' created no song tab").arg(song->value()));
    if (!waitForTabReady(*workspace, tab))
        return fail(QStringLiteral("song tab '%1' never became ready").arg(song->value()));

    // uiTick is a private slot but still a slot: invoke it through the meta
    // object so the status polyphony meter reflects the loaded song.
    if (!QMetaObject::invokeMethod(shell.window.get(), "uiTick"))
        return fail(QStringLiteral("the production shell exposes no uiTick slot"));
    QApplication::processEvents();

    shell.tab = tab;
    return shell;
}

} // namespace checks::support
