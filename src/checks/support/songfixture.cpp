#include "checks/support/songfixture.h"

#include <cmath>
#include <utility>

#include "core/miditimeline.h"
#include "ui/songview.h"

namespace checks {

std::unique_ptr<LoadedSong> LoadedSong::load(const QString &projectRoot, const QString &songLabel,
                                             QString &error)
{
    error.clear();
    auto loadedSong = std::unique_ptr<LoadedSong>(new LoadedSong(SongInfo{}));
    if (!loadedSong->m_project.open(projectRoot, &error))
        return nullptr;

    const SongInfo *song = nullptr;
    for (const SongInfo &candidate : loadedSong->m_project.songs()) {
        if (candidate.label == songLabel && candidate.isPlayable()) {
            song = &candidate;
            break;
        }
    }
    if (!song) {
        error = QStringLiteral("no playable song '%1'").arg(songLabel);
        return nullptr;
    }
    if (!loadedSong->m_document.load(*song, &error))
        return nullptr;
    loadedSong->m_song = *song;
    return loadedSong;
}

LoadedSong::LoadedSong(SongInfo song) : m_song(std::move(song)) {}

LoadedSong::~LoadedSong() = default;

SongDocument &LoadedSong::document() noexcept
{
    return m_document;
}

const SongDocument &LoadedSong::document() const noexcept
{
    return m_document;
}

SongInfo LoadedSong::songInfo() const
{
    return m_song;
}

std::unique_ptr<SongViewRig> SongViewRig::create(std::unique_ptr<LoadedSong> loadedSong,
                                                 double sampleRate, QString &error)
{
    error.clear();
    if (!loadedSong) {
        error = QStringLiteral("loaded song is required");
        return nullptr;
    }
    if (!std::isfinite(sampleRate) || sampleRate <= 0.0) {
        error = QStringLiteral("sample rate must be finite and positive");
        return nullptr;
    }

    auto timeline = loadedSong->document().buildTimeline(sampleRate);
    if (!timeline) {
        error = QStringLiteral("could not build song timeline");
        return nullptr;
    }

    auto rig = std::unique_ptr<SongViewRig>(
        new SongViewRig(std::move(loadedSong), std::move(timeline), sampleRate));
    if (rig->m_view->internalWinId() != 0 || rig->m_view->testAttribute(Qt::WA_NativeWindow)) {
        error = QStringLiteral("SongView constructor forced native window creation");
        return nullptr;
    }

    rig->m_view->setSong(rig->m_timeline.get(), nullptr);
    rig->m_view->setDocument(&rig->m_song->document());
    return rig;
}

SongViewRig::SongViewRig(std::unique_ptr<LoadedSong> loadedSong,
                         std::unique_ptr<MidiTimeline> timeline, double sampleRate)
    : m_sampleRate(sampleRate)
    , m_song(std::move(loadedSong))
    , m_timeline(std::move(timeline))
    , m_view(std::make_unique<SongView>())
{}

SongViewRig::~SongViewRig()
{
    m_view->setSong(nullptr, nullptr);
    m_view->setDocument(nullptr);
}

SongDocument &SongViewRig::document() noexcept
{
    return m_song->document();
}

const SongDocument &SongViewRig::document() const noexcept
{
    return m_song->document();
}

const MidiTimeline &SongViewRig::timeline() const noexcept
{
    return *m_timeline;
}

SongView &SongViewRig::view() noexcept
{
    return *m_view;
}

const SongView &SongViewRig::view() const noexcept
{
    return *m_view;
}

bool SongViewRig::rebuildTimeline(QString &error)
{
    auto rebuilt = m_song->document().buildTimeline(m_sampleRate);
    if (!rebuilt) {
        error = QStringLiteral("could not build song timeline");
        return false;
    }

    m_view->updateSong(rebuilt.get());
    m_timeline = std::move(rebuilt);
    error.clear();
    return true;
}

} // namespace checks
