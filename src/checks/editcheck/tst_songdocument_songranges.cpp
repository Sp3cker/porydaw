#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>

#include "checks/editcheck/tst_songdocument_support.h"

namespace {

// Synthetic near-ceiling document: one engine track whose note (50 ticks
// long), CC-7 point, and conductor tempo sit just below kMaxTick so range
// edits can land on or past the domain edge.
SmfFile ceilingFile(Tick noteTick, Tick laneTick, Tick tempoTick)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack conductor;
    conductor.events = {
        songdocument_test::meta(0x01, 0, QByteArrayLiteral("ceiling")),
        songdocument_test::meta(0x51, tempoTick, QByteArray("\x07\xA1\x20", 3)),
    };
    conductor.endTick = CoreTimeDefaults::kMaxTick;
    smf.tracks.push_back(conductor);
    SmfTrack track;
    track.events = {
        songdocument_test::channel(0xC0, 0, 1, 0),
        songdocument_test::channel(0x90, noteTick, 60, 100),
        songdocument_test::channel(0x80, noteTick + 50, 60, 0),
        songdocument_test::channel(0xB0, laneTick, 7, 80),
    };
    std::stable_sort(track.events.begin(), track.events.end(),
                     [](const SmfEvent &a, const SmfEvent &b) { return a.tick < b.tick; });
    track.endTick = CoreTimeDefaults::kMaxTick;
    smf.tracks.push_back(track);
    return smf;
}

const TempoPoint *tempoAt(const SongDocument &document, Tick tick)
{
    for (const TempoPoint &point : document.tempoPoints()) {
        if (point.tick == tick)
            return &point;
    }
    return nullptr;
}

} // namespace

