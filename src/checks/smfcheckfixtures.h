#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

class QTemporaryDir;
class QString;
class SongDocument;
struct DocNote;
struct SmfFile;

namespace SmfCheck {

bool loadDocument(const SmfFile &smf, const QTemporaryDir &dir, const char *name, SongDocument *doc,
                  QString *error);
int engineTrackForChunk(const SongDocument &doc, int chunk);
int checkNote(const std::vector<DocNote> &notes, size_t n, size_t onIndex, size_t endIndex,
              uint32_t duration, uint8_t key, uint8_t velocity, uint8_t channel);

} // namespace SmfCheck

int runSmfFixtureChecks(const QTemporaryDir &dir, bool includeStress);
