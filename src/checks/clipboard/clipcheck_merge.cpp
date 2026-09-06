#include "checks/clipboard/clipcheck_test.h"

#include <QtTest>

#include "core/songdocument.h"
#include "ui/songview.h"
#include <memory>

#include "ui/songview/clip.h"
#include "ui/songview/clipmime.h"

namespace checks::clipboard {

namespace {

constexpr uint8_t kCcModulation = 0x01;
constexpr uint8_t kCcVolume = 0x07;

} // namespace

void ClipCheckTest::crossTpbNotePaste()
{
    QString error;
    std::unique_ptr<ClipTabRig> source = ClipTabRig::create(24, error);
    QVERIFY2(source, qPrintable(error));
    QCOMPARE(source->document().addTrack(0), 0);
    source->document().addNotes(0, {{0, 60, 24, 100}});
    source->view().selectionModel().setNoteSelection(noteIds(source->document(), 0));
    QVERIFY(source->sendRollKey(Qt::Key_C, Qt::ControlModifier));
    QVERIFY(clipcheck_support::checkClipboardClip().has_value());

    std::unique_ptr<ClipTabRig> target = ClipTabRig::create(48, error);
    QVERIFY2(target, qPrintable(error));
    QCOMPARE(target->document().smf().division, uint16_t{48});
    QCOMPARE(target->document().addTrack(0), 0);
    target->document().addNotes(0, {{0, 70, 24, 90}});
    target->view().commitEditCursor(24);
    const int undoCountBefore = target->document().undoStack()->count();

    QVERIFY(target->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(target->document(), 0) ==
             std::vector<NoteSpec>{{0, 70, 24, 90}, {24, 60, 48, 100}}));
    QCOMPARE(target->document().undoStack()->count(), undoCountBefore + 1);
    QCOMPARE(target->view().editCursorTick(), uint64_t{72});
}

void ClipCheckTest::mergeTimeRangeAndUndo()
{
    // Pin the same half-up/last-wins conversion rule the merge consumes before
    // asserting its document effect, so a scaling regression diagnoses locally.
    songview::Clip roundingProbe;
    roundingProbe.span = 1;
    roundingProbe.tracks = {{2, {{1, 60, 1, 100}, {3, 61, 0, 80}}}};
    roundingProbe.lanes = {{2, kCcVolume, {{2, 20}, {1, 10}, {3, 30}}}};
    roundingProbe.tempo = {{2, 500000}, {1, 600000}, {3, 700000}};
    songview::Clip scaledProbe;
    scaledProbe.span = 1;
    scaledProbe.tracks = {{2, {{1, 60, 1, 100}, {2, 61, 0, 80}}}};
    scaledProbe.lanes = {{2, kCcVolume, {{1, 10}, {2, 30}}}};
    scaledProbe.tempo = {{1, 600000}, {2, 700000}};
    QVERIFY(clipcheck_support::sameClip(songview::rescaleClip(roundingProbe, 48, 24), scaledProbe));

    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->document().addNotes(0, {{24, 60, 24, 100}, {48, 64, 24, 100}});
    rig->document().addLanePoint(0, kCcModulation, 36, 40);
    rig->document().addLanePoint(0, kCcModulation, 60, 70);
    rig->document().addLanePoint(0, kCcModulation, 96, 40);
    rig->document().applyTempoEdit({{}, {{0, 500000}, {25, 600000}, {60, 700000}}});
    rig->view().commitEditCursor(24);

    const int undoBeforeMerge = rig->document().undoStack()->count();
    songview::Clip clip;
    clip.span = 48;
    clip.tracks = {{0, {{0, 60, 24, 120}}}};
    clip.lanes = {{0, kCcModulation, {{23, 110}, {24, 120}}}};
    clip.tempo = {{1, 300000}, {2, 400000}};
    songview::writeClipboard(clip, 48);

    QVERIFY(rig->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{24, 60, 12, 120}, {36, 60, 12, 100}, {48, 64, 24, 100}}));
    QVERIFY((lanesOf(rig->document(), 0, kCcModulation) ==
             std::vector<LaneSpec>{{36, 120}, {60, 70}, {96, 40}}));
    QVERIFY((tempoOf(rig->document()) ==
             std::vector<TempoSpec>{{0, 500000}, {25, 400000}, {60, 700000}}));
    QVERIFY(!rig->view().selectionModel().timeSelection().active());
    QCOMPARE(rig->view().editCursorTick(), uint64_t{48});
    QCOMPARE(rig->document().undoStack()->count(), undoBeforeMerge + 1);

    rig->document().undoStack()->undo();
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{24, 60, 24, 100}, {48, 64, 24, 100}}));
    QVERIFY((lanesOf(rig->document(), 0, kCcModulation) ==
             std::vector<LaneSpec>{{36, 40}, {60, 70}, {96, 40}}));
    QVERIFY((tempoOf(rig->document()) ==
             std::vector<TempoSpec>{{0, 500000}, {25, 600000}, {60, 700000}}));
}

void ClipCheckTest::emptyLaneMergeIsNoop()
{
    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->document().addNotes(0, {{24, 62, 24, 100}});
    rig->document().addLanePoint(0, kCcVolume, 144, 90);
    rig->view().commitEditCursor(120);
    const int undoBefore = rig->document().undoStack()->count();

    songview::Clip clip;
    clip.span = 48;
    clip.lanes = {{0, kCcVolume, {}}};
    songview::writeClipboard(clip, 24);

    QVERIFY(rig->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(rig->document(), 0) == std::vector<NoteSpec>{{24, 62, 24, 100}}));
    QVERIFY((lanesOf(rig->document(), 0, kCcVolume) == std::vector<LaneSpec>{{144, 90}}));
    QCOMPARE(rig->document().undoStack()->count(), undoBefore);
    QCOMPARE(rig->view().editCursorTick(), uint64_t{120});
}

void ClipCheckTest::tiledTimePasteUndoesOneTileAtATime()
{
    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->view().commitEditCursor(0);
    const int undoBefore = rig->document().undoStack()->count();

    songview::Clip clip;
    clip.span = 96;
    clip.tracks = {{0, {{0, 60, 24, 100}}}};
    songview::writeClipboard(clip, 24);

    QVERIFY(rig->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(rig->document(), 0) == std::vector<NoteSpec>{{0, 60, 24, 100}}));
    QCOMPARE(rig->view().editCursorTick(), uint64_t{96});
    QVERIFY(rig->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{0, 60, 24, 100}, {96, 60, 24, 100}}));
    QCOMPARE(rig->view().editCursorTick(), uint64_t{192});
    QCOMPARE(rig->document().undoStack()->count(), undoBefore + 2);

    rig->document().undoStack()->undo();
    QVERIFY((notesOf(rig->document(), 0) == std::vector<NoteSpec>{{0, 60, 24, 100}}));
    rig->document().undoStack()->undo();
    QVERIFY(notesOf(rig->document(), 0).empty());
}

} // namespace checks::clipboard
