#include "ui/songview/pitchenvelopehost.h"

#include "ui/m4asemantics.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"

#include <QHideEvent>
#include <QKeyEvent>
#include <QLabel>
#include <QMetaObject>
#include <QPainter>
#include <QResizeEvent>
#include <QSizePolicy>
#include <QVBoxLayout>
#include <cmath>
#include <limits>
#include <utility>
#include <vector>

namespace {
constexpr uint8_t kBendRangeController = 0x14;
constexpr int kDefaultBendRange = 2;
} // namespace

namespace songview {

PitchEnvelopeHost::PitchEnvelopeHost(::SongView *songView, QWidget *parent)
    : QWidget(parent)
    , m_songView(songView)
{
    setObjectName(QStringLiteral("pitchEnvelopeHost"));
    setAccessibleName(SongView::tr("Track pitch envelope"));
    setMinimumHeight(196);
    setMaximumHeight(196);
    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(8, 4, 8, 4);
    layout->setSpacing(2);
    m_status = new QLabel(this);
    m_status->setObjectName(QStringLiteral("pitchEnvelopeStatus"));
    m_status->setWordWrap(false);
    layout->addWidget(m_status);
    m_graph = new CurveGraph(makeGraphSpec(), this);
    m_graph->setObjectName(QStringLiteral("pitchEnvelopeGraph"));
    m_graph->setMinimumHeight(164);
    m_graph->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    CurveGraph::Callbacks callbacks;
    callbacks.previewChanged = [this] {
        if (m_session)
            m_session->gestureDirty = true;
    };
    callbacks.commitRequested = [this] { commitCurve(); };
    callbacks.cancelRequested = [this] {
        if (m_session)
            m_session->gestureDirty = false;
    };
    callbacks.auditionRequested = [this] {
        if (!m_songView || !m_session)
            return;
        const uint64_t startTick = m_session->templateSourceTick;
        commitCurve();
        if (m_songView)
            m_songView->requestPlayPauseFrom(startTick);
    };
    m_graph->setCallbacks(std::move(callbacks));
    layout->addWidget(m_graph, 1);
    applyReadOnlyState(
        SongView::tr("Select a track with eligible note starts to edit its pitch envelope."));
}

void PitchEnvelopeHost::setEnvelopeVisible(bool visible)
{
    if (!visible) {
        applyReadOnlyState(
            SongView::tr("Select a track with eligible note starts to edit its pitch envelope."));
        hide();
        return;
    }
    show();
    refresh();
}

void PitchEnvelopeHost::refreshGrid()
{
    if (!m_graph || !m_session)
        return;
    cancelGesture();
    m_graph->setSpec(makeGraphSpec());
}

void PitchEnvelopeHost::refresh()
{
    const auto engineTrack = selectedPrimaryTrack();
    if (!engineTrack) {
        applyReadOnlyState(
            SongView::tr("Select a track with eligible note starts to edit its pitch envelope."));
        return;
    }
    const std::vector<pitch_envelope::Projection> projections =
        eligibleProjectionsForTrack(*engineTrack);
    if (projections.empty()) {
        applyReadOnlyState(
            SongView::tr("The selected track has no eligible note starts for pitch envelopes."));
        return;
    }
    auto templateSource = std::find_if(projections.begin(), projections.end(),
                                       [](const pitch_envelope::Projection &projection) {
                                           return projection.endTick == projection.windowEndTick;
                                       });
    if (templateSource == projections.end()) {
        templateSource = std::max_element(
            projections.begin(), projections.end(),
            [](const pitch_envelope::Projection &lhs, const pitch_envelope::Projection &rhs) {
                const uint64_t lhsSpan =
                    lhs.endTick > lhs.startTick ? lhs.endTick - lhs.startTick : 0;
                const uint64_t rhsSpan =
                    rhs.endTick > rhs.startTick ? rhs.endTick - rhs.startTick : 0;
                return lhsSpan < rhsSpan;
            });
    }
    const pitch_envelope::Projection &source = *templateSource;
    const uint64_t windowTicks = source.windowEndTick > source.startTick
                                     ? source.windowEndTick - source.startTick
                                     : pitch_envelope::kDefaultWindowTicks;
    m_session = {
        *engineTrack,   projections,      source.startTick, source.windowEndTick,
        source.endTick, source.bendRange, windowTicks,      m_songView->document()->revision()};
    m_graph->setSpec(makeGraphSpec());
    loadCurve();
    m_graph->setEnabled(true);
    updateStatus(SongView::tr("Track pitch envelope: curve applies to every eligible note start "
                              "(%1).")
                     .arg(int(projections.size())));
}

void PitchEnvelopeHost::applyReadOnlyState(const QString &text)
{
    cancelGesture();
    m_session.reset();
    m_graph->setEnabled(false);
    updateStatus(text);
}

void PitchEnvelopeHost::cancelGesture()
{
    if (m_graph)
        m_graph->cancelGesture();
    if (m_session)
        m_session->gestureDirty = false;
}
void PitchEnvelopeHost::paintEvent(QPaintEvent *event)
{
    QWidget::paintEvent(event);
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    const QRectF bounds = QRectF(rect()).adjusted(0.5, 0.5, -0.5, -0.5);
    painter.setBrush(themes::color(themes::Role::song_view_piano_roll_background));
    painter.setPen(QPen(themes::color(themes::Role::song_view_separator), 1.0));
    painter.drawRoundedRect(bounds, 4.0, 4.0);
}

void PitchEnvelopeHost::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape && m_songView && m_session) {
        const int track = m_session->engineTrack;
        m_songView->setPitchEnvelopeVisible(track, false);
        event->accept();
        return;
    }
    QWidget::keyPressEvent(event);
}

