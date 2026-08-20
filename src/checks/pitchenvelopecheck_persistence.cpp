#include "pitchenvelopecheck_persistence.hpp"

#include "ui/songview/pitchenvelopemapping.h"

#include <QCoreApplication>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdio>

namespace {
DocLanePoint expectedLanePoint(uint64_t tick, int value)
{
    DocLanePoint point;
    point.tick = tick;
    point.value = value;
    return point;
}

bool sameCurve(const std::vector<songview::CurvePoint> &lhs,
               const std::vector<songview::CurvePoint> &rhs)
{
    if (lhs.size() != rhs.size())
        return false;
    for (size_t i = 0; i < lhs.size(); i++) {
        if (std::abs(lhs[i].x - rhs[i].x) > 1e-9 || std::abs(lhs[i].y - rhs[i].y) > 1e-9)
            return false;
    }
    return true;
}

bool sameLane(const std::vector<DocLanePoint> &lhs, const std::vector<DocLanePoint> &rhs)
{
    if (lhs.size() != rhs.size())
        return false;
    for (size_t i = 0; i < lhs.size(); i++) {
        if (lhs[i].tick != rhs[i].tick || lhs[i].value != rhs[i].value)
            return false;
    }
    return true;
}

songview::EditableCurveGraph *graphFor(QWidget *host)
{
    auto *widget =
        host ? host->findChild<QWidget *>(QStringLiteral("pitchEnvelopeGraph")) : nullptr;
    return dynamic_cast<songview::EditableCurveGraph *>(widget);
}

std::vector<DocLanePoint> lanePointsInRange(const std::vector<DocLanePoint> &points,
                                            uint64_t startTick, uint64_t endTick)
{
    std::vector<DocLanePoint> result;
    for (const DocLanePoint &point : points) {
        if (point.tick >= startTick && point.tick <= endTick)
            result.push_back(point);
    }
    return result;
}

bool hasLanePoint(const std::vector<DocLanePoint> &points, uint64_t tick, int value)
{
    for (const DocLanePoint &point : points) {
        if (point.tick == tick && point.value == value)
            return true;
    }
    return false;
}

double linearCurveValue(const std::vector<songview::CurvePoint> &curve, double milliseconds)
{
    if (curve.empty() || milliseconds <= curve.front().x)
        return curve.empty() ? 0.0 : curve.front().y;
    for (size_t i = 1; i < curve.size(); i++) {
        if (milliseconds > curve[i].x)
            continue;
        const songview::CurvePoint &left = curve[i - 1];
        const songview::CurvePoint &right = curve[i];
        const double span = right.x - left.x;
        if (span <= 0.0)
            return right.y;
        const double fraction = (milliseconds - left.x) / span;
        return left.y + fraction * (right.y - left.y);
    }
    return curve.back().y;
}

std::vector<DocLanePoint>
expectedProjection(const SongView &view, const MidiTimeline *timeline,
                   const std::vector<songview::CurvePoint> &curve,
                   const pitchenvelopecheck::PitchEnvelopeProjection &projection)
{
    std::vector<DocLanePoint> result;
    result.push_back(expectedLanePoint(projection.note.tick, 0));
    const uint64_t span = projection.endTick - projection.note.tick;
    const uint64_t beatTicks =
        std::max<uint64_t>(1, view.gridSegAt(projection.note.tick).beatTicks);
    const auto offsetForBoundary = [beatTicks](uint64_t index) {
        return uint64_t((__uint128_t(index) * beatTicks + 8) / 16);
    };
    int previousEffective = 64;
    for (uint64_t index = 1;; index++) {
        const uint64_t offset = offsetForBoundary(index);
        if (offset >= span)
            break;
        const uint64_t tick = projection.note.tick + offset;
        const double milliseconds = std::clamp(
            songview::pitch_envelope::elapsedMilliseconds(timeline, projection.note.tick, tick),
            0.0, songview::pitch_envelope::kWindowMilliseconds);
        const int value = songview::pitch_envelope::semitonesToBend(
            linearCurveValue(curve, milliseconds), projection.bendRange);
        const int effective = (std::clamp(value, -8192, 8191) + 8192) >> 7;
        if (effective == previousEffective)
            continue;
        result.push_back(expectedLanePoint(tick, value));
        previousEffective = effective;
    }
    result.push_back(expectedLanePoint(projection.endTick, 0));
    return result;
}

bool fixedCadenceEscapesEditingGrid(const SongView &view,
                                    const pitchenvelopecheck::PitchEnvelopeProjection &projection,
                                    uint64_t editingGridTicks)
{
    if (editingGridTicks == 0 || projection.endTick <= projection.note.tick)
        return false;
    const uint64_t beatTicks =
        std::max<uint64_t>(1, view.gridSegAt(projection.note.tick).beatTicks);
    for (uint64_t index = 1;; index++) {
        const uint64_t offset = uint64_t((__uint128_t(index) * beatTicks + 8) / 16);
        if (offset >= projection.endTick - projection.note.tick)
            return false;
        const uint64_t tick = projection.note.tick + offset;
        const SongView::GridSeg segment = view.gridSegAt(tick);
        if (tick >= segment.start && (tick - segment.start) % editingGridTicks != 0)
            return true;
    }
}

} // namespace

