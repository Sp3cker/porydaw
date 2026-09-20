#pragma once

#include <QString>

#include <memory>

class MainWindow;
class SongTab;

// Staged production shell for the visual baselines that capture a loaded
// session (project open, one song tab ready). The staging is asynchronous
// production work — a real project load followed by a real song open — so it
// lives here instead of in every scenario that needs a loaded shell shown.
namespace checks::support {

/// A shell window with a project open and one song tab fully loaded.
/// `window` owns the shell and is null exactly when staging failed, with
/// `error` describing what was missing; `tab` is that song's tab.
struct LoadedShell {
    std::unique_ptr<MainWindow> window;
    SongTab *tab = nullptr;
};

/// Opens `projectRoot` (the staged decomp project fixture) in a fresh
/// MainWindow through the production workspace API, opens the fixture's
/// canonical song, and waits for the project and the song tab to reach their
/// ready states; the status meter ticks once so the returned shell shows the
/// state a real session shows. The caller owns `window` and shows, captures,
/// and closes it. The programmatic open leaves the browser unselected — a
/// scenario that freezes the loaded song as the current row must pin it after
/// the window has shown and laid out, or the list's scroll-to-selection
/// no-ops. Returns a shell with a null `window` and a description in `error`
/// when the root is missing, the window lacks its workspace/panels, or an
/// open never becomes ready.
LoadedShell openLoadedShell(const QString &projectRoot, QString *error);

} // namespace checks::support
