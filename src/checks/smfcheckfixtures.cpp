#include "checks/smfcheckfixtures.h"

#include <QByteArray>
#include <QString>
#include <QTemporaryDir>

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "core/smf.h"
#include "core/songdocument.h"

namespace SmfCheck {

bool loadDocument(const SmfFile &smf, const QTemporaryDir &dir, const char *name, SongDocument *doc,
                  QString *error)
{
    SongInfo song;
    song.label = QString::fromLatin1(name);
    song.midPath = dir.filePath(QString::fromLatin1(name) + QStringLiteral(".mid"));
    song.hasMid = true;
    return smf.writeFile(song.midPath, error) && doc->load(song, error);
}

int engineTrackForChunk(const SongDocument &doc, int chunk)
{
    for (int track = 0; track < doc.engineTrackCount(); ++track) {
        if (doc.smfTrackFor(track) == chunk)
            return track;
    }
    return -1;
}

int checkNote(const std::vector<DocNote> &notes, size_t n, size_t onIndex, size_t endIndex,
              uint32_t duration, uint8_t key, uint8_t velocity, uint8_t channel)
{
    if (n >= notes.size()) {
        std::fprintf(stderr, "smfcheck: FAIL: note %zu missing\n", n);
        return 1;
    }
    const DocNote &note = notes[n];
    if (note.onIndex != onIndex || note.endIndex != endIndex || note.duration != duration ||
        note.key != key || note.velocity != velocity || note.channel != channel) {
        std::fprintf(stderr,
                     "smfcheck: FAIL: note %zu = on %zu end %zu dur %u key %u vel %u ch %u, "
                     "want on %zu end %zu dur %u key %u vel %u ch %u\n",
                     n, note.onIndex, note.endIndex, note.duration, note.key, note.velocity,
                     note.channel, onIndex, endIndex, duration, key, velocity, channel);
        return 1;
    }
    return 0;
}

} // namespace SmfCheck