void PitchEnvelopeHost::hideEvent(QHideEvent *event)
{
    QWidget::hideEvent(event);
    return;
    QMetaObject::invokeMethod(
        m_songView.data(),
        [songView = m_songView] {
            if (songView)
                songView->focusContent();
        },
        Qt::QueuedConnection);
}

void PitchEnvelopeHost::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    if (m_graph && m_session && !m_graph->hasGesture())
        m_graph->setSpec(makeGraphSpec());
}

std::optional<int> PitchEnvelopeHost::selectedPrimaryTrack() const
{
    if (!m_songView || !m_songView->document())
        return std::nullopt;
    const int engineTrack = m_songView->selectionModel().primaryTrack();
    return engineTrack >= 0 ? std::optional<int>(engineTrack) : std::nullopt;
}

std::vector<pitch_envelope::Projection>
PitchEnvelopeHost::eligibleProjectionsForTrack(int engineTrack) const
{
    if (!m_songView || !m_songView->document() ||
        m_songView->selectionModel().primaryTrack() != engineTrack) {
        return {};
    }
    std::vector<DocNote> notes = m_songView->document()->notesForTrack(engineTrack);
    std::sort(notes.begin(), notes.end(),
              [](const DocNote &lhs, const DocNote &rhs) { return lhs.tick < rhs.tick; });
    std::vector<pitch_envelope::Projection> projections;
    for (size_t index = 0; index < notes.size();) {
        const uint64_t startTick = notes[index].tick;
        size_t nextIndex = index + 1;
        while (nextIndex < notes.size() && notes[nextIndex].tick == startTick)
            ++nextIndex;
        const DrawerPageVoiceContext context = m_songView->voiceContext(startTick);
        if (context.voice && voiceSupportsPitchEnvelope(context.voice->type)) {
            const uint64_t windowEndTick =
                pitch_envelope::creationEndTick(startTick, pitch_envelope::kDefaultWindowTicks);
            const uint64_t endTick = nextIndex == notes.size()
                                         ? windowEndTick
                                         : std::min(windowEndTick, notes[nextIndex].tick);
            projections.push_back(
                {startTick, endTick, windowEndTick, activeBendRange(engineTrack, startTick)});
        }
        index = nextIndex;
    }
    return projections;
}

