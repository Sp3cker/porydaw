#include "pitchbendcurveadapter.hpp"

#include "songview.h"
#include "theme/themeruntime.h"
#include "ui/keymap.h"

#include <algorithm>
#include <cmath>
#include <iterator>
#include <utility>

namespace songview {

PitchBendCurveAdapter::PitchBendCurveAdapter(::SongView *songView, int engineTrack,
                                             uint64_t startTick, uint64_t endTick,
                                             bool unterminated, Lane lane, QWidget *parent)
    : m_songView(songView)
    , m_engineTrack(engineTrack)
    , m_startTick(startTick)
    , m_endTick(endTick)
    , m_unterminated(unterminated)
    , m_lane(lane)
    , m_graph(std::make_unique<CurveGraph>(makeSpec(), parent))
{
    m_graph->setObjectName(lane == Lane::PitchBend ? QStringLiteral("pitchBendGraph")
                                                   : QStringLiteral("modWheelGraph"));
    m_graph->setAttribute(Qt::WA_NoMousePropagation);
}

CurveGraph &PitchBendCurveAdapter::graph()
{
    return *m_graph;
}

void PitchBendCurveAdapter::setBendRange(int range)
{
    m_bendRange = std::clamp(range, 0, 127);
    refreshSpec();
}

void PitchBendCurveAdapter::setCurve(const std::map<uint64_t, int> &points, int endValue)
{
    m_endValue = std::clamp(endValue, minimumValue(), maximumValue());
    setPointsFromMap(points);
}

std::vector<SongDocument::LanePointValue> PitchBendCurveAdapter::curvePoints() const
{
    std::vector<SongDocument::LanePointValue> result;
    const auto appendSample = [this, &result](uint64_t tick, bool endpoint) {
        const int value = curveValueAt(tick);
        if (!result.empty() && result.back().tick == tick) {
            result.back().value = value;
            return;
        }
        const auto effectiveBend = [](int bend) {
            return (std::clamp(bend, -8192, 8191) + 8192) >> 7;
        };
        if (!endpoint && m_lane == Lane::PitchBend && !result.empty() &&
            effectiveBend(value) == effectiveBend(result.back().value))
            return;
        result.push_back({tick, value});
    };

    appendSample(m_startTick, true);
    if (m_endTick > m_startTick) {
        const uint64_t ticksPerQuarter = std::max<uint64_t>(
            1, m_songView && m_songView->document() ? m_songView->document()->smf().division : 24);
        using WideTick = unsigned __int128;
        const WideTick firstBoundary = WideTick(m_startTick) * 16 / ticksPerQuarter + 1;
        for (WideTick boundary = firstBoundary;; ++boundary) {
            const WideTick roundedTick = (boundary * ticksPerQuarter + 8) / 16;
            if (roundedTick >= m_endTick)
                break;
            appendSample(uint64_t(roundedTick), false);
        }
    }
    appendSample(m_endTick, true);
    return result;
}

int PitchBendCurveAdapter::curveValueAt(uint64_t tick) const
{
    const auto &points = m_graph->points();
    if (points.empty())
        return defaultValue();

    const double x = double(tick);
    const auto next =
        std::lower_bound(points.begin(), points.end(), x,
                         [](const CurvePoint &point, double value) { return point.x < value; });
    if (next == points.begin())
        return qRound(next->y);
    if (next == points.end())
        return qRound(points.back().y);

    const CurvePoint &previous = *std::prev(next);
    const double fraction = (x - previous.x) / (next->x - previous.x);
    return qRound(std::clamp(previous.y + fraction * (next->y - previous.y), double(minimumValue()),
                             double(maximumValue())));
}

CurveGraph::CurveSpec PitchBendCurveAdapter::makeSpec() const
{
    CurveGraph::CurveSpec spec;
    spec.xAxis.minimum = double(m_startTick);
    spec.xAxis.maximum = double(m_endTick);
    spec.yAxis.minimum = minimumValue();
    spec.yAxis.maximum = maximumValue();
    spec.yAxis.mapping = m_lane == Lane::PitchBend ? CurveGraph::CurveAxisMapping::BipolarCenter
                                                   : CurveGraph::CurveAxisMapping::Linear;
    spec.yAxis.quantizationStep = m_lane == Lane::PitchBend ? 128.0 : 1.0;
    spec.yAxis.zeroDetentPixels = m_lane == Lane::PitchBend ? 8 : 0;
    spec.defaultY = defaultValue();
    spec.sampling.endpointInset = 1.0;
    spec.sampling.interiorStep = 1.0;
    spec.canvasRect = QRect(52, 44, 280, 112);
    spec.title = laneTitle();
    spec.startLabel = SongView::tr("Note on");
    spec.endLabel = m_unterminated ? SongView::tr("Song end") : SongView::tr("Note off");
    spec.text.zeroLabel = QStringLiteral("0");
    spec.text.showZeroLabel = m_lane == Lane::PitchBend;
    spec.colors = {themes::color(themes::Role::song_view_piano_roll_background),
                   themes::color(themes::Role::song_view_grid),
                   SongView::trackColor(m_engineTrack),
                   themes::color(themes::Role::focus_outline),
                   themes::color(themes::Role::song_view_edit_preview_outline),
                   themes::color(themes::Role::song_view_secondary_text)};
    spec.sampling.snap = [this](double x, CurveGraph::Sampling sampling) {
        if (m_endTick <= m_startTick)
            return double(m_startTick);
        const double fraction =
            std::clamp((x - double(m_startTick)) / double(m_endTick - m_startTick), 0.0, 1.0);
        return double(tickAtFraction(fraction, sampling));
    };
    spec.sampling.nextSample = [this](double x, CurveGraph::Sampling sampling) {
        return double(nextSampleTick(uint64_t(std::llround(x)), sampling));
    };
    spec.sampling.lastEditable = [this](CurveGraph::Sampling sampling) {
        return double(lastEditableTick(sampling));
    };
    spec.segments.allLinear = true;
    spec.gridLines = gridLines();
    spec.text.formatLiveValue = [this](double) { return formatLiveValue(); };
    spec.text.formatRangeLimit = [this](bool positive) { return formatRangeLimit(positive); };
    spec.matchesAuditionKey = [](const QKeyEvent &event) {
        return keymap::Registry::instance().matches(&event, QStringLiteral("transport.play_pause"));
    };
    return spec;
}

std::vector<double> PitchBendCurveAdapter::gridLines() const
{
    std::vector<double> result;
    if (!m_songView || m_endTick <= m_startTick)
        return result;
    uint64_t segmentTick = m_startTick;
    while (segmentTick < m_endTick) {
        const SampleParams params = sampleParamsAt(segmentTick, CurveGraph::Sampling::Normal);
        uint64_t tick = nextSampleTick(segmentTick, params);
        while (tick < params.segmentEnd) {
            result.push_back(double(tick));
            tick = nextSampleTick(tick, params);
        }
        if (params.segmentEnd >= m_endTick)
            break;
        segmentTick = params.segmentEnd;
    }
    return result;
}

void PitchBendCurveAdapter::refreshSpec()
{
    m_graph->setSpec(makeSpec());
}

void PitchBendCurveAdapter::setPointsFromMap(const std::map<uint64_t, int> &points)
{
    std::vector<CurvePoint> converted;
    converted.reserve(points.size() + 1);
    for (const auto &[tick, value] : points)
        converted.push_back(
            {double(tick), double(std::clamp(value, minimumValue(), maximumValue()))});
    if (std::none_of(converted.begin(), converted.end(),
                     [this](const auto &point) { return point.x == double(m_startTick); }))
        converted.push_back({double(m_startTick), double(defaultValue())});
    if (std::none_of(converted.begin(), converted.end(),
                     [this](const auto &point) { return point.x == double(m_endTick); }))
        converted.push_back({double(m_endTick), double(m_endValue)});
    m_graph->setPoints(std::move(converted));
}

uint64_t PitchBendCurveAdapter::normalCellTicksAt(uint64_t tick) const
{
    if (!m_songView)
        return 1;
    const uint64_t span = std::max<uint64_t>(1, m_endTick - m_startTick);
    return std::max<uint64_t>(1, m_songView->gridTicksAtScale(tick, 279.0 / double(span)));
}

PitchBendCurveAdapter::SampleParams
PitchBendCurveAdapter::sampleParamsAt(uint64_t tick, CurveGraph::Sampling sampling) const
{
    if (sampling == CurveGraph::Sampling::Fine)
        return {std::max<uint64_t>(1, m_songView ? m_songView->fineGridTicks() : 1), 0, m_endTick};
    SampleParams params{normalCellTicksAt(tick), 0, m_endTick};
    if (!m_songView)
        return params;
    const SongView::GridSeg segment = m_songView->gridSegAt(tick);
    params.anchor = segment.start;
    params.segmentEnd = std::min(m_endTick, segment.next);
    return params;
}

uint64_t PitchBendCurveAdapter::nextSampleTick(uint64_t tick, const SampleParams &params) const
{
    const uint64_t offset = tick > params.anchor ? tick - params.anchor : 0;
    const uint64_t quotient = offset / params.cell;
    const uint64_t maximumSteps = (UINT64_MAX - params.anchor) / params.cell;
    if (quotient >= maximumSteps)
        return params.segmentEnd;
    const uint64_t aligned = params.anchor + (quotient + 1) * params.cell;
    return std::min(aligned, params.segmentEnd);
}

uint64_t PitchBendCurveAdapter::nextSampleTick(uint64_t tick, CurveGraph::Sampling sampling) const
{
    if (tick >= m_endTick)
        return m_endTick;
    return nextSampleTick(tick, sampleParamsAt(tick, sampling));
}

uint64_t PitchBendCurveAdapter::lastEditableTick(CurveGraph::Sampling sampling) const
{
    if (m_endTick <= m_startTick + 1)
        return m_startTick;
    const uint64_t lastRaw = m_endTick - 1;
    const SampleParams params = sampleParamsAt(lastRaw, sampling);
    const uint64_t offset = lastRaw > params.anchor ? lastRaw - params.anchor : 0;
    const uint64_t aligned = params.anchor + offset / params.cell * params.cell;
    return std::clamp(aligned, m_startTick, lastRaw);
}

uint64_t PitchBendCurveAdapter::tickAtFraction(double fraction, CurveGraph::Sampling sampling) const
{
    if (fraction <= 0.0)
        return m_startTick;
    if (fraction >= 1.0)
        return lastEditableTick(sampling);
    const double raw = double(m_startTick) + fraction * double(m_endTick - m_startTick);
    const uint64_t rawTick =
        std::clamp<uint64_t>(uint64_t(std::max(0.0, std::round(raw))), m_startTick, m_endTick);
    const SampleParams params = sampleParamsAt(rawTick, sampling);
    const double snapped =
        double(params.anchor) +
        std::round((raw - double(params.anchor)) / double(params.cell)) * params.cell;
    if (snapped <= double(m_startTick))
        return m_startTick;
    const uint64_t maximum =
        params.segmentEnd < m_endTick ? params.segmentEnd : lastEditableTick(sampling);
    return std::clamp(uint64_t(snapped), m_startTick, maximum);
}

int PitchBendCurveAdapter::minimumValue() const
{
    return m_lane == Lane::PitchBend ? -8192 : 0;
}

int PitchBendCurveAdapter::maximumValue() const
{
    return m_lane == Lane::PitchBend ? 8191 : 127;
}

int PitchBendCurveAdapter::defaultValue() const
{
    return 0;
}

QString PitchBendCurveAdapter::laneTitle() const
{
    return m_lane == Lane::PitchBend ? SongView::tr("Pitch bend (BEND)")
                                     : SongView::tr("Mod wheel (CC1)");
}

QString PitchBendCurveAdapter::formatLiveValue() const
{
    const int value = qRound(m_graph->liveValue());
    if (m_lane == Lane::ModWheel)
        return QString::number(value);
    if (value == 0 || m_bendRange == 0)
        return SongView::tr("0 st");
    const double semitones = double(value) * double(m_bendRange) / double(value > 0 ? 8191 : 8192);
    return SongView::tr("%1%2 st")
        .arg(semitones > 0 ? QStringLiteral("+") : "")
        .arg(semitones, 0, 'f', 2);
}

QString PitchBendCurveAdapter::formatRangeLimit(bool positive) const
{
    if (m_lane == Lane::ModWheel)
        return positive ? QStringLiteral("127") : QStringLiteral("0");
    if (m_bendRange == 0)
        return SongView::tr("0 st");
    return SongView::tr("%1%2 st")
        .arg(positive ? QStringLiteral("+") : QStringLiteral("-"))
        .arg(m_bendRange);
}

} // namespace songview
