#include "checks/samplecheck/fixtures.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <algorithm>
#include <cmath>

bool writeFile(const QString &path, const QByteArray &bytes)
{
    QDir().mkpath(QFileInfo(path).path());
    QFile out(path);
    return out.open(QIODevice::WriteOnly) && out.write(bytes) == bytes.size();
}

QByteArray readFileBytes(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return QByteArray();
    return f.readAll();
}

void putU16(QByteArray *out, quint16 v)
{
    out->append(char(v)).append(char(v >> 8));
}

void putU32(QByteArray *out, quint32 v)
{
    out->append(char(v)).append(char(v >> 8)).append(char(v >> 16)).append(char(v >> 24));
}

quint32 getU32(const QByteArray &b, qsizetype at)
{
    return quint32(quint8(b[at])) | quint32(quint8(b[at + 1])) << 8 |
           quint32(quint8(b[at + 2])) << 16 | quint32(quint8(b[at + 3])) << 24;
}

// A .wav per FORMATS.md §1's chunk vocabulary: fmt/data[/smpl/agbp/agbl].
QByteArray fixtureWav(const FixtureSpec &spec)
{
    const quint16 blockAlign = spec.channels * (spec.bits / 8);
    QByteArray wav("RIFF\0\0\0\0WAVE", 12);
    wav += "fmt ";
    putU32(&wav, 16);
    putU16(&wav, spec.formatTag);
    putU16(&wav, spec.channels);
    putU32(&wav, spec.rate);
    putU32(&wav, spec.rate * blockAlign);
    putU16(&wav, blockAlign);
    putU16(&wav, spec.bits);
    wav += "data";
    putU32(&wav, quint32(spec.samples.size()));
    wav += spec.samples;
    if (spec.samples.size() & 1)
        wav += '\0'; // RIFF pad byte
    if (spec.withSmpl) {
        wav += "smpl";
        putU32(&wav, quint32(36 + 24 * spec.numLoops));
        putU32(&wav, 0); // manufacturer
        putU32(&wav, 0); // product
        putU32(&wav, 0); // sample period
        putU32(&wav, spec.unityKey);
        putU32(&wav, spec.pitchFraction);
        putU32(&wav, 0); // SMPTE format
        putU32(&wav, 0); // SMPTE offset
        putU32(&wav, quint32(spec.numLoops));
        putU32(&wav, 0); // sampler data
        for (int i = 0; i < spec.numLoops; i++) {
            putU32(&wav, quint32(i)); // cue point id
            putU32(&wav, spec.loopType);
            putU32(&wav, spec.loopStart);
            putU32(&wav, spec.loopEndIncl);
            putU32(&wav, 0); // fraction
            putU32(&wav, 0); // play count
        }
    }
    if (spec.agbp) {
        wav += "agbp";
        putU32(&wav, 4);
        putU32(&wav, spec.agbp);
    }
    if (spec.agbl) {
        wav += "agbl";
        putU32(&wav, 4);
        putU32(&wav, spec.agbl);
    }
    const quint32 riffSize = quint32(wav.size()) - 8;
    wav[4] = char(riffSize);
    wav[5] = char(riffSize >> 8);
    wav[6] = char(riffSize >> 16);
    wav[7] = char(riffSize >> 24);
    return wav;
}

void putBe16(QByteArray *out, quint16 v)
{
    out->append(char(v >> 8)).append(char(v));
}

void putBe32(QByteArray *out, quint32 v)
{
    out->append(char(v >> 24)).append(char(v >> 16)).append(char(v >> 8)).append(char(v));
}

// 80-bit IEEE extended float, the COMM sample-rate encoding.
void putExtended80(QByteArray *out, double v)
{
    int exp2 = 0;
    const double mant = std::frexp(v, &exp2);
    const quint64 m = quint64(std::ldexp(mant, 64));
    putBe16(out, quint16(16382 + exp2));
    for (int i = 7; i >= 0; i--)
        out->append(char(m >> (i * 8)));
}