int PitchEnvelopeHost::activeBendRange(int engineTrack, uint64_t tick) const
{
    if (!m_songView || !m_songView->document())
        return kDefaultBendRange;
    int range = kDefaultBendRange;
    uint64_t rangeTick = 0;
    bool found = false;
    for (const DocLanePoint &point :
         m_songView->document()->lanePoints(engineTrack, kBendRangeController)) {
        if (point.tick <= tick && (!found || point.tick >= rangeTick)) {
            range = std::clamp(point.value, 0, 127);
            rangeTick = point.tick;
            found = true;
        }
    }
    return range;
}

PitchEnvelopeHost::EditingGrid PitchEnvelopeHost::editingGridAt(uint64_t tick,
                                                                CurveGraph::Sampling sampling) const
{
    if (!m_songView || !m_session)
        return {};
    const EnvelopeSession &session = *m_session;
    if (sampling == CurveGraph::Sampling::Fine) {
        return {std::max<uint64_t>(1, m_songView->fineGridTicks()), 0,
                session.templateWindowEndTick};
    }
    const QSize graphSize = m_graph ? m_graph->size() : QSize(480, 164);
    const int canvasWidth = std::max(80, graphSize.width() - 60);
    const uint64_t span =
        std::max<uint64_t>(1, session.templateWindowEndTick - session.templateSourceTick);
    const SongView::GridSeg segment = m_songView->gridSegAt(tick);
    return {std::max<uint64_t>(
                1, m_songView->gridTicksAtScale(tick, double(canvasWidth) / double(span))),
            segment.start, std::min(session.templateWindowEndTick, segment.next)};
}

uint64_t PitchEnvelopeHost::snappedGridTick(uint64_t tick, CurveGraph::Sampling sampling) const
{
    if (!m_session)
        return 0;
    const EnvelopeSession &session = *m_session;
    const EditingGrid grid = editingGridAt(tick, sampling);
    if (grid.endTick <= session.templateSourceTick)
        return session.templateSourceTick;
    const uint64_t clampedTick = std::min(tick, grid.endTick);
    const uint64_t offset = clampedTick > grid.anchorTick ? clampedTick - grid.anchorTick : 0;
    const uint64_t lower = grid.anchorTick + offset / grid.cellTicks * grid.cellTicks;
    const uint64_t upper =
        std::min(grid.endTick, lower > std::numeric_limits<uint64_t>::max() - grid.cellTicks
                                   ? std::numeric_limits<uint64_t>::max()
                                   : lower + grid.cellTicks);
    const uint64_t snapped = clampedTick - lower <= upper - clampedTick ? lower : upper;
    return std::clamp(snapped, session.templateSourceTick, session.templateWindowEndTick);
}

uint64_t PitchEnvelopeHost::nextGridTick(uint64_t tick, CurveGraph::Sampling sampling) const
{
    if (!m_session)
        return 0;
    const EnvelopeSession &session = *m_session;
    if (tick >= session.templateWindowEndTick)
        return session.templateWindowEndTick;
    const EditingGrid grid = editingGridAt(tick, sampling);
    const uint64_t offset = tick > grid.anchorTick ? tick - grid.anchorTick : 0;
    const uint64_t lower = grid.anchorTick + offset / grid.cellTicks * grid.cellTicks;
    const uint64_t next = lower > std::numeric_limits<uint64_t>::max() - grid.cellTicks
                              ? std::numeric_limits<uint64_t>::max()
                              : lower + grid.cellTicks;
    return std::min(grid.endTick, next);
}