namespace {

bool require(bool condition, int *failures, const char *fixture, const char *property)
{
    if (condition)
        return true;
    std::fprintf(stderr, "smfcheck: FAIL: fixture %s: %s\n", fixture, property);
    ++*failures;
    return false;
}

bool loadFixture(const char *fixture, SmfFile *smf)
{
    QString error;
    const QString path = QStringLiteral(":/checks/test_midis/smf/") + QString::fromLatin1(fixture);
    if (SmfFile::readFile(path, smf, &error))
        return true;
    std::fprintf(stderr, "smfcheck: FAIL: fixture %s: %s\n", fixture, qUtf8Printable(error));
    return false;
}

bool sameSmf(const SmfFile &a, const SmfFile &b)
{
    if (a.format != b.format || a.division != b.division || a.tracks.size() != b.tracks.size())
        return false;
    for (size_t i = 0; i < a.tracks.size(); ++i) {
        if (a.tracks[i].endTick != b.tracks[i].endTick || a.tracks[i].events != b.tracks[i].events)
            return false;
    }
    return true;
}

void checkSemanticReparse(const char *fixture, const SmfFile &smf, int *failures)
{
    SmfFile reread;
    QString error;
    if (!SmfFile::read(smf.write(), &reread, &error)) {
        std::fprintf(stderr, "smfcheck: FAIL: fixture %s: write/re-read: %s\n", fixture,
                     qUtf8Printable(error));
        ++*failures;
        return;
    }
    require(sameSmf(smf, reread), failures, fixture, "semantic write/re-read mismatch");
}

bool isEvent(const SmfEvent &event, uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    return event.tick == tick && event.status == status && event.data0 == data0 &&
           event.data1 == data1;
}

bool checkStressValue(const char *fixture, int track, int group, const char *eventName,
                      const char *field, uint64_t actual, uint64_t expected, int *failures)
{
    if (actual == expected)
        return true;
    std::fprintf(
        stderr,
        "smfcheck: FAIL: fixture %s: track %d, group %d, property %s.%s = %llu, want %llu\n",
        fixture, track, group, eventName, field, static_cast<unsigned long long>(actual),
        static_cast<unsigned long long>(expected));
    ++*failures;
    return false;
}

bool checkStressEvent(const SmfTrack &track, size_t eventIndex, const char *fixture,
                      int trackNumber, int group, const char *eventName, uint64_t tick,
                      uint8_t status, uint8_t data0, uint8_t data1, bool isMeta, int *failures)
{
    if (eventIndex >= track.events.size()) {
        std::fprintf(
            stderr,
            "smfcheck: FAIL: fixture %s: track %d, group %d, property %s: event %zu missing\n",
            fixture, trackNumber, group, eventName, eventIndex);
        ++*failures;
        return false;
    }

    const SmfEvent &event = track.events[eventIndex];
    if (!isMeta) {
        if (event.tick == tick && event.status == status && event.data0 == data0 &&
            event.data1 == data1) {
            return true;
        }
        const bool isPitchBend = (status & 0xF0) == 0xE0;
        const char *data0Name = isPitchBend ? "lsb" : "controller";
        const char *data1Name = isPitchBend ? "msb" : "value";
        std::fprintf(stderr,
                     "smfcheck: FAIL: fixture %s: track %d, group %d, property %s: actual tick "
                     "%llu status %02x %s %u %s %u; expected tick %llu status %02x %s %u %s %u\n",
                     fixture, trackNumber, group, eventName,
                     static_cast<unsigned long long>(event.tick), event.status, data0Name,
                     event.data0, data1Name, event.data1, static_cast<unsigned long long>(tick),
                     status, data0Name, data0, data1Name, data1);
        ++*failures;
        return false;
    }

    return checkStressValue(fixture, trackNumber, group, eventName, "tick", event.tick, tick,
                            failures) &&
           checkStressValue(fixture, trackNumber, group, eventName, "status", event.status, status,
                            failures) &&
           checkStressValue(fixture, trackNumber, group, eventName, "meta-type", event.metaType,
                            data0, failures);
}

bool checkStressTrackShape(const SmfTrack &track, const char *fixture, int trackNumber, int group,
                           size_t eventCount, uint64_t endTick, int *failures)
{
    return checkStressValue(fixture, trackNumber, group, "event stream", "count",
                            track.events.size(), eventCount, failures) &&
           checkStressValue(fixture, trackNumber, group, "EOT", "tick", track.endTick, endTick,
                            failures);
}

void checkOpaqueSysExFixture(int *failures)
{
    constexpr auto fixture = "valid/opaque_sysex.mid";
    SmfFile smf;
    if (!loadFixture(fixture, &smf)) {
        ++*failures;
        return;
    }

    require(smf.format == 1 && smf.division == 48 && smf.tracks.size() == 2, failures, fixture,
            "expected format-1, 48-PPQN, two-track file");
    if (smf.tracks.size() == 2) {
        const SmfTrack &conductor = smf.tracks[0];
        const SmfTrack &notes = smf.tracks[1];
        require(conductor.endTick == 0 && conductor.events.size() == 4 && notes.endTick == 24 &&
                    notes.events.size() == 2,
                failures, fixture, "unexpected event or end-tick count");
        if (conductor.events.size() == 4) {
            require(conductor.events[1].status == 0xF0 &&
                        conductor.events[1].blob == QByteArray::fromHex("7e7f0903f7") &&
                        conductor.events[2].status == 0xFF &&
                        conductor.events[2].metaType == 0x7F &&
                        conductor.events[2].blob == QByteArray::fromHex("deadbeef") &&
                        conductor.events[3].status == 0xF7 &&
                        conductor.events[3].blob == QByteArray::fromHex("4312f7"),
                    failures, fixture, "opaque F0/F7/FF7F order or payload changed");
        }
        if (notes.events.size() == 2) {
            require(isEvent(notes.events[0], 0, 0x90, 0x3c, 0x40) &&
                        isEvent(notes.events[1], 24, 0x90, 0x3c, 0),
                    failures, fixture, "channel event ordering changed");
        }
    }
    checkSemanticReparse(fixture, smf, failures);
}

void checkVlqRunningStatusFixture(int *failures)
{
    constexpr auto fixture = "valid/vlq_running_status.mid";
    SmfFile smf;
    if (!loadFixture(fixture, &smf)) {
        ++*failures;
        return;
    }

    require(smf.format == 1 && smf.division == 96 && smf.tracks.size() == 2, failures, fixture,
            "expected format-1, 96-PPQN, two-track file");
    if (smf.tracks.size() == 2) {
        const SmfTrack &track = smf.tracks[1];
        require(track.endTick == 24835 && track.events.size() == 12, failures, fixture,
                "unexpected RPN track length");
        if (track.events.size() == 12) {
            require(isEvent(track.events[0], 0, 0xB0, 0x65, 0) &&
                        isEvent(track.events[1], 0, 0xB0, 0x64, 1) &&
                        isEvent(track.events[2], 0, 0xB0, 0x06, 2) &&
                        isEvent(track.events[3], 0, 0xB0, 0x26, 0) &&
                        isEvent(track.events[4], 24611, 0xC0, 5, 0) &&
                        isEvent(track.events[5], 24611, 0xC0, 6, 0) &&
                        track.events[6].tick == 24611 && track.events[6].status == 0xFF &&
                        track.events[6].metaType == 1 && track.events[6].blob == "X" &&
                        isEvent(track.events[7], 24611, 0xC0, 7, 0) &&
                        isEvent(track.events[8], 24739, 0x90, 0x3c, 0x64) &&
                        isEvent(track.events[9], 24739, 0x90, 0x3e, 0x50) &&
                        isEvent(track.events[10], 24835, 0x80, 0x3c, 0) &&
                        isEvent(track.events[11], 24835, 0x80, 0x3e, 0),
                    failures, fixture,
                    "VLQ tick, RPN running status, or post-meta status reset changed");
        }
    }
    checkSemanticReparse(fixture, smf, failures);
}

void checkNoteLifecycleFixture(const QTemporaryDir &dir, int *failures)
{
    constexpr auto fixture = "valid/note_lifecycle.mid";
    SmfFile smf;
    if (!loadFixture(fixture, &smf)) {
        ++*failures;
        return;
    }

    require(smf.format == 1 && smf.division == 24 && smf.tracks.size() == 2, failures, fixture,
            "expected format-1, 24-PPQN, two-track file");
    if (smf.tracks.size() == 2) {
        const SmfTrack &track = smf.tracks[1];
        require(track.endTick == 120 && track.events.size() == 10, failures, fixture,
                "unexpected note lifecycle track length");
        if (track.events.size() == 10) {
            require(isEvent(track.events[2], 0, 0x90, 0x3c, 0x64) &&
                        isEvent(track.events[3], 24, 0x90, 0x3c, 0) &&
                        isEvent(track.events[4], 24, 0x90, 0x3c, 0x6e) &&
                        isEvent(track.events[6], 72, 0x90, 0x3e, 0x50) &&
                        isEvent(track.events[7], 72, 0x80, 0x3e, 0) &&
                        isEvent(track.events[8], 96, 0x90, 0x40, 0x60) &&
                        isEvent(track.events[9], 120, 0x80, 0x40, 0),
                    failures, fixture, "velocity-zero status or same-tick note ordering changed");
        }

        SongDocument doc;
        QString error;
        if (!SmfCheck::loadDocument(smf, dir, "note_lifecycle", &doc, &error)) {
            std::fprintf(stderr, "smfcheck: FAIL: fixture %s: document load: %s\n", fixture,
                         qUtf8Printable(error));
            ++*failures;
        } else {
            const int engineTrack = SmfCheck::engineTrackForChunk(doc, 1);
            const std::vector<DocNote> notes = doc.notesForTrack(engineTrack);
            require(notes.size() == 4, failures, fixture, "note pairing count changed");
            if (notes.size() == 4) {
                *failures += SmfCheck::checkNote(notes, 0, 2, 3, 24, 0x3c, 0x64, 0);
                *failures += SmfCheck::checkNote(notes, 1, 4, 5, 24, 0x3c, 0x6e, 0);
                *failures += SmfCheck::checkNote(notes, 2, 6, 7, 0, 0x3e, 0x50, 0);
                *failures += SmfCheck::checkNote(notes, 3, 8, 9, 24, 0x40, 0x60, 0);
            }
        }
    }
    checkSemanticReparse(fixture, smf, failures);
}

void checkDuplicateEotFixture(int *failures)
{
    constexpr auto fixture = "malformed/duplicate_eot.mid";
    SmfFile smf;
    if (!loadFixture(fixture, &smf)) {
        ++*failures;
        return;
    }

    require(smf.format == 1 && smf.division == 24 && smf.tracks.size() == 1 &&
                smf.tracks[0].events.empty() && smf.tracks[0].endTick == 0,
            failures, fixture, "duplicate end-of-track was not accepted canonically");
    const QByteArray canonical =
        QByteArray::fromHex("4d546864000000060001000100184d54726b0000000400ff2f00");
    const QByteArray serialized = smf.write();
    require(serialized.size() == 26 && serialized == canonical, failures, fixture,
            "duplicate end-of-track did not serialize to the 26-byte canonical F1 file");
    checkSemanticReparse(fixture, smf, failures);
}

void checkAutomationStressFixture(int *failures)
{
    constexpr auto fixture = "stress/automation_burst.mid";
    SmfFile smf;
    if (!loadFixture(fixture, &smf)) {
        ++*failures;
        return;
    }

    if (smf.format != 1 || smf.division != 96 || smf.tracks.size() != 3) {
        require(false, failures, fixture, "expected format-1, 96-PPQN, three-track file");
    } else {
        constexpr int kGroupCount = 64;
        constexpr size_t kEventsPerGroup = 3;
        constexpr size_t kAutomationEventCount = size_t(kGroupCount) * kEventsPerGroup;
        constexpr size_t kEventTrackEventCount = 1 + kAutomationEventCount + 2;
        constexpr uint64_t kEndTick = 352;
        bool structureMatches = true;
        const SmfTrack &conductor = smf.tracks[0];
        if (!checkStressTrackShape(conductor, fixture, 0, 0, 2, kEndTick, failures)) {
            structureMatches = false;
        } else if (!checkStressEvent(conductor, 0, fixture, 0, 0, "tempo", 0, 0xFF, 0x51, 0, true,
                                     failures)) {
            structureMatches = false;
        } else if (!checkStressEvent(conductor, 1, fixture, 0, 0, "time signature", 0, 0xFF, 0x58,
                                     0, true, failures)) {
            structureMatches = false;
        }

        for (int channel = 0; channel < 2 && structureMatches; ++channel) {
            const int trackNumber = channel + 1;
            const SmfTrack &track = smf.tracks[size_t(trackNumber)];
            if (!checkStressEvent(track, 0, fixture, trackNumber, 0, "program", 0,
                                  uint8_t(0xC0 + channel), uint8_t(channel == 0 ? 5 : 40), 0, false,
                                  failures)) {
                structureMatches = false;
                break;
            }
            for (int group = 0; group < kGroupCount && structureMatches; ++group) {
                const size_t base = 1 + size_t(group) * kEventsPerGroup;
                const uint8_t ccStatus = uint8_t(0xB0 + channel);
                const uint8_t bendStatus = uint8_t(0xE0 + channel);
                const uint8_t cc0 = uint8_t(channel == 0 ? 7 : 1);
                const uint8_t value0 = uint8_t(channel == 0 ? 20 + group : (3 * group) & 0x7F);
                const uint8_t cc1 = uint8_t(channel == 0 ? 11 : 10);
                const uint8_t value1 = uint8_t(channel == 0 ? 0x7F - group : 40 + group);
                const uint8_t bend0 = uint8_t(channel == 0 ? group : (5 * group) & 0x7F);
                const uint8_t bend1 =
                    uint8_t(channel == 0 ? (2 * group) & 0x7F : (7 * group) & 0x7F);
                const uint64_t tick = uint64_t(4 * group);
                if (!checkStressEvent(track, base, fixture, trackNumber, group, "first CC", tick,
                                      ccStatus, cc0, value0, false, failures) ||
                    !checkStressEvent(track, base + 1, fixture, trackNumber, group, "second CC",
                                      tick, ccStatus, cc1, value1, false, failures) ||
                    !checkStressEvent(track, base + 2, fixture, trackNumber, group, "pitch bend",
                                      tick, bendStatus, bend0, bend1, false, failures)) {
                    structureMatches = false;
                }
            }
            if (!structureMatches)
                break;

            const size_t noteOn = 1 + kAutomationEventCount;
            const uint8_t note = uint8_t(channel == 0 ? 0x3C : 0x43);
            if (!checkStressEvent(track, noteOn, fixture, trackNumber, kGroupCount, "note-on", 256,
                                  uint8_t(0x90 + channel), note, 0x50, false, failures) ||
                !checkStressEvent(track, noteOn + 1, fixture, trackNumber, kGroupCount, "note-off",
                                  kEndTick, uint8_t(0x80 + channel), note, 0, false, failures)) {
                structureMatches = false;
                break;
            }
            if (!checkStressTrackShape(track, fixture, trackNumber, kGroupCount,
                                       kEventTrackEventCount, kEndTick, failures)) {
                structureMatches = false;
                break;
            }
        }
    }
    checkSemanticReparse(fixture, smf, failures);
}

} // namespace

int runSmfFixtureChecks(const QTemporaryDir &dir)
{
    int failures = 0;
    checkOpaqueSysExFixture(&failures);
    checkVlqRunningStatusFixture(&failures);
    checkNoteLifecycleFixture(dir, &failures);
    checkDuplicateEotFixture(&failures);
    checkAutomationStressFixture(&failures);
    return failures;
}