namespace pitchenvelopecheck {

PitchEnvelopePersistenceResult
verifyPitchEnvelopePersistence(const PitchEnvelopePersistenceInput &input)
{
    PitchEnvelopePersistenceResult result;
    const auto fail = [&](const char *what) {
        std::fprintf(stderr, "rollcheck: FAIL %s: %s\n", qUtf8Printable(input.songLabel), what);
        result.failures++;
    };
    if (input.document.undoStack()->index() != input.undoIndex + 1)
        fail("track pitch-envelope gesture did not push exactly one undo command");
    const QByteArray committedBytes = input.document.smf().write();
    result.committedBends = input.document.lanePoints(input.track, DOC_CC_BEND);
    result.committedCurve = input.graph.points();
    const uint64_t endSample = input.view.timeline()->sampleForTick(input.expectedEndTick);
    const uint64_t endpointError = endSample > input.targetEndSample
                                       ? endSample - input.targetEndSample
                                       : input.targetEndSample - endSample;
    const bool zeroEndpoints = result.committedCurve.size() >= 2 &&
                               std::abs(result.committedCurve.front().y) <= 1e-9 &&
                               std::abs(result.committedCurve.back().y) <= 1e-9;
    if (!zeroEndpoints || endpointError > input.playableGridSamples)
        fail("track pitch-envelope gesture did not retain its 100ms zero-reset template");
    bool sawFixedCadenceOutsideEditingGrid = false;
    const auto inspectFixedSamples = [&](const std::vector<DocLanePoint> &points) {
        for (size_t i = 1; i + 1 < points.size(); i++) {
            const int previousEffective =
                (std::clamp(points[i - 1].value, -8192, 8191) + 8192) >> 7;
            const int effective = (std::clamp(points[i].value, -8192, 8191) + 8192) >> 7;
            if (effective == previousEffective)
                fail("pitch-envelope persistence retained consecutive equal M4A bend samples");
        }
    };
    for (const PitchEnvelopeProjection &projection : input.fullProjections) {
        const std::vector<DocLanePoint> expected =
            expectedProjection(input.view, input.view.timeline(), input.authoredCurve, projection);
        const std::vector<DocLanePoint> actual =
            lanePointsInRange(result.committedBends, projection.note.tick, projection.endTick);
        if (!sameLane(expected, actual)) {
            fail(
                projection.note.tick == input.sameTickProjectionTick
                    ? "same-tick eligible note-ons produced more than one pitch-envelope projection"
                    : "eligible note-on did not receive the fixed 1/64-note pitch-envelope "
                      "projection at its active BENDR");
        }
        inspectFixedSamples(actual);
        sawFixedCadenceOutsideEditingGrid =
            sawFixedCadenceOutsideEditingGrid ||
            fixedCadenceEscapesEditingGrid(input.view, projection, input.authoredGridTicks);
    }
    const std::vector<DocLanePoint> expectedClipped = expectedProjection(
        input.view, input.view.timeline(), input.authoredCurve, input.clippedProjection);
    const std::vector<DocLanePoint> actualClipped = lanePointsInRange(
        result.committedBends, input.clippedProjection.note.tick, input.clippedProjection.endTick);
    if (!sameLane(expectedClipped, actualClipped))
        fail("eligible note-on did not receive the template before the next note clipped it");
    inspectFixedSamples(actualClipped);
    sawFixedCadenceOutsideEditingGrid =
        sawFixedCadenceOutsideEditingGrid ||
        fixedCadenceEscapesEditingGrid(input.view, input.clippedProjection,
                                       input.authoredGridTicks);
    if (!sawFixedCadenceOutsideEditingGrid)
        fail("pitch-envelope fixture did not expose fixed 1/64 cadence beyond its editing grid");
    for (const DocLanePoint &point : result.committedBends) {
        if (point.tick > input.clippingNote.tick &&
            point.tick < input.fullProjections.back().note.tick && point.value != 0) {
            fail("ineligible note-on received a pitch-envelope projection");
            break;
        }
    }
    if (!hasLanePoint(result.committedBends, input.preservedGapTick, input.preservedGapValue))
        fail("track pitch-envelope gesture overwrote a bend in a gap between projections");
    if (!hasLanePoint(result.committedBends, input.postSpanTick, input.postSpanValue))
        fail("track pitch-envelope gesture overwrote a bend after the final projection");
    input.document.undoStack()->undo();
    if (input.document.undoStack()->index() != input.undoIndex ||
        input.document.smf().write() != input.beforeCurve) {
        fail("track pitch-envelope undo did not restore exact SMF bytes");
    }
    input.document.undoStack()->redo();
    if (input.document.undoStack()->index() != input.undoIndex + 1 ||
        input.document.smf().write() != committedBytes ||
        !sameLane(result.committedBends, input.document.lanePoints(input.track, DOC_CC_BEND))) {
        fail("track pitch-envelope redo did not restore exact SMF bend data");
    }

    const double originalSampleRate = input.view.timeline()->sampleRate;
    QString roundTripError;
    if (!input.document.save(&roundTripError)) {
        fail("track pitch-envelope document save failed");
    } else {
        SongInfo reloadedSong;
        reloadedSong.label = input.document.label();
        reloadedSong.midPath = input.document.midPath();
        reloadedSong.hasMid = true;
        reloadedSong.hasCfg = true;
        reloadedSong.cfg = input.document.cfg();
        SongDocument reloadedDocument;
        if (!reloadedDocument.load(reloadedSong, &roundTripError)) {
            fail("track pitch-envelope document reload failed");
        } else {
            auto reloadedTimeline = reloadedDocument.buildTimeline(originalSampleRate);
            if (!reloadedTimeline || reloadedTimeline->sampleRate != originalSampleRate ||
                reloadedTimeline->sampleForTick(input.expectedEndTick) !=
                    input.view.timeline()->sampleForTick(input.expectedEndTick)) {
                fail("track pitch-envelope round trip changed its timing");
            } else {
                SongView reloadedView;
                reloadedView.resize(input.view.size());
                reloadedView.setSong(reloadedTimeline.get(), &input.voicegroup);
                reloadedView.setDocument(&reloadedDocument);
                reloadedView.selectTrack(input.track);
                reloadedView.selectionModel().clearNoteSelection();
                reloadedView.setPitchEnvelopeVisible(input.track, true);
                QCoreApplication::processEvents();
                (void)reloadedView.grab();
                const std::optional<int> reloadedTrack = reloadedView.pitchEnvelopeTrack();
                auto *reloadedHost =
                    reloadedView.findChild<QWidget *>(QStringLiteral("pitchEnvelopeHost"));
                auto *reloadedGraph = graphFor(reloadedHost);
                if (!reloadedTrack || *reloadedTrack != input.track ||
                    !reloadedView.selectionModel().noteSelection().empty() ||
                    !sameLane(result.committedBends,
                              reloadedDocument.lanePoints(input.track, DOC_CC_BEND)) ||
                    !reloadedGraph || !reloadedGraph->isEnabled() ||
                    !sameCurve(result.committedCurve, reloadedGraph->points())) {
                    fail("track pitch-envelope disk round trip did not reconstruct from bend "
                         "events");
                }
            }
        }
    }
    return result;
}

} // namespace pitchenvelopecheck