uint64_t PitchEnvelopeHost::lastEditableGridTick(CurveGraph::Sampling sampling) const
{
    if (!m_session)
        return 0;
    const EnvelopeSession &session = *m_session;
    if (session.templateEndTick <= session.templateSourceTick)
        return session.templateSourceTick;
    const uint64_t lastTick = session.templateEndTick - 1;
    const EditingGrid grid = editingGridAt(lastTick, sampling);
    const uint64_t offset = lastTick > grid.anchorTick ? lastTick - grid.anchorTick : 0;
    const uint64_t lower = grid.anchorTick + offset / grid.cellTicks * grid.cellTicks;
    return std::max(session.templateSourceTick, lower);
}

std::vector<double> PitchEnvelopeHost::gridLines() const
{
    std::vector<double> lines;
    if (!m_songView || !m_session)
        return lines;
    const EnvelopeSession &session = *m_session;
    for (uint64_t tick = session.templateSourceTick;;) {
        const uint64_t next = nextGridTick(tick, CurveGraph::Sampling::Normal);
        if (next <= tick || next >= session.templateWindowEndTick)
            break;
        lines.push_back(double(next - session.templateSourceTick));
        tick = next;
    }
    return lines;
}

CurveGraph::CurveSpec PitchEnvelopeHost::makeGraphSpec() const
{
    const EnvelopeSession *session = m_session ? &*m_session : nullptr;
    const int bendRange = session ? session->templateBendRange : kDefaultBendRange;
    CurveGraph::CurveSpec spec;
    const QSize graphSize = m_graph ? m_graph->size() : QSize(480, 164);
    const double range = double(bendRange);
    const double windowTicks =
        double(session ? (session->templateWindowEndTick - session->templateSourceTick)
                       : pitch_envelope::kDefaultWindowTicks);
    spec.xAxis.minimum = 0.0;
    spec.xAxis.maximum = windowTicks;
    spec.yAxis.minimum = -range;
    spec.yAxis.maximum = range;
    spec.yAxis.mapping = CurveGraph::CurveAxisMapping::BipolarCenter;
    spec.yAxis.zeroDetentPixels = 8;
    spec.defaultY = 0.0;
    spec.lockStartEndpointY = true;
    spec.sampling.endpointInset = 0.1;
    spec.sampling.interiorStep = spec.sampling.endpointInset;
    spec.canvasRect =
        QRect(52, 16, std::max(1, graphSize.width() - 60), std::max(1, graphSize.height() - 36));
    spec.title = SongView::tr("Track pitch envelope (BEND)");
    spec.startLabel = SongView::tr("0");
    spec.endLabel = SongView::tr("%1 ticks").arg(int(windowTicks));
    spec.text.zeroLabel = QStringLiteral("0");
    spec.text.showZeroLabel = true;
    spec.gridLines = gridLines();
    spec.colors = {themes::color(themes::Role::song_view_piano_roll_background),
                   themes::color(themes::Role::song_view_grid),
                   themes::color(themes::Role::song_view_separator),
                   SongView::trackColor(session ? session->engineTrack : 0),
                   themes::color(themes::Role::song_view_secondary_text),
                   themes::color(themes::Role::focus_outline),
                   themes::color(themes::Role::song_view_edit_preview_outline),
                   themes::color(themes::Role::song_view_secondary_text)};
    spec.sampling.snap = [this](double x, CurveGraph::Sampling sampling) {
        if (!m_songView || !m_session)
            return 0.0;
        const EnvelopeSession &sess = *m_session;
        const double window = double(sess.templateWindowEndTick - sess.templateSourceTick);
        if (x <= 0.0)
            return 0.0;
        if (x >= window)
            return window;
        const uint64_t tick = sess.templateSourceTick + uint64_t(std::llround(x));
        const uint64_t snapped =
            std::min(snappedGridTick(tick, sampling), lastEditableGridTick(sampling));
        const uint64_t clamped =
            std::clamp(snapped, sess.templateSourceTick, sess.templateWindowEndTick);
        return double(clamped - sess.templateSourceTick);
    };
    spec.sampling.nextSample = [this](double x, CurveGraph::Sampling sampling) {
        if (!m_songView || !m_session)
            return double(m_session
                              ? m_session->templateWindowEndTick - m_session->templateSourceTick
                              : pitch_envelope::kDefaultWindowTicks);
        const EnvelopeSession &sess = *m_session;
        const double window = double(sess.templateWindowEndTick - sess.templateSourceTick);
        if (x >= window)
            return window;
        const uint64_t tick = sess.templateSourceTick + uint64_t(std::llround(x));
        const uint64_t next = nextGridTick(tick, sampling);
        if (next <= tick || next >= sess.templateEndTick)
            return window;
        return double(next - sess.templateSourceTick);
    };
    spec.sampling.lastEditable = [this](CurveGraph::Sampling sampling) {
        if (!m_songView || !m_session)
            return 0.0;
        const EnvelopeSession &sess = *m_session;
        return double(lastEditableGridTick(sampling) - sess.templateSourceTick);
    };
    spec.text.formatLiveValue = [](double semitones) {
        return SongView::tr("%1%2 st")
            .arg(semitones > 0.0 ? QStringLiteral("+") : QStringLiteral(""))
            .arg(semitones, 0, 'f', 2);
    };
    spec.text.formatRangeLimit = [range](bool positive) {
        if (range == 0.0)
            return SongView::tr("0 st");
        return SongView::tr("%1%2 st")
            .arg(positive ? QStringLiteral("+") : QStringLiteral("-"))
            .arg(range, 0, 'f', 0);
    };
    return spec;
}

