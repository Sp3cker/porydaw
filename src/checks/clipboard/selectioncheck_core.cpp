#include "checks/clipboard/selectioncheck_test.h"

#include <QtTest>

#include <span>
#include <vector>

#include "core/songdocument.h"

namespace checks::clipboard {

namespace {

using EditorSelectionModel = songview::EditorSelectionModel;
using SelectionChange = EditorSelectionModel::SelectionChange;

constexpr uint32_t kPrimaryTrack = static_cast<uint32_t>(SelectionChange::PrimaryTrack);
constexpr uint32_t kTrackScope = static_cast<uint32_t>(SelectionChange::TrackScope);
constexpr uint32_t kNoteSelection = static_cast<uint32_t>(SelectionChange::NoteSelection);
constexpr uint32_t kTimeSelection = static_cast<uint32_t>(SelectionChange::TimeSelection);

bool received(const NotificationLog &log, size_t before, uint32_t changes)
{
    return log.transitions.size() == before + 1 &&
           static_cast<uint32_t>(log.transitions.back().changes) == changes;
}

} // namespace

void SelectionCheckTest::noteSelectionSanitizesAndExcludesTime()
{
    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);

    model.setNoteSelection({NoteId{}, NoteId{7}, NoteId{7}, NoteId{8}});
    QVERIFY((model.noteSelection() == std::vector<NoteId>{NoteId{7}, NoteId{8}}));
    QVERIFY(model.isNoteSelected(NoteId{7}));
    QVERIFY(model.isNoteSelected(NoteId{8}));
    QVERIFY(!model.isNoteSelected(NoteId{9}));
    QVERIFY(!model.isNoteSelected(NoteId{}));
    QVERIFY(received(notifications, 0, kNoteSelection));

    const size_t beforeEquivalent = notifications.transitions.size();
    model.setNoteSelection({NoteId{}, NoteId{7}, NoteId{8}, NoteId{8}});
    QCOMPARE(notifications.transitions.size(), beforeEquivalent);

    EditorSelectionModel::TimeSelection time;
    time.startTick = 10;
    time.endTick = 20;
    model.setTimeSelection(time);
    QVERIFY(model.noteSelection().empty());
    QVERIFY(model.timeSelection().active());
    QVERIFY(received(notifications, beforeEquivalent, kNoteSelection | kTimeSelection));

    const size_t afterTime = notifications.transitions.size();
    model.setNoteSelection({NoteId{}});
    QVERIFY(model.timeSelection().active());
    QVERIFY(model.noteSelection().empty());
    QCOMPARE(notifications.transitions.size(), afterTime);

    model.setNoteSelection({NoteId{19}});
    QVERIFY((model.noteSelection() == std::vector<NoteId>{NoteId{19}}));
    QVERIFY(!model.timeSelection().active());
    QVERIFY(received(notifications, afterTime, kNoteSelection | kTimeSelection));

    EditorSelectionModel::TimeSelection inactive;
    const size_t beforeInactive = notifications.transitions.size();
    model.setTimeSelection(inactive);
    QVERIFY((model.noteSelection() == std::vector<NoteId>{NoteId{19}}));
    QVERIFY(!model.timeSelection().active());
    QCOMPARE(notifications.transitions.size(), beforeInactive);

    model.clearNoteSelection();
    QVERIFY(received(notifications, beforeInactive, kNoteSelection));
    const size_t beforeClearEmptyTime = notifications.transitions.size();
    model.clearTimeSelection();
    QCOMPARE(notifications.transitions.size(), beforeClearEmptyTime);

    model.setTimeSelection(time);
    const size_t beforeClearTime = notifications.transitions.size();
    model.clearTimeSelection();
    QVERIFY(!model.timeSelection().active());
    QVERIFY(model.noteSelection().empty());
    QVERIFY(received(notifications, beforeClearTime, kTimeSelection));
}

