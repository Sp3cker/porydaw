#include <QtTest>

#include <bit>
#include <memory>
#include <utility>
#include <vector>

#include "checks/support/songfixture.h"
#include "commands_check.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/swiftgrid/intent_executor.h"
#include "ui/songview/quick/swiftgrid/swift_grid_document_feed.h"

namespace {

uint64_t tokenOf(const DocNote &note)
{
    return std::bit_cast<uint64_t>(note.noteId);
}

struct CommandFixture {
    std::unique_ptr<checks::LoadedSong> song;
    std::unique_ptr<checks::SongViewRig> rig;
    std::unique_ptr<SwiftGridDocumentFeed> feed;
    std::unique_ptr<SwiftGridIntentExecutor> executor;

    bool prepare(const QString &projectRoot, const QString &songLabel, QString &error)
    {
        song = checks::LoadedSong::load(projectRoot, songLabel, error);
        if (!song)
            return false;
        rig = checks::SongViewRig::create(std::move(song), 48000.0, error);
        if (!rig)
            return false;
        feed = std::make_unique<SwiftGridDocumentFeed>(rig->document());
        executor = std::make_unique<SwiftGridIntentExecutor>(rig->view(), feed->documentId());
        return true;
    }

    SongDocument &document() { return rig->document(); }
    SongView &view() { return rig->view(); }
    uint64_t documentId() const { return feed->documentId(); }
};

struct Capture {
    int deliveries = 0;
    SgdDocumentHeader header{};
    std::vector<SgdNote> notes;

    static void receive(const SgdDocumentHeader *incomingHeader, const SgdNote *incomingNotes,
                        const SgdTimeSignature *, void *context)
    {
        auto &capture = *static_cast<Capture *>(context);
        ++capture.deliveries;
        capture.header = *incomingHeader;
        capture.notes.clear();
        if (incomingNotes && incomingHeader->noteCount > 0)
            capture.notes.assign(incomingNotes, incomingNotes + incomingHeader->noteCount);
    }
};

SgcResult dummyExecute(const SgcIntentCommand *, SgcOutcome *outcome, void *context)
{
    ++*static_cast<int *>(context);
    if (outcome) {
        outcome->result = SGC_EXECUTED;
        outcome->noteId = 77;
    }
    return SGC_EXECUTED;
}

void expectSubmit(const SgcIntentCommand &command, SgcResult expected,
                  SgcOutcome *outcome = nullptr)
{
    SgcOutcome local{};
    QCOMPARE(sgc_submit(&command, &local), expected);
    QCOMPARE(local.result, expected);
    if (outcome)
        *outcome = local;
}

SgcIntentCommand noteCommand(uint64_t documentId, SgcIntent intent, uint64_t noteId)
{
    SgcIntentCommand command{};
    command.documentId = documentId;
    command.intent = intent;
    command.payload.noteMove.noteId = noteId;
    return command;
}

SgcIntentCommand trackCommand(uint64_t documentId, SgcIntent intent, int32_t track)
{
    SgcIntentCommand command{};
    command.documentId = documentId;
    command.intent = intent;
    command.payload.trackIndex.trackIndex = track;
    return command;
}

class SwiftCommandsTest final : public QObject
{
    Q_OBJECT

