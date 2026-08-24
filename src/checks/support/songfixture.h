#pragma once

#include <QString>
#include <memory>

#include "core/songdocument.h"
#include "project/decompproject.h"

class MidiTimeline;
class SongView;

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

} // namespace checks
