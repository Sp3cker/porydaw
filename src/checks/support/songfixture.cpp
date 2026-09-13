#include "checks/support/songfixture.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <cmath>
#include <utility>

#include "checks/support/support.h"
#include "core/miditimeline.h"
#include "ui/songview.h"

namespace checks {

namespace {
bool copyTree(const QString &source, const QString &destination, QString &error)
{
    if (!QFileInfo(source).isDir()) {
        error = QStringLiteral("fixture source is not a directory: %1").arg(source);
        return false;
    }
    const QDir sourceDir(source);
    const auto entries =
        sourceDir.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries | QDir::Hidden);
    for (const QFileInfo &entry : entries) {
        const QString target = destination + QLatin1Char('/') + entry.fileName();
        if (entry.isDir()) {
            if (!QDir().mkpath(target)) {
                error = QStringLiteral("could not create fixture directory: %1").arg(target);
                return false;
            }
            if (!copyTree(entry.absoluteFilePath(), target, error))
                return false;
        } else if (entry.isFile()) {
            if (!QFile::copy(entry.absoluteFilePath(), target)) {
                error =
                    QStringLiteral("could not copy fixture file: %1").arg(entry.absoluteFilePath());
                return false;
            }
        }
    }
    return true;
}
} // namespace

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
    rig->m_view->setSong(rig->m_timeline.get(), nullptr);
    rig->m_view->setDocument(&rig->m_song->document());
    support::bindEditActionsForTest(*rig->m_view);
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

std::unique_ptr<ProjectFixture> ProjectFixture::copyOf(const QString &source, QString &error)
{
    error.clear();
    auto fixture = std::unique_ptr<ProjectFixture>(new ProjectFixture);
    fixture->m_directory = std::make_unique<QTemporaryDir>();
    if (!fixture->m_directory->isValid()) {
        error = QStringLiteral("could not create temporary fixture directory");
        return nullptr;
    }
    if (!copyTree(source, fixture->m_directory->path(), error))
        return nullptr;
    fixture->m_root = fixture->m_directory->path();
    return fixture;
}

ProjectFixture::~ProjectFixture() = default;

const QString &ProjectFixture::root() const noexcept
{
    return m_root;
}

} // namespace checks
