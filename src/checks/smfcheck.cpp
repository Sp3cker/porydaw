#include <QByteArray>
#include <QElapsedTimer>
#include <QString>
#include <QTemporaryDir>
#include <cstdint>
#include <cstdio>

#include "checks/smfcheckfixtures.h"
#include "core/smf.h"
#include "core/songdocument.h"

extern "C" {
#include "m4a_engine.h"
}

namespace {

void appendU32(QByteArray &out, uint32_t v)
{
    out.append(char(v >> 24));
    out.append(char(v >> 16));
    out.append(char(v >> 8));
    out.append(char(v));
}

void appendU16(QByteArray &out, uint16_t v)
{
    out.append(char(v >> 8));
    out.append(char(v));
}

// A format-0 container for parser cases that SmfFile::write cannot produce.
QByteArray smfBytes(const QByteArray &trackBody)
{
    QByteArray out("MThd");
    appendU32(out, 6);
    appendU16(out, 0);
    appendU16(out, 1);
    appendU16(out, 24);
    out.append("MTrk");
    appendU32(out, uint32_t(trackBody.size()));
    out.append(trackBody);
    return out;
}

int checkEvent(const std::vector<SmfEvent> &events, size_t n, uint8_t status, uint8_t data0,
               uint8_t data1)
{
    if (n >= events.size()) {
        std::fprintf(stderr, "smfcheck: FAIL: event %zu missing\n", n);
        return 1;
    }
    const SmfEvent &event = events[n];
    if (event.status != status || event.data0 != data0 || event.data1 != data1) {
        std::fprintf(stderr, "smfcheck: FAIL: event %zu = %02x %02x %02x, want %02x %02x %02x\n", n,
                     event.status, event.data0, event.data1, status, data0, data1);
        return 1;
    }
    return 0;
}

SmfEvent channelEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

} // namespace

