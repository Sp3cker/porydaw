#include "audio/swift_audio_service.h"

#include "audio/audioengine.h"
#include "project/swift_project_service.h"

#include <QByteArray>
#include <QString>

#include <algorithm>
#include <cstring>
#include <memory>

struct PdAudioService {
    AudioEngine engine;
    bool initialized = false;
};

namespace {

void copyError(const QString &error, char *output, size_t capacity)
{
    if (!output || capacity == 0)
        return;
    const QByteArray bytes = error.toUtf8();
    const auto count = std::min(capacity - 1, size_t(bytes.size()));
    std::memcpy(output, bytes.constData(), count);
    output[count] = '\0';
}

std::shared_ptr<const PdPlaybackData> adopt(PdPlaybackData *publication)
{
    return {publication, pd_playback_data_release};
}

SongSettings nativeSettings(PdAudioSettings settings)
{
    SongSettings result;
    if (settings.pcmMixer >= 0)
        result.pcmMixer = static_cast<M4APcmMixerMode>(settings.pcmMixer);
    result.songVolume = settings.songVolume;
    result.reverb = settings.reverb;
    result.maxPcmChannels = settings.maxPcmChannels;
    result.pcmMixRate = settings.pcmMixRate;
    result.analogFilter = settings.analogFilter;
    return result;
}

} // namespace

extern "C" PdAudioService *pd_audio_service_create()
{
    return new PdAudioService;
}

extern "C" void pd_audio_service_destroy(PdAudioService *service)
{
    delete service;
}

extern "C" bool pd_audio_service_init(PdAudioService *service, char *error, size_t errorCapacity)
{
    if (!service)
        return false;
    QString detail;
    service->initialized = service->engine.init(&detail);
    copyError(detail, error, errorCapacity);
    return service->initialized;
}

extern "C" double pd_audio_service_sample_rate(const PdAudioService *service)
{
    return service && service->initialized ? service->engine.sampleRate() : 0.0;
}

extern "C" bool pd_audio_service_bind(PdAudioService *service, PdPlaybackData *publication,
                                      const PdBankLease *bank, PdAudioSettings settings)
{
    auto timeline = adopt(publication);
    if (!service || !service->initialized || !timeline || !bank)
        return false;
    service->engine.loadSong(std::move(timeline), pd_bank_lease_native(bank),
                             nativeSettings(settings));
    return true;
}

extern "C" bool pd_audio_service_publish(PdAudioService *service, PdPlaybackData *publication)
{
    auto timeline = adopt(publication);
    if (!service || !service->initialized || !timeline || !service->engine.songLoaded())
        return false;
    service->engine.updateTimeline(std::move(timeline));
    return true;
}

extern "C" void pd_audio_service_unload(PdAudioService *service)
{
    if (service && service->initialized)
        service->engine.unloadSong();
}

extern "C" void pd_audio_service_play(PdAudioService *service)
{
    if (service)
        service->engine.play();
}

extern "C" void pd_audio_service_pause(PdAudioService *service)
{
    if (service)
        service->engine.pause();
}

extern "C" void pd_audio_service_stop(PdAudioService *service)
{
    if (service)
        service->engine.stop();
}

extern "C" void pd_audio_service_seek(PdAudioService *service, uint64_t samplePosition)
{
    if (service)
        service->engine.seek(samplePosition);
}

extern "C" void pd_audio_service_preview_note(PdAudioService *service, uint8_t track, uint8_t key,
                                              uint8_t velocity)
{
    if (service)
        service->engine.previewNote(track, key, velocity);
}

extern "C" int32_t pd_audio_service_transport(const PdAudioService *service)
{
    return service ? int32_t(service->engine.transport()) : int32_t(Transport::Stopped);
}

extern "C" uint64_t pd_audio_service_playhead(const PdAudioService *service)
{
    return service ? service->engine.playheadSamples() : 0;
}

extern "C" int32_t pd_audio_service_active_pcm(const PdAudioService *service)
{
    return service ? service->engine.activePcmChannels() : 0;
}

extern "C" int32_t pd_audio_service_active_cgb(const PdAudioService *service)
{
    return service ? service->engine.activeCgbChannels() : 0;
}
