#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

// Audio → UI tap of the final stereo mix (docs/scripting/PLAN.md §3
// "audiotap"): the audio thread appends every callback's interleaved
// output (post output gain) to a fixed ring; the UI thread copies the
// newest frames out at its own cadence. Single producer, single consumer,
// no locks, no allocation after construction: the callback never waits
// on the reader, and a reader that falls behind simply loses the oldest
// frames (the ring is a window, not a queue). A read that overlaps a
// concurrent write may see a torn frame or two at its oldest edge —
// harmless for meters, which is all this feeds.
class AudioTap
{
  public:
    // capacityFrames is rounded up to a power of two.
    explicit AudioTap(uint32_t capacityFrames = 32768);

    uint32_t capacity() const { return m_mask + 1; }

    // Audio thread: appends `frames` interleaved stereo frames.
    void write(const float *interleaved, uint32_t frames);

    // UI thread: total frames ever written (monotonic).
    uint64_t framesWritten() const { return m_written.load(std::memory_order_acquire); }

    // UI thread: copies the newest `frames` frames (interleaved) into
    // `out`, oldest first. Frames beyond what has ever been written read
    // as silence. Returns the number of those frames that are real (not
    // pre-history padding).
    uint32_t readLatest(float *out, uint32_t frames) const;

  private:
    std::vector<float> m_ring; // capacity * 2 floats
    uint32_t m_mask;
    std::atomic<uint64_t> m_written{0};
};

// UI-thread analysis over an AudioTap (PLAN §4 `audio.on('frame')`): one
// poll per UI frame computes peak and RMS per channel over the frames
// written since the previous poll (so a meter integrates the whole
// interval, not a snapshot), keeps the newest `windowFrames` frames for
// scripts that want the waveform, and derives a magnitude spectrum of
// that window on demand (Hann-windowed mono mix, radix-2 FFT, computed
// at most once per poll no matter how many subscribers ask).
class AudioAnalyzer
{
  public:
    explicit AudioAnalyzer(uint32_t windowFrames = 2048);

    uint32_t windowFrames() const { return m_window; }

    // Polls the tap. Returns the number of new frames since the last poll
    // (0 when the device produced nothing — the peak/RMS then read 0).
    uint32_t poll(const AudioTap &tap);

    float peak(int channel) const { return m_peak[channel & 1]; }
    float rms(int channel) const { return m_rms[channel & 1]; }
    uint32_t newFrames() const { return m_newFrames; }
    // Newest windowFrames() frames, interleaved stereo, oldest first.
    const std::vector<float> &window() const { return m_pcm; }

    // Magnitude spectrum of the current window folded into `bins` bands
    // (linear frequency, 0 .. sampleRate/2), each 0..1 where 1 is a
    // full-scale sine at that frequency. bins is clamped to
    // [1, windowFrames/2].
    const std::vector<float> &spectrum(uint32_t bins);

    // Standalone in-place radix-2 FFT on interleaved (re, im) pairs; n
    // must be a power of two. Public for the harness.
    static void fft(float *reim, uint32_t n);

  private:
    void computeMagnitudes();

    uint32_t m_window;
    uint64_t m_lastWritten = 0;
    uint32_t m_newFrames = 0;
    float m_peak[2] = {0.0f, 0.0f};
    float m_rms[2] = {0.0f, 0.0f};
    std::vector<float> m_pcm;     // window * 2
    std::vector<float> m_extra;   // a stalled UI's oversized interval
    std::vector<float> m_scratch; // window * 2 (re, im)
    std::vector<float> m_hann;    // window
    std::vector<float> m_mags;    // window / 2, valid when m_magsValid
    std::vector<float> m_bands;   // last spectrum() result
    uint32_t m_bandsBins = 0;
    bool m_magsValid = false;
};
