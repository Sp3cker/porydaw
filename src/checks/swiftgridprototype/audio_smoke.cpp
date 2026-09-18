#include "grid_smoke.h"

#include "audio_session.h"
#include "audio_session_internal.h"
#include "checks/support/audioengineaccess.h"
#include "core/miditimeline.h"

#include <QCoreApplication>
#include <QDir>

#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <span>
#include <vector>

namespace {
void requireAudio(bool condition, const char *message)
{
    if (!condition) {
        std::fprintf(stderr, "SWIFT_GRID_SMOKE FAIL: %s\n", message);
        std::exit(EXIT_FAILURE);
    }
}

using Session = std::unique_ptr<SGAudioSession, decltype(&sga_destroy)>;

Session makeSession()
{
#ifdef Q_OS_MACOS
    const QByteArray root = QDir(QCoreApplication::applicationDirPath())
                                .absoluteFilePath("../Resources/AudioFixture")
                                .toUtf8();
#else
    const QByteArray root =
        QDir(QCoreApplication::applicationDirPath()).absoluteFilePath("AudioFixture").toUtf8();
#endif
    std::array<char, 1024> error{};
    Session session(sga_create(root.constData(), error.data(), error.size()), sga_destroy);
    requireAudio(bool(session), error.data());
    requireAudio(sga_using_null_backend(session.get()), "audio smoke must use the null device");
    return session;
}

std::vector<float> render(Session &session, double ticks)
{
    const auto frames = session->timeline->sampleForTick(Tick(ticks));
    const auto target = session->engine.playheadSamples() + frames;
    const auto budget = frames + size_t(sga_sample_rate(session.get()));
    std::vector<float> output;
    output.reserve(budget * 2);
    std::array<float, 1024> block;
    while (session->engine.playheadSamples() < target && output.size() / 2 < budget) {
        const auto count = std::min<uint64_t>(512, target - session->engine.playheadSamples());
        const auto samples = std::span(block).first(count * 2);
        checks::AudioEngineTestAccess::renderParked(session->engine, samples);
        output.insert(output.end(), samples.begin(), samples.end());
    }
    requireAudio(session->engine.playheadSamples() == target,
                 "audio transport did not advance within its startup deadline");
    return output;
}

double energy(std::span<const float> samples)
{
    double result = 0;
    for (const float sample : samples) {
        requireAudio(std::isfinite(sample), "poryaaaa emitted non-finite PCM");
        result += double(sample) * sample;
    }
    return result;
}

std::vector<float> firstPhrase(std::span<const SGController> controllers)
{
    auto session = makeSession();
    const SGNote note{0, 48, 0, 60, 100};
    sga_sync(session.get(), &note, 1, controllers.data(), controllers.size());
    requireAudio(checks::AudioEngineTestAccess::parkDevice(session->engine),
                 "cannot park audio device for deterministic render");
    sga_play(session.get());
    return render(session, 6);
}
} // namespace

void verifyGridAudio()
{
    const auto plain = firstPhrase({});
    requireAudio(energy(plain) > 0.001, "bundled fixture produced silent PCM");
    std::puts("SWIFT_GRID_SMOKE bundled-poryaaaa-pcm PASS");

    const std::array<SGController, 2> curve{{{0, 0, 255, -4096}, {12, 0, 255, 4096}}};
    const auto bent = firstPhrase(curve);
    requireAudio(bent.size() == plain.size(), "audio renders disagree on duration");
    double difference = 0;
    for (size_t i = 0; i < plain.size(); ++i)
        difference += std::abs(double(plain[i]) - bent[i]);
    requireAudio(difference > 0.01,
                 "early pitch-bend point was discarded in favor of the final curve point");
    std::puts("SWIFT_GRID_SMOKE pitch-curve-affects-real-pcm PASS");

    auto session = makeSession();
    const SGNote original{0, 48, 0, 60, 100};
    sga_sync(session.get(), &original, 1, nullptr, 0);
    requireAudio(checks::AudioEngineTestAccess::parkDevice(session->engine),
                 "cannot park device before hot timeline update");
    sga_sync(session.get(), nullptr, 0, nullptr, 0);
    sga_play(session.get());
    requireAudio(energy(render(session, 6)) == 0,
                 "deleted notes still play after a hot timeline update");
    sga_stop(session.get());
    sga_sync(session.get(), &original, 1, nullptr, 0);
    sga_seek_tick(session.get(), 0);
    sga_play(session.get());
    requireAudio(energy(render(session, 6)) > 0.001,
                 "restored notes remain silent after hot timeline update");
    std::puts("SWIFT_GRID_SMOKE hot-note-publication-pcm PASS");
}
