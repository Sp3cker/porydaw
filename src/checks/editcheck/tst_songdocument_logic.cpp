#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include <QTemporaryDir>
#include <QTemporaryFile>

#include <array>
#include <cstring>

#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "porydaw_scale.h"

namespace {

struct ExpectedScale {
    porydaw_scale::ScaleId id;
    const char *name;
    uint16_t mask;
};

constexpr std::array<ExpectedScale, 28> expectedScales = {
    ExpectedScale{porydaw_scale::ScaleId::major, "Major", 0xAB5},
    {porydaw_scale::ScaleId::natural_minor, "Natural Minor", 0x5AD},
    {porydaw_scale::ScaleId::dorian, "Dorian", 0x6AD},
    {porydaw_scale::ScaleId::phrygian, "Phrygian", 0x5AB},
    {porydaw_scale::ScaleId::lydian, "Lydian", 0xAD5},
    {porydaw_scale::ScaleId::mixolydian, "Mixolydian", 0x6B5},
    {porydaw_scale::ScaleId::locrian, "Locrian", 0x56B},
    {porydaw_scale::ScaleId::harmonic_minor, "Harmonic Minor", 0x9AD},
    {porydaw_scale::ScaleId::melodic_minor, "Melodic Minor", 0xAAD},
    {porydaw_scale::ScaleId::harmonic_major, "Harmonic Major", 0x9B5},
    {porydaw_scale::ScaleId::major_pentatonic, "Major Pentatonic", 0x295},
    {porydaw_scale::ScaleId::minor_pentatonic, "Minor Pentatonic", 0x4A9},
    {porydaw_scale::ScaleId::minor_blues, "Minor Blues", 0x4E9},
    {porydaw_scale::ScaleId::whole_tone, "Whole Tone", 0x555},
    {porydaw_scale::ScaleId::half_whole_diminished, "Half-Whole Diminished", 0x6DB},
    {porydaw_scale::ScaleId::whole_half_diminished, "Whole-Half Diminished", 0xB6D},
    {porydaw_scale::ScaleId::dorian_sharp_4, "Dorian #4", 0x6CD},
    {porydaw_scale::ScaleId::phrygian_dominant, "Phrygian Dominant", 0x5B3},
    {porydaw_scale::ScaleId::lydian_augmented, "Lydian Augmented", 0xB55},
    {porydaw_scale::ScaleId::lydian_dominant, "Lydian Dominant", 0x6D5},
    {porydaw_scale::ScaleId::altered, "Altered (Super Locrian)", 0x55B},
    {porydaw_scale::ScaleId::eight_tone_spanish, "8-Tone Spanish", 0x57B},
    {porydaw_scale::ScaleId::bhairav, "Bhairav", 0x9B3},
    {porydaw_scale::ScaleId::hungarian_minor, "Hungarian Minor", 0x9CD},
    {porydaw_scale::ScaleId::hirajoshi, "Hirajoshi", 0x18D},
    {porydaw_scale::ScaleId::in_sen, "In-Sen", 0x4A3},
    {porydaw_scale::ScaleId::iwato, "Iwato", 0x463},
    {porydaw_scale::ScaleId::kumoi, "Kumoi", 0x28D},
};

SmfFile duplicateNoteFile()
{
    SmfFile source;
    source.tracks.resize(1);
    SmfTrack &track = source.tracks.front();
    SmfEvent noteOn;
    noteOn.tick = 24;
    noteOn.status = 0x90;
    noteOn.data0 = 60;
    noteOn.data1 = 100;
    SmfEvent noteOff = noteOn;
    noteOff.tick = 48;
    noteOff.status = 0x80;
    noteOff.data1 = 0;
    track.events = {noteOn, noteOn, noteOff};
    track.endTick = 72;
    return source;
}

} // namespace

void ScaleCheckTest::table_data()
{
    QTest::addColumn<int>("index");
    for (size_t index = 0; index < expectedScales.size(); ++index)
        QTest::newRow(expectedScales[index].name) << int(index);
}

