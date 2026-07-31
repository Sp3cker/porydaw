#include <QByteArray>
#include <QElapsedTimer>
#include <QThread>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <functional>
#include <memory>

#include "audio/audioengine.h"
#include "core/miditimeline.h"
#include "core/smf.h"

// --transportcheck: transport transitions halt ringing sound (self-contained,
// needs a working audio output device — SKIPs cleanly without one). A
// slow-release voice keeps ringing long after a note-off, so every
// transition cuts hard: entering Playing halts auditions before the song
// sounds, and entering Paused falls silent like Stop instead of ringing
// through the pause. Plays a synthesized song with NO notes, so the engine's
// active-channel telemetry isolates the previews: after each transition the
// count must drop to zero. Scenarios: play from Stopped with a ringing tail;
// pause with a preview sounding; the Space path (pause, audition, seek +
// play — Space toggles pause, so this is how playback usually starts);
// resuming with a preview still counting down; and unloadSong with the song
// still playing (the song-switch path — the caller frees the outgoing
// voicegroup right after unloadSong returns, so a channel left CHN_ON would
// keep rendering the freed WaveData).

namespace {

constexpr uint32_t kDivision = 24;

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent ev;
    ev.tick = tick;
    ev.status = status;
    ev.data0 = data0;
    ev.data1 = data1;
    return ev;
}

// Two voiced tracks and no notes: both use program 0 (release 254, a tail
// that rings for ~12 s — only a hard cut can silence it promptly). The late
// CC stretches lengthSamples so playback doesn't auto-stop under the checks.
SmfFile buildSilentSong()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(3);

    SmfTrack &conductor = smf.tracks[0];
    SmfEvent tempo;
    tempo.tick = 0;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3); // 120 BPM
    conductor.events.push_back(tempo);
    conductor.endTick = 4800;

    SmfTrack &t0 = smf.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, 0, 0));
    t0.events.push_back(channelEvent(4800, 0xB0, 7, 100)); // 100 s at 120 BPM
    t0.endTick = 4800;

    SmfTrack &t1 = smf.tracks[2];
    t1.events.push_back(channelEvent(0, 0xC1, 1, 0));
    t1.endTick = 4800;

    return smf;
}

// One track holding a note for the whole song: the unload scenario needs the
// PLAYER, not a preview, to be the source of the sounding channel.
SmfFile buildNoteSong(uint8_t program = 0)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kDivision;
    smf.tracks.resize(2);

    SmfTrack &conductor = smf.tracks[0];
    SmfEvent tempo;
    tempo.tick = 0;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3); // 120 BPM
    conductor.events.push_back(tempo);
    conductor.endTick = 4800;

    SmfTrack &t0 = smf.tracks[1];
    t0.events.push_back(channelEvent(0, 0xC0, program, 0));
    t0.events.push_back(channelEvent(0, 0x90, 60, 127));
    t0.events.push_back(channelEvent(4800, 0x80, 60, 0));
    t0.endTick = 4800;

    return smf;
}

// A minimal in-memory voicegroup (primecheck's recipe): one looped PCM square
// wave, instant attack, full sustain; only the release rates differ.
struct TestVoicegroup {
    // 64 samples + the loader's guard byte: the interpolating mixer reads
    // one sample ahead, and voicegroup_loader duplicates the last byte past
    // the end (wd->data[size] = data[size - 1]).
    int8_t sample[65];
    WaveData wave;
    LoadedVoiceGroup vg;

    TestVoicegroup()
    {
        for (int i = 0; i < 64; i++)
            sample[i] = i < 32 ? 100 : -100;
        sample[64] = sample[63];
        std::memset(&wave, 0, sizeof(wave));
        wave.status = 0xC000; // looped
        wave.freq = 8363u * 1024u;
        wave.loopStart = 0;
        wave.size = 64;
        wave.data = sample;
        std::memset(&vg, 0, sizeof(vg));
        for (ToneData &v : vg.voices) {
            v.type = VOICE_DIRECTSOUND;
            v.key = 60;
            v.wav = &wave;
            v.attack = 255;
            v.decay = 0;
            v.sustain = 255;
            v.release = 254; // slow: (env * 254) >> 8 per frame, ~12 s ring
        }
        auto &square = vg.voices[2];
        square.type = VOICE_SQUARE_2;
        square.key = 60;
        square.wavePointer = reinterpret_cast<uint32_t *>(uintptr_t{2});
        square.attack = 7;
        square.decay = 0;
        square.sustain = 15;
        square.release = 7;
    }
};

