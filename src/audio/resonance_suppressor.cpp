#include "resonance_suppressor.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace {

constexpr double kPi = 3.1415926535897932384626433832795;
constexpr double kKnotFrequencies[] = {63.0,   125.0,  250.0,  400.0,  630.0,   1000.0,
                                       1600.0, 2500.0, 4000.0, 6300.0, 10000.0, 16000.0};

} // namespace

ResonanceSuppressor::ResonanceSuppressor()
    : m_window(kN)
    , m_twiddleReal(kN / 2)
    , m_twiddleImag(kN / 2)
    , m_bitReverse(kN)
    , m_inFifo(2 * kN)
    , m_outBuf(2 * kN)
    , m_fftRealL(kN)
    , m_fftImagL(kN)
    , m_fftRealR(kN)
    , m_fftImagR(kN)
    , m_depthEnv(kN / 2 + 1)
    , m_curGb(kN / 2 + 1)
    , m_mask(kN / 2 + 1, 1.0)
{
    resetState();
}

ResonanceSuppressor::~ResonanceSuppressor() = default;

void ResonanceSuppressor::init(float sampleRate)
{
    m_sampleRate = sampleRate;
    m_calibration = 0.5 * kPi * kPi / (double(kN) * double(kN));

    for (int n = 0; n < kN; ++n) {
        const double phase = 2.0 * kPi * double(n) / double(kN);
        m_window[static_cast<size_t>(n)] = std::sqrt(0.5 - 0.5 * std::cos(phase));
    }

    for (int k = 0; k < kN / 2; ++k) {
        const double phase = -2.0 * kPi * double(k) / double(kN);
        m_twiddleReal[static_cast<size_t>(k)] = std::cos(phase);
        m_twiddleImag[static_cast<size_t>(k)] = std::sin(phase);
    }

    constexpr int kFftBits = 11;
    for (int i = 0; i < kN; ++i) {
        uint32_t reversed = 0;
        uint32_t value = static_cast<uint32_t>(i);
        for (int bit = 0; bit < kFftBits; ++bit) {
            reversed = (reversed << 1) | (value & 1U);
            value >>= 1;
        }
        m_bitReverse[static_cast<size_t>(i)] = reversed;
    }

    rebuildTiming();
    rebuildDepthEnvelope();
    resetState();
    m_appliedEnabled = false;
    m_appliedGeneration = 0;
}

void ResonanceSuppressor::setEnabled(bool on)
{
    m_requestedEnabled.store(on, std::memory_order_release);
    m_requestedGeneration.fetch_add(1, std::memory_order_release);
}

bool ResonanceSuppressor::enabled() const
{
    return m_requestedEnabled.load(std::memory_order_acquire);
}

void ResonanceSuppressor::setParams(const ResonanceParams &p)
{
    m_params = p;
    rebuildTiming();
    rebuildDepthEnvelope();
}

const ResonanceParams &ResonanceSuppressor::params() const
{
    return m_params;
}
double ResonanceSuppressor::binGainDb(int bin) const
{
    if (bin < 0 || bin > kN / 2)
        return 0.0;
    return m_curGb[static_cast<size_t>(bin)];
}

void ResonanceSuppressor::process(float *interleaved, uint32_t frames)
{
    applyPendingTransition();
    if (!m_appliedEnabled)
        return;

    for (uint32_t i = 0; i < frames; ++i) {
        const size_t inputSlot = static_cast<size_t>(m_count % static_cast<uint64_t>(kN));
        m_inFifo[2 * inputSlot] = interleaved[2 * i];
        m_inFifo[2 * inputSlot + 1] = interleaved[2 * i + 1];
        ++m_count;

        if (m_count >= static_cast<uint64_t>(kN) && m_count % static_cast<uint64_t>(kH) == 0)
            processHop(m_count - static_cast<uint64_t>(kN));

        // The first kH positions in the padded output timeline are the
        // leading-silence portion of the first analysis frame. Do not read or
        // clear those ring slots until their real output time arrives.
        if (m_count >= static_cast<uint64_t>(kN + kH)) {
            const uint64_t outputPosition = m_count - static_cast<uint64_t>(kN);
            const size_t outputSlot =
                static_cast<size_t>(outputPosition % static_cast<uint64_t>(kN));
            interleaved[2 * i] = static_cast<float>(m_outBuf[2 * outputSlot]);
            interleaved[2 * i + 1] = static_cast<float>(m_outBuf[2 * outputSlot + 1]);
            m_outBuf[2 * outputSlot] = 0.0;
            m_outBuf[2 * outputSlot + 1] = 0.0;
        } else {
            interleaved[2 * i] = 0.0f;
            interleaved[2 * i + 1] = 0.0f;
        }
    }
}

