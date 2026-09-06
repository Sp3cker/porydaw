#pragma once

#include <QTemporaryDir>

#include <cstdint>
#include <memory>

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
bool hasLiveTempo(const SongDocument &document);
bool sameNotes(const std::vector<DocNote> &left, const std::vector<DocNote> &right);
bool findsTimeSig(const SongDocument &document, uint64_t tick, DocTimeSig *out);

int firstEditableTrack(const SongDocument &document);
uint64_t distantBase(const SongDocument &document);

} // namespace songdocument_test