// TestVoicegroup's heap-backed twin for the unload scenario: freeAll mimics
// voicegroup_free while the device keeps running, so under ASAN a channel
// that survives unloadSong turns into a use-after-free report instead of
// silently rendering stale sample memory.
struct HeapVoicegroup {
    int8_t *sample = nullptr;
    WaveData *wave = nullptr;
    LoadedVoiceGroup *vg = nullptr;

    HeapVoicegroup()
    {
        // 64 samples + the loader's guard byte: the interpolating mixer reads
        // one sample ahead, and voicegroup_loader duplicates the last byte
        // past the end (wd->data[size] = data[size - 1]).
        sample = new int8_t[65];
        for (int i = 0; i < 64; i++)
            sample[i] = i < 32 ? 100 : -100;
        sample[64] = sample[63];
        wave = new WaveData();
        std::memset(wave, 0, sizeof(*wave));
        wave->status = 0xC000; // looped
        wave->freq = 8363u * 1024u;
        wave->loopStart = 0;
        wave->size = 64;
        wave->data = sample;
        vg = new LoadedVoiceGroup();
        std::memset(vg, 0, sizeof(*vg));
        for (ToneData &v : vg->voices) {
            v.type = VOICE_DIRECTSOUND;
            v.key = 60;
            v.wav = wave;
            v.attack = 255;
            v.decay = 0;
            v.sustain = 255;
            v.release = 254;
        }
    }

    void freeAll()
    {
        delete vg;
        delete wave;
        delete[] sample;
        vg = nullptr;
        wave = nullptr;
        sample = nullptr;
    }
};

// The audio thread runs on the device's own callbacks, so conditions are
// polled in real time.
bool waitFor(const std::function<bool()> &cond, int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < timeoutMs) {
        if (cond())
            return true;
        QThread::msleep(10);
    }
    return cond();
}

} // namespace