void EditCheckTest::rangeEdit_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeEdit()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for range editing");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNotes(track, {{Tick(base + step * 30), 60, step * 2, 90},
                              {Tick(base + step * 32), 62, step * 2, 90}});
    document.addLanePoint(track, 7, base + step * 30, 80);
    document.applyTempoEdit({{}, {songdocument_test::tempo(base + step * 31, 140)}});
    SongDocument::RangeEdit edit;
    for (const DocNote &note : document.notesForTrack(track)) {
        if (note.tick == base + step * 30 || note.tick == base + step * 32)
            edit.removeNotes.push_back(note);
    }
    for (const DocLanePoint &point : document.lanePoints(track, 7)) {
        if (point.tick == base + step * 30)
            edit.removePoints.push_back(point);
    }
    edit.removeTempo.push_back(songdocument_test::tempo(base + step * 31, 140));
    edit.addNotes.push_back({track, {{Tick(base + step * 40), 65, step * 2, 90}}});
    edit.addPoints.push_back({track, 7, {{Tick(base + step * 40), 70}}});
    edit.addTempo.push_back(songdocument_test::tempo(base + step * 41, 155));
    const int before = document.undoStack()->count();
    document.applyRangeEdit(QStringLiteral("range edit"), edit);
    DocNote note;
    DocLanePoint point;
    QVERIFY(!document.findNote(track, base + step * 30, 60, &note));
    QVERIFY(!document.findNote(track, base + step * 32, 62, &note));
    QVERIFY(document.findNote(track, base + step * 40, 65, &note));
    QVERIFY(document.findLanePoint(track, 7, base + step * 40, &point));
    QCOMPARE(point.value, 70);
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 41, 155)));
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 30, 60, &note));
    QVERIFY(document.findNote(track, base + step * 32, 62, &note));
    QVERIFY(!document.findNote(track, base + step * 40, 65, &note));
    QVERIFY(!songdocument_test::containsTempo(document,
                                              songdocument_test::tempo(base + step * 41, 155)));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 40, 65, &note));

    // Synthetic document just below kMaxTick: a range edit may land exactly
    // on the ceiling, but any destination past it rejects the whole edit.
    SongDocument ceiling;
    SongInfo ceilingInfo;
    ceilingInfo.label = QStringLiteral("range-ceiling");
    QVERIFY2(ceiling.adoptSmf(ceilingFile(CoreTimeDefaults::kMaxTick - 200,
                                          CoreTimeDefaults::kMaxTick - 200,
                                          CoreTimeDefaults::kMaxTick - 200),
                              ceilingInfo, &error),
             qPrintable(error));
    DocNote existing;
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 200, 60, &existing));

    SongDocument::RangeEdit boundary;
    boundary.minimumEngineTrackCount = 2;
    boundary.removeNotes.push_back(existing);
    boundary.addNotes.push_back({0, {{Tick(CoreTimeDefaults::kMaxTick - 10), 65, 10, 90}}});
    boundary.addPoints.push_back({0, 7, {{CoreTimeDefaults::kMaxTick, 70}}});
    boundary.addTempo.push_back({CoreTimeDefaults::kMaxTick, 500000});
    const int ceilingBefore = ceiling.undoStack()->count();
    ceiling.applyRangeEdit(QStringLiteral("range edit"), boundary);
    QCOMPARE(ceiling.undoStack()->count(), ceilingBefore + 1);
    QCOMPARE(ceiling.engineTrackCount(), 2);
    QVERIFY(!ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 200, 60, &existing));
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 10, 65, &existing));
    QCOMPARE(existing.duration, uint32_t(10));
    QVERIFY(ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick, &point));
    QCOMPARE(point.value, 70);
    QVERIFY(songdocument_test::containsTempo(ceiling, {CoreTimeDefaults::kMaxTick, 500000}));
    ceiling.undoStack()->undo();
    QCOMPARE(ceiling.engineTrackCount(), 1);
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 200, 60, &existing));
    QVERIFY(!ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 10, 65, &existing));
    QVERIFY(!ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick, &point));
    QVERIFY(!songdocument_test::containsTempo(ceiling, {CoreTimeDefaults::kMaxTick, 500000}));
    ceiling.undoStack()->redo();
    QCOMPARE(ceiling.engineTrackCount(), 2);
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 10, 65, &existing));

    // One added note whose normalized end passes kMaxTick rejects the whole
    // edit: the removal, lane point, tempo point, and track expansion all
    // stay unapplied.
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 10, 65, &existing));
    SongDocument::RangeEdit overflow = boundary;
    overflow.minimumEngineTrackCount = 3;
    overflow.removeNotes = {existing};
    overflow.addNotes = {{0, {{Tick(CoreTimeDefaults::kMaxTick - 9), 66, 10, 90}}}};
    overflow.addPoints = {{0, 7, {{Tick(CoreTimeDefaults::kMaxTick - 5), 55}}}};
    overflow.addTempo = {{Tick(CoreTimeDefaults::kMaxTick - 5), 400000}};
    const QByteArray smfBefore = ceiling.smf().write();
    const std::vector<TempoPoint> tempoBefore = ceiling.tempoPoints();
    const uint64_t revisionBefore = ceiling.revision();
    const int undoBefore = ceiling.undoStack()->count();
    ceiling.applyRangeEdit(QStringLiteral("range edit"), overflow);
    QCOMPARE(ceiling.smf().write(), smfBefore);
    QVERIFY(ceiling.tempoPoints() == tempoBefore);
    QCOMPARE(ceiling.revision(), revisionBefore);
    QCOMPARE(ceiling.undoStack()->count(), undoBefore);
    QCOMPARE(ceiling.engineTrackCount(), 2);
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 10, 65, &existing));
    QVERIFY(!ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 9, 66, &existing));
    QVERIFY(!ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick - 5, &point));
    QVERIFY(
        !songdocument_test::containsTempo(ceiling, {Tick(CoreTimeDefaults::kMaxTick - 5), 400000}));
}

