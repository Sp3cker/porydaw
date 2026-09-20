#include "native_check.h"

#include <QByteArray>

#include <cstdint>
#include <memory>

#include "checks/playback/sustainvoicegroup.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {
QByteArray gFixtureRoot;
} // namespace

struct PdcPlaybackEngine {
    M4AEngine engine{};
    checks::SustainVoicegroup bank;
    bool initialized = false;

    explicit PdcPlaybackEngine(double sampleRate)
    {
        ToneData &square = bank.voices[2];
        square.type = VOICE_SQUARE_2;
        square.key = 60;
        square.wavePointer = reinterpret_cast<uint32_t *>(uintptr_t{2});
        square.attack = 7;
        square.decay = 0;
        square.sustain = 15;
        square.release = 7;
        initialized = m4a_engine_init(&engine, float(sampleRate));
        if (initialized)
            m4a_engine_set_voicegroup(&engine, bank.voices);
    }

    ~PdcPlaybackEngine()
    {
        if (initialized)
            m4a_engine_destroy(&engine);
    }
};

extern "C" void pdc_check_set_fixture_root(const char *path)
{
    gFixtureRoot = path ? QByteArray(path) : QByteArray();
}

extern "C" const char *pdc_check_fixture_root()
{
    return gFixtureRoot.isEmpty() ? nullptr : gFixtureRoot.constData();
}

extern "C" PdcPlaybackEngine *pdc_playback_engine_create(double sampleRate)
{
    std::unique_ptr<PdcPlaybackEngine> engine = std::make_unique<PdcPlaybackEngine>(sampleRate);
    if (!engine->initialized)
        return nullptr;
    return engine.release();
}

extern "C" void pdc_playback_engine_destroy(PdcPlaybackEngine *engine)
{
    delete engine;
}

extern "C" void *pdc_playback_engine_pointer(PdcPlaybackEngine *engine)
{
    return engine ? &engine->engine : nullptr;
}
