#pragma once

#include <QByteArray>
#include <QString>
#include <cstdint>
#include <optional>
#include <vector>

#include "core/songdocument.h"
#include "ui/curvegraph/editablecurvegraph.hpp"
#include "ui/songview.h"

namespace pitchenvelopecheck {

struct PitchEnvelopeProjection {
    DocNote note;
    uint64_t endTick = 0;
    uint64_t windowEndTick = 0;
    int bendRange = 2;
};

struct PitchEnvelopePersistenceInput {
    SongDocument &document;
    SongView &view;
    const LoadedVoiceGroup &voicegroup;
    songview::EditableCurveGraph &graph;
    std::vector<songview::CurvePoint> authoredCurve;
    DocNote templateSource;
    std::vector<PitchEnvelopeProjection> fullProjections;
    uint64_t sameTickProjectionTick = 0;
    PitchEnvelopeProjection clippedProjection;
    DocNote clippingNote;
    int track = -1;
    uint64_t expectedEndTick = 0;
    uint64_t targetEndSample = 0;
    uint64_t playableGridSamples = 0;
    uint64_t authoredGridTicks = 0;
    uint64_t preservedGapTick = 0;
    int preservedGapValue = 0;
    uint64_t postSpanTick = 0;
    int postSpanValue = 0;
    QByteArray beforeCurve;
    int undoIndex = 0;
    const QString &songLabel;
};

struct PitchEnvelopePersistenceResult {
    int failures = 0;
    std::vector<DocLanePoint> committedBends;
    std::vector<songview::CurvePoint> committedCurve;
};

PitchEnvelopePersistenceResult
verifyPitchEnvelopePersistence(const PitchEnvelopePersistenceInput &input);

} // namespace pitchenvelopecheck