void ResonanceSuppressor::applyPendingTransition()
{
    const uint32_t requestedGeneration = m_requestedGeneration.load(std::memory_order_acquire);
    if (requestedGeneration == m_appliedGeneration)
        return;

    const bool requestedEnabled = m_requestedEnabled.load(std::memory_order_acquire);
    m_appliedGeneration = requestedGeneration;
    if (requestedEnabled == m_appliedEnabled)
        return;

    m_appliedEnabled = requestedEnabled;
    resetState();
}

void ResonanceSuppressor::fft(std::vector<double> &real, std::vector<double> &imag, bool inverse)
{
    for (int i = 0; i < kN; ++i) {
        const int j = static_cast<int>(m_bitReverse[static_cast<size_t>(i)]);
        if (i < j) {
            std::swap(real[static_cast<size_t>(i)], real[static_cast<size_t>(j)]);
            std::swap(imag[static_cast<size_t>(i)], imag[static_cast<size_t>(j)]);
        }
    }

    for (int length = 2; length <= kN; length <<= 1) {
        const int halfLength = length / 2;
        const int twiddleStep = kN / length;
        for (int block = 0; block < kN; block += length) {
            for (int j = 0; j < halfLength; ++j) {
                const int twiddleIndex = j * twiddleStep;
                const double wr = m_twiddleReal[static_cast<size_t>(twiddleIndex)];
                const double wi = inverse ? -m_twiddleImag[static_cast<size_t>(twiddleIndex)]
                                          : m_twiddleImag[static_cast<size_t>(twiddleIndex)];
                const int even = block + j;
                const int odd = even + halfLength;
                const double tr =
                    real[static_cast<size_t>(odd)] * wr - imag[static_cast<size_t>(odd)] * wi;
                const double ti =
                    real[static_cast<size_t>(odd)] * wi + imag[static_cast<size_t>(odd)] * wr;
                const double er = real[static_cast<size_t>(even)];
                const double ei = imag[static_cast<size_t>(even)];
                real[static_cast<size_t>(even)] = er + tr;
                imag[static_cast<size_t>(even)] = ei + ti;
                real[static_cast<size_t>(odd)] = er - tr;
                imag[static_cast<size_t>(odd)] = ei - ti;
            }
        }
    }

    if (inverse) {
        for (int i = 0; i < kN; ++i) {
            real[static_cast<size_t>(i)] /= double(kN);
            imag[static_cast<size_t>(i)] /= double(kN);
        }
    }
}

void ResonanceSuppressor::processHop(uint64_t start)
{
    for (int n = 0; n < kN; ++n) {
        const size_t inputSlot =
            static_cast<size_t>((start + static_cast<uint64_t>(n)) % static_cast<uint64_t>(kN));
        const double window = m_window[static_cast<size_t>(n)];
        m_fftRealL[static_cast<size_t>(n)] = m_inFifo[2 * inputSlot] * window;
        m_fftImagL[static_cast<size_t>(n)] = 0.0;
        m_fftRealR[static_cast<size_t>(n)] = m_inFifo[2 * inputSlot + 1] * window;
        m_fftImagR[static_cast<size_t>(n)] = 0.0;
    }

    fft(m_fftRealL, m_fftImagL, false);
    fft(m_fftRealR, m_fftImagR, false);

    constexpr int kNyquist = kN / 2;
    for (int k = 0; k <= kNyquist; ++k) {
        double target = 0.0;
        if (k != 0 && k != kNyquist) {
            const double leftPower =
                m_fftRealL[static_cast<size_t>(k)] * m_fftRealL[static_cast<size_t>(k)] +
                m_fftImagL[static_cast<size_t>(k)] * m_fftImagL[static_cast<size_t>(k)];
            const double rightPower =
                m_fftRealR[static_cast<size_t>(k)] * m_fftRealR[static_cast<size_t>(k)] +
                m_fftImagR[static_cast<size_t>(k)] * m_fftImagR[static_cast<size_t>(k)];
            const double power = 0.5 * (leftPower + rightPower);
            const double level = 10.0 * std::log10(power * m_calibration + 1e-24);
            const double excess = level - (kSilenceDb + double(m_params.guardDb));

            double excessLaw = 0.0;
            if (excess > 0.0) {
                if (excess < kKneeDb) {
                    const double ratio = excess / kKneeDb;
                    excessLaw = 0.5 * ratio * ratio;
                } else if (excess < kMaxExcessDb) {
                    const double ratio = (excess - kKneeDb) / (kMaxExcessDb - kKneeDb);
                    excessLaw = 1.0 - 0.5 * (1.0 - ratio) * (1.0 - ratio);
                } else {
                    excessLaw = 1.0;
                }
            }
            target = -kDepth * m_depthEnv[static_cast<size_t>(k)] * excessLaw;
        }

        const size_t index = static_cast<size_t>(k);
        const double current = m_curGb[index];
        const double alpha = target < current ? m_alphaAttack : m_alphaRelease;
        const double step = std::clamp((target - current) * alpha, -m_stepCap, m_stepCap);
        m_curGb[index] = current + step;
        m_mask[index] = m_params.forceMaskOne ? 1.0 : std::pow(10.0, m_curGb[index] / 20.0);
    }

    for (int k = 0; k <= kNyquist; ++k) {
        const double mask = m_mask[static_cast<size_t>(k)];
        m_fftRealL[static_cast<size_t>(k)] *= mask;
        m_fftImagL[static_cast<size_t>(k)] *= mask;
        m_fftRealR[static_cast<size_t>(k)] *= mask;
        m_fftImagR[static_cast<size_t>(k)] *= mask;
        if (k != 0 && k != kNyquist) {
            const int mirror = kN - k;
            m_fftRealL[static_cast<size_t>(mirror)] *= mask;
            m_fftImagL[static_cast<size_t>(mirror)] *= mask;
            m_fftRealR[static_cast<size_t>(mirror)] *= mask;
            m_fftImagR[static_cast<size_t>(mirror)] *= mask;
        }
    }

    fft(m_fftRealL, m_fftImagL, true);
    fft(m_fftRealR, m_fftImagR, true);

    for (int n = 0; n < kN; ++n) {
        const size_t outputSlot =
            static_cast<size_t>((start + static_cast<uint64_t>(n)) % static_cast<uint64_t>(kN));
        const double window = m_window[static_cast<size_t>(n)];
        m_outBuf[2 * outputSlot] += m_fftRealL[static_cast<size_t>(n)] * window;
        m_outBuf[2 * outputSlot + 1] += m_fftRealR[static_cast<size_t>(n)] * window;
    }
}