void EditCheckTest::rangeMove_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeMove()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for range moving");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addNotes(track, {{Tick(base + step * 80), 60, step * 2, 90},
                              {Tick(base + step * 82), 64, step * 2, 90}});
    document.addLanePoint(track, 7, base + step * 80, 45);
    document.applyTempoEdit({{}, {songdocument_test::tempo(base + step * 81, 140)}});
    DocNote first;
    DocNote second;
    DocLanePoint point;
    QVERIFY(document.findNote(track, base + step * 80, 60, &first));
    QVERIFY(document.findNote(track, base + step * 82, 64, &second));
    QVERIFY(document.findLanePoint(track, 7, base + step * 80, &point));
    const int before = document.undoStack()->count();
    document.moveRange({first, second}, {point}, int64_t(step) * 3,
                       {songdocument_test::tempo(base + step * 81, 140)});
    QVERIFY(document.findNote(track, base + step * 83, 60, &first));
    QCOMPARE(first.duration, step * 2);
    QVERIFY(document.findNote(track, base + step * 85, 64, &second));
    QCOMPARE(second.duration, step * 2);
    QVERIFY(document.findLanePoint(track, 7, base + step * 83, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(songdocument_test::containsTempo(document,
                                             songdocument_test::tempo(base + step * 84, 140)));
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.moveRange({first}, {point}, 0, {});
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findNote(track, base + step * 80, 60, &first));
    QVERIFY(document.findNote(track, base + step * 82, 64, &second));
    document.undoStack()->redo();
    QVERIFY(document.findNote(track, base + step * 83, 60, &first));

    // Synthetic document just below kMaxTick: a mixed move may land exactly
    // on the ceiling, but any destination past it rejects the whole move.
    SongDocument ceiling;
    SongInfo ceilingInfo;
    ceilingInfo.label = QStringLiteral("move-ceiling");
    QVERIFY2(ceiling.adoptSmf(ceilingFile(CoreTimeDefaults::kMaxTick - 200,
                                          CoreTimeDefaults::kMaxTick - 200,
                                          CoreTimeDefaults::kMaxTick - 200),
                              ceilingInfo, &error),
             qPrintable(error));
    DocNote moved;
    DocLanePoint movedPoint;
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 200, 60, &moved));
    QVERIFY(ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick - 200, &movedPoint));
    const TempoPoint *movedTempo = tempoAt(ceiling, CoreTimeDefaults::kMaxTick - 200);
    QVERIFY(movedTempo);

    // +50 lands the note-off exactly on kMaxTick; the move applies and
    // round-trips through undo/redo.
    const int ceilingBefore = ceiling.undoStack()->count();
    ceiling.moveRange({moved}, {movedPoint}, 50, {*movedTempo});
    QCOMPARE(ceiling.undoStack()->count(), ceilingBefore + 1);
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 150, 60, &moved));
    QCOMPARE(moved.duration, uint32_t(50));
    QVERIFY(ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick - 150, &movedPoint));
    QVERIFY(songdocument_test::containsTempo(ceiling,
                                             {Tick(CoreTimeDefaults::kMaxTick - 150), 500000}));
    ceiling.undoStack()->undo();
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 200, 60, &moved));
    QVERIFY(ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick - 200, &movedPoint));
    QVERIFY(songdocument_test::containsTempo(ceiling,
                                             {Tick(CoreTimeDefaults::kMaxTick - 200), 500000}));
    ceiling.undoStack()->redo();
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 150, 60, &moved));

    // Only the note-off destination overflows (+120 puts the 50-tick note's
    // end at kMaxTick + 20 while its on, the lane point, and the tempo point
    // still fit): the complete move is rejected.
    QVERIFY(ceiling.findNote(0, CoreTimeDefaults::kMaxTick - 150, 60, &moved));
    QVERIFY(ceiling.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick - 150, &movedPoint));
    movedTempo = tempoAt(ceiling, CoreTimeDefaults::kMaxTick - 150);
    QVERIFY(movedTempo);
    const QByteArray smfBefore = ceiling.smf().write();
    const std::vector<TempoPoint> tempoBefore = ceiling.tempoPoints();
    const uint64_t revisionBefore = ceiling.revision();
    const int undoBefore = ceiling.undoStack()->count();
    ceiling.moveRange({moved}, {movedPoint}, 120, {*movedTempo});
    QCOMPARE(ceiling.smf().write(), smfBefore);
    QVERIFY(ceiling.tempoPoints() == tempoBefore);
    QCOMPARE(ceiling.revision(), revisionBefore);
    QCOMPARE(ceiling.undoStack()->count(), undoBefore);

    // Only the lane destination overflows: the note and tempo destinations
    // fit, yet the complete move is still rejected.
    SongDocument high;
    QVERIFY2(
        high.adoptSmf(ceilingFile(CoreTimeDefaults::kMaxTick - 200, CoreTimeDefaults::kMaxTick - 40,
                                  CoreTimeDefaults::kMaxTick - 200),
                      ceilingInfo, &error),
        qPrintable(error));
    QVERIFY(high.findNote(0, CoreTimeDefaults::kMaxTick - 200, 60, &moved));
    QVERIFY(high.findLanePoint(0, 7, CoreTimeDefaults::kMaxTick - 40, &movedPoint));
    movedTempo = tempoAt(high, CoreTimeDefaults::kMaxTick - 200);
    QVERIFY(movedTempo);
    const QByteArray highSmf = high.smf().write();
    const std::vector<TempoPoint> highTempo = high.tempoPoints();
    const uint64_t highRevision = high.revision();
    const int highUndo = high.undoStack()->count();
    high.moveRange({moved}, {movedPoint}, 60, {*movedTempo});
    QCOMPARE(high.smf().write(), highSmf);
    QVERIFY(high.tempoPoints() == highTempo);
    QCOMPARE(high.revision(), highRevision);
    QCOMPARE(high.undoStack()->count(), highUndo);
}

