#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QObject>

class AudioEngine;
class MidiTimeline;
struct SmfFile;

namespace checks {
struct AuditionVoicegroup;

// Transport contracts migrated from the legacy --transportcheck runner.
//
// Device-driven slots prove the hot-publish seam on a live (forced-null)
// device: rapid timeline publications keep the audio thread's snapshot
// alive, seek/updateTimeline publish requests without blocking the UI
// thread, timeline rebuilds are pure data-source swaps that never release
// sounding voices, every transport transition cuts ringing audition tails,
// and unloadSong cuts inside itself because the song-switch path frees the
// outgoing bank right after it returns.
//
// Parked-device slots drive AudioEngine::process frame by frame so the
// cut-fade and resonance-suppressor contracts are checked sample for
// sample: song starts enter at unity gain without advancing early, pause
// preserves suppressor adaptation, stop/replacement leak no delayed audio,
// resume parks the sequencer through the settle hold, and a pending cut
// retargets onto an already-applied Playing.
//
// Every slot runs on a fresh AudioEngine bound to the forced null backend;
// a failed forced-null init fails the slot, it is never skipped.
class TransportTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TransportTest)

  public:
    TransportTest();
    ~TransportTest() override;

  private slots:
    void init();
    void cleanup();

    // TimelineHandoff ownership between the UI publisher and the audio thread.
    void timelineHandoffOwnership();

    // Hot publishes: request semantics, never device restarts or blocking.
    void seekPublishesWithoutBlocking();
    void stopCancelsPendingSeek();
    void updateTimelineCarriesPendingSeek();
    void liveTimelineReplacementDoesNotBlock();

    // Timeline rebuilds must not release sounding hardware voices.
    void rebuildKeepsSoundingCgbSongNote();
    void rebuildKeepsCgbNotePreview();

    // Transport transitions cut ringing audition tails.
    void playFromStoppedCutsAuditionTail();
    void pauseSilencesPlayingPreview();
    void spacePathSeekAndPlayCutsTail();
    void resumeCutsCountingDownPreview();
    void unloadWhilePlayingCutsSongVoices();

    // Parked-device deterministic cut-fade/suppressor contracts.
    void songStartEntersAtUnityGain();
    void pausePreservesSuppressorAdaptation();
    void stopLeaksNoDelayedSuppressorAudio();
    void restartProducesAudioWithSuppression();
    void secondSongStartDoesNotReuseResumeFade();
    void resumeParksSequencerThroughSettle();
    void pendingCutRetargetsOntoPlaying();
    void coldReplacementLeaksNoPriorSongAudio();

  private:
    AudioEngine &engine() noexcept;

    // Builds smf at the engine's rate; null on synthesis failure. Callers
    // QVERIFY2 the result with `what` before dereferencing or loading it.
    std::shared_ptr<const MidiTimeline> loadedSong(SmfFile smf, const char *what);

    // Control expectations for the tail-cut slots: the timed preview sounds
    // within 2 s and its slow release still rings 400 ms after the note-off.
    // Returns false (after recording the failure) when a control breaks.
    bool ringingTail(AudioEngine &engine, uint8_t track);

    // Parked-device deterministic support (settle.cpp).
    bool parkSuppressed(AudioEngine &engine);
    bool renderUntilApplied(AudioEngine &engine, int transport);
    bool engageSuppressorWithNoteSong(AudioEngine &engine);
    std::vector<float> renderParked(AudioEngine &engine, uint32_t frames);
    static float peak(const std::vector<float> &audio);
    double deepestResonanceGain(AudioEngine &engine) const;

    // The bank is borrowed by the engine's song session, so it must outlive
    // the engine; declaration order makes the engine die first in cleanup.
    std::unique_ptr<AuditionVoicegroup> m_bank;
    std::unique_ptr<AudioEngine> m_engine;
};

} // namespace checks
