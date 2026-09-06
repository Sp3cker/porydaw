#include "checks/clipboard/clipcheck_test.h"

#include <QtTest>

#include <memory>
#include <optional>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/clip.h"
#include "ui/songview/clipmime.h"

namespace checks::clipboard {

namespace {

constexpr uint8_t kCcModulation = 0x01;

songview::EditorSelectionModel::TimeSelection tracksSelection(uint64_t start, uint64_t end)
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = start;
    selection.endTick = end;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Tracks;
    return selection;
}

} // namespace

void ClipCheckTest::crossViewNoteCopyPaste()
{
    QString error;
    std::unique_ptr<ClipTabRig> source = ClipTabRig::create(24, error);
    QVERIFY2(source, qPrintable(error));
    QCOMPARE(source->document().addTrack(0), 0);
    source->document().addNotes(0, {{24, 60, 24, 100}, {36, 64, 12, 80}});
    source->view().selectionModel().setNoteSelection(noteIds(source->document(), 0));

    QVERIFY(source->sendRollKey(Qt::Key_C, Qt::ControlModifier));
    const std::optional<songview::DecodedClip> copied = clipcheck_support::checkClipboardClip();
    QVERIFY(copied.has_value());
    QCOMPARE(copied->ticksPerBeat, uint32_t{24});
    songview::Clip expected;
    expected.tracks = {{0, {{0, 60, 24, 100}, {12, 64, 12, 80}}}};
    QVERIFY(clipcheck_support::sameClip(copied->clip, expected));

    std::unique_ptr<ClipTabRig> target = ClipTabRig::create(24, error);
    QVERIFY2(target, qPrintable(error));
    QCOMPARE(target->document().addTrack(0), 0);
    QCOMPARE(target->document().addTrack(1), 1);
    target->document().addNotes(0, {{0, 70, 24, 90}});
    target->view().selectTrack(1);
    target->view().selectionModel().clearNoteSelection();
    target->view().commitEditCursor(48);
    const std::vector<NoteSpec> beforePaste = notesOf(target->document(), 0);

    QVERIFY(target->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(target->document(), 1) ==
             std::vector<NoteSpec>{{48, 60, 24, 100}, {60, 64, 12, 80}}));
    QVERIFY(notesOf(target->document(), 0) == beforePaste);
    QCOMPARE(target->view().selectionModel().noteSelection().size(), size_t{2});
    QCOMPARE(target->view().editCursorTick(), uint64_t{72});
}

void ClipCheckTest::sameViewNoteCopyPaste()
{
    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->document().addNotes(0, {{24, 60, 24, 100}});
    rig->view().selectionModel().setNoteSelection(noteIds(rig->document(), 0));

    QVERIFY(rig->sendRollKey(Qt::Key_C, Qt::ControlModifier));
    const std::optional<songview::DecodedClip> copied = clipcheck_support::checkClipboardClip();
    QVERIFY(copied.has_value());
    QCOMPARE(copied->ticksPerBeat, uint32_t{24});
    QCOMPARE(copied->clip.span, uint64_t{0});
    songview::Clip expected;
    expected.tracks = {{0, {{0, 60, 24, 100}}}};
    QVERIFY(clipcheck_support::sameClip(copied->clip, expected));

    rig->view().selectionModel().clearNoteSelection();
    rig->view().commitEditCursor(48);
    QVERIFY(rig->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{24, 60, 24, 100}, {48, 60, 24, 100}}));
    QCOMPARE(rig->view().selectionModel().noteSelection().size(), size_t{1});
    QCOMPARE(rig->view().editCursorTick(), uint64_t{72});
}

void ClipCheckTest::songViewEditKeyPaste()
{
    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->document().addNotes(0, {{24, 60, 24, 100}});
    rig->view().selectionModel().setNoteSelection(noteIds(rig->document(), 0));
    QVERIFY(rig->sendRollKey(Qt::Key_C, Qt::ControlModifier));
    QVERIFY(clipcheck_support::checkClipboardClip().has_value());

    rig->view().selectionModel().clearNoteSelection();
    rig->view().commitEditCursor(48);
    QVERIFY(rig->sendViewKey(Qt::Key_V, Qt::ControlModifier));
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{24, 60, 24, 100}, {48, 60, 24, 100}}));
    QCOMPARE(rig->view().selectionModel().noteSelection().size(), size_t{1});
    QCOMPARE(rig->view().editCursorTick(), uint64_t{72});
}