void ScaleCheckTest::table()
{
    QFETCH(int, index);
    QCOMPARE(porydaw_scale::cScaleCount, int(expectedScales.size()));
    const porydaw_scale::ScaleId *const order = porydaw_scale::displayOrder();
    QVERIFY(order != nullptr);
    const ExpectedScale &expected = expectedScales[size_t(index)];
    QCOMPARE(static_cast<int>(expected.id), index);
    QCOMPARE(std::strcmp(porydaw_scale::scaleDisplayName(expected.id), expected.name), 0);
    QCOMPARE(porydaw_scale::scaleMask(expected.id), expected.mask);
    QCOMPARE(order[index], expected.id);
}

void ScaleCheckTest::rootsAndDefaults()
{
    constexpr std::array rootNames = {"C",  "C#", "D",  "D#", "E",  "F",
                                      "F#", "G",  "G#", "A",  "A#", "B"};
    QCOMPARE(porydaw_scale::cRootCount, int(rootNames.size()));
    for (int index = 0; index < porydaw_scale::cRootCount; ++index)
        QCOMPARE(std::strcmp(porydaw_scale::rootDisplayName(index), rootNames[size_t(index)]), 0);
    QCOMPARE(porydaw_scale::defaultScale(), porydaw_scale::ScaleId::major);
    QCOMPARE(porydaw_scale::defaultRoot(), 0);
}

void ScaleCheckTest::membershipAndNeighbors()
{
    using namespace porydaw_scale;
    QVERIFY(isScalePitch(ScaleId::major, 0, 60));
    QVERIFY(!isScalePitch(ScaleId::major, 0, 61));
    QVERIFY(isScalePitch(ScaleId::major, 2, 62));
    QVERIFY(!isScalePitch(ScaleId::major, 2, 60));
    QCOMPARE(firstScalePitchAbove(ScaleId::major, 0, 61), 62);
    QCOMPARE(firstScalePitchBelow(ScaleId::major, 0, 61), 60);
    QCOMPARE(firstScalePitchAbove(ScaleId::major, 0, 127), -1);
    QCOMPARE(firstScalePitchBelow(ScaleId::major, 0, 0), -1);
    QCOMPARE(nextScalePitch(ScaleId::major, 0, 60, 1), 62);
    QCOMPARE(nextScalePitch(ScaleId::major, 0, 62, -1), 60);
    QCOMPARE(nextScalePitch(ScaleId::major, 0, 60, 3), 65);
    QCOMPARE(nextScalePitch(ScaleId::major, 0, 67, -3), 62);
}

void ScaleCheckTest::diatonicDestinations_data()
{
    QTest::addColumn<QByteArray>("sources");
    QTest::addColumn<QByteArray>("degrees");
    QTest::addColumn<QByteArray>("expected");
    QTest::addColumn<bool>("accepted");
    QTest::newRow("upward-separates")
        << QByteArray::fromHex("3c3d") << QByteArray::fromRawData("\x01\x01", 2)
        << QByteArray::fromHex("3e40") << true;
    QTest::newRow("downward-separates")
        << QByteArray::fromHex("3d3e") << QByteArray::fromRawData("\xff\xff", 2)
        << QByteArray::fromHex("3b3c") << true;
    QTest::newRow("repeated-source")
        << QByteArray::fromHex("3c3c3d") << QByteArray::fromRawData("\x01\x04\x01", 3)
        << QByteArray::fromHex("3e3e40") << true;
    QTest::newRow("ordered") << QByteArray::fromHex("3c3d3e")
                             << QByteArray::fromRawData("\x01\x01\x01", 3)
                             << QByteArray::fromHex("3e4041") << true;
    // A resolved out-of-range destination clears the whole output to the
    // rejection sentinel. A shape mismatch is rejected before resolution,
    // so it leaves the caller's output untouched.
    QTest::newRow("high-boundary")
        << QByteArray::fromHex("7f") << QByteArray::fromRawData("\x01", 1)
        << QByteArray::fromHex("ff") << false;
    QTest::newRow("low-boundary") << QByteArray::fromHex("00") << QByteArray::fromRawData("\xff", 1)
                                  << QByteArray::fromHex("ff") << false;
    QTest::newRow("mismatched") << QByteArray::fromHex("3c")
                                << QByteArray::fromRawData("\x01\x01", 2)
                                << QByteArray::fromHex("2a") << false;
}