int runSmfCheck()
{
    int failures = 0;
    {
        SmfFile smf;
        QString error;
        const QByteArray body = QByteArray::fromHex("00903c4010803c4000c07f00ff2f00");
        if (!SmfFile::read(smfBytes(body), &smf, &error)) {
            std::fprintf(stderr, "smfcheck: FAIL: valid file rejected: %s\n",
                         qUtf8Printable(error));
            ++failures;
        }
    }

    // Channel-event data values are preserved even where MIDI data bytes have
    // bit 7 set, so an importer cannot lose stream alignment.
    {
        SmfFile smf;
        QString error;
        const QByteArray body = QByteArray::fromHex("00c08000903c4000b00780000a4000ff2f00");
        if (!SmfFile::read(smfBytes(body), &smf, &error)) {
            std::fprintf(stderr, "smfcheck: FAIL: high data bytes rejected: %s\n",
                         qUtf8Printable(error));
            ++failures;
        } else {
            const std::vector<SmfEvent> &events = smf.tracks[1].events;
            if (events.size() != 4) {
                std::fprintf(stderr, "smfcheck: FAIL: %zu events, want 4\n", events.size());
                ++failures;
            }
            failures += checkEvent(events, 0, 0xC0, 0x80, 0);
            failures += checkEvent(events, 1, 0x90, 0x3C, 0x40);
            failures += checkEvent(events, 2, 0xB0, 0x07, 0x80);
            failures += checkEvent(events, 3, 0xB0, 0x0A, 0x40);
        }
    }

    QTemporaryDir dir;
    if (!dir.isValid()) {
        std::fprintf(stderr, "smfcheck: FAIL: no temp dir\n");
        std::printf("smfcheck: FAIL\n");
        return 1;
    }
    failures += runSmfFixtureChecks(dir);

    // Shared ends, velocity-zero note ends, mixed channels, unterminated
    // notes, and raw 8-bit key equality keep the linear pairing rule honest.
    {
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        smf.tracks.resize(2);
        smf.tracks[0].endTick = 40;
        SmfTrack &track = smf.tracks[1];
        track.events.push_back(channelEvent(0, 0x90, 60, 100));
        track.events.push_back(channelEvent(0, 0x90, 62, 80));
        track.events.push_back(channelEvent(0, 0x91, 60, 70));
        track.events.push_back(channelEvent(5, 0x90, 62, 0));
        track.events.push_back(channelEvent(7, 0x81, 60, 0));
        track.events.push_back(channelEvent(10, 0x90, 60, 90));
        track.events.push_back(channelEvent(20, 0x80, 60, 0));
        track.events.push_back(channelEvent(30, 0x90, 64, 50));
        track.events.push_back(channelEvent(31, 0x90, 0x83, 60));
        track.events.push_back(channelEvent(33, 0x80, 0x03, 0));
        track.events.push_back(channelEvent(39, 0x80, 0x83, 0));
        track.endTick = 40;

        SongDocument doc;
        QString error;
        if (!SmfCheck::loadDocument(smf, dir, "pairing", &doc, &error)) {
            std::fprintf(stderr, "smfcheck: FAIL: pairing song load: %s\n", qUtf8Printable(error));
            ++failures;
        } else {
            const std::vector<DocNote> notes =
                doc.notesForTrack(SmfCheck::engineTrackForChunk(doc, 1));
            if (notes.size() != 5) {
                std::fprintf(stderr, "smfcheck: FAIL: %zu notes, want 5\n", notes.size());
                ++failures;
            }
            failures += SmfCheck::checkNote(notes, 0, 0, 6, 20, 60, 100, 0);
            failures += SmfCheck::checkNote(notes, 1, 1, 3, 5, 62, 80, 0);
            failures += SmfCheck::checkNote(notes, 2, 5, 6, 10, 60, 90, 0);
            failures += SmfCheck::checkNote(notes, 3, 7, SIZE_MAX, 0, 64, 50, 0);
            failures += SmfCheck::checkNote(notes, 4, 8, 10, 8, 0x83, 60, 0);
        }
    }

    // The hostile shape from the security report: pairing must stay linear.
    {
        constexpr int kNoteOns = 300000;
        SmfFile smf;
        smf.format = 1;
        smf.division = 24;
        smf.tracks.resize(2);
        smf.tracks[0].endTick = kNoteOns;
        SmfTrack &track = smf.tracks[1];
        track.events.reserve(kNoteOns);
        for (int i = 0; i < kNoteOns; ++i)
            track.events.push_back(channelEvent(uint64_t(i), 0x90, 60, 100));
        track.endTick = kNoteOns;

        SongDocument doc;
        QString error;
        if (!SmfCheck::loadDocument(smf, dir, "unterminated", &doc, &error)) {
            std::fprintf(stderr, "smfcheck: FAIL: unterminated song load: %s\n",
                         qUtf8Printable(error));
            ++failures;
        } else {
            QElapsedTimer timer;
            timer.start();
            const std::vector<DocNote> notes =
                doc.notesForTrack(SmfCheck::engineTrackForChunk(doc, 1));
            const qint64 ms = timer.elapsed();
            if (notes.size() != kNoteOns) {
                std::fprintf(stderr, "smfcheck: FAIL: %zu notes, want %d\n", notes.size(),
                             kNoteOns);
                ++failures;
            } else if (!notes.front().unterminated() || !notes.back().unterminated()) {
                std::fprintf(stderr, "smfcheck: FAIL: unterminated note gained an end\n");
                ++failures;
            }
            if (ms > 10000) {
                std::fprintf(stderr,
                             "smfcheck: FAIL: pairing %d unterminated note-ons took %lld ms\n",
                             kNoteOns, static_cast<long long>(ms));
                ++failures;
            }
        }
    }

    // Out-of-range program/key values must be ignored at the engine boundary.
    {
        static ToneData voices[128];
        static ToneData sub[128];
        static uint8_t splitTable[128];
        voices[5].type = VOICE_KEYSPLIT;
        voices[5].subGroup = sub;
        voices[5].keySplitTable = splitTable;

        M4AEngine engine;
        m4a_engine_init(&engine, 48000.0f);
        m4a_engine_set_voicegroup(&engine, voices);
        m4a_engine_program_change(&engine, 0, 5);
        if (engine.tracks[0].currentProgram != 5) {
            std::fprintf(stderr, "smfcheck: FAIL: in-range program change ignored\n");
            ++failures;
        }
        m4a_engine_program_change(&engine, 0, 128);
        m4a_engine_program_change(&engine, 0, 255);
        if (engine.tracks[0].currentProgram != 5) {
            std::fprintf(stderr, "smfcheck: FAIL: out-of-range program %u applied\n",
                         engine.tracks[0].currentProgram);
            ++failures;
        }

        m4a_engine_note_on(&engine, 0, 128, 100);
        m4a_engine_note_on(&engine, 0, 255, 100);
        m4a_engine_note_off(&engine, 0, 255);
        for (int i = 0; i < TOTAL_PCM_CHANNELS; ++i) {
            if (engine.pcmChannels[i].status & CHN_ON) {
                std::fprintf(stderr, "smfcheck: FAIL: out-of-range key started a channel\n");
                ++failures;
                break;
            }
        }
        m4a_engine_destroy(&engine);
    }

    std::printf("smfcheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
