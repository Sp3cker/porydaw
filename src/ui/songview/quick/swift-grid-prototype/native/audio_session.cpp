#include "audio_session.h"
#include "audio_session_internal.h"

#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timedefaults.h"

#include <QString>

extern "C" {
#include "voicegroup_loader.h"
}

#include <algorithm>
#include <cstdio>
#include <memory>
#include <vector>

namespace {

constexpr uint8_t kControllerBend = 0xFF;

// Projects the Swift-owned state into an SMF: conductor chunk 0 with the
// 120 BPM tempo meta, one chunk per engine track (programs 0 and 2 latched on
// the two demo engine tracks so empty Swift tracks keep the file mapping).
SmfFile buildSmf(const SGNote *notes, size_t noteCount, const SGController *controllers,
                 size_t controllerCount)
{
    SmfFile smf;
    smf.division = 24;
    smf.tracks.resize(3);
    SmfEvent tempo;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArrayLiteral("\x07\xa1\x20");
    smf.tracks[0].events.push_back(std::move(tempo));
    for (int track = 0; track < 2; ++track)
        smf.tracks[track + 1].events.push_back(
            {0, uint8_t(0xC0 | track), 0, uint8_t(track == 0 ? 0 : 2), 0, {}, {}});
    for (size_t i = 0; i < controllerCount; ++i) {
        const auto &controller = controllers[i];
        SmfEvent event;
        event.tick = Tick(controller.tick);
        if (controller.controller == kControllerBend) {
            const int value = controller.value + 8192;
            event.status = uint8_t(0xE0 | controller.track);
            event.data0 = uint8_t(value & 0x7F);
            event.data1 = uint8_t(value >> 7);
        } else {
            event.status = uint8_t(0xB0 | controller.track);
            event.data0 = uint8_t(controller.controller);
            event.data1 = uint8_t(controller.value);
        }
        smf.tracks[controller.track + 1].events.push_back(std::move(event));
    }
    for (size_t i = 0; i < noteCount; ++i) {
        const auto &note = notes[i];
        auto &events = smf.tracks[note.track + 1].events;
        events.push_back({Tick(note.tick),
                          uint8_t(0x90 | note.track),
                          0,
                          uint8_t(note.pitch),
                          uint8_t(note.velocity),
                          {},
                          {}});
        events.push_back({Tick(note.tick + note.duration),
                          uint8_t(0x80 | note.track),
                          0,
                          uint8_t(note.pitch),
                          0,
                          {},
                          {}});
    }
    const auto priority = [](const SmfEvent &event) {
        return event.isNoteEnd() ? 0 : event.isNoteOn() ? 2 : 1;
    };
    for (auto &track : smf.tracks) {
        std::stable_sort(track.events.begin(), track.events.end(),
                         [&](const SmfEvent &a, const SmfEvent &b) {
                             return a.tick != b.tick ? a.tick < b.tick : priority(a) < priority(b);
                         });
        track.endTick = track.events.back().tick;
    }
    return smf;
}

std::unique_ptr<MidiTimeline> buildTimeline(const SGNote *notes, size_t noteCount,
                                            const SGController *controllers, size_t controllerCount,
                                            double sampleRate)
{
    return MidiTimeline::build(buildSmf(notes, noteCount, controllers, controllerCount),
                               sampleRate);
}

} // namespace

extern "C" {

SGAudioSession *sga_create(const char *fixture_root, char *error_buffer, size_t error_capacity)
{
    auto report = [&](const QString &message) {
        std::snprintf(error_buffer, error_capacity, "%s", message.toUtf8().constData());
    };
    auto session = std::make_unique<SGAudioSession>();
    QString engineError;
    if (!session->engine.init(&engineError)) {
        report(engineError);
        return nullptr;
    }
    LoadedVoiceGroup *bank = voicegroup_load(fixture_root, "fixture_rich", nullptr);
    if (!bank) {
        report(QStringLiteral("Failed to load voicegroup fixture_rich from %1")
                   .arg(QString::fromUtf8(fixture_root)));
        return nullptr;
    }
    session->voicegroup = wrapVoicegroupLease(bank);
    session->backendName = session->engine.backendName().toUtf8();
    return session.release();
}

void sga_destroy(SGAudioSession *session)
{
    delete session;
}

void sga_sync(SGAudioSession *session, const SGNote *notes, size_t note_count,
              const SGController *controllers, size_t controller_count)
{
    const bool loaded = bool(session->timeline);
    session->timeline = buildTimeline(notes, note_count, controllers, controller_count,
                                      session->engine.sampleRate());
    if (loaded)
        session->engine.updateTimeline(session->timeline);
    else
        session->engine.loadSong(session->timeline, session->voicegroup, SongSettings{});
}

void sga_play(SGAudioSession *session)
{
    session->engine.play();
}
void sga_pause(SGAudioSession *session)
{
    session->engine.pause();
}
void sga_stop(SGAudioSession *session)
{
    session->engine.stop();
}

void sga_seek_tick(SGAudioSession *session, double tick)
{
    session->engine.seek(session->timeline->sampleForTick(CoreTimeDefaults::tickFromDouble(tick)));
}

void sga_preview(SGAudioSession *session, int track, int key, int velocity)
{
    session->engine.previewNote(uint8_t(track), uint8_t(key), uint8_t(velocity));
}

int sga_is_playing(SGAudioSession *session)
{
    return session->engine.transport() == Transport::Playing ? 1 : 0;
}

double sga_playhead_tick(SGAudioSession *session)
{
    return session->timeline->tickForSample(session->engine.playheadSamples());
}

double sga_sample_rate(SGAudioSession *session)
{
    return session->engine.sampleRate();
}

int sga_using_null_backend(SGAudioSession *session)
{
    return session->engine.usingNullBackend() ? 1 : 0;
}

const char *sga_backend_name(SGAudioSession *session)
{
    return session->backendName.constData();
}
} // extern "C"
