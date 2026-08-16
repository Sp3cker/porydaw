#include <QDir>
#include <QTemporaryFile>
#include <cstdio>

#include "core/miditimeline.h"
#include "core/smf.h"

// --check-note-identity <scratch-project>: make sure transient NoteId values
// give duplicate note-on records different IDs in one document, survive timeline
// projection, and stay out of parsed or serialized MIDI data.
int runNoteIdentityCheck(const QString &scratchProject)
{
    auto failures = 0;
    const auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "noteidcheck: FAIL: %s\n", what);
        failures++;
    };
    const auto scratch = QDir{scratchProject};
    if (!scratch.exists()) {
        std::fprintf(stderr, "noteidcheck: scratch project not found: %s\n",
                     qUtf8Printable(scratchProject));
        return 1;
    }
    auto source = SmfFile{};
    source.tracks.resize(1);
    auto &track = source.tracks[0];
    auto noteOn = SmfEvent{};
    noteOn.tick = 24;
    noteOn.status = 0x90;
    noteOn.data0 = 60;
    noteOn.data1 = 100;
    auto noteOff = noteOn;
    noteOff.tick = 48;
    noteOff.status = 0x80;
    noteOff.data1 = 0;
    track.events.push_back(noteOn);
    track.events.push_back(noteOn);
    track.events.push_back(noteOff);
    track.endTick = 72;
    auto input = QTemporaryFile{scratch.filePath(QStringLiteral("noteidcheck-XXXXXX.mid"))};
    if (!input.open()) {
        std::fprintf(stderr, "noteidcheck: cannot create input: %s\n",
                     qUtf8Printable(input.errorString()));
        return 1;
    }
    const auto bytes = source.write();
    if (input.write(bytes) != bytes.size()) {
        std::fprintf(stderr, "noteidcheck: cannot write input: %s\n",
                     qUtf8Printable(input.errorString()));
        return 1;
    }
    input.close();
    auto smf = SmfFile{};
    auto error = QString{};
    if (!SmfFile::readFile(input.fileName(), &smf, &error)) {
        std::fprintf(stderr, "noteidcheck: parse: %s\n", qUtf8Printable(error));
        return 1;
    }
    if (smf.tracks.size() != 1 || smf.tracks[0].events.size() != 3) {
        fail("parsed input lost duplicate note-on slots");
        return failures;
    }
    // MIDI parsing does not give document-local identities.
    const auto baseline = smf.write();
    const auto &firstNoteOn = smf.tracks[0].events[0];
    const auto &secondNoteOn = smf.tracks[0].events[1];
    const auto &ordinaryEvent = smf.tracks[0].events[2];
    if (!firstNoteOn.isNoteOn() || !secondNoteOn.isNoteOn() || !ordinaryEvent.isNoteEnd()) {
        fail("parsed input has the wrong note event kinds");
        return failures;
    }
    if (firstNoteOn.noteId.isAssigned() || secondNoteOn.noteId.isAssigned() ||
        ordinaryEvent.noteId.isAssigned()) {
        fail("parsed MIDI event unexpectedly has an assigned identity");
        return failures;
    }
    // MIDI input must not give records document-local IDs.
    const auto plainTimeline = MidiTimeline::load(input.fileName(), 48000.0, &error);
    if (!plainTimeline) {
        std::fprintf(stderr, "noteidcheck: timeline load: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto plainNoteOns = 0;
    auto plainOrdinaryIsUnassigned = false;
    for (const auto &event : plainTimeline->events) {
        if (event.track == 0 && event.tick == 24 && event.type == 0x9) {
            plainNoteOns++;
            if (event.noteId.isAssigned())
                fail("loaded note-on unexpectedly has an assigned identity");
        }
        if (event.track == 0 && event.tick == 48 && event.type == 0x8)
            plainOrdinaryIsUnassigned = !event.noteId.isAssigned();
    }
    if (plainNoteOns != 2)
        fail("loaded timeline lost duplicate note-on slots");
    if (!plainOrdinaryIsUnassigned)
        fail("ordinary timeline event has an assigned identity");
    // In one document, duplicate note-on records must have different IDs when their MIDI fields are equal.
    const auto firstId = NoteId{1};
    const auto secondId = NoteId{2};
    if (!firstId.isAssigned() || !secondId.isAssigned() || firstId == secondId) {
        fail("assigned note identities are not distinct");
        return failures;
    }
    smf.tracks[0].events[0].noteId = firstId;
    smf.tracks[0].events[1].noteId = secondId;
    if (!(smf.tracks[0].events[0] == smf.tracks[0].events[1]))
        fail("SMF equality includes transient identity");
    if (smf.write() != baseline)
        fail("SMF serialization includes transient identity");
    // Timeline projection must keep document-local IDs on note-on records and give no IDs to other records.
    const auto timeline = MidiTimeline::build(smf, 48000.0);
    if (!timeline) {
        fail("timeline build failed");
        return failures;
    }
    auto transportedNoteOns = 0;
    auto sawFirstId = false;
    auto sawSecondId = false;
    auto ordinaryIsUnassigned = false;
    for (const auto &event : timeline->events) {
        if (event.track == 0 && event.tick == 24 && event.type == 0x9) {
            transportedNoteOns++;
            if (event.noteId == firstId)
                sawFirstId = true;
            else if (event.noteId == secondId)
                sawSecondId = true;
            else
                fail("timeline changed a note-on identity");
        }
        if (event.track == 0 && event.tick == 48 && event.type == 0x8)
            ordinaryIsUnassigned = !event.noteId.isAssigned();
    }
    if (transportedNoteOns != 2 || !sawFirstId || !sawSecondId)
        fail("timeline did not preserve each duplicate note-on identity");
    if (!ordinaryIsUnassigned)
        fail("timeline assigned an ordinary event identity");
    return failures == 0 ? 0 : 1;
}
