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

songview::CurveGraph *graphFor(QWidget *host)
{
    auto *widget =
        host ? host->findChild<QWidget *>(QStringLiteral("pitchEnvelopeGraph")) : nullptr;
    return dynamic_cast<songview::CurveGraph *>(widget);
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

std::vector<DocLanePoint>
expectedProjection(const std::vector<songview::CurvePoint> &curve,
                   const pitchenvelopecheck::PitchEnvelopeProjection &projection)
{
    std::vector<DocLanePoint> result;
    result.push_back(expectedLanePoint(projection.note.tick, 0));
    const uint64_t span = projection.endTick - projection.note.tick;
    for (const songview::CurvePoint &point : curve) {
        if (point.x <= 0.0)
            continue;
        const uint64_t offset = uint64_t(std::llround(point.x));
        if (offset >= span)
            continue;
        const int value = songview::pitch_envelope::semitonesToBend(point.y, projection.bendRange);
        result.push_back(expectedLanePoint(projection.note.tick + offset, value));
    }
    result.push_back(expectedLanePoint(projection.endTick, 0));
    return result;
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
    const double expectedEndX = input.expectedWindowTicks != 0
                                    ? double(input.expectedWindowTicks)
                                    : double(input.expectedEndTick > input.templateSource.tick
                                                 ? input.expectedEndTick - input.templateSource.tick
                                                 : 0);
    const bool zeroEndpoints = result.committedCurve.size() >= 2 &&
                               std::abs(result.committedCurve.front().x - 0.0) <= 1e-9 &&
                               std::abs(result.committedCurve.front().y) <= 1e-9 &&
                               std::abs(result.committedCurve.back().x - expectedEndX) <= 1e-9 &&
                               std::abs(result.committedCurve.back().y) <= 1e-9;
    if (!zeroEndpoints)
        fail("track pitch-envelope gesture did not retain its 24-tick zero-reset template");
    if (!input.fullProjections.empty()) {
        const int templateBendRange = input.fullProjections.front().bendRange;
        const bool retainedAuthoredPoints = std::all_of(
            input.authoredCurve.begin(), input.authoredCurve.end(),
            [&](const songview::CurvePoint &authored) {
                const double persistedY = songview::pitch_envelope::bendToSemitones(
                    songview::pitch_envelope::semitonesToBend(authored.y, templateBendRange),
                    templateBendRange);
                return std::any_of(result.committedCurve.begin(), result.committedCurve.end(),
                                   [&](const songview::CurvePoint &committed) {
                                       return std::abs(committed.x - authored.x) <= 1e-9 &&
                                              std::abs(committed.y - persistedY) <= 1e-9;
                                   });
            });
        if (!retainedAuthoredPoints)
            fail("track pitch-envelope commit moved an authored graph handle");
        if (result.committedCurve.size() != input.authoredCurve.size())
            fail("track pitch-envelope commit introduced undisplayed bend events");
    }
    for (const PitchEnvelopeProjection &projection : input.fullProjections) {
        const std::vector<DocLanePoint> expected =
            expectedProjection(input.authoredCurve, projection);
        const std::vector<DocLanePoint> actual =
            lanePointsInRange(result.committedBends, projection.note.tick, projection.endTick);
        if (!sameLane(expected, actual)) {
            fail(
                projection.note.tick == input.sameTickProjectionTick
                    ? "same-tick eligible note-ons produced more than one pitch-envelope projection"
                    : "eligible note-on did not receive the displayed M4A bend events at its "
                      "active BENDR");
        }
    }
    const std::vector<DocLanePoint> expectedClipped =
        expectedProjection(input.authoredCurve, input.clippedProjection);
    const std::vector<DocLanePoint> actualClipped = lanePointsInRange(
        result.committedBends, input.clippedProjection.note.tick, input.clippedProjection.endTick);
    if (!sameLane(expectedClipped, actualClipped))
        fail("eligible note-on did not receive the template before the next note clipped it");
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
