#include "intent_executor.h"

#include <algorithm>
#include <bit>
#include <cstdlib>
#include <vector>

#include <QString>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "core/tracklimits.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace {

static_assert(sizeof(NoteId) == sizeof(uint64_t));

uint64_t noteToken(NoteId id)
{
    return std::bit_cast<uint64_t>(id);
}

bool trackInBounds(const SongDocument &document, int32_t track)
{
    return track >= 0 && track < document.engineTrackCount();
}

bool sessionTrackInBounds(int32_t track)
{
    return track >= 0 && track < track_limits::kHardwareCapacity;
}

bool resolveNote(const SongDocument &document, uint64_t token, DocNote *out)
{
    return document.findNote(NoteId{token}, out);
}

// Resolves a batch token list to live notes for one production batch call:
// non-empty, non-null, every token live, no duplicates. False leaves notes
// untouched and the caller rejects without mutating anything.
bool resolveNoteBatch(const SongDocument &document, const uint64_t *tokens, int32_t count,
                      std::vector<DocNote> &notes)
{
    if (count <= 0 || !tokens)
        return false;
    notes.clear();
    notes.reserve(size_t(count));
    for (int32_t i = 0; i < count; ++i) {
        DocNote note;
        if (!resolveNote(document, tokens[i], &note))
            return false;
        notes.push_back(note);
    }
    std::sort(notes.begin(), notes.end(),
              [](const DocNote &a, const DocNote &b) { return a.noteId < b.noteId; });
    if (std::adjacent_find(notes.begin(), notes.end(), [](const DocNote &a, const DocNote &b) {
            return a.noteId == b.noteId;
        }) != notes.end())
        return false;
    return true;
}

SgcResult reject(SgcOutcome &outcome, SgcResult result)
{
    outcome.result = result;
    return result;
}

} // namespace

SwiftGridIntentExecutor::SwiftGridIntentExecutor(SongView &view, uint64_t documentId)
    : m_view(view)
    , m_documentId(documentId)
{
    sgc_register_executor(m_documentId, &m_executor);
    if (!sgc_set_executor(m_documentId, &SwiftGridIntentExecutor::execute, this))
        std::abort();
}

SwiftGridIntentExecutor::~SwiftGridIntentExecutor()
{
    sgc_unregister_executor(m_documentId);
}

SgcResult SwiftGridIntentExecutor::execute(const SgcIntentCommand *command, SgcOutcome *outcome,
                                           void *context)
{
    SgcOutcome local{};
    if (!command || !context) {
        local.result = SGC_REJECTED_INVALID;
        if (outcome)
            *outcome = local;
        return SGC_REJECTED_INVALID;
    }
    auto &self = *static_cast<SwiftGridIntentExecutor *>(context);
    const SgcResult result = self.run(*command, local);
    if (outcome)
        *outcome = local;
    return result;
}

