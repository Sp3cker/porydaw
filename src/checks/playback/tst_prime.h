#pragma once

#include <memory>

#include <QObject>

class MidiTimeline;
struct M4AEngine;

namespace checks {

// Voice-priming contracts migrated from the legacy --primecheck runner. A
// freshly loaded engine has no instrument on any track until playback
// dispatches the first program change, so previewNote used to be silent
// until the song had been played. TimelinePlayer::primeVoices fixes that by
// applying each track's first program change up front; chase-applied
// programs are never overridden, and voiceless tracks stay untouched.
class PrimeTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PrimeTest)

  public:
    PrimeTest();
    ~PrimeTest() override;

  private slots:
    void init();
    void cleanup();

    // Control: chase alone at position 0 leaves the later-voice track with
    // no instrument, so an auditioned note renders pure silence — the
    // reported symptom.
    void unprimedTrackAuditionIsSilent();

    // The load recipe (chase + primeVoices at position 0), one row per
    // track shape: voice at tick 0, voice only later in the song, and no
    // voice at all.
    void primeVoicesApplyTrackPrograms_data();
    void primeVoicesApplyTrackPrograms();

    // The primed later-voice track auditions audibly end to end.
    void primedTrackAuditionIsAudible();

    // Past both of track 0's voice events, chase supplies every track's
    // program and priming adds nothing.
    void midSongChaseSuppliesAllPrograms();

  private:
    // Renders up to 4096 frames; true when any sample comes out nonzero.
    bool rendersAudibly();

    std::unique_ptr<MidiTimeline> m_timeline;
    // The engine borrows the bank's voices, so the bank must outlive it.
    std::unique_ptr<struct SustainVoicegroup> m_bank;
    std::unique_ptr<M4AEngine> m_engine;
};

} // namespace checks