  public:
    SwiftCommandsTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void registryRoutingAndOutcomeContract()
    {
        SgcOutcome outcome{};
        QCOMPARE(sgc_submit(nullptr, &outcome), SGC_REJECTED_INVALID);
        QCOMPARE(outcome.result, SGC_REJECTED_INVALID);

        SgcIntentCommand command{};
        command.intent = SGC_SELECTION_CLEAR;
        expectSubmit(command, SGC_REJECTED_UNAVAILABLE);
        command.documentId = 424242;
        expectSubmit(command, SGC_REJECTED_UNAVAILABLE);

        {
            CommandFixture fixture;
            QString error;
            QVERIFY2(fixture.prepare(m_projectRoot, m_songLabel, error), qPrintable(error));
            const uint64_t id = fixture.documentId();

            command.documentId = id;
            outcome.noteId = 999;
            expectSubmit(command, SGC_EXECUTED, &outcome);
            QCOMPARE(outcome.noteId, uint64_t(0));

            int calls = 0;
            QVERIFY(!sgc_set_executor(id, dummyExecute, &calls));
            QVERIFY(!sgc_set_executor(id, nullptr, &calls));
            QVERIFY(!sgc_set_executor(id, dummyExecute, nullptr));
            QVERIFY(!sgc_set_executor(0, dummyExecute, &calls));

            sgc_clear_executor(id);
            expectSubmit(command, SGC_REJECTED_UNAVAILABLE);

            QVERIFY(sgc_set_executor(id, dummyExecute, &calls));
            expectSubmit(command, SGC_EXECUTED, &outcome);
            QCOMPARE(calls, 1);
            QCOMPARE(outcome.noteId, uint64_t(77));
            sgc_clear_executor(id);
            expectSubmit(command, SGC_REJECTED_UNAVAILABLE);
        }
        expectSubmit(command, SGC_REJECTED_UNAVAILABLE);
    }

    void noteIntentValidationAndUndoGranularity()
    {
        CommandFixture fixture;
        QString error;
        QVERIFY2(fixture.prepare(m_projectRoot, m_songLabel, error), qPrintable(error));
        SongDocument &document = fixture.document();
        QUndoStack *const undo = document.undoStack();
        const uint64_t id = fixture.documentId();

        const auto firstNotes = document.notesForTrack(0);
        QVERIFY(!firstNotes.empty());
        const DocNote first = firstNotes.front();
        const uint64_t token = tokenOf(first);
        const int baseUndo = undo->count();

        // Valid move: one undo entry, production clamp semantics.
        SgcIntentCommand command = noteCommand(id, SGC_NOTE_MOVE, token);
        command.payload.noteMove.deltaTicks = 96;
        command.payload.noteMove.deltaKeys = 0;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 1);
        DocNote moved;
        QVERIFY(document.findNote(NoteId{token}, &moved));
        QCOMPARE(moved.tick, first.tick + 96);

        // A zero-delta move is a well-formed no-op: executed, no undo entry.
        command.payload.noteMove.deltaTicks = 0;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 1);

        // Stale token and out-of-range delta reject without mutation.
        SgcIntentCommand stale = noteCommand(id, SGC_NOTE_MOVE, token + 100000);
        stale.payload.noteMove.deltaTicks = 1;
        expectSubmit(stale, SGC_REJECTED_INVALID);
        stale = noteCommand(id, SGC_NOTE_MOVE, token);
        stale.payload.noteMove.deltaTicks = int64_t(CoreTimeDefaults::kMaxTick) + 1;
        expectSubmit(stale, SGC_REJECTED_INVALID);
        QCOMPARE(undo->count(), baseUndo + 1);
        QVERIFY(document.findNote(NoteId{token}, &moved));
        QCOMPARE(moved.tick, first.tick + 96);

