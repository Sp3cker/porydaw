#include "checks/rollcheck/rollcheck.h"
#include "checks/rollcheck/tst_pianoroll.h"

#include <QByteArray>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QSize>
#include <QtTest>

#include <algorithm>
#include <cmath>
#include <memory>
#include <utility>
#include <vector>

#include "checks/support/songfixture.h"
#include "checks/support/support.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songviewmodel.h"

void PianoRollTest::noteIdentityEditDiscipline()
{
    QString error;
    const std::unique_ptr<checks::LoadedSong> source =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(source, qPrintable(error));

    SongDocument projectionDoc;
    QString projectionError;
    if (!projectionDoc.load(source->songInfo(), &projectionError)) {
        QFAIL("could not load note identity projection fixture");
    }

    const int track = m_fixture->track();
    const std::vector<DocNote> before = projectionDoc.notesForTrack(track);
    const Tick tick = projectionDoc.buildTimeline(48000.0)->lengthTicks + 48;
    projectionDoc.addNotes(track, {{tick, 60, 24, 100}, {tick, 64, 24, 100}});
    const std::vector<DocNote> after = projectionDoc.notesForTrack(track);
    std::vector<DocNote> inserted;
    for (const DocNote &candidate : after) {
        const bool existed =
            std::any_of(before.begin(), before.end(), [&](const DocNote &previous) {
                return previous.noteId == candidate.noteId;
            });
        if (!existed)
            inserted.push_back(candidate);
    }
    if (inserted.size() != 2 || !inserted[0].noteId.isAssigned() ||
        !inserted[1].noteId.isAssigned() || inserted[0].noteId == inserted[1].noteId ||
        inserted[0].tick != inserted[1].tick || inserted[0].key == inserted[1].key) {
        QFAIL("document did not mint distinct IDs for same-tick different-key notes");
    }

    SongView identityView(projectionDoc);
    auto identityTimeline = projectionDoc.buildTimeline(48000.0);
    songview::TimelineQuickView *const identityQuick = identityView.quickView();
    QVERIFY(identityQuick && identityQuick->quickWindow());
    identityQuick->quickWindow()->resize(QSize(800, 480));
    identityView.setSong(identityTimeline.get(), nullptr);
    checks::support::bindEditActionsForTest(identityView);
    QObject::connect(&projectionDoc, &SongDocument::documentChanged, &identityView, [&] {
        auto rebuilt = projectionDoc.buildTimeline(48000.0);
        identityView.updateSong(rebuilt.get());
        identityTimeline = std::move(rebuilt);
    });
    identityView.selectTrack(track);
    identityView.selectionModel().setNoteSelection({inserted[0].noteId, inserted[1].noteId});
    identityView.trackHeaderClicked(track, Qt::NoModifier);
    if (!identityView.selectionModel().noteSelection().empty())
        QFAIL("plain click on the active track header did not clear note selection");

    const DocNote firstBefore = inserted[0];
    const DocNote secondBefore = inserted[1];
    const auto sameNoteIdentityAndValue = [](const DocNote &lhs, const DocNote &rhs) {
        return lhs.noteId == rhs.noteId && lhs.engineTrack == rhs.engineTrack &&
               lhs.smfTrack == rhs.smfTrack && lhs.tick == rhs.tick &&
               lhs.duration == rhs.duration && lhs.key == rhs.key && lhs.velocity == rhs.velocity &&
               lhs.channel == rhs.channel;
    };
    identityView.selectionModel().setNoteSelection({firstBefore.noteId});
    projectionDoc.moveNotes({firstBefore}, 0, 1);
    DocNote firstMoved;
    DocNote secondUntouched;
    DocNote expectedMoved = firstBefore;
    expectedMoved.key++;
    const bool firstEdit = projectionDoc.findNote(firstBefore.noteId, &firstMoved) &&
                           sameNoteIdentityAndValue(firstMoved, expectedMoved);
    const bool secondStable = projectionDoc.findNote(secondBefore.noteId, &secondUntouched) &&
                              sameNoteIdentityAndValue(secondUntouched, secondBefore);
    const std::vector<NoteId> &editedSelection = identityView.selectionModel().noteSelection();
    if (!firstEdit || !secondStable || editedSelection.size() != 1 ||
        editedSelection.front() != firstBefore.noteId) {
        QFAIL("one-ID edit changed the wrong note or lost selection");
    }

    projectionDoc.undoStack()->undo();
    DocNote firstRestored;
    DocNote secondRestored;
    const bool undoRestored = projectionDoc.findNote(firstBefore.noteId, &firstRestored) &&
                              projectionDoc.findNote(secondBefore.noteId, &secondRestored) &&
                              sameNoteIdentityAndValue(firstRestored, firstBefore) &&
                              sameNoteIdentityAndValue(secondRestored, secondBefore);
    const std::vector<NoteId> &undoSelection = identityView.selectionModel().noteSelection();
    if (!undoRestored || undoSelection.size() != 1 || undoSelection.front() != firstBefore.noteId) {
        QFAIL("one-ID SongView edit did not restore both notes on Undo");
    }

    identityView.selectionModel().setNoteSelection({inserted[0].noteId, inserted[1].noteId});
    const int otherTrack = track == 0 ? 1 : 0;
    if (otherTrack < projectionDoc.engineTrackCount()) {
        identityView.trackHeaderClicked(otherTrack, Qt::NoModifier);
        if (!identityView.selectionModel().noteSelection().empty())
            QFAIL("switching track headers did not clear note selection");
    }

    // Ordinary note-selection arrows must not reveal or audition a refused
    // destination. Exercise both directions with an offscreen destination,
    // then remove the blocker and repeat the identical key route.
    checks::rollcheck::PianoRollFixture &check = *m_fixture;
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const checks::rollcheck::SnappedRows rows{view, check.rollInput()};
    for (const int direction : {1, -1}) {
        const Tick start = check.timeline().lengthTicks + 48;
        const int destinationKey = 60 + direction;
        doc.addNotes(track, {{start, 60, 24, 100}, {start, uint8_t(destinationKey), 24, 100}});
        DocNote participant;
        DocNote blocker;
        QVERIFY(doc.findNote(track, start, 60, &participant));
        QVERIFY(doc.findNote(track, start, uint8_t(destinationKey), &blocker));
        view.selectionModel().setNoteSelection({participant.noteId});
        QVERIFY(!view.selectionModel().timeSelection().active());
        view.scrollRollBy((129 - destinationKey) * view.camera().keyHeight() -
                          view.camera().scrollY());
        QVERIFY(rows.bottom(destinationKey) <= 0.0);
        const QByteArray refusedBytes = doc.smf().write();
        const uint64_t refusedRevision = doc.revision();
        const int refusedIndex = doc.undoStack()->index();
        const int refusedCount = doc.undoStack()->count();
        const bool refusedRedo = doc.undoStack()->canRedo();
        const auto selected = view.selectionModel().noteSelection();
        const Tick cursor = view.editCursorTick();
        const double scrollX = view.camera().scrollX();
        const double scrollY = view.camera().scrollY();
        QSignalSpy publications(&doc, &SongDocument::documentChanged);
        QSignalSpy auditions(&view, &SongView::auditionNote);
        const int key = direction > 0 ? Qt::Key_Up : Qt::Key_Down;
        checks::rollcheck::sendKeyStroke(check.rollInput(), key, Qt::NoModifier, false);
        QCOMPARE(doc.smf().write(), refusedBytes);
        QCOMPARE(doc.revision(), refusedRevision);
        QCOMPARE(doc.undoStack()->index(), refusedIndex);
        QCOMPARE(doc.undoStack()->count(), refusedCount);
        QCOMPARE(doc.undoStack()->canRedo(), refusedRedo);
        QVERIFY(view.selectionModel().noteSelection() == selected);
        QVERIFY(!view.selectionModel().timeSelection().active());
        QCOMPARE(view.editCursorTick(), cursor);
        QCOMPARE(view.camera().scrollX(), scrollX);
        QCOMPARE(view.camera().scrollY(), scrollY);
        QCOMPARE(publications.count(), 0);
        for (const auto &audition : std::as_const(auditions))
            QVERIFY(audition.at(2).toInt() <= 0);

        doc.deleteNotes({blocker});
        const QByteArray acceptedBytes = doc.smf().write();
        const uint64_t acceptedRevision = doc.revision();
        const int acceptedIndex = doc.undoStack()->index();
        const int acceptedCount = doc.undoStack()->count();
        publications.clear();
        auditions.clear();
        checks::rollcheck::sendKeyStroke(check.rollInput(), key, Qt::NoModifier, false);
        DocNote transposed;
        QVERIFY(doc.findNote(participant.noteId, &transposed));
        DocNote expected = participant;
        expected.key = uint8_t(destinationKey);
        QVERIFY(sameNoteIdentityAndValue(transposed, expected));
        QCOMPARE(doc.revision(), acceptedRevision + 1);
        QCOMPARE(publications.count(), 1);
        QCOMPARE(doc.undoStack()->index(), acceptedIndex + 1);
        QCOMPARE(doc.undoStack()->count(), acceptedCount + 1);
        QVERIFY(view.selectionModel().noteSelection() == selected);
        QVERIFY(!view.selectionModel().timeSelection().active());
        QVERIFY(rows.top(destinationKey) >= 0.0);
        QVERIFY(rows.bottom(destinationKey) <= check.rollInput().bounds().height());
        QVERIFY(view.camera().scrollY() != scrollY);
        int positiveAuditions = 0;
        for (const auto &audition : std::as_const(auditions)) {
            if (audition.at(2).toInt() <= 0)
                continue;
            ++positiveAuditions;
            QCOMPARE(audition.at(0).toInt(), track);
            QCOMPARE(audition.at(1).toInt(), destinationKey);
            QCOMPARE(audition.at(2).toInt(), int(participant.velocity));
        }
        QCOMPARE(positiveAuditions, 1);
        doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), acceptedBytes);
        QCOMPARE(doc.undoStack()->index(), acceptedIndex);
        QVERIFY(doc.findNote(participant.noteId, &transposed));
        QVERIFY(sameNoteIdentityAndValue(transposed, participant));
        QVERIFY(view.selectionModel().noteSelection() == selected);
    }
}