void EditCheckTest::rangeLaneBulk_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeLaneBulk()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for bulk lane moves");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addLanePoint(track, 7, base + step * 90, 20);
    document.addLanePoint(track, 7, base + step * 91, 40);
    document.addLanePoint(track, 7, base + step * 92, 60);
    DocLanePoint first;
    DocLanePoint second;
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &first));
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &second));
    const int before = document.undoStack()->count();
    document.moveLanePoints({{track, 7, first, Tick(base + step * 93), 25},
                             {track, 7, second, Tick(base + step * 94), 45}});
    DocLanePoint point;
    QVERIFY(document.findLanePoint(track, 7, base + step * 93, &point));
    QCOMPARE(point.value, 25);
    QVERIFY(document.findLanePoint(track, 7, base + step * 94, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(document.findLanePoint(track, 7, base + step * 92, &point));
    QCOMPARE(point.value, 60);
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &point));
    QCOMPARE(point.value, 20);
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &point));
    QCOMPARE(point.value, 40);
    QVERIFY(!document.findLanePoint(track, 7, base + step * 93, &point));
    document.undoStack()->redo();
    QVERIFY(document.findLanePoint(track, 7, base + step * 93, &point));
}

void EditCheckTest::rangeLaneConverge_data()
{
    addSongRows(SongCapability::EditableTrack);
}

void EditCheckTest::rangeLaneConverge()
{
    QFETCH(QString, songLabel);
    const SongInfo song = songForLabel(songLabel);
    QVERIFY2(!song.midPath.isEmpty(), "corpus staged no editable song for converging lane moves");

    SongDocument document;
    QString error;
    QVERIFY2(document.load(song, &error), qPrintable(error));
    const int track = songdocument_test::firstEditableTrack(document);
    QVERIFY2(track >= 0, "classified editable song loaded without an editable track");
    const uint64_t base = songdocument_test::distantBase(document);
    const uint32_t step = document.ticksPerClock();

    document.addLanePoint(track, 7, base + step * 90, 25);
    document.addLanePoint(track, 7, base + step * 91, 45);
    DocLanePoint first;
    DocLanePoint second;
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &first));
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &second));
    const int before = document.undoStack()->count();
    document.moveLanePoints({{track, 7, first, Tick(base + step * 97), 70},
                             {track, 7, second, Tick(base + step * 97), 72}});
    const auto atDestination = document.lanePoints(track, 7);
    int destinationCount = 0;
    for (const DocLanePoint &point : atDestination) {
        if (point.tick == base + step * 97) {
            ++destinationCount;
            QCOMPARE(point.value, 72);
        }
    }
    QCOMPARE(destinationCount, 1);
    QCOMPARE(document.undoStack()->count(), before + 1);
    document.undoStack()->undo();
    DocLanePoint point;
    QVERIFY(document.findLanePoint(track, 7, base + step * 90, &point));
    QCOMPARE(point.value, 25);
    QVERIFY(document.findLanePoint(track, 7, base + step * 91, &point));
    QCOMPARE(point.value, 45);
    QVERIFY(!document.findLanePoint(track, 7, base + step * 97, &point));
}