void ResonanceSuppressor::rebuildDepthEnvelope()
{
    double effectiveDepth[12] = {};
    for (int i = 0; i < 12; ++i) {
        double depth = m_params.knotActive[i]
                           ? double(m_params.gDb) * double(m_params.knotDepthDb[i]) / 10.0
                           : 0.0;
        depth += double(m_params.tilt) * std::log2(kKnotFrequencies[i] / 1000.0);
        effectiveDepth[i] = std::clamp(depth, 0.0, 10.0);
    }

    for (int k = 0; k <= kN / 2; ++k) {
        const double frequency = double(k) * double(m_sampleRate) / double(kN);
        double depth = effectiveDepth[0];
        if (frequency >= kKnotFrequencies[11]) {
            depth = effectiveDepth[11];
        } else if (frequency > kKnotFrequencies[0]) {
            int upper = 1;
            while (upper < 12 && frequency > kKnotFrequencies[upper])
                ++upper;
            if (upper < 12) {
                const double lowerLog = std::log(kKnotFrequencies[upper - 1]);
                const double upperLog = std::log(kKnotFrequencies[upper]);
                const double amount = (std::log(frequency) - lowerLog) / (upperLog - lowerLog);
                depth = effectiveDepth[upper - 1] +
                        amount * (effectiveDepth[upper] - effectiveDepth[upper - 1]);
            }
        }
        m_depthEnv[static_cast<size_t>(k)] = depth;
    }
}

void ResonanceSuppressor::rebuildTiming()
{
    if (m_sampleRate <= 0.0f) {
        m_alphaAttack = 0.0;
        m_alphaRelease = 0.0;
        m_stepCap = 0.0;
        return;
    }

    const double dt = double(kH) / double(m_sampleRate);
    const double timing = double(m_params.timingMs) * 0.001;
    if (timing > 0.0) {
        m_alphaAttack = 1.0 - std::exp(-dt / timing);
        m_alphaRelease = 1.0 - std::exp(-dt / (4.0 * timing));
    } else {
        m_alphaAttack = 1.0;
        m_alphaRelease = 1.0;
    }
    m_stepCap = 100.0 * dt;
}

void ResonanceSuppressor::resetState()
{
    std::fill(m_inFifo.begin(), m_inFifo.end(), 0.0);
    std::fill(m_outBuf.begin(), m_outBuf.end(), 0.0);
    std::fill(m_curGb.begin(), m_curGb.end(), 0.0);
    std::fill(m_mask.begin(), m_mask.end(), 1.0);
    m_count = static_cast<uint64_t>(kH);
}
