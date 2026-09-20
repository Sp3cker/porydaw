#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "audio/swift_playback.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PdAudioService PdAudioService;
typedef struct PdBankLease PdBankLease;

typedef struct PdAudioSettings {
    int32_t pcmMixer;
    uint8_t songVolume;
    uint8_t reverb;
    uint8_t maxPcmChannels;
    float pcmMixRate;
    bool analogFilter;
} PdAudioSettings;

PdAudioService *pd_audio_service_create(void);
void pd_audio_service_destroy(PdAudioService *service);
bool pd_audio_service_init(PdAudioService *service, char *error, size_t errorCapacity);
double pd_audio_service_sample_rate(const PdAudioService *service);

// bind/publish consume the caller's one owned publication reference, including
// failure paths. The bank lease remains borrowed and must outlive bind/unload.
bool pd_audio_service_bind(PdAudioService *service, PdPlaybackData *publication,
                           const PdBankLease *bank, PdAudioSettings settings);
bool pd_audio_service_publish(PdAudioService *service, PdPlaybackData *publication);
void pd_audio_service_unload(PdAudioService *service);

void pd_audio_service_play(PdAudioService *service);
void pd_audio_service_pause(PdAudioService *service);
void pd_audio_service_stop(PdAudioService *service);
void pd_audio_service_seek(PdAudioService *service, uint64_t samplePosition);
void pd_audio_service_preview_note(PdAudioService *service, uint8_t track, uint8_t key,
                                   uint8_t velocity);
int32_t pd_audio_service_transport(const PdAudioService *service);
uint64_t pd_audio_service_playhead(const PdAudioService *service);
int32_t pd_audio_service_active_pcm(const PdAudioService *service);
int32_t pd_audio_service_active_cgb(const PdAudioService *service);

#ifdef __cplusplus
}
#endif
