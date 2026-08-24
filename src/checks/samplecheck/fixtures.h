#pragma once

#include <QByteArray>
#include <QString>
#include <cstddef>
#include <vector>

struct FixtureSpec {
    quint32 rate = 13379;
    QByteArray samples;
    quint16 channels = 1;
    quint16 formatTag = 1;
    quint16 bits = 8;
    bool withSmpl = true;
    quint32 unityKey = 60;
    quint32 pitchFraction = 0;
    int numLoops = 0;
    quint32 loopType = 0;
    quint32 loopStart = 0;
    quint32 loopEndIncl = 0;
    quint32 agbp = 0;
    quint32 agbl = 0;
};

struct AiffSpec {
    quint16 channels = 1;
    quint32 numFrames = 0;
    quint16 sampleSize = 16;
    double rate = 22050.0;
    QByteArray ssnd;
    int baseNote = 60;
    int detune = 0;
    bool loop = false;
    quint32 loopStartPos = 0;
    quint32 loopEndPos = 0;
};

bool writeFile(const QString &path, const QByteArray &bytes);
QByteArray readFileBytes(const QString &path);
void putU16(QByteArray *out, quint16 value);
void putU32(QByteArray *out, quint32 value);
quint32 getU32(const QByteArray &bytes, qsizetype at);
QByteArray fixtureWav(const FixtureSpec &spec);
void putBe16(QByteArray *out, quint16 value);
void putBe32(QByteArray *out, quint32 value);
QByteArray fixtureAiff(const AiffSpec &spec);
std::vector<float> genSine(double rate, double freq, double seconds, double amp);
std::vector<float> genSineFast(double rate, double freq, double seconds, double amp);
double rmsOf(const std::vector<float> &values, size_t from, size_t to);
double toneAmp(const std::vector<float> &values, double rate, double freq, size_t from, size_t to);
double median(std::vector<double> values);
std::vector<float> genSaw(double rate, double freq, double seconds, double amp);
double centsOff(double f0, double reference);
