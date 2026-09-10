#include "audio/audiotap.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace {

// MSVC does not define M_PI without _USE_MATH_DEFINES.
constexpr float kPi = 3.14159265358979323846f;

uint32_t roundUpPow2(uint32_t v)
{
    uint32_t p = 1;
    while (p < v && p < (1u << 30))
        p <<= 1;
    return p;
}

} // namespace

AudioTap::AudioTap(uint32_t capacityFrames)
    : m_ring(size_t(roundUpPow2(std::max<uint32_t>(capacityFrames, 2))) * 2, 0.0f)
    , m_mask(roundUpPow2(std::max<uint32_t>(capacityFrames, 2)) - 1)
{}

void AudioTap::write(const float *interleaved, uint32_t frames)
{
    if (frames == 0)
        return;
    const uint32_t cap = capacity();
    const uint64_t written = m_written.load(std::memory_order_relaxed);
    const uint64_t total = written + frames;
    if (frames > cap) {
        // Only the tail can survive anyway; it lands where it would have
        // had the whole batch been written.
        interleaved += size_t(frames - cap) * 2;
        frames = cap;
    }
    const uint32_t start = uint32_t((total - frames) & m_mask);
    const uint32_t first = std::min(frames, cap - start);
    std::memcpy(&m_ring[size_t(start) * 2], interleaved, size_t(first) * 2 * sizeof(float));
    if (first < frames) {
        std::memcpy(&m_ring[0], interleaved + size_t(first) * 2,
                    size_t(frames - first) * 2 * sizeof(float));
    }
    // Release: the reader's acquire load of m_written sees the samples.
    m_written.store(total, std::memory_order_release);
}

uint32_t AudioTap::readLatest(float *out, uint32_t frames) const
{
    const uint64_t written = m_written.load(std::memory_order_acquire);
    const uint32_t cap = capacity();
    if (frames > cap) {
        std::fill(out, out + size_t(frames - cap) * 2, 0.0f);
        out += size_t(frames - cap) * 2;
        frames = cap;
    }
    const uint32_t real = uint32_t(std::min<uint64_t>(frames, written));
    const uint32_t pad = frames - real;
    std::fill(out, out + size_t(pad) * 2, 0.0f);
    out += size_t(pad) * 2;
    if (real == 0)
        return 0;
    const uint32_t start = uint32_t((written - real) & m_mask);
    const uint32_t first = std::min(real, cap - start);
    std::memcpy(out, &m_ring[size_t(start) * 2], size_t(first) * 2 * sizeof(float));
    if (first < real) {
        std::memcpy(out + size_t(first) * 2, &m_ring[0], size_t(real - first) * 2 * sizeof(float));
    }
    return real;
}

AudioAnalyzer::AudioAnalyzer(uint32_t windowFrames)
    : m_window(roundUpPow2(std::max<uint32_t>(windowFrames, 16)))
    , m_pcm(size_t(m_window) * 2, 0.0f)
    , m_scratch(size_t(m_window) * 2, 0.0f)
    , m_hann(m_window, 0.0f)
    , m_mags(m_window / 2, 0.0f)
{
    for (uint32_t i = 0; i < m_window; i++)
        m_hann[i] = 0.5f - 0.5f * std::cos(2.0f * kPi * float(i) / float(m_window));
}

