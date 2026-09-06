#include "checks/project/iofixture.h"

#include <QDir>
#include <QFileInfo>
#include <QThread>
#include <QTimer>

#include <utility>

#include "checks/support/songfixture.h"
#include "project/songregistry.h"

namespace project_check {

ProjectIoFixture::ProjectIoFixture(QString stagedRoot) : m_stagedRoot(std::move(stagedRoot)) {}

ProjectIoFixture::~ProjectIoFixture() = default;

bool ProjectIoFixture::initialize(QString &error)
{
    m_project = checks::ProjectFixture::copyOf(m_stagedRoot, error);
    if (!m_project)
        return false;

    m_callerThread = QThread::currentThread();
    m_io = std::make_unique<ProjectIo>([this](ProjectResult result, std::optional<ProjectCommand>) {
        m_callbacksReturnToCallerThread &= QThread::currentThread() == m_callerThread;
        m_results.push_back(std::move(result));
        m_loop.quit();
    });
    return true;
}

bool ProjectIoFixture::waitFor(int count, QString &error)
{
    bool timedOut = false;
    QTimer timer;
    timer.setSingleShot(true);
    timer.setInterval(30000);
    QObject::connect(&timer, &QTimer::timeout, &m_loop, [&] {
        timedOut = true;
        m_loop.quit();
    });

    while (!timedOut && resultCount() < count) {
        timer.start();
        m_loop.exec();
    }
    timer.stop();
    if (resultCount() >= count)
        return true;

    error = QStringLiteral("timed out waiting for %1 ProjectIo result(s); received %2")
                .arg(count)
                .arg(resultCount());
    return false;
}

std::optional<OpenedProject> ProjectIoFixture::open(QString &error, bool *completedInline)
{
    const int resultBase = resultCount();
    m_io->submit(ProjectCommand{OpenProjectInput{root()}});
    if (completedInline)
        *completedInline = resultCount() != resultBase;
    if (!waitFor(resultBase + 1, error))
        return std::nullopt;

    const auto *const snapshot = std::get_if<ProjectSnapshot>(&m_results[resultBase]);
    if (!snapshot || !snapshot->isOpen()) {
        error = QStringLiteral("opening the fixture did not publish an open ProjectSnapshot");
        return std::nullopt;
    }

    const SongInfo *playableSong = nullptr;
    std::optional<SongInfo> oneTrackSong;
    for (const SongInfo &song : snapshot->songs()) {
        if (song.label == QStringLiteral("se_fanfare_1trk"))
            oneTrackSong = song;
        if (!playableSong && song.isPlayable() && QFileInfo::exists(song.midPath))
            playableSong = &song;
    }
    if (!playableSong) {
        error = QStringLiteral("fixture snapshot has no playable song with a MIDI source");
        return std::nullopt;
    }

    const std::optional<SongName> songName = SongName::create(playableSong->label);
    if (!songName) {
        error = QStringLiteral("fixture playable song label is not a SongName");
        return std::nullopt;
    }

    return OpenedProject{*snapshot, *playableSong, std::move(oneTrackSong), std::move(*songName),
                         SongRegistry::constantForLabel(playableSong->label)};
}

ProjectIo &ProjectIoFixture::io() noexcept
{
    return *m_io;
}

const std::deque<ProjectResult> &ProjectIoFixture::results() const noexcept
{
    return m_results;
}

std::deque<ProjectResult> &ProjectIoFixture::results() noexcept
{
    return m_results;
}

int ProjectIoFixture::resultCount() const noexcept
{
    return static_cast<int>(m_results.size());
}

const QString &ProjectIoFixture::root() const noexcept
{
    return m_project->root();
}

bool ProjectIoFixture::callbacksReturnToCallerThread() const noexcept
{
    return m_callbacksReturnToCallerThread;
}

std::optional<SongLoad> songChainAt(const std::deque<ProjectResult> &results, int base,
                                    const SongName &song, QString &error)
{
    if (base < 0 || base + 2 >= static_cast<int>(results.size())) {
        error = QStringLiteral("song load did not publish all three stages");
        return std::nullopt;
    }

    const auto *const midi = std::get_if<MidiStage>(&results[base]);
    const auto *const view = std::get_if<LoadedBankView>(&results[base + 1]);
    const auto *const bound = std::get_if<VoicegroupBound>(&results[base + 2]);
    if (!(midi && view && bound)) {
        error = QStringLiteral("song load stages were not MIDI, bank view, then bound");
        return std::nullopt;
    }
    if (midi->song != song || bound->song != song) {
        error = QStringLiteral("song load stages lost their song key");
        return std::nullopt;
    }
    if (midi->smf.tracks.empty() || midi->info.label != song.value() || midi->trackBudget < 1) {
        error = QStringLiteral("MIDI stage did not carry detached playable-song values");
        return std::nullopt;
    }
    if (view->id != bound->id || !view->bank) {
        error = QStringLiteral("bank view did not precede the matching bound result");
        return std::nullopt;
    }

    return SongLoad{*midi, bound->id};
}

std::optional<SongLoad> loadSong(ProjectIoFixture &fixture, const SongName &song,
                                 SongLoadEntry entry, bool *completedInline, QString &error)
{
    const int resultBase = fixture.resultCount();
    switch (entry) {
    case SongLoadEntry::Open:
        fixture.io().submit(ProjectCommand{OpenSongInput{song}});
        break;
    case SongLoadEntry::Reload:
        fixture.io().submit(ProjectCommand{ReloadSongInput{song}});
        break;
    case SongLoadEntry::PrivateLoad:
        fixture.io().submit(ProjectCommand{LoadSongCommand{song}});
        break;
    }
    if (completedInline)
        *completedInline = fixture.resultCount() != resultBase;
    if (!fixture.waitFor(resultBase + 3, error))
        return std::nullopt;
    return songChainAt(fixture.results(), resultBase, song, error);
}

} // namespace project_check
