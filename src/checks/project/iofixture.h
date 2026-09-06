#pragma once

#include <QEventLoop>
#include <QString>

#include <deque>
#include <memory>
#include <optional>

#include "project/projectio.h"

namespace checks {
class ProjectFixture;
}

namespace project_check {

struct OpenedProject {
    ProjectSnapshot snapshot;
    SongInfo playableSong;
    std::optional<SongInfo> oneTrackSong;
    SongName song;
    QString constant;
};

enum class SongLoadEntry { Open, Reload, PrivateLoad };

struct SongLoad {
    MidiStage midi;
    VoicegroupId bankId;
};

std::optional<SongLoad> songChainAt(const std::deque<ProjectResult> &results, int base,
                                    const SongName &song, QString &error);

class ProjectIoFixture final
{
  public:
    explicit ProjectIoFixture(QString stagedRoot);
    ~ProjectIoFixture();

    ProjectIoFixture(const ProjectIoFixture &) = delete;
    ProjectIoFixture &operator=(const ProjectIoFixture &) = delete;
    ProjectIoFixture(ProjectIoFixture &&) = delete;
    ProjectIoFixture &operator=(ProjectIoFixture &&) = delete;

    bool initialize(QString &error);
    bool waitFor(int count, QString &error);
    std::optional<OpenedProject> open(QString &error, bool *completedInline = nullptr);

    ProjectIo &io() noexcept;
    const std::deque<ProjectResult> &results() const noexcept;
    std::deque<ProjectResult> &results() noexcept;
    int resultCount() const noexcept;
    const QString &root() const noexcept;
    bool callbacksReturnToCallerThread() const noexcept;

  private:
    QString m_stagedRoot;
    std::unique_ptr<checks::ProjectFixture> m_project;
    QEventLoop m_loop;
    std::deque<ProjectResult> m_results;
    std::unique_ptr<ProjectIo> m_io;
    class QThread *m_callerThread = nullptr;
    bool m_callbacksReturnToCallerThread = true;
};

std::optional<SongLoad> loadSong(ProjectIoFixture &fixture, const SongName &song,
                                 SongLoadEntry entry, bool *completedInline, QString &error);

} // namespace project_check
