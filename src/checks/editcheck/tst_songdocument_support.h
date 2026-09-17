#pragma once

#include <QByteArray>
#include <QTemporaryDir>

#include <cstdint>
#include <memory>
#include <vector>

#include "core/songdocument.h"

namespace songdocument_test {

struct SyntheticDocument final {
    QTemporaryDir directory;
    SongInfo song;
    SongDocument document;
    QString error;

    bool stage(SmfFile smf, const QString &label = QStringLiteral("songdocument"));
};

std::unique_ptr<SyntheticDocument>
makeDocument(SmfFile smf, const QString &label = QStringLiteral("songdocument"));

SmfEvent channel(uint8_t status, uint64_t tick, uint8_t data0, uint8_t data1);
SmfEvent meta(uint8_t type, uint64_t tick, const QByteArray &blob);
SmfTrack conductor();
TempoPoint tempo(uint64_t tick, uint32_t bpm);
bool containsTempo(const SongDocument &document, const TempoPoint &point);
bool tracksSorted(const SmfFile &smf);
bool noteEndsBeforeOnsAt(const SongDocument &document, int engineTrack, uint64_t tick);
bool notePairsConsistent(const SongDocument &document, int engineTrack);
bool hasLiveTempo(const SongDocument &document);
bool sameNotes(const std::vector<DocNote> &left, const std::vector<DocNote> &right);

// Snapshot of every observable a rejected or no-op edit must leave untouched.
struct SavedDocState {
    QByteArray bytes;
    uint64_t revision = 0;
    uint64_t saveStateToken = 0;
    int undoCount = 0;
    int undoIndex = 0;
    bool undoClean = false;
    bool canRedo = false;
    int engineTrackCount = 0;
    std::vector<TempoPoint> tempos;
    std::vector<DocNote> notes;
};

SavedDocState captureDocState(SongDocument &document, int engineTrack = 0);
// Empty when the live document still matches saved; otherwise names the first
// differing field. Note comparison covers noteId and velocity per note.
QString docStateMismatch(SongDocument &document, const SavedDocState &saved, int engineTrack = 0);
bool findsTimeSig(const SongDocument &document, uint64_t tick, DocTimeSig *out);

int firstEditableTrack(const SongDocument &document);
uint64_t distantBase(const SongDocument &document);

} // namespace songdocument_test