int runTransportCheck()
{
    auto failures = 0;
    auto fail = [&](const char *what) {
        std::fprintf(stderr, "transportcheck: FAIL: %s\n", what);
        failures++;
    };
    TestVoicegroup tvg;
    std::shared_ptr<MidiTimeline> timeline;
    AudioEngine engine;
    QString error;
    if (!engine.init(&error)) {
        std::printf("transportcheck: SKIP (no audio device: %s)\n", qUtf8Printable(error));
        return 0;
    }
    const auto smf = buildSilentSong();
    timeline = std::shared_ptr<MidiTimeline>(MidiTimeline::build(smf, engine.sampleRate()));
    if (!timeline || timeline->usedTrackCount != 2) {
        std::fprintf(stderr, "transportcheck: synthesized song built wrong\n");
        return 1;
    }
    engine.loadSong(timeline, &tvg.vg, SongSettings{});
    // Hot seek must only publish a request; restarting the Core Audio device
    // here used to block the UI thread for tens of milliseconds.
    auto slowestSeekNs = qint64{0};
    const auto midSong = timeline->lengthSamples / 2;
    for (int i = 0; i < 5; i++) {
        QElapsedTimer seekTimer;
        seekTimer.start();
        engine.seek(i & 1 ? 0 : midSong);
        slowestSeekNs = std::max(slowestSeekNs, seekTimer.nsecsElapsed());
    }
    if (slowestSeekNs > 20'000'000)
        fail("seek blocked instead of publishing to the audio thread");
    if (!waitFor([&] { return engine.playheadSamples() == midSong; }, 2000))
        fail("audio thread did not apply the latest seek");
    engine.seek(0);
    if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
        fail("audio thread did not apply the reset seek");
    const auto active = [&] { return engine.activePcmChannels(); };
    engine.play();
    if (!waitFor([&] { return engine.playheadSamples() > 0; }, 2000)) {
        fail("playback did not start for pending-seek cancellation check");
    } else {
        engine.seek(midSong);
        engine.stop();
        if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
            fail("Stop did not cancel a pending seek");
    }
    // An edit rebuild must carry a pending seek onto a distinct replacement
    // timeline. The old owner retires only after the callback acknowledges
    // this publication.
    auto seekReplacementSmf = smf;
    seekReplacementSmf.tracks[1].events[0].data0 = 1;
    auto seekReplacement = std::shared_ptr<MidiTimeline>(
        MidiTimeline::build(seekReplacementSmf, engine.sampleRate()));
    if (!seekReplacement) {
        fail("seek replacement timeline built wrong");
    } else {
        engine.seek(midSong);
        engine.updateTimeline(seekReplacement);
        timeline = std::move(seekReplacement);
        if (!waitFor([&] {
                return engine.timeline() == timeline.get() &&
                       engine.playheadSamples() == midSong;
            }, 2000)) {
            fail("updateTimeline dropped a pending seek or retained old data");
        }
    }
    engine.seek(0);
    if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
        fail("reset seek after updateTimeline not applied");
    // Publishing an edit must not wait for a callback. The replacement has a
    // different event layout and becomes the active data source during play.
    auto liveReplacementSmf = smf;
    liveReplacementSmf.tracks[1].events[1].tick = 4700;
    auto liveReplacement = std::shared_ptr<MidiTimeline>(
        MidiTimeline::build(liveReplacementSmf, engine.sampleRate()));
    engine.play();
    if (!liveReplacement) {
        fail("live replacement timeline built wrong");
    } else if (!waitFor([&] { return engine.playheadSamples() > 0; }, 2000)) {
        fail("playback did not start for live timeline replacement");
    } else {
        const auto beforeUpdate = engine.playheadSamples();
        QElapsedTimer updateTimer;
        updateTimer.start();
        engine.updateTimeline(liveReplacement);
        timeline = std::move(liveReplacement);
        const auto updateNs = updateTimer.nsecsElapsed();
        if (updateNs > 20'000'000)
            fail("timeline replacement blocked instead of publishing to the audio thread");
        if (!waitFor([&] {
                return engine.timeline() == timeline.get() &&
                       engine.playheadSamples() > beforeUpdate;
            }, 2000)) {
            fail("live timeline replacement did not adopt its data source");
        }
    }
    engine.stop();
    if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
        fail("stop after live timeline replacement did not reset");
    // A timeline rebuild is only a data-source swap. It must not release
    // hardware voices already sounding, including the PSG channel used here,
    // nor a PSG note being previewed during a note-drag interaction.
    const auto cgbSmf = buildNoteSong(2);
    auto cgbTimeline =
        std::shared_ptr<MidiTimeline>(MidiTimeline::build(cgbSmf, engine.sampleRate()));
    const auto activeCgb = [&] { return engine.activeCgbChannels(); };
    if (!cgbTimeline || cgbTimeline->usedTrackCount != 1) {
        fail("CGB note song built wrong");
    } else {
        engine.loadSong(cgbTimeline, &tvg.vg, SongSettings{});
        engine.play();
        if (!waitFor([&] { return activeCgb() >= 1; }, 2000)) {
            fail("CGB song note never sounded before timeline replacement");
        } else {
            auto cgbReplacementSmf = cgbSmf;
            cgbReplacementSmf.tracks[1].events.insert(
                cgbReplacementSmf.tracks[1].events.begin() + 1,
                channelEvent(0, 0xB0, 0x78, 0));
            cgbReplacementSmf.tracks[1].events[3].tick = 4700;
            auto cgbReplacement = std::shared_ptr<MidiTimeline>(
                MidiTimeline::build(cgbReplacementSmf, engine.sampleRate()));
            if (!cgbReplacement) {
                fail("CGB replacement timeline built wrong");
            } else {
                engine.updateTimeline(cgbReplacement);
                cgbTimeline = std::move(cgbReplacement);
                if (!waitFor([&] {
                        return engine.timeline() == cgbTimeline.get();
                    }, 2000)) {
                    fail("CGB timeline replacement retained the old data source");
                } else if (activeCgb() < 1) {
                    fail("timeline replacement released a sounding CGB song note");
                }
            }
        }
        engine.stop();
        if (!waitFor([&] { return engine.playheadSamples() == 0; }, 2000))
            fail("stop after CGB timeline replacement did not reset");
        engine.previewNote(0, 60, 127);
        if (!waitFor([&] { return activeCgb() >= 1; }, 2000)) {
            fail("CGB preview never sounded before timeline replacement");
        } else {
            auto previewReplacementSmf = cgbSmf;
            previewReplacementSmf.tracks[1].events.insert(
                previewReplacementSmf.tracks[1].events.begin() + 1,
                channelEvent(0, 0xB0, 0x78, 0));
            previewReplacementSmf.tracks[1].events[3].tick = 4600;
            auto previewReplacement = std::shared_ptr<MidiTimeline>(
                MidiTimeline::build(previewReplacementSmf, engine.sampleRate()));
            if (!previewReplacement) {
                fail("CGB preview replacement timeline built wrong");
            } else {
                engine.updateTimeline(previewReplacement);
                cgbTimeline = std::move(previewReplacement);
                if (!waitFor([&] {
                        return engine.timeline() == cgbTimeline.get();
                    }, 2000)) {
                    fail("CGB preview replacement retained the old data source");
                } else if (activeCgb() < 1) {
                    fail("timeline replacement released a CGB note preview");
                }
                engine.previewNote(0, 60, 0);
            }
        }
    }
    engine.loadSong(timeline, &tvg.vg, SongSettings{});
    // A short audition whose note-off has already gone out, leaving a
    // ringing slow-release tail — the reported symptom. Fails the whole
    // check if the preview never sounds or the tail dies early (the
    // control expectation changed).
    const auto ringingTail = [&](uint8_t track) {
        engine.previewNoteTimed(track, 60, 127, uint32_t(0.15 * engine.sampleRate()));
        if (!waitFor([&] { return active() >= 1; }, 2000)) {
            fail("timed preview never sounded");
            return false;
        }
        QThread::msleep(400); // note-off sent; the slow release rings on
        if (active() < 1) {
            fail("slow-release tail died early (control expectation changed?)");
            return false;
        }
        return true;
    };
    // Stopped → Playing: the ringing tail must be cut when playback starts.
    if (ringingTail(0)) {
        engine.play();
        if (!waitFor([&] { return active() == 0; }, 2000))
            fail("audition tail persisted after playback started from stop");
    }
    // Playing → Paused: pausing silences like Stop — a preview sounding
    // when pause hits must not ring through it.
    engine.previewNoteTimed(0, 60, 127, uint32_t(60.0 * engine.sampleRate()));
    if (!waitFor([&] { return active() >= 1; }, 2000)) {
        fail("timed preview during playback never sounded");
    } else {
        engine.pause();
        if (!waitFor([&] { return active() == 0; }, 2000))
            fail("pause left the preview ringing");
    }
    // Paused → Playing, the Space path (pause, audition, seek + play):
    // Space toggles pause and restarts from the edit cursor, so this is how
    // playback usually starts — the tail must be cut here too.
    QThread::msleep(300); // the pause transition drains the preview ring
    if (ringingTail(0)) {
        engine.seek(0);
        engine.play();
        if (!waitFor([&] { return active() == 0; }, 2000))
            fail("audition tail persisted after Space-style seek + play from pause");
    }
    // Paused → Playing with the preview still counting down: resuming must
    // cut it rather than let it sound over the song for the full duration.
    engine.pause();
    QThread::msleep(300); // the pause transition drains the preview ring
    engine.previewNoteTimed(1, 64, 127, uint32_t(60.0 * engine.sampleRate()));
    if (!waitFor([&] { return active() >= 1; }, 2000)) {
        fail("timed preview during pause never sounded");
    } else {
        engine.play();
        if (!waitFor([&] { return active() == 0; }, 2000))
            fail("counting-down preview persisted after resuming playback");
    }
    engine.stop();
    engine.unloadSong();
    // Unload with the song still playing — the song-switch path. unloadSong
    // assigns both transport fields itself, so the callback never sees a
    // Playing→Stopped transition and cutAllSound never runs there; the cut
    // must happen inside unloadSong. MainWindow::loadSong frees the outgoing
    // voicegroup right after unloadSong returns, so freeAll + the sleep below
    // give ASAN a window to catch any channel still rendering it.
    const auto noteSmf = buildNoteSong();
    auto noteTimeline =
        std::shared_ptr<MidiTimeline>(MidiTimeline::build(noteSmf, engine.sampleRate()));
    HeapVoicegroup hvg;
    if (!noteTimeline || noteTimeline->usedTrackCount != 1) {
        fail("note song built wrong");
    } else {
        engine.loadSong(noteTimeline, hvg.vg, SongSettings{});
        engine.play();
        if (!waitFor([&] { return active() >= 1; }, 2000)) {
            fail("song note never sounded before unload");
            engine.unloadSong();
        } else {
            engine.unloadSong();
            if (!waitFor([&] { return active() == 0; }, 2000))
                fail("unloadSong left song channels sounding — they outlive "
                     "the voicegroup the switch path frees");
        }
    }
    hvg.freeAll();
    // The device keeps calling back; a channel that survived the unload now
    // reads the freed WaveData (ASAN reports it even when the count above
    // somehow reached zero).
    QThread::msleep(300);
    if (failures == 0)
        std::printf("transportcheck: PASS\n");
    return failures ? 1 : 0;
}
