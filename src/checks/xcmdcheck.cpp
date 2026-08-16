#include <cstdio>

#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timelineplayer.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {

constexpr double kSampleRate = 48000.0;
constexpr uint8_t kPseudoEchoVolume = 0x22;
constexpr uint8_t kPseudoEchoLength = 0x11;

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

std::unique_ptr<MidiTimeline> buildXcmdTimeline()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(1);
    SmfTrack &track = smf.tracks[0];
    track.events.push_back(channelEvent(0, 0xC0, 0, 0));
    track.events.push_back(channelEvent(1, 0xB0, 0x1E, 0x08));
    track.events.push_back(channelEvent(1, 0xB0, 0x1D, kPseudoEchoVolume));
    track.events.push_back(channelEvent(1, 0xB0, 0x1E, 0x09));
    track.events.push_back(channelEvent(1, 0xB0, 0x1F, kPseudoEchoLength));
    track.events.push_back(channelEvent(2, 0x90, 60, 127));
    track.endTick = 3;
    return MidiTimeline::build(smf, kSampleRate);
}

int checkEchoState(const M4AEngine &engine, uint8_t volume, uint8_t length, const char *path)
{
    const M4ATrack &track = engine.tracks[0];
    if (track.pseudoEchoVolume == volume && track.pseudoEchoLength == length)
        return 0;

    std::fprintf(stderr,
                 "xcmdcheck: FAIL: %s produced pseudo-echo volume %u, length %u; "
                 "expected %u, %u\n",
                 path, unsigned(track.pseudoEchoVolume), unsigned(track.pseudoEchoLength),
                 unsigned(volume), unsigned(length));
    return 1;
}

int checkAltVoiceEcho(const M4AEngine &engine)
{
    const M4ATrack &track = engine.tracks[0];
    const M4ACGBChannel &channel = engine.cgbChannels[0];
    if (track.currentVoice.type == VOICE_SQUARE_1_ALT && channel.trackIndex == 0 &&
        channel.pseudoEchoVolume == kPseudoEchoVolume &&
        channel.pseudoEchoLength == kPseudoEchoLength)
        return 0;

    std::fprintf(stderr, "xcmdcheck: FAIL: _alt voice did not inherit XCMD pseudo-echo state\n");
    return 1;
}

} // namespace

int runXcmdCheck()
{
    const auto timeline = buildXcmdTimeline();
    if (!timeline || timeline->usedTrackCount != 1) {
        std::fprintf(stderr, "xcmdcheck: FAIL: synthesized timeline built wrong\n");
        return 1;
    }

    int failures = 0;
    {
        M4AEngine engine;
        m4a_engine_init(&engine, float(kSampleRate));
        ToneData voices[128] = {};
        voices[0].type = VOICE_SQUARE_1_ALT;
        voices[0].key = 60;
        voices[0].attack = 255;
        voices[0].sustain = 255;
        voices[0].release = 165;
        m4a_engine_set_voicegroup(&engine, voices);
        TimelinePlayer player;
        float left[2001], right[2001];
        player.render(&engine, timeline.get(), left, right, 2001, false, 0);
        failures +=
            checkEchoState(engine, kPseudoEchoVolume, kPseudoEchoLength, "linear playback");
        failures += checkAltVoiceEcho(engine);
        m4a_engine_destroy(&engine);
    }
    {
        M4AEngine engine;
        m4a_engine_init(&engine, float(kSampleRate));
        TimelinePlayer::chase(&engine, timeline.get(), 1001);
        failures +=
            checkEchoState(engine, kPseudoEchoVolume, kPseudoEchoLength, "mid-song chase");
        TimelinePlayer::chase(&engine, timeline.get(), 0);
        failures += checkEchoState(engine, 0, 0, "backward chase");
        m4a_engine_destroy(&engine);
    }

    std::printf("xcmdcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
