#include <QDir>
#include <QTemporaryFile>
#include <cstdio>

#include "core/miditimeline.h"
#include "core/smf.h"

// --noteidcheck <scratch-dir>: NoteId boundary check. NoteIds are transient
// document identities: nothing below the document layer may create one, and
// none may leak into MIDI bytes. Proves the parse layer leaves duplicate
// note-on records unassigned, that identity never changes SMF equality or
// serialization, and that MidiTimeline::build carries assigned ids through
// to note-on events (and only those). SongDocument's own minting rules are
// editcheck's territory.
int runNoteIdCheck(const QString &scratchDir)
{
    int failures = 0;
    auto fail = [&failures](const char *what) {
        std::fprintf(stderr, "noteidcheck: FAIL: %s\n", what);
        failures++;
    };
    const QDir scratch(scratchDir);
    if (!scratch.exists()) {
        std::fprintf(stderr, "noteidcheck: scratch dir not found: %s\n",
                     qUtf8Printable(scratchDir));
        return 1;
    }

    // Two byte-identical note-ons sharing one end — the exact case identity
    // exists for — plus a real note-off.
    SmfFile source;
    source.tracks.resize(1);
    SmfTrack &track = source.tracks[0];
    SmfEvent noteOn;
    noteOn.tick = 24;
    noteOn.status = 0x90;
    noteOn.data0 = 60;
    noteOn.data1 = 100;
    SmfEvent noteOff = noteOn;
    noteOff.tick = 48;
    noteOff.status = 0x80;
    noteOff.data1 = 0;
    track.events.push_back(noteOn);
    track.events.push_back(noteOn);
    track.events.push_back(noteOff);
    track.endTick = 72;

    QTemporaryFile input(scratch.filePath(QStringLiteral("noteidcheck-XXXXXX.mid")));
    if (!input.open()) {
        std::fprintf(stderr, "noteidcheck: cannot create input: %s\n",
                     qUtf8Printable(input.errorString()));
        return 1;
    }
    const QByteArray bytes = source.write();
    if (input.write(bytes) != bytes.size()) {
        std::fprintf(stderr, "noteidcheck: cannot write input: %s\n",
                     qUtf8Printable(input.errorString()));
        return 1;
    }
    input.close();

    SmfFile smf;
    QString error;
    if (!SmfFile::readFile(input.fileName(), &smf, &error)) {
        std::fprintf(stderr, "noteidcheck: parse: %s\n", qUtf8Printable(error));
        return 1;
    }
    if (smf.tracks.size() != 1 || smf.tracks[0].events.size() != 3) {
        fail("parsed input lost the duplicate note-on records");
        return 1;
    }
    const QByteArray baseline = smf.write();
    if (smf.tracks[0].events[0].noteId.isAssigned() ||
        smf.tracks[0].events[1].noteId.isAssigned() || smf.tracks[0].events[2].noteId.isAssigned())
        fail("the parse layer assigned a note identity (documents mint them)");

    // A timeline loaded straight from the file (no document) stays
    // unassigned too.
    const auto plain = MidiTimeline::load(input.fileName(), 48000.0, &error);
    if (!plain) {
        std::fprintf(stderr, "noteidcheck: timeline load: %s\n", qUtf8Printable(error));
        return 1;
    }
    int plainNoteOns = 0;
    for (const TimelineEvent &ev : plain->events) {
        if (ev.noteId.isAssigned())
            fail("a document-free timeline event has an assigned identity");
        if (ev.track == 0 && ev.tick == 24 && ev.type == 0x9)
            plainNoteOns++;
    }
    if (plainNoteOns != 2)
        fail("the timeline lost a duplicate note-on record");

    // Assign distinct ids by hand (standing in for the document): equality
    // and the writer must not see them.
    const NoteId firstId{1};
    const NoteId secondId{2};
    if (!firstId.isAssigned() || firstId == secondId)
        fail("hand-assigned note identities are not distinct");
    smf.tracks[0].events[0].noteId = firstId;
    smf.tracks[0].events[1].noteId = secondId;
    // An id smuggled onto a non-note-on must not survive the projection.
    smf.tracks[0].events[2].noteId = NoteId{3};
    if (!(smf.tracks[0].events[0] == smf.tracks[0].events[1]))
        fail("SmfEvent equality includes the transient identity");
    if (smf.write() != baseline)
        fail("SMF serialization includes the transient identity");

    // The timeline projection carries each note-on's id through unchanged
    // and gives none to other events.
    const auto timeline = MidiTimeline::build(smf, 48000.0);
    if (!timeline) {
        fail("timeline build failed");
        return 1;
    }
    int noteOns = 0;
    bool sawFirst = false, sawSecond = false;
    for (const TimelineEvent &ev : timeline->events) {
        if (ev.track == 0 && ev.tick == 24 && ev.type == 0x9) {
            noteOns++;
            if (ev.noteId == firstId)
                sawFirst = true;
            else if (ev.noteId == secondId)
                sawSecond = true;
            else
                fail("the timeline changed a note-on's identity");
        } else if (ev.noteId.isAssigned()) {
            fail("the timeline assigned an identity to a non-note-on event");
        }
    }
    if (noteOns != 2 || !sawFirst || !sawSecond)
        fail("the timeline did not preserve each duplicate note-on's identity");

    std::printf("noteidcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