void ScaleCheckTest::diatonicDestinations()
{
    QFETCH(QByteArray, sources);
    QFETCH(QByteArray, degrees);
    QFETCH(QByteArray, expected);
    QFETCH(bool, accepted);
    std::vector<uint8_t> source(sources.begin(), sources.end());
    std::vector<int> displacement;
    displacement.reserve(size_t(degrees.size()));
    for (const char degree : degrees)
        displacement.push_back(int(int8_t(degree)));
    std::vector<uint8_t> destination(expected.size(), uint8_t(42));
    const bool result = porydaw_scale::resolveDiatonicDestinations(
        porydaw_scale::ScaleId::major, 0, source, displacement, destination);
    QCOMPARE(result, accepted);
    QCOMPARE(
        QByteArray(reinterpret_cast<const char *>(destination.data()), int(destination.size())),
        expected);
}

void NoteIdentityCheckTest::parsedMidiLeavesIdsUnassigned()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const SmfFile source = duplicateNoteFile();
    const QByteArray bytes = source.write();
    QTemporaryFile file(directory.filePath(QStringLiteral("noteidcheck-XXXXXX.mid")));
    QVERIFY(file.open());
    QCOMPARE(file.write(bytes), qint64(bytes.size()));
    file.close();
    SmfFile parsed;
    QString error;
    QVERIFY2(SmfFile::readFile(file.fileName(), &parsed, &error), qPrintable(error));
    QCOMPARE(parsed.tracks.size(), size_t(1));
    QCOMPARE(parsed.tracks.front().events.size(), size_t(3));
    const SmfEvent &first = parsed.tracks.front().events[0];
    const SmfEvent &second = parsed.tracks.front().events[1];
    const SmfEvent &ordinary = parsed.tracks.front().events[2];
    QVERIFY(first.isNoteOn());
    QVERIFY(second.isNoteOn());
    QVERIFY(ordinary.isNoteEnd());
    QVERIFY(!first.noteId.isAssigned());
    QVERIFY(!second.noteId.isAssigned());
    QVERIFY(!ordinary.noteId.isAssigned());

    const auto timeline = MidiTimeline::load(file.fileName(), 48000.0, &error);
    QVERIFY2(timeline, qPrintable(error));
    int noteOns = 0;
    bool ordinaryUnassigned = false;
    for (const auto &event : timeline->events) {
        if (event.type == 0x9 && event.tick == 24) {
            ++noteOns;
            QVERIFY(!event.noteId.isAssigned());
        }
        if (event.type == 0x8 && event.tick == 48)
            ordinaryUnassigned = !event.noteId.isAssigned();
    }
    QCOMPARE(noteOns, 2);
    QVERIFY(ordinaryUnassigned);
}

void NoteIdentityCheckTest::adoptedSmfRemintsForeignIds()
{
    SongDocument document;
    SongInfo song;
    song.label = QStringLiteral("note-identity");
    QString error;
    QVERIFY2(document.adoptSmf(duplicateNoteFile(), song, &error), qPrintable(error));

    const auto noteOnIds = [](const SmfFile &smf) {
        std::vector<NoteId> ids;
        for (const SmfTrack &track : smf.tracks) {
            for (const SmfEvent &event : track.events) {
                if (event.isNoteOn())
                    ids.push_back(event.noteId);
            }
        }
        return ids;
    };
    const std::vector<NoteId> original = noteOnIds(document.smf());
    QCOMPARE(original.size(), size_t(2));
    QVERIFY(original[0].isAssigned());
    QVERIFY(original[1].isAssigned());
    QVERIFY(original[0] != original[1]);

    QVERIFY2(document.adoptSmf(document.smf(), song, &error), qPrintable(error));
    document.addNote(0, 96, 64, 24, 80);
    const std::vector<NoteId> adopted = noteOnIds(document.smf());
    QCOMPARE(adopted.size(), size_t(3));
    for (const NoteId id : adopted) {
        QVERIFY(id.isAssigned());
        QVERIFY(std::find(original.begin(), original.end(), id) == original.end());
    }
    for (size_t left = 0; left < adopted.size(); ++left) {
        for (size_t right = left + 1; right < adopted.size(); ++right)
            QVERIFY(adopted[left] != adopted[right]);
    }
}