QByteArray fixtureAiff(const AiffSpec &spec)
{
    QByteArray aif("FORM\0\0\0\0AIFF", 12);
    aif += "COMM";
    putBe32(&aif, 18);
    putBe16(&aif, spec.channels);
    putBe32(&aif, spec.numFrames);
    putBe16(&aif, spec.sampleSize);
    putExtended80(&aif, spec.rate);
    if (spec.loop) {
        aif += "MARK";
        putBe32(&aif, 2 + 2 * 8);
        putBe16(&aif, 2); // two markers, empty pascal names (pad to even)
        putBe16(&aif, 1);
        putBe32(&aif, spec.loopStartPos);
        aif += QByteArray("\0\0", 2);
        putBe16(&aif, 2);
        putBe32(&aif, spec.loopEndPos);
        aif += QByteArray("\0\0", 2);
    }
    aif += "INST";
    putBe32(&aif, 20);
    aif += char(qint8(spec.baseNote));
    aif += char(qint8(spec.detune));
    aif += QByteArray(6, '\0');       // low/high note, low/high velocity, gain
    putBe16(&aif, spec.loop ? 1 : 0); // sustain loop playMode
    putBe16(&aif, 1);                 // begin marker id
    putBe16(&aif, 2);                 // end marker id
    aif += QByteArray(6, '\0');       // release loop, unused
    aif += "SSND";
    putBe32(&aif, quint32(8 + spec.ssnd.size()));
    putBe32(&aif, 0); // offset
    putBe32(&aif, 0); // block size
    aif += spec.ssnd;
    if (spec.ssnd.size() & 1)
        aif += '\0';
    const quint32 formSize = quint32(aif.size()) - 8;
    aif[4] = char(formSize >> 24);
    aif[5] = char(formSize >> 16);
    aif[6] = char(formSize >> 8);
    aif[7] = char(formSize);
    return aif;
}

namespace {
constexpr double kPi = 3.14159265358979323846;
}

std::vector<float> genSine(double rate, double freq, double seconds, double amp)
{
    std::vector<float> v(size_t(rate * seconds));
    for (size_t i = 0; i < v.size(); i++)
        v[i] = float(amp * std::sin(2.0 * kPi * freq * double(i) / rate));
    return v;
}
std::vector<float> genSineFast(double rate, double freq, double seconds, double amp)
{
    const float frate = float(rate);
    const float ffreq = float(freq);
    const float famp = float(amp);
    const float kPiF = float(kPi);
    std::vector<float> v(size_t(rate * seconds));
    for (size_t i = 0; i < v.size(); i++)
        v[i] = famp * std::sin(2.0f * kPiF * ffreq * float(i) / frate);
    return v;
}

double rmsOf(const std::vector<float> &v, size_t from, size_t to)
{
    if (to <= from)
        return 0.0;
    double sum = 0.0;
    for (size_t i = from; i < to; i++)
        sum += double(v[i]) * double(v[i]);
    return std::sqrt(sum / double(to - from));
}

// Hann-windowed single-tone amplitude estimate: immune to partial-cycle
// leakage, so passband gain measures to well under 0.01 dB.
double toneAmp(const std::vector<float> &v, double rate, double freq, size_t from, size_t to)
{
    double re = 0.0, im = 0.0, wsum = 0.0;
    const double span = double(to - from);
    for (size_t i = from; i < to; i++) {
        const double w = 0.5 * (1.0 - std::cos(2.0 * kPi * double(i - from) / span));
        const double phase = 2.0 * kPi * freq * double(i) / rate;
        re += double(v[i]) * w * std::cos(phase);
        im += double(v[i]) * w * std::sin(phase);
        wsum += w;
    }
    return 2.0 * std::sqrt(re * re + im * im) / wsum;
}

double median(std::vector<double> v)
{
    if (v.empty())
        return 0.0;
    std::sort(v.begin(), v.end());
    const size_t mid = v.size() / 2;
    return v.size() & 1 ? v[mid] : 0.5 * (v[mid - 1] + v[mid]);
}

// Band-limited sawtooth (additive, harmonics below 0.45·rate): naive saws
// alias, which would smear the pitch-detection acceptance sweep.
std::vector<float> genSaw(double rate, double freq, double seconds, double amp)
{
    std::vector<float> v(size_t(rate * seconds), 0.0f);
    for (int k = 1; freq * k < 0.45 * rate; k++) {
        for (size_t i = 0; i < v.size(); i++)
            v[i] += float(amp * (2.0 / kPi) * std::sin(2.0 * kPi * freq * k * double(i) / rate) /
                          double(k));
    }
    return v;
}

double centsOff(double f0, double reference)
{
    return 1200.0 * std::log2(f0 / reference);
}
