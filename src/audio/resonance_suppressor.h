#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

// Resonance suppressor from dsp/DETECTOR.md (plan v6). The device-rate
// decision is intentional: this runs at the live engine sample rate, not a
// fixed 32768 Hz.
struct ResonanceParams {
    float gDb = 3.0f;        // global depth 0..10 dB (gentler shipping default, §6)
    float guardDb = 6.0f;    // guard 0..12 dB above the spectral contrast reference (§7)
    float timingMs = 500.0f; // attack tau; release = 4x
    float tilt = 0.0f;       // dB/oct, +-3
    float knotDepthDb[12] = {0, 0, 0, 0, 0, 10, 10, 10, 10, 10, 10, 10};
    // Shipping default: only knots 7-10 (2.5-10 kHz) active — plateau
    // 2.5*gDb = -7.5 dB over the whistle band instead of the full high end.
    bool knotActive[12] = {false, false, false, false, false, false,
                           false, true,  true,  true,  true,  false};
    bool forceMaskOne = false; // verification hook (DETECTOR.md §14 passthrough): mask forced to 1
};

class ResonanceSuppressor
{
  public:
    static constexpr int kN = 2048;         // FFT size
    static constexpr int kH = 1024;         // hop (50% overlap)
    static constexpr int kLatency = kN - 1; // 2047 samples while enabled
    static constexpr double kDepth = 2.5;   // plateau = kDepth * depthEnv
    static constexpr double kSilenceDb = -120.0;
    static constexpr double kKneeDb = 3.0;
    static constexpr double kMaxExcessDb = 24.0;

    ResonanceSuppressor();
    ~ResonanceSuppressor();
    ResonanceSuppressor(const ResonanceSuppressor &) = delete;
    ResonanceSuppressor &operator=(const ResonanceSuppressor &) = delete;

    // Cold (device stopped): rebuild rate-dependent tables, reset all state.
    void init(float sampleRate);
    // Hot: request enable/disable. Applied at the next process() entry on the
    // audio thread; enabling resets the pipeline (fresh prime from silence).
    void setEnabled(bool on);
    bool enabled() const;
    // Cold (harness / future UI): re-derive per-bin depth envelope.
    void setParams(const ResonanceParams &p);
    const ResonanceParams &params() const;
    // Hot, audio thread. In-place stereo interleaved, arbitrary frame counts
    // (chunked by the engine). Enabled: output = input delayed kLatency via
    // the FFT path. Disabled: identity (bit-exact no-op). Never allocates.
    void process(float *interleaved, uint32_t frames);
    // Test entry point (DETECTOR.md §15, §14 release case): the
    // current per-bin gain in dB. Signal-level probes of release are smeared
    // by the STFT hop lookahead, so the harness reads the gain state itself.
    double binGainDb(int bin) const;

  private:
    void applyPendingTransition();
    void fft(std::vector<double> &real, std::vector<double> &imag, bool inverse);
    void processHop(uint64_t start);
    void rebuildDepthEnvelope();
    void rebuildTiming();
    void resetState();

    std::atomic<bool> m_requestedEnabled{false};
    std::atomic<uint32_t> m_requestedGeneration{0};
    bool m_appliedEnabled = false;
    uint32_t m_appliedGeneration = 0;

    float m_sampleRate = 0.0f;
    ResonanceParams m_params;
    double m_alphaAttack = 0.0;
    double m_alphaRelease = 0.0;
    double m_stepCap = 0.0;
    double m_calibration = 0.0;
    uint64_t m_count = kH;

    std::vector<double> m_window;
    std::vector<double> m_twiddleReal;
    std::vector<double> m_twiddleImag;
    std::vector<uint32_t> m_bitReverse;
    std::vector<double> m_inFifo;
    std::vector<double> m_outBuf;
    std::vector<double> m_fftRealL;
    std::vector<double> m_fftImagL;
    std::vector<double> m_fftRealR;
    std::vector<double> m_fftImagR;
    std::vector<double> m_depthEnv;
    std::vector<double> m_binLevel;
    std::vector<double> m_curGb;
    std::vector<double> m_mask;
};