void ClipCheckTest::timeSelectionCopy()
{
    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->document().addNotes(0, {{0, 60, 24, 100}});
    rig->view().selectionModel().setNoteSelection(noteIds(rig->document(), 0));

    rig->view().selectionModel().setTimeSelection(tracksSelection(0, 96));
    QVERIFY(rig->view().selectionModel().noteSelection().empty());
    const auto &selection = rig->view().selectionModel().timeSelection();
    QVERIFY(selection.active());
    QCOMPARE(selection.startTick, uint64_t{0});
    QCOMPARE(selection.endTick, uint64_t{96});
    QCOMPARE(selection.scope, songview::EditorSelectionModel::TimeSelection::Tracks);
    QCOMPARE(rig->view().selectionModel().storedTrackScope(), uint32_t{0x1});
    QVERIFY(rig->sendRollKey(Qt::Key_C, Qt::ControlModifier));
    const std::optional<songview::DecodedClip> copied = clipcheck_support::checkClipboardClip();
    QVERIFY(copied.has_value());
    QCOMPARE(copied->ticksPerBeat, uint32_t{24});
    QCOMPARE(copied->clip.span, uint64_t{96});
    songview::Clip expected;
    expected.span = 96;
    expected.tracks = {{0, {{0, 60, 24, 100}}}};
    // addTrack() seeds the source track with its initial program change;
    // track-scoped range copy preserves that voice lane and its value.
    expected.lanes = {{0, DOC_CC_VOICE, {{0, 0}}}};
    QVERIFY(clipcheck_support::sameClip(copied->clip, expected));
}

void ClipCheckTest::scopedRangeCopyPasteCreatesTracks()
{
    QString error;
    std::unique_ptr<ClipTabRig> source = ClipTabRig::create(24, error);
    QVERIFY2(source, qPrintable(error));
    QCOMPARE(source->document().addTrack(0), 0);
    QCOMPARE(source->document().addTrack(0), 1);
    QCOMPARE(source->document().addTrack(0), 2);
    source->document().addNotes(0, {{12, 60, 12, 90}});
    source->document().addNotes(1, {{24, 64, 24, 100}});
    source->document().addNotes(2, {{36, 68, 36, 110}});
    source->document().addLanePoint(0, kCcModulation, 18, 11);
    source->document().addLanePoint(1, kCcModulation, 30, 22);
    source->document().addLanePoint(2, kCcModulation, 42, 33);

    source->view().selectionModel().setTimeSelectionAndTrackScope(tracksSelection(0, 96), 0x7);
    QVERIFY(source->view().selectionModel().timeSelection().active());
    QCOMPARE(source->view().selectionModel().storedTrackScope(), uint32_t{0x7});
    const auto &selection = source->view().selectionModel().timeSelection();
    QCOMPARE(selection.startTick, uint64_t{0});
    QCOMPARE(selection.endTick, uint64_t{96});
    QCOMPARE(selection.scope, songview::EditorSelectionModel::TimeSelection::Tracks);
    QVERIFY(source->sendRollKey(Qt::Key_C, Qt::ControlModifier));
    const std::optional<songview::DecodedClip> copied = clipcheck_support::checkClipboardClip();
    QVERIFY(copied.has_value());
    QCOMPARE(copied->ticksPerBeat, uint32_t{24});

    songview::Clip expected;
    expected.span = 96;
    expected.tracks = {
        {0, {{12, 60, 12, 90}}},
        {1, {{24, 64, 24, 100}}},
        {2, {{36, 68, 36, 110}}},
    };
    // Each addTrack() call contributes the initial voice point at tick zero.
    // Those points are clipboard content, not cosmetic empty lane padding.
    expected.lanes = {{0, kCcModulation, {{18, 11}}}, {0, DOC_CC_VOICE, {{0, 0}}},
                      {1, kCcModulation, {{30, 22}}}, {1, DOC_CC_VOICE, {{0, 0}}},
                      {2, kCcModulation, {{42, 33}}}, {2, DOC_CC_VOICE, {{0, 0}}}};
    QVERIFY(clipcheck_support::sameClip(copied->clip, expected));

    std::unique_ptr<ClipTabRig> target = ClipTabRig::create(24, error);
    QVERIFY2(target, qPrintable(error));
    QCOMPARE(target->document().addTrack(0), 0);
    target->view().commitEditCursor(0);
    const int undoBeforePaste = target->document().undoStack()->count();
    QCOMPARE(target->document().engineTrackCount(), 1);

    QVERIFY(target->sendRollKey(Qt::Key_V, Qt::ControlModifier));
    QCOMPARE(target->document().engineTrackCount(), 3);
    QVERIFY((notesOf(target->document(), 0) == std::vector<NoteSpec>{{12, 60, 12, 90}}));
    QVERIFY((notesOf(target->document(), 1) == std::vector<NoteSpec>{{24, 64, 24, 100}}));
    QVERIFY((notesOf(target->document(), 2) == std::vector<NoteSpec>{{36, 68, 36, 110}}));
    QVERIFY((lanesOf(target->document(), 0, kCcModulation) == std::vector<LaneSpec>{{18, 11}}));
    QVERIFY((lanesOf(target->document(), 1, kCcModulation) == std::vector<LaneSpec>{{30, 22}}));
    QVERIFY((lanesOf(target->document(), 2, kCcModulation) == std::vector<LaneSpec>{{42, 33}}));
    QVERIFY((lanesOf(target->document(), 0, DOC_CC_VOICE) == std::vector<LaneSpec>{{0, 0}}));
    QVERIFY((lanesOf(target->document(), 1, DOC_CC_VOICE) == std::vector<LaneSpec>{{0, 0}}));
    QVERIFY((lanesOf(target->document(), 2, DOC_CC_VOICE) == std::vector<LaneSpec>{{0, 0}}));
    QCOMPARE(target->document().undoStack()->count(), undoBeforePaste + 1);

    target->document().undoStack()->undo();
    QCOMPARE(target->document().engineTrackCount(), 1);
    QVERIFY(notesOf(target->document(), 0).empty());
    QVERIFY(lanesOf(target->document(), 0, kCcModulation).empty());
    QVERIFY((lanesOf(target->document(), 0, DOC_CC_VOICE) == std::vector<LaneSpec>{{0, 0}}));
}

