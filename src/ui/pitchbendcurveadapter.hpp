#pragma once

#include "core/songdocument.h"
#include "curvegraph/curvegraph.hpp"

#include <cstdint>
#include <map>
#include <memory>
#include <vector>

class SongView;
class QWidget;

namespace songview {

class PitchBendCurveAdapter final
{
  public:
    enum class Lane { PitchBend, ModWheel };

    PitchBendCurveAdapter(::SongView *songView, int engineTrack, uint64_t startTick,
                          uint64_t endTick, bool unterminated, Lane lane, QWidget *parent);

    CurveGraph &graph();
    void setBendRange(int range);
    void setCurve(const std::map<uint64_t, int> &points, int endValue);
    std::vector<SongDocument::LanePointValue> curvePoints() const;

  private:
    struct SampleParams
    {
        uint64_t cell;
        uint64_t anchor;
        uint64_t segmentEnd;
    };

    CurveGraph::CurveSpec makeSpec() const;
    std::vector<double> gridLines() const;
    void refreshSpec();
    void setPointsFromMap(const std::map<uint64_t, int> &points);
    uint64_t normalCellTicksAt(uint64_t tick) const;
    SampleParams sampleParamsAt(uint64_t tick, CurveGraph::Sampling sampling) const;
    uint64_t nextSampleTick(uint64_t tick, const SampleParams &params) const;
    uint64_t nextSampleTick(uint64_t tick, CurveGraph::Sampling sampling) const;
    uint64_t lastEditableTick(CurveGraph::Sampling sampling) const;
    int curveValueAt(uint64_t tick) const;
    uint64_t tickAtFraction(double fraction, CurveGraph::Sampling sampling) const;
    int minimumValue() const;
    int maximumValue() const;
    int defaultValue() const;
    QString laneTitle() const;
    QString formatLiveValue() const;
    QString formatRangeLimit(bool positive) const;

    ::SongView *m_songView = nullptr;
    int m_engineTrack = -1;
    uint64_t m_startTick = 0;
    uint64_t m_endTick = 0;
    bool m_unterminated = false;
    int m_bendRange = 2;
    int m_endValue = 0;
    Lane m_lane = Lane::PitchBend;
    std::unique_ptr<CurveGraph> m_graph;
};
} // namespace songview