uint32_t AudioAnalyzer::poll(const AudioTap &tap)
{
    const uint64_t written = tap.framesWritten();
    uint64_t fresh = written - m_lastWritten;
    if (m_lastWritten > written) // a re-created tap
        fresh = written;
    m_lastWritten = written;
    // The interval's frames are bounded by the ring; a stalled UI (a
    // modal dialog) only loses the oldest part.
    const uint32_t count = uint32_t(std::min<uint64_t>(fresh, tap.capacity()));
    m_newFrames = count;
    m_magsValid = false;
    m_bandsBins = 0;
    tap.readLatest(m_pcm.data(), m_window);

    m_peak[0] = m_peak[1] = 0.0f;
    m_rms[0] = m_rms[1] = 0.0f;
    if (count == 0)
        return 0;
    // Peak/RMS over every new frame — larger intervals than the window
    // read from the tap again rather than growing m_pcm.
    const float *frames = m_pcm.data();
    if (count > m_window) {
        if (m_extra.size() < size_t(count) * 2)
            m_extra.resize(size_t(count) * 2);
        tap.readLatest(m_extra.data(), count);
        frames = m_extra.data();
    } else {
        frames += size_t(m_window - count) * 2;
    }
    double sum[2] = {0.0, 0.0};
    for (uint32_t i = 0; i < count; i++) {
        for (int c = 0; c < 2; c++) {
            const float v = frames[size_t(i) * 2 + c];
            const float a = std::fabs(v);
            if (a > m_peak[c])
                m_peak[c] = a;
            sum[c] += double(v) * double(v);
        }
    }
    for (int c = 0; c < 2; c++)
        m_rms[c] = float(std::sqrt(sum[c] / double(count)));
    return count;
}

void AudioAnalyzer::fft(float *reim, uint32_t n)
{
    // Bit-reversal permutation.
    for (uint32_t i = 1, j = 0; i < n; i++) {
        uint32_t bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j) {
            std::swap(reim[i * 2], reim[j * 2]);
            std::swap(reim[i * 2 + 1], reim[j * 2 + 1]);
        }
    }
    for (uint32_t len = 2; len <= n; len <<= 1) {
        const float ang = -2.0f * kPi / float(len);
        const float wr = std::cos(ang), wi = std::sin(ang);
        for (uint32_t i = 0; i < n; i += len) {
            float cr = 1.0f, ci = 0.0f;
            for (uint32_t k = 0; k < len / 2; k++) {
                const uint32_t a = (i + k) * 2, b = (i + k + len / 2) * 2;
                const float xr = reim[b] * cr - reim[b + 1] * ci;
                const float xi = reim[b] * ci + reim[b + 1] * cr;
                reim[b] = reim[a] - xr;
                reim[b + 1] = reim[a + 1] - xi;
                reim[a] += xr;
                reim[a + 1] += xi;
                const float ncr = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = ncr;
            }
        }
    }
}

void AudioAnalyzer::computeMagnitudes()
{
    for (uint32_t i = 0; i < m_window; i++) {
        const float mono = 0.5f * (m_pcm[size_t(i) * 2] + m_pcm[size_t(i) * 2 + 1]);
        m_scratch[size_t(i) * 2] = mono * m_hann[i];
        m_scratch[size_t(i) * 2 + 1] = 0.0f;
    }
    fft(m_scratch.data(), m_window);
    // A full-scale sine under a Hann window peaks at N/4 in magnitude.
    const float norm = 4.0f / float(m_window);
    for (uint32_t i = 0; i < m_window / 2; i++) {
        const float re = m_scratch[size_t(i) * 2], im = m_scratch[size_t(i) * 2 + 1];
        m_mags[i] = std::min(1.0f, std::sqrt(re * re + im * im) * norm);
    }
    m_magsValid = true;
}

const std::vector<float> &AudioAnalyzer::spectrum(uint32_t bins)
{
    const uint32_t half = m_window / 2;
    bins = std::clamp<uint32_t>(bins, 1, half);
    if (m_magsValid && m_bandsBins == bins)
        return m_bands;
    if (!m_magsValid)
        computeMagnitudes();
    m_bands.assign(bins, 0.0f);
    // Each band takes the loudest FFT bin it covers, so narrow bands at
    // low frequencies and wide ones up top both read as "the tone here".
    for (uint32_t i = 0; i < half; i++) {
        const uint32_t b = uint32_t((uint64_t(i) * bins) / half);
        m_bands[b] = std::max(m_bands[b], m_mags[i]);
    }
    m_bandsBins = bins;
    return m_bands;
}