void ClipCheckTest::rangeDeleteCutAndUndo()
{
    QString error;
    std::unique_ptr<ClipTabRig> rig = ClipTabRig::create(24, error);
    QVERIFY2(rig, qPrintable(error));
    QCOMPARE(rig->document().addTrack(0), 0);
    rig->document().addNotes(0, {{24, 60, 24, 100}, {96, 64, 24, 80}});
    rig->document().addLanePoint(0, DOC_CC_VOICE, 24, 3);
    rig->document().addLanePoint(0, DOC_CC_VOICE, 96, 5);
    rig->document().applyTempoEdit({{}, {{24, 600000}, {96, 400000}}});
    rig->view().selectionModel().setTimeSelection(tracksSelection(0, 48));

    const int undoBeforeDelete = rig->document().undoStack()->count();
    QVERIFY(rig->sendRollKey(Qt::Key_Delete, Qt::NoModifier));
    QVERIFY((notesOf(rig->document(), 0) == std::vector<NoteSpec>{{96, 64, 24, 80}}));
    QVERIFY((lanesOf(rig->document(), 0, DOC_CC_VOICE) == std::vector<LaneSpec>{{96, 5}}));
    QVERIFY((tempoOf(rig->document()) == std::vector<TempoSpec>{{96, 400000}}));
    QCOMPARE(rig->document().undoStack()->count(), undoBeforeDelete + 1);
    QVERIFY(rig->view().selectionModel().timeSelection().active());

    rig->document().undoStack()->undo();
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{24, 60, 24, 100}, {96, 64, 24, 80}}));
    // RangeEdit restores the document's normalized boundary point at the
    // range start; this is observable undo behavior, not fixture setup.
    QVERIFY((lanesOf(rig->document(), 0, DOC_CC_VOICE) ==
             std::vector<LaneSpec>{{0, 0}, {24, 3}, {96, 5}}));
    QVERIFY((tempoOf(rig->document()) == std::vector<TempoSpec>{{24, 600000}, {96, 400000}}));

    const int undoIndexBeforeCut = rig->document().undoStack()->index();
    QVERIFY(rig->sendRollKey(Qt::Key_X, Qt::ControlModifier));
    const std::optional<songview::DecodedClip> cut = clipcheck_support::checkClipboardClip();
    QVERIFY(cut.has_value());
    QCOMPARE(cut->clip.span, uint64_t{48});
    QVERIFY((notesOf(rig->document(), 0) == std::vector<NoteSpec>{{96, 64, 24, 80}}));
    QVERIFY((lanesOf(rig->document(), 0, DOC_CC_VOICE) == std::vector<LaneSpec>{{96, 5}}));
    QVERIFY((tempoOf(rig->document()) == std::vector<TempoSpec>{{96, 400000}}));
    QCOMPARE(rig->document().undoStack()->index(), undoIndexBeforeCut + 1);

    rig->document().undoStack()->undo();
    QVERIFY((notesOf(rig->document(), 0) ==
             std::vector<NoteSpec>{{24, 60, 24, 100}, {96, 64, 24, 80}}));
    QVERIFY((lanesOf(rig->document(), 0, DOC_CC_VOICE) ==
             std::vector<LaneSpec>{{0, 0}, {24, 3}, {96, 5}}));
    QVERIFY((tempoOf(rig->document()) == std::vector<TempoSpec>{{24, 600000}, {96, 400000}}));
}

} // namespace checks::clipboard