void SelectionCheckTest::timeSelectionAndScopeCommitAtomically()
{
    EditorSelectionModel model;
    model.applyPrimaryTrackTransition(3);
    NotificationLog notifications;
    notifications.attach(model);

    EditorSelectionModel::TimeSelection selection;
    selection.startTick = 40;
    selection.endTick = 80;
    model.setTimeSelectionAndTrackScope(selection, trackBit(1) | trackBit(20));
    QCOMPARE(model.timeSelection().startTick, uint64_t{40});
    QCOMPARE(model.timeSelection().endTick, uint64_t{80});
    QCOMPARE(model.storedTrackScope(), trackBit(1) | trackBit(3));
    QVERIFY(received(notifications, 0, kTrackScope | kTimeSelection));
    const auto &first = notifications.transitions.back();
    QCOMPARE(first.previousTrackTime.trackScope, uint32_t{0});
    QCOMPARE(first.trackTime.startTick, uint64_t{40});
    QCOMPARE(first.trackTime.endTick, uint64_t{80});
    QCOMPARE(first.trackTime.trackScope, trackBit(1) | trackBit(3));

    model.setNoteSelection({NoteId{23}});
    notifications.clear();
    selection.startTick = 50;
    selection.endTick = 90;
    model.setTimeSelectionAndTrackScope(selection, trackBit(2));
    QVERIFY(model.noteSelection().empty());
    QCOMPARE(model.storedTrackScope(), trackBit(2) | trackBit(3));
    QCOMPARE(model.timeSelection().startTick, uint64_t{50});
    QCOMPARE(model.timeSelection().endTick, uint64_t{90});
    QVERIFY(received(notifications, 0, kTrackScope | kNoteSelection | kTimeSelection));
    const auto &second = notifications.transitions.back();
    QCOMPARE(second.previousTrackTime.trackScope, uint32_t{0});
    QCOMPARE(second.trackTime.startTick, uint64_t{50});
    QCOMPARE(second.trackTime.endTick, uint64_t{90});
    QCOMPARE(second.trackTime.trackScope, trackBit(2) | trackBit(3));

    const size_t beforeNoOp = notifications.transitions.size();
    model.setTimeSelectionAndTrackScope(selection, trackBit(2) | trackBit(3));
    QCOMPARE(notifications.transitions.size(), beforeNoOp);
}

void SelectionCheckTest::clearOperationsPreserveTheOtherSelection()
{
    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);

    EditorSelectionModel::TimeSelection time;
    time.startTick = 5;
    time.endTick = 10;
    model.setTimeSelection(time);
    notifications.clear();
    model.clearNoteSelection();
    QVERIFY(model.timeSelection().active());
    QVERIFY(notifications.transitions.empty());

    model.clearTimeSelection();
    model.setNoteSelection({NoteId{81}});
    notifications.clear();
    model.clearNoteSelection();
    QVERIFY(model.noteSelection().empty());
    QVERIFY(received(notifications, 0, kNoteSelection));
    const size_t beforeRepeatedClear = notifications.transitions.size();
    model.clearNoteSelection();
    QCOMPARE(notifications.transitions.size(), beforeRepeatedClear);
}

void SelectionCheckTest::reconciliationPreservesSelectionOrder()
{
    EditorSelectionModel model;
    NotificationLog notifications;
    notifications.attach(model);
    model.setNoteSelection({NoteId{1}, NoteId{2}, NoteId{3}});
    notifications.clear();

    const std::vector<NoteId> valid = {NoteId{3}, NoteId{1}, NoteId{4}, NoteId{1}};
    model.reconcileNoteSelection(std::span<const NoteId>{valid});
    QVERIFY((model.noteSelection() == std::vector<NoteId>{NoteId{1}, NoteId{3}}));
    QVERIFY(received(notifications, 0, kNoteSelection));

    const size_t beforeSame = notifications.transitions.size();
    const std::vector<NoteId> sameValid = {NoteId{3}, NoteId{1}, NoteId{3}};
    model.reconcileNoteSelection(std::span<const NoteId>{sameValid});
    QCOMPARE(notifications.transitions.size(), beforeSame);

    model.reconcileNoteSelection(std::span<const NoteId>{});
    QVERIFY(model.noteSelection().empty());
    QVERIFY(received(notifications, beforeSame, kNoteSelection));
}

} // namespace checks::clipboard

int runSelectionCheck(const QStringList &qtArguments)
{
    checks::clipboard::SelectionCheckTest test;
    QStringList arguments{QStringLiteral("selectioncheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