void PitchEnvelopeHost::loadCurve()
{
    if (!m_session || !m_songView || !m_songView->document())
        return;
    const EnvelopeSession &session = *m_session;
    std::vector<DocLanePoint> bends =
        m_songView->document()->lanePoints(session.engineTrack, DOC_CC_BEND);
    std::stable_sort(
        bends.begin(), bends.end(),
        [](const DocLanePoint &lhs, const DocLanePoint &rhs) { return lhs.tick < rhs.tick; });
    std::vector<CurvePoint> points;
    points.push_back({0.0, 0.0});
    for (const DocLanePoint &point : bends) {
        if (point.tick <= session.templateSourceTick || point.tick >= session.templateEndTick)
            continue;
        const double offsetTick = double(point.tick - session.templateSourceTick);
        if (offsetTick <= 0.0)
            continue;
        const double semitones =
            pitch_envelope::bendToSemitones(point.value, session.templateBendRange);
        if (!points.empty() && points.back().x == offsetTick)
            points.back().y = semitones;
        else
            points.push_back({offsetTick, semitones});
    }
    points.push_back({double(session.templateWindowEndTick - session.templateSourceTick), 0.0});
    m_graph->setPoints(std::move(points));
}

void PitchEnvelopeHost::commitCurve()
{
    if (!m_session || !m_session->gestureDirty || !m_songView || !m_songView->document())
        return;
    const EnvelopeSession &session = *m_session;
    auto *document = m_songView->document();
    if (session.documentRevision != document->revision()) {
        refresh();
        return;
    }
    std::vector<pitch_envelope::CurveSample> curve;
    curve.reserve(m_graph->points().size());
    for (const CurvePoint &point : m_graph->points())
        curve.push_back({point.x, point.y});
    const pitch_envelope::LaneWrite write =
        pitch_envelope::compileLaneWrite(curve, session.projections);
    std::vector<SongDocument::LanePointRange> ranges;
    ranges.reserve(write.ranges.size());
    for (const pitch_envelope::LaneRange &range : write.ranges)
        ranges.push_back({range.tickBegin, range.tickEnd});
    std::vector<SongDocument::LanePointValue> points;
    points.reserve(write.points.size());
    for (const pitch_envelope::LanePoint &point : write.points)
        points.push_back({point.tick, point.value});
    m_session->gestureDirty = false;
    document->writeLanePointRanges(session.engineTrack, DOC_CC_BEND, ranges, points);
}

void PitchEnvelopeHost::updateStatus(const QString &text)
{
    m_status->setText(text);
    setAccessibleDescription(text);
}

} // namespace songview