void NoteIdentityCheckTest::identityDoesNotAffectEqualityOrSerialization()
{
    SmfFile file = duplicateNoteFile();
    const QByteArray baseline = file.write();
    const NoteId first{1};
    const NoteId second{2};
    QVERIFY(first.isAssigned());
    QVERIFY(second.isAssigned());
    QVERIFY(first != second);
    file.tracks.front().events[0].noteId = first;
    file.tracks.front().events[1].noteId = second;
    QVERIFY(file.tracks.front().events[0] == file.tracks.front().events[1]);
    QCOMPARE(file.write(), baseline);
}

void NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds()
{
    SmfFile file = duplicateNoteFile();
    file.tracks.front().events[0].noteId = NoteId{1};
    file.tracks.front().events[1].noteId = NoteId{2};
    const auto timeline = MidiTimeline::build(file, 48000.0);
    QVERIFY(timeline);
    int noteOns = 0;
    bool firstSeen = false;
    bool secondSeen = false;
    bool ordinaryUnassigned = false;
    for (const auto &event : timeline->events) {
        if (event.type == 0x9 && event.tick == 24) {
            ++noteOns;
            firstSeen |= event.noteId == NoteId{1};
            secondSeen |= event.noteId == NoteId{2};
        }
        if (event.type == 0x8 && event.tick == 48)
            ordinaryUnassigned = !event.noteId.isAssigned();
    }
    QCOMPARE(noteOns, 2);
    QVERIFY(firstSeen);
    QVERIFY(secondSeen);
    QVERIFY(ordinaryUnassigned);
}

void NoteIdentityCheckTest::adoptedIdsDoNotCollideWithEdits()
{
    SongInfo song;
    song.label = QStringLiteral("note-id-adopt");
    QString error;

    SongDocument source;
    QVERIFY2(source.adoptSmf(duplicateNoteFile(), song, &error), qPrintable(error));
    const auto foreignNotes = source.notesForTrack(0);
    QCOMPARE(foreignNotes.size(), size_t(2));
    QVERIFY(foreignNotes[0].noteId.isAssigned());
    QVERIFY(foreignNotes[1].noteId.isAssigned());

    SongDocument destination;
    QVERIFY2(destination.adoptSmf(source.smf(), song, &error), qPrintable(error));
    const auto donorNotesAfter = source.notesForTrack(0);
    QCOMPARE(donorNotesAfter.size(), foreignNotes.size());
    for (size_t index = 0; index < foreignNotes.size(); ++index) {
        QCOMPARE(donorNotesAfter[index].noteId, foreignNotes[index].noteId);
        QCOMPARE(donorNotesAfter[index].velocity, foreignNotes[index].velocity);
    }
    const auto imported = destination.notesForTrack(0);
    QCOMPARE(imported.size(), size_t(2));
    QVERIFY(imported[0].noteId != imported[1].noteId);
    for (const DocNote &note : imported) {
        QVERIFY(note.noteId.isAssigned());
        DocNote resolved;
        QVERIFY(destination.findNote(note.noteId, &resolved));
        QCOMPARE(resolved.noteId, note.noteId);
    }

    destination.addNote(0, 72, 67, 12, 90);
    DocNote added;
    QVERIFY(destination.findNote(0, 72, 67, &added));
    QVERIFY(added.noteId != imported[0].noteId);
    QVERIFY(added.noteId != imported[1].noteId);

    const auto changed =
        destination.setNotesVelocities(destination.revision(), {{added.noteId, 77}});
    QVERIFY(changed.has_value());
    QVERIFY(destination.findNote(0, 72, 67, &added));
    QCOMPARE(added.velocity, uint8_t(77));
    for (const DocNote &note : imported) {
        DocNote preserved;
        QVERIFY(destination.findNote(note.noteId, &preserved));
        QCOMPARE(preserved.velocity, note.velocity);
    }

    destination.undoStack()->undo();
    QVERIFY(destination.findNote(0, 72, 67, &added));
    QCOMPARE(added.velocity, uint8_t(90));
    for (const DocNote &note : imported) {
        DocNote preserved;
        QVERIFY(destination.findNote(note.noteId, &preserved));
        QCOMPARE(preserved.velocity, note.velocity);
    }
}
