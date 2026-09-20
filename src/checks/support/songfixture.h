#pragma once

#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>
#include <functional>
#include <memory>

#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/samplepicker.h"

class MidiTimeline;
class SongView;

class QTemporaryDir;
namespace checks {

class LoadedSong final
{
  public:
    static std::unique_ptr<LoadedSong> load(const QString &projectRoot, const QString &songLabel,
                                            QString &error);
    ~LoadedSong();

    LoadedSong(const LoadedSong &) = delete;
    LoadedSong &operator=(const LoadedSong &) = delete;
    LoadedSong(LoadedSong &&) = delete;
    LoadedSong &operator=(LoadedSong &&) = delete;

    SongDocument &document() noexcept;
    const SongDocument &document() const noexcept;
    SongInfo songInfo() const;

  private:
    explicit LoadedSong(SongInfo song);

    DecompProject m_project;
    SongDocument m_document;
    SongInfo m_song;
};

class SongViewRig final
{
  public:
    static std::unique_ptr<SongViewRig> create(std::unique_ptr<LoadedSong> loadedSong,
                                               double sampleRate, QString &error);
    ~SongViewRig();

    SongViewRig(const SongViewRig &) = delete;
    SongViewRig &operator=(const SongViewRig &) = delete;

    SongDocument &document() noexcept;
    const SongDocument &document() const noexcept;
    const MidiTimeline &timeline() const noexcept;
    SongView &view() noexcept;
    const SongView &view() const noexcept;
    bool rebuildTimeline(QString &error);

  private:
    SongViewRig(std::unique_ptr<LoadedSong> loadedSong, std::unique_ptr<MidiTimeline> timeline,
                double sampleRate);

    double m_sampleRate = 0.0;
    std::unique_ptr<LoadedSong> m_song;
    std::unique_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
};

class ProjectFixture final
{
  public:
    static std::unique_ptr<ProjectFixture> copyOf(const QString &source, QString &error);
    ~ProjectFixture();

    ProjectFixture(const ProjectFixture &) = delete;
    ProjectFixture &operator=(const ProjectFixture &) = delete;
    ProjectFixture(ProjectFixture &&) = delete;
    ProjectFixture &operator=(ProjectFixture &&) = delete;

    const QString &root() const noexcept;

  private:
    ProjectFixture() = default;

    std::unique_ptr<QTemporaryDir> m_directory;
    QString m_root;
};

// The decomp fixture's DirectSound samples, programmable waves, and keysplit
// instruments loaded as one LoadedSampleSet through the production path
// (DecompProject::loadSampleSet), plus the sample metadata lookup a
// VoicegroupBrowser owner feeds the picker.
class FixtureSampleSet final
{
  public:
    // catalog / directSound are the project's published catalog scans
    // (VoicegroupSource::catalogScan, ::directSoundCatalog) and progWaveSymbols
    // its programmable waves (::progWaveSymbols); the loaded set's sample and
    // wave arrays are parallel to directSound.directSound and progWaveSymbols.
    static std::unique_ptr<FixtureSampleSet>
    load(DecompProject &project, const VgCatalogScan &catalog, const VgDirectSoundScan &directSound,
         const QStringList &progWaveSymbols, QString &error);
    ~FixtureSampleSet();

    FixtureSampleSet(const FixtureSampleSet &) = delete;
    FixtureSampleSet &operator=(const FixtureSampleSet &) = delete;
    FixtureSampleSet(FixtureSampleSet &&) = delete;
    FixtureSampleSet &operator=(FixtureSampleSet &&) = delete;

    // The provider VoicegroupBrowser::setSampleInfoProvider takes: the same
    // known/looped/rate/seconds lookup WorkspaceUi::samplePickInfoFor performs
    // against the loaded set. Borrows this, so the set must outlive the
    // browser it feeds.
    std::function<SamplePickInfo(const QString &)> pickInfoProvider() const;

  private:
    FixtureSampleSet() = default;

    // WorkspaceUi::samplePickInfoFor against this set: the symbol's committed
    // WaveData, resolved through the DirectSound list; unknown when the symbol
    // is outside it or its wave did not resolve.
    SamplePickInfo pickInfoFor(const QString &symbol) const;

    QStringList m_directSoundSymbols; // parallel to the loaded set's waves
    // Shared ownership exactly as ProjectWorkspace's SampleSetLease models it:
    // the C loader's set is freed by voicegroup_free_samples.
    std::shared_ptr<const LoadedSampleSet> m_set;
};

} // namespace checks