        // Valid resize: one undo entry.
        command = noteCommand(id, SGC_NOTE_RESIZE, token);
        command.payload.noteResize.durationTicks = first.duration + 24;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 2);
        QVERIFY(document.findNote(NoteId{token}, &moved));
        QCOMPARE(moved.duration, first.duration + 24);

        // Malformed resizes reject without mutation.
        command.payload.noteResize.durationTicks = 0;
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteResize.durationTicks = CoreTimeDefaults::kMaxTick;
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(undo->count(), baseUndo + 2);

        // Batch delete: one undo entry for the whole token list.
        std::vector<DocNote> batch;
        for (int track = 0; track < document.engineTrackCount() && batch.size() < 2; ++track) {
            const auto notes = document.notesForTrack(track);
            batch.insert(batch.end(), notes.begin(), notes.end());
        }
        QVERIFY(batch.size() >= 2);
        const uint64_t batchTokens[] = {tokenOf(batch[0]), tokenOf(batch[1])};
        command = noteCommand(id, SGC_NOTE_DELETE, 0);
        command.payload.noteList = {batchTokens, 2};
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 3);
        QVERIFY(!document.findNote(NoteId{batchTokens[0]}, &moved));
        QVERIFY(!document.findNote(NoteId{batchTokens[1]}, &moved));
        DocNote survivor{};
        for (int track = 0; track < document.engineTrackCount() && !survivor.noteId.isAssigned();
             ++track) {
            const auto notes = document.notesForTrack(track);
            if (!notes.empty())
                survivor = notes.front();
        }
        QVERIFY(survivor.noteId.isAssigned());
        // A stale member rejects the whole batch; nothing is deleted.
        const uint64_t mixedTokens[] = {tokenOf(survivor), token + 100000};
        command.payload.noteList = {mixedTokens, 2};
        expectSubmit(command, SGC_REJECTED_INVALID);
        QVERIFY(document.findNote(survivor.noteId, &moved));
        // Duplicate tokens are malformed.
        const uint64_t duplicateTokens[] = {tokenOf(survivor), tokenOf(survivor)};
        command.payload.noteList = {duplicateTokens, 2};
        expectSubmit(command, SGC_REJECTED_INVALID);
        QVERIFY(document.findNote(survivor.noteId, &moved));
        // Empty and null lists are malformed.
        command.payload.noteList = {batchTokens, 0};
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteList = {nullptr, 1};
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(undo->count(), baseUndo + 3);

        // Valid add: executed, outcome carries the minted token, one undo entry.
        command.documentId = id;
        command.intent = SGC_NOTE_ADD;
        command.payload.noteAdd = {0, 60, 0, 24, 90};
        SgcOutcome added{};
        expectSubmit(command, SGC_EXECUTED, &added);
        QVERIFY(added.noteId != 0);
        QCOMPARE(undo->count(), baseUndo + 4);
        QVERIFY(document.findNote(NoteId{added.noteId}, &moved));
        QCOMPARE(moved.key, uint8_t(60));
        QCOMPARE(moved.tick, Tick(0));
        QCOMPARE(moved.duration, uint32_t(24));
        QCOMPARE(moved.velocity, uint8_t(90));

        // Out-of-range fields reject without mutation.
        const int beforeInvalid = undo->count();
        command.payload.noteAdd = {-1, 60, 0, 24, 90};
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteAdd = {document.engineTrackCount(), 60, 0, 24, 90};
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteAdd = {0, 128, 0, 24, 90};
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteAdd = {0, 60, 0, 24, 0};
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteAdd = {0, 60, 0, 0, 90};
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.noteAdd = {0, 60, CoreTimeDefaults::kMaxTick, 1, 90};
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(undo->count(), beforeInvalid);
    }

    void trackIntentValidationAndRouting()
    {
        CommandFixture fixture;
        QString error;
        QVERIFY2(fixture.prepare(m_projectRoot, m_songLabel, error), qPrintable(error));
        SongDocument &document = fixture.document();
        SongView &view = fixture.view();
        QUndoStack *const undo = document.undoStack();
        const uint64_t id = fixture.documentId();
        const int tracks = document.engineTrackCount();
        QVERIFY(tracks >= 2);
        const int baseUndo = undo->count();

        // Add: one undo entry, appended engine slot, production selection follow.
        SgcIntentCommand command{};
        command.documentId = id;
        command.intent = SGC_TRACK_ADD;
        command.payload.trackAdd.voice = 40;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(document.engineTrackCount(), tracks + 1);
        QCOMPARE(undo->count(), baseUndo + 1);
        QCOMPARE(view.selectionModel().primaryTrack(), tracks);
        command.payload.trackAdd.voice = -1;
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.trackAdd.voice = 128;
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(document.engineTrackCount(), tracks + 1);

        // Duplicate: one undo entry, copy selected.
        command = trackCommand(id, SGC_TRACK_DUPLICATE, 0);
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(document.engineTrackCount(), tracks + 2);
        QCOMPARE(undo->count(), baseUndo + 2);
        QCOMPARE(view.selectionModel().primaryTrack(), tracks + 1);

        // Rename: one undo entry; the name anchors the reorder below.
        command = trackCommand(id, SGC_TRACK_RENAME, 0);
        const char name[] = "Bass";
        command.payload.trackRename.name = name;
        command.payload.trackRename.nameLength = 4;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 3);
        QCOMPARE(document.trackName(0), QStringLiteral("Bass"));

        // Reorder: one undo entry. Name-anchored like
        // tst_songdocument_metadata.cpp's moveTrack oracle: the chunk carries
        // its name to the target engine slot whatever the engine->chunk map.
        command = trackCommand(id, SGC_TRACK_REORDER, 0);
        command.payload.trackReorder.newIndex = 1;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 4);
        QCOMPARE(document.trackName(1), QStringLiteral("Bass"));
        // from == to is a well-formed no-op: production moveTrack returns
        // false and pushes nothing; the executor still reports the intent
        // executed since nothing needed to change.
        command = trackCommand(id, SGC_TRACK_REORDER, 1);
        command.payload.trackReorder.newIndex = 1;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(undo->count(), baseUndo + 4);
        QCOMPARE(document.trackName(1), QStringLiteral("Bass"));

        // Loop-marker and malformed names reject without mutation.
        command = trackCommand(id, SGC_TRACK_RENAME, 1);
        const char marker[] = "[";
        command.payload.trackRename.name = marker;
        command.payload.trackRename.nameLength = 1;
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.trackRename.name = nullptr;
        command.payload.trackRename.nameLength = 4;
        expectSubmit(command, SGC_REJECTED_INVALID);
        command.payload.trackRename.name = name;
        command.payload.trackRename.nameLength = -1;
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(document.trackName(1), QStringLiteral("Bass"));

        // Delete: one undo entry.
        command = trackCommand(id, SGC_TRACK_DELETE, document.engineTrackCount() - 1);
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(document.engineTrackCount(), tracks + 1);
        QCOMPARE(undo->count(), baseUndo + 5);

        // Out-of-range tracks reject without mutation.
        const int beforeInvalid = undo->count();
        command = trackCommand(id, SGC_TRACK_DUPLICATE, -1);
        expectSubmit(command, SGC_REJECTED_INVALID);
        command = trackCommand(id, SGC_TRACK_DUPLICATE, document.engineTrackCount());
        expectSubmit(command, SGC_REJECTED_INVALID);
        command = trackCommand(id, SGC_TRACK_DELETE, document.engineTrackCount());
        expectSubmit(command, SGC_REJECTED_INVALID);
        command = trackCommand(id, SGC_TRACK_REORDER, 0);
        command.payload.trackReorder.newIndex = document.engineTrackCount();
        expectSubmit(command, SGC_REJECTED_INVALID);
        command = trackCommand(id, SGC_TRACK_RENAME, document.engineTrackCount());
        command.payload.trackRename.name = name;
        command.payload.trackRename.nameLength = 4;
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(undo->count(), beforeInvalid);
    }

    void sessionIntentsLeaveUndoStackUntouched()
    {
        CommandFixture fixture;
        QString error;
        QVERIFY2(fixture.prepare(m_projectRoot, m_songLabel, error), qPrintable(error));
        SongDocument &document = fixture.document();
        SongView &view = fixture.view();
        QUndoStack *const undo = document.undoStack();
        const uint64_t id = fixture.documentId();
        const int baseUndo = undo->count();
        const uint64_t baseRevision = document.revision();

        const auto notes = document.notesForTrack(0);
        QVERIFY(!notes.empty());
        const uint64_t token = tokenOf(notes.front());

        SgcIntentCommand command = trackCommand(id, SGC_TRACK_MUTE, 2);
        command.payload.trackFlag.on = 1;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(view.muteMask(), uint32_t(1u << 2));
        command.intent = SGC_TRACK_SOLO;
        command.payload.trackFlag.trackIndex = 3;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(view.soloMask(), uint32_t(1u << 3));
        command.intent = SGC_TRACK_MUTE;
        command.payload.trackFlag.trackIndex = 2;
        command.payload.trackFlag.on = 0;
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(view.muteMask(), uint32_t(0));

        const uint64_t selection[] = {token};
        command = noteCommand(id, SGC_SELECTION_SET_NOTES, 0);
        command.payload.noteList = {selection, 1};
        expectSubmit(command, SGC_EXECUTED);
        QCOMPARE(view.selectionModel().noteSelection(), (std::vector<NoteId>{NoteId{token}}));
        command.intent = SGC_SELECTION_CLEAR;
        expectSubmit(command, SGC_EXECUTED);
        QVERIFY(view.selectionModel().noteSelection().empty());

        QCOMPARE(undo->count(), baseUndo);
        QCOMPARE(document.revision(), baseRevision);

        // Invalid session payloads reject without touching the masks.
        command = trackCommand(id, SGC_TRACK_MUTE, 16);
        command.payload.trackFlag.on = 1;
        expectSubmit(command, SGC_REJECTED_INVALID);
        command = trackCommand(id, SGC_TRACK_MUTE, 0);
        command.payload.trackFlag.on = 2;
        expectSubmit(command, SGC_REJECTED_INVALID);
        command = trackCommand(id, SGC_TRACK_SOLO, -1);
        command.payload.trackFlag.on = 1;
        expectSubmit(command, SGC_REJECTED_INVALID);
        const uint64_t staleSelection[] = {token + 100000};
        command = noteCommand(id, SGC_SELECTION_SET_NOTES, 0);
        command.payload.noteList = {staleSelection, 1};
        expectSubmit(command, SGC_REJECTED_INVALID);
        QCOMPARE(view.muteMask(), uint32_t(0));
        QCOMPARE(view.soloMask(), uint32_t(1u << 3));
        QVERIFY(view.selectionModel().noteSelection().empty());
        QCOMPARE(undo->count(), baseUndo);
        QCOMPARE(document.revision(), baseRevision);
    }

    void addRoundTripsThroughDocumentFeed()
    {
        CommandFixture fixture;
        QString error;
        QVERIFY2(fixture.prepare(m_projectRoot, m_songLabel, error), qPrintable(error));
        SongDocument &document = fixture.document();
        const uint64_t id = fixture.documentId();

        Capture capture;
        QVERIFY(sgd_set_delivery(id, Capture::receive, &capture));
        fixture.feed->pushSnapshot();
        QCOMPARE(capture.deliveries, 1);

        SgcIntentCommand command{};
        command.documentId = id;
        command.intent = SGC_NOTE_ADD;
        command.payload.noteAdd = {0, 72, 480, 96, 100};
        SgcOutcome outcome{};
        expectSubmit(command, SGC_EXECUTED, &outcome);
        QVERIFY(outcome.noteId != 0);

        // The documentChanged emission pushed a fresh snapshot synchronously.
        QCOMPARE(capture.deliveries, 2);
        QCOMPARE(capture.header.revision, document.revision());
        QCOMPARE(capture.header.documentId, id);
        bool found = false;
        for (const SgdNote &note : capture.notes) {
            if (note.trackIndex == 0 && note.key == 72 && note.onTick == 480 &&
                note.durationTicks == 96 && note.velocity == 100)
                found = true;
        }
        QVERIFY(found);
        DocNote added;
        QVERIFY(document.findNote(NoteId{outcome.noteId}, &added));
        QCOMPARE(added.key, uint8_t(72));
        sgd_clear_delivery(id);
    }

    void swiftSubmissionGuard()
    {
        CommandFixture fixture;
        QString error;
        QVERIFY2(fixture.prepare(m_projectRoot, m_songLabel, error), qPrintable(error));
        SongDocument &document = fixture.document();
        SongView &view = fixture.view();
        const int baseUndo = document.undoStack()->count();

        QCOMPARE(sgc_check_swift_submission(fixture.documentId()), int32_t(0));

        // The Swift-driven intents landed through the same executor.
        DocNote note;
        QVERIFY(document.findNote(0, 48, 62, &note));
        QCOMPARE(note.duration, uint32_t(96));
        QCOMPARE(document.trackName(0), QStringLiteral("Lead"));
        QCOMPARE(view.muteMask(), uint32_t(1u << 0));
        QCOMPARE(view.soloMask(), uint32_t(1u << 1));
        QVERIFY(view.selectionModel().noteSelection().empty());
        QCOMPARE(document.undoStack()->count(), baseUndo + 4);
    }

  private:
    QString m_projectRoot;
    QString m_songLabel;
};

} // namespace

int runSwiftCommandsCheck(const QString &projectRoot, const QString &songLabel,
                          const QStringList &qtArguments)
{
    SwiftCommandsTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("swiftcommands")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_swiftcommands.moc"
