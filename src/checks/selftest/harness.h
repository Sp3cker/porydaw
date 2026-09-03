#pragma once

#include <QString>

#include <cstdint>

#include "project/songregistry.h"

class MainWindow;
class SongTab;
class SongView;

namespace checks {

enum class SelfTestScenario {
    Timeline,
    Transport,
    Workspace,
};

class SelfTestHarness
{
  public:
    static int run(MainWindow &window, SelfTestScenario scenario, const QString &projectRoot,
                   const QString &songLabel);

  private:
    explicit SelfTestHarness(MainWindow &window);

    bool openSong(const QString &projectRoot, const QString &songLabel);
    bool beginObservedPlayback(uint64_t samplePosition = 0);
    bool closeCleanly();
    bool tabIsLive() const;

    bool runTimelineScenario();
    bool runTransportScenario();
    bool runWorkspaceScenario();

    MainWindow &m_window;
    QString m_projectRoot;
    SongInfo m_songInfo;
    SongTab *m_tab = nullptr;
    SongView *m_view = nullptr;
};

} // namespace checks
