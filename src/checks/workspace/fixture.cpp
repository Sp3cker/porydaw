#include "checks/workspace/fixture.h"

#include "ui/songtab.h"
#include "ui/workspaceui.h"

namespace workspace_test {

SongTab *waitReady(WorkspaceUi &workspace, const SongName &name, int timeoutMs)
{
    SongTab *tab = nullptr;
    const auto result = checks::async_wait::waitUntil(
        [&workspace, &name, &tab] {
            tab = workspace.songTabFor(name);
            return tab != nullptr;
        },
        [&workspace, &name, &tab] {
            tab = workspace.songTabFor(name);
            return tab && tab->isReady();
        },
        timeoutMs, 1);
    return result == checks::async_wait::Result::Ready ? tab : nullptr;
}

SongTab *openReady(WorkspaceUi &workspace, const SongName &name, bool newTab, int timeoutMs)
{
    workspace.requestSongOpen(name, newTab);
    return waitReady(workspace, name, timeoutMs);
}

} // namespace workspace_test