void PianoRollTest::timelineProjection()
{
    MidiTimeline ordinaryTimeline;
    ordinaryTimeline.lengthTicks = 288;
    ordinaryTimeline.events = {
        {0, 240, 0x9, 2, 65, 83, NoteId{}},
        {0, 288, 0x8, 2, 65, 0, NoteId{}},
    };
    const SongViewModel ordinary = buildSongViewModel(ordinaryTimeline);
    if (ordinary.notes.size() != 1) {
        QFAIL("ordinary unassigned timeline note did not project");
    }

    const ViewNote &note = ordinary.notes.front();
    if (note.noteId.isAssigned() || note.startTick != 240 || note.endTick() != 288 ||
        note.key != 65 || note.velocity != 83 || note.track != 2) {
        QFAIL("ordinary unassigned timeline note changed during projection");
    }
}

void PianoRollTest::viewStateRoundTrip()
{
    SongView &view = m_fixture->view();
    songview::TimelineInputItem &rollInput = m_fixture->rollInput();
    const SongView::ViewState before = view.viewState();
    const int track = m_fixture->track();
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, uint8_t(track), 7};
    EditorViewState cosmetics;
    cosmetics.laneHeight = 64;
    cosmetics.laneHeights.emplace(lane, 96);
    cosmetics.laneRanges.emplace(lane, 91);
    cosmetics.emptyLanes.emplace(lane);
    view.applyEditorViewState(cosmetics);
    if (view.editorViewState() != cosmetics)
        QFAIL("SongView did not retain typed cosmetic EditorViewState");

    view.setEditCursorTick(view.grid().snapTick(96.0));
    const SongView::ViewState snapshot = view.viewState();
    SongView::ViewState perturbed = snapshot;
    perturbed.pxPerBeat = snapshot.pxPerBeat < 64.0 ? 64.0 : 16.0;
    perturbed.keyHeight = snapshot.keyHeight < 16.0 ? 16.0 : 8.0;
    perturbed.scrollPx = snapshot.scrollPx == 0.0 ? 1.0 : 0.0;
    perturbed.scrollY = snapshot.scrollY == 0.0 ? 1.0 : 0.0;
    int alternateTrack = snapshot.selectedTrack;
    for (int candidate = 0; candidate < 16; ++candidate) {
        if (candidate != snapshot.selectedTrack && m_fixture->timeline().tracks[candidate].used) {
            alternateTrack = candidate;
            break;
        }
    }
    perturbed.selectedTrack = alternateTrack;
    perturbed.editCursorTick = snapshot.editCursorTick == 0 ? 1 : 0;
    perturbed.gridSelection = snapshot.gridSelection == songview::GridSelection::musical(4)
                                  ? songview::GridSelection::musical(8)
                                  : songview::GridSelection::musical(4);
    perturbed.gridTriplet = !snapshot.gridTriplet;
    perturbed.eventList = !snapshot.eventList;
    SongView::ViewState expected = perturbed;
    expected.pxPerBeat = std::clamp(perturbed.pxPerBeat, 4.0, 640.0);
    expected.keyHeight = std::clamp(perturbed.keyHeight, 4.0, 32.0);
    const double tpb = double(m_fixture->timeline().ticksPerBeat);
    const double maxHScroll =
        std::max(0.0, double(m_fixture->timeline().lengthTicks) * expected.pxPerBeat / tpb + 100.0 -
                          std::max<qreal>(50, rollInput.width()));
    expected.scrollPx = std::clamp(perturbed.scrollPx, 0.0, maxHScroll);
    const double maxRollScroll = std::max(0.0, 128.0 * expected.keyHeight - rollInput.height());
    expected.scrollY = std::clamp(perturbed.scrollY, 0.0, maxRollScroll);
    expected.selectedTrack = snapshot.selectedTrack;
    if (perturbed.selectedTrack >= 0 && perturbed.selectedTrack < 16 &&
        m_fixture->timeline().tracks[perturbed.selectedTrack].used) {
        expected.selectedTrack = perturbed.selectedTrack;
    }
    expected.editCursorTick = std::min(perturbed.editCursorTick, m_fixture->timeline().lengthTicks);
    expected.gridSelection = perturbed.gridSelection;
    view.applyViewState(perturbed);
    const SongView::ViewState applied = view.viewState();
    const auto sameViewState = [](const SongView::ViewState &lhs, const SongView::ViewState &rhs) {
        return lhs.valid == rhs.valid && std::abs(lhs.pxPerBeat - rhs.pxPerBeat) <= 1e-12 &&
               std::abs(lhs.keyHeight - rhs.keyHeight) <= 1e-12 &&
               std::abs(lhs.scrollPx - rhs.scrollPx) <= 1e-12 &&
               std::abs(lhs.scrollY - rhs.scrollY) <= 1e-12 &&
               lhs.selectedTrack == rhs.selectedTrack && lhs.editCursorTick == rhs.editCursorTick &&
               lhs.gridSelection == rhs.gridSelection && lhs.gridTriplet == rhs.gridTriplet &&
               lhs.eventList == rhs.eventList;
    };
    const auto differs = [](double lhs, double rhs) { return std::abs(lhs - rhs) > 1e-12; };
    if (!differs(expected.pxPerBeat, snapshot.pxPerBeat) ||
        !differs(expected.keyHeight, snapshot.keyHeight) ||
        !differs(expected.scrollPx, snapshot.scrollPx) ||
        !differs(expected.scrollY, snapshot.scrollY) ||
        expected.selectedTrack == snapshot.selectedTrack ||
        expected.editCursorTick == snapshot.editCursorTick ||
        expected.gridSelection == snapshot.gridSelection ||
        expected.gridTriplet == snapshot.gridTriplet || expected.eventList == snapshot.eventList) {
        QFAIL("ViewState perturbation did not change every retained field");
    }
    if (!sameViewState(applied, expected))
        QFAIL("ViewState apply did not retain every normalized perturbed field");

    view.applyViewState(snapshot);
    const SongView::ViewState restored = view.viewState();
    if (view.editorViewState() != cosmetics || !sameViewState(restored, snapshot))
        QFAIL("ViewState capture/apply did not restore runtime state without changing cosmetics");

    view.applyViewState(before);
}