SgcResult SwiftGridIntentExecutor::run(const SgcIntentCommand &command, SgcOutcome &outcome) const
{
    SongDocument &document = m_view.document();
    switch (command.intent) {
    case SGC_NOTE_ADD: {
        const SgcNoteAdd &p = command.payload.noteAdd;
        if (!trackInBounds(document, p.trackIndex) || p.key < 0 || p.key > 127 || p.velocity < 1 ||
            p.velocity > 127 || p.durationTicks < 1 ||
            uint64_t(p.onTick) + p.durationTicks > CoreTimeDefaults::kMaxTick)
            return reject(outcome, SGC_REJECTED_INVALID);
        const std::vector<DocNote> before = document.notesForTrack(p.trackIndex);
        document.addNote(p.trackIndex, p.onTick, uint8_t(p.key), p.durationTicks,
                         uint8_t(p.velocity));
        const std::vector<NoteId> inserted = document.insertedNoteIds(p.trackIndex, before);
        // Validated args make addNote infallible (single well-formed span
        // always passes resolveNoteOverlaps); anything else is a bug, not a
        // rejection — a rejected intent must never have mutated.
        Q_ASSERT(inserted.size() == 1);
        outcome.result = SGC_EXECUTED;
        outcome.noteId = noteToken(inserted.front());
        return SGC_EXECUTED;
    }
    case SGC_NOTE_MOVE: {
        const SgcNoteMove &p = command.payload.noteMove;
        DocNote note;
        if (!resolveNote(document, p.noteId, &note) ||
            p.deltaTicks < -int64_t(CoreTimeDefaults::kMaxTick) ||
            p.deltaTicks > int64_t(CoreTimeDefaults::kMaxTick))
            return reject(outcome, SGC_REJECTED_INVALID);
        if (p.deltaTicks != 0 || p.deltaKeys != 0)
            document.moveNotes({note}, p.deltaTicks, p.deltaKeys);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_NOTE_RESIZE: {
        const SgcNoteResize &p = command.payload.noteResize;
        DocNote note;
        if (!resolveNote(document, p.noteId, &note) || p.durationTicks < 1 ||
            uint64_t(note.tick) + p.durationTicks > CoreTimeDefaults::kMaxTick)
            return reject(outcome, SGC_REJECTED_INVALID);
        const int64_t delta = int64_t(p.durationTicks) - int64_t(note.duration);
        if (delta != 0)
            document.resizeNotes({note}, delta);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_NOTE_MOVE_BATCH: {
        const SgcNoteMoveBatch &p = command.payload.noteMoveBatch;
        if (p.deltaTicks < -int64_t(CoreTimeDefaults::kMaxTick) ||
            p.deltaTicks > int64_t(CoreTimeDefaults::kMaxTick))
            return reject(outcome, SGC_REJECTED_INVALID);
        std::vector<DocNote> notes;
        if (!resolveNoteBatch(document, p.noteIds, p.count, notes))
            return reject(outcome, SGC_REJECTED_INVALID);
        if (p.deltaTicks != 0 || p.deltaKeys != 0)
            document.moveNotes(notes, p.deltaTicks, p.deltaKeys);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_NOTE_RESIZE_BATCH: {
        const SgcNoteResizeBatch &p = command.payload.noteResizeBatch;
        std::vector<DocNote> notes;
        if (!resolveNoteBatch(document, p.noteIds, p.count, notes))
            return reject(outcome, SGC_REJECTED_INVALID);
        // Per-note range checks mirroring the single resize over the implied
        // absolute durations; overlap/trim rules stay production-side.
        for (const DocNote &note : notes) {
            const int64_t duration = int64_t(note.duration) + p.dDuration;
            if (duration < 1 ||
                uint64_t(note.tick) + uint64_t(duration) > CoreTimeDefaults::kMaxTick)
                return reject(outcome, SGC_REJECTED_INVALID);
        }
        if (p.dDuration != 0)
            document.resizeNotes(notes, p.dDuration);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_NOTE_DELETE: {
        const SgcNoteList &p = command.payload.noteList;
        if (p.count <= 0 || !p.noteIds)
            return reject(outcome, SGC_REJECTED_INVALID);
        std::vector<DocNote> notes;
        notes.reserve(size_t(p.count));
        for (int32_t i = 0; i < p.count; ++i) {
            DocNote note;
            if (!resolveNote(document, p.noteIds[i], &note))
                return reject(outcome, SGC_REJECTED_INVALID);
            notes.push_back(note);
        }
        std::sort(notes.begin(), notes.end(),
                  [](const DocNote &a, const DocNote &b) { return a.noteId < b.noteId; });
        if (std::adjacent_find(notes.begin(), notes.end(), [](const DocNote &a, const DocNote &b) {
                return a.noteId == b.noteId;
            }) != notes.end())
            return reject(outcome, SGC_REJECTED_INVALID);
        document.deleteNotes(notes);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_TRACK_ADD: {
        const SgcTrackAdd &p = command.payload.trackAdd;
        if (p.voice < 0 || p.voice > 127)
            return reject(outcome, SGC_REJECTED_INVALID);
        if (!document.canAddTrack())
            return reject(outcome, SGC_REJECTED_UNAVAILABLE);
        const int track = document.addTrack(p.voice);
        if (track < 0)
            return reject(outcome, SGC_REJECTED_UNAVAILABLE);
        m_view.selectTrack(track);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_TRACK_DUPLICATE: {
        const SgcTrackIndex &p = command.payload.trackIndex;
        if (!trackInBounds(document, p.trackIndex))
            return reject(outcome, SGC_REJECTED_INVALID);
        if (!document.canAddTrack())
            return reject(outcome, SGC_REJECTED_UNAVAILABLE);
        const int copy = document.duplicateTrack(p.trackIndex);
        if (copy < 0)
            return reject(outcome, SGC_REJECTED_UNAVAILABLE);
        m_view.selectTrack(copy);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_TRACK_DELETE: {
        const SgcTrackIndex &p = command.payload.trackIndex;
        if (!trackInBounds(document, p.trackIndex))
            return reject(outcome, SGC_REJECTED_INVALID);
        m_view.deleteTrack(p.trackIndex);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_TRACK_REORDER: {
        const SgcTrackReorder &p = command.payload.trackReorder;
        if (!trackInBounds(document, p.trackIndex) || !trackInBounds(document, p.newIndex))
            return reject(outcome, SGC_REJECTED_INVALID);
        m_view.moveTrack(p.trackIndex, p.newIndex);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_TRACK_RENAME: {
        const SgcTrackRename &p = command.payload.trackRename;
        if (!trackInBounds(document, p.trackIndex) || p.nameLength < 0 ||
            (p.nameLength > 0 && !p.name))
            return reject(outcome, SGC_REJECTED_INVALID);
        const QString name = p.name ? QString::fromUtf8(p.name, p.nameLength) : QString();
        if (nameIsLoopMarker(name.trimmed()))
            return reject(outcome, SGC_REJECTED_INVALID);
        document.renameTrack(p.trackIndex, name);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_SELECTION_SET_NOTES: {
        const SgcNoteList &p = command.payload.noteList;
        if (p.count < 0 || (p.count > 0 && !p.noteIds))
            return reject(outcome, SGC_REJECTED_INVALID);
        std::vector<NoteId> ids;
        ids.reserve(size_t(p.count));
        for (int32_t i = 0; i < p.count; ++i) {
            DocNote note;
            if (!resolveNote(document, p.noteIds[i], &note))
                return reject(outcome, SGC_REJECTED_INVALID);
            ids.push_back(note.noteId);
        }
        m_view.selectionModel().setNoteSelection(std::move(ids));
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    case SGC_SELECTION_CLEAR:
        m_view.selectionModel().clearNoteSelection();
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    case SGC_TRACK_MUTE:
    case SGC_TRACK_SOLO: {
        const SgcTrackFlag &p = command.payload.trackFlag;
        if (!sessionTrackInBounds(p.trackIndex) || p.on > 1)
            return reject(outcome, SGC_REJECTED_INVALID);
        if (command.intent == SGC_TRACK_MUTE)
            m_view.setTrackMute(p.trackIndex, p.on != 0);
        else
            m_view.setTrackSolo(p.trackIndex, p.on != 0);
        outcome.result = SGC_EXECUTED;
        return SGC_EXECUTED;
    }
    }
    return reject(outcome, SGC_REJECTED_INVALID);
}
