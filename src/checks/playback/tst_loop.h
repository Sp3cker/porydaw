#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QObject>

#include "core/timelineplayer.h"

class MidiTimeline;
struct M4AEngine;

namespace checks {

// Loop-wrap playback contracts migrated from the legacy --loopcheck runner.
// Looping playback matches hardware GOTO: mid2agb sorts same-tick events so
// the loop GOTO lands after note-ends but before note-starts, therefore a
// note starting at the loop end never sounds while looping and one ending
// there still releases; a spanning note of <= 96 clocks (a direct note
// command) gate-carries across the wrap and releases at its full written
// duration; a longer spanning note (TIE + EOT, the EOT unreachable beyond
// the loop end) is held forever, stacking one fresh instance per pass.
//
// Each data row renders a fresh engine from sample zero and probes the
// keyed-on PCM channels in un-wrapped (global) playback time.
class LoopTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(LoopTest)

  public:
    LoopTest();
    ~LoopTest() override;

  private slots:
    void init();
    void cleanup();

    // The synthesized song's loop markers land on the exact sample
    // positions every probe below relies on.
    void synthesizedLoopSongHasExactLoopPoints();

    // One row per loop-boundary relationship, looping and not.
    void loopWrapMatchesHardwareGoto_data();
    void loopWrapMatchesHardwareGoto();

  private:
    // Renders from the current position up to samplePos in 512-frame
    // chunks and returns the sorted keys of the PCM channels still keyed on
    // (started and not yet released); duplicates preserved, so the stacked
    // tied notes show as repeated keys.
    std::vector<uint8_t> renderAndProbe(uint64_t samplePos, bool looping);

    std::unique_ptr<MidiTimeline> m_timeline;
    // The engine borrows the bank's voices, so the bank must outlive it.
    std::unique_ptr<struct SustainVoicegroup> m_bank;
    std::unique_ptr<M4AEngine> m_engine;
    TimelinePlayer m_player;
    uint64_t m_rendered = 0;
};

} // namespace checks
