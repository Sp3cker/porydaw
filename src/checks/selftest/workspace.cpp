#include "harness.h"

#include "checks/support/asyncwait.h"
#include "mainwindow.h"

#include <cmath>

#include <QFile>
#include <QTimer>

#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/viewsidecar.h"
#include "ui/workspaceui.h"

namespace checks {

bool SelfTestHarness::runWorkspaceScenario()
{
    const ProjectState &project = m_window.m_workspace->projectState();
    NewSongWizard::ProjectData projectData;
    projectData.songs = project.snapshot.songs();
    projectData.players = project.snapshot.players();
    projectData.voicegroupArgs = project.catalog.groupArgs;
    projectData.canCreateVoicegroup = project.catalog.perFileVoicegroups;
    NewSongWizard wizard(projectData, &m_window);
    const SongTarget songTarget{m_tab->document().cfg(), m_tab->document().label()};
    SettingsDialog settingsDialog(m_window.m_engineSettings, songTarget, project.catalog.groupArgs,
                                  SettingsDialog::Tab::Engine, &m_window);
    qInfo("selftest-workspace: New Song wizard + unified settings dialog constructed");
    const ViewSidecar::Snapshot original{m_view->viewState(), m_view->editorViewState()};
    if (!SongRegistry::saveRegistrationMeta(m_projectRoot, m_songInfo.label,
                                            QStringLiteral("MUS_SELFTEST"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"))) {
        qWarning("selftest-workspace: registration metadata save failed");
        return false;
    }
    m_view->setGridMinDenom(8);
    m_view->setGridFeel(SongView::GridFeel::Triplet);
    m_view->setLaneDisplayRange(0, 0x01, 16);
    const ViewSidecar::Snapshot saved{m_view->viewState(), m_view->editorViewState()};
    auto succeeded = ViewSidecar::save(m_projectRoot, m_songInfo.label, saved);
    m_view->zoomAroundContentX(2.0, 0);
    m_view->setGridMinDenom(0);
    m_view->setGridFeel(SongView::GridFeel::Straight);
    m_view->setLaneDisplayRange(0, 0x01, 0);
    ViewSidecar::Snapshot loaded;
    succeeded = succeeded && ViewSidecar::load(m_projectRoot, m_songInfo.label, &loaded);
    if (succeeded) {
        m_view->applyViewState(loaded.view);
        loaded.editor.setDrawerState(m_window.m_editorDrawerState);
        m_view->applyEditorViewState(loaded.editor);
        const ViewSidecar::Snapshot restored{m_view->viewState(), m_view->editorViewState()};
        auto constant = QString{};
        auto player = QString{};
        succeeded = loaded.view.scrollPx == 0.0 && loaded.view.scrollY == 0.0 &&
                    std::abs(restored.view.pxPerBeat - saved.view.pxPerBeat) < 0.001 &&
                    std::abs(restored.view.keyHeight - saved.view.keyHeight) < 0.001 &&
                    restored.view.selectedTrack == saved.view.selectedTrack &&
                    restored.view.editCursorTick == saved.view.editCursorTick &&
                    restored.view.gridMinDenom == 8 && restored.view.gridTriplet &&
                    restored.editor == saved.editor &&
                    SongRegistry::loadRegistrationMeta(m_projectRoot, m_songInfo.label, &constant,
                                                       &player) &&
                    constant == QLatin1String("MUS_SELFTEST") &&
                    player == QLatin1String("MUSIC_PLAYER_BGM");
    }
    m_view->applyViewState(original.view);
    m_view->applyEditorViewState(original.editor);
    QFile::remove(ViewSidecar::pathFor(m_projectRoot, m_songInfo.label));
    if (!succeeded) {
        qWarning("selftest-workspace: sidecar view-state round trip FAILED");
        return false;
    }
    qInfo("selftest-workspace: sidecar view-state round trip OK");
    if (m_window.m_workspace->selectedSongDirty()) {
        qWarning("selftest-workspace: song still dirty before closing its tab");
        return false;
    }
    if (!beginObservedPlayback())
        return false;
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this] {
                                  m_window.synchronizePlayhead();
                                  return m_window.m_playheadTimer->isActive();
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-workspace: playhead timer did not start during playback");
        return false;
    }
    const SongName closingSong = m_tab->name();
    m_window.m_workspace->requestCloseSelectedTab();
    if (async_wait::waitUntil([] { return true; },
                              [this, &closingSong] {
                                  return !m_window.m_workspace->songTabFor(closingSong) &&
                                         !m_window.m_playheadTimer->isActive();
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-workspace: closing final tab left playhead timer active");
        return false;
    }
    m_tab = nullptr;
    m_view = nullptr;
    qInfo("selftest-workspace: closing final tab stopped playhead timer");
    return m_window.m_workspace->openTabCount() == 0;
}

} // namespace checks
