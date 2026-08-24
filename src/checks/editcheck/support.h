#pragma once

#include <QString>

#include <cstdint>

#include "core/songdocument.h"
#include "project/decompproject.h"

namespace editcheck {

bool tracksSorted(const SmfFile &smf);
TempoPoint tempoPoint(uint64_t tick, uint32_t bpm);
bool containsTempoPoint(const SongDocument &doc, const TempoPoint &point);

struct SongEditScenario {
    SongDocument &doc;
    const QString &songLabel;
    int track;
    uint64_t base;
    uint32_t step;
    int &failures;

    void fail(const char *what) const;
    bool checkSorted(const char *what) const;
};

int documentContractFailures();
int documentPublicationTempoVelocityRemapFailures();
int documentTrackDuplicationOwnershipFailures();
int documentTrackGlobalMetadataFailures();
int documentMoveIdentityFailures();
int documentMovePublicationFailures();
int timeRangeContractFailures();
int format0ConvertFailures();
int markerVsNameFailures();
int sameTickDuplicateFailures();

bool checkSongNoteEdits(SongEditScenario &scenario);
void checkSongRawEventContracts(SongEditScenario &scenario);
bool checkSongRangeEdits(SongEditScenario &scenario);
bool checkSongNoteMoveContracts(SongEditScenario &scenario);
bool checkSongTimeRangeAndAutomation(SongEditScenario &scenario);
bool checkSongTrackAndSongContracts(SongEditScenario &scenario);

void runSongRoundTrip(const SongInfo &song, int &checked, int &failures);

} // namespace editcheck
