#include "ui/songview/tempostrip.h"

#include <algorithm>
#include <set>

#include <QCoreApplication>
#include <QSizePolicy>

#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/nodelane/batchcommit.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"

namespace songview {
namespace {

uint32_t usedTrackMask(const MidiTimeline *timeline) noexcept
{
    if (!timeline)
        return 0;
    uint32_t mask = 0;
    for (int track = 0; track < 16; ++track) {
        if (timeline->tracks[track].used)
            mask |= uint32_t{1} << track;
    }
    return mask;
}

QString translated(const char *text)
{
    return QCoreApplication::translate("TempoStrip", text);
}

} // namespace

TempoStrip::TempoStrip(SongView &view)
    : TimelineSurface(&view)
    , m_view(view)
    , m_geometry(AutomationGeometry::resolve())
    , m_lane(*this)
{
    setFocusPolicy(Qt::StrongFocus);
    setMouseTracking(true);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    setFixedHeight(m_geometry.rowDefaultHeight);
}

TempoStrip::~TempoStrip() = default;

int TempoStrip::plotOrigin() const noexcept
{
    return m_geometry.plotOrigin;
}

bool TempoStrip::ready() const noexcept
{
    return m_view.document() && m_view.timeline();
}

uint32_t TempoStrip::usedTrackMask() const noexcept
{
    return songview::usedTrackMask(m_view.timeline());
}

AutomationProjection TempoStrip::projection() const
{
    return {m_geometry, &m_view};
}

NodeLaneHoverTarget TempoStrip::hoverTarget() const
{
    return {rect(), font(), devicePixelRatioF(),
            m_view.document() ? m_view.document()->revision() : 0, ready()};
}

NodePoint TempoStrip::mappedPoint(QPointF position, Qt::KeyboardModifiers modifiers) const
{
    NodePoint result;
    if (!ready())
        return result;
    const AutomationProjection proj = projection();
    const bool fine = modifiers & Qt::AltModifier;
    const uint64_t tick = m_view.snapTick(proj.rawTickAt(position.x()), fine);
    updateValuePoint(proj, m_lane, m_body, result, position.y(), tick,
                     modifiers & Qt::ControlModifier, m_geometry.neutralSnapRadius, -1);
    return result;
}

bool TempoStrip::nodePointHit(QPointF position, NodePoint *point) const
{
    return ready() && position.x() >= m_geometry.plotOrigin &&
           hitNodePoint(m_lane, m_body, projection(), m_geometry, position, devicePixelRatioF(),
                        false, point);
}

void TempoStrip::contentGeometryChanged()
{
    m_geometry = AutomationGeometry::resolve();
    m_body = rect();
    m_hover.invalidateCaches();
    m_hover.clearHover();
}

void TempoStrip::cancelInteraction()
{
    const bool active = gestureActive();
    m_drag.reset();
    m_band.clear();
    m_hover.previewValueLabel = {};
    m_hover.hover.highlightLocked = false;
    updateAxisLockCursor(AxisLock::None);
    if (active)
        invalidateContent(m_hover.clearHover());
}

bool TempoStrip::gestureActive() const noexcept
{
    return m_drag.has_value() || m_band.pending;
}

void TempoStrip::applyTempoEdit(const TempoEdit &edit)
{
    if (edit.empty() || !m_view.document())
        return;
    m_view.document()->applyTempoEdit(edit);
    m_hover.invalidateCaches();
    invalidateContent();
}

TempoStrip::TempoLane::TempoLane(TempoStrip &strip) noexcept : m_strip(strip) {}

QString TempoStrip::TempoLane::title() const
{
    return translated("Tempo (BPM)");
}

std::vector<NodePoint> TempoStrip::TempoLane::points() const
{
    std::vector<NodePoint> result;
    const SongDocument *document = m_strip.m_view.document();
    if (!document)
        return result;
    const auto &tempo = document->tempoPoints();
    result.reserve(tempo.size());
    for (const TempoPoint &point : tempo) {
        result.push_back(
            {point.tick, qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote))});
    }
    return result;
}

int TempoStrip::TempoLane::minimumValue() const
{
    return CoreTimeDefaults::kMinTempoBpm;
}

int TempoStrip::TempoLane::maximumValue() const
{
    return CoreTimeDefaults::kMaxTempoBpm;
}

QString TempoStrip::TempoLane::valueText(int value) const
{
    return QString::number(value);
}

bool TempoStrip::TempoLane::pointSelected(uint64_t tick) const
{
    const auto &selection = m_strip.m_view.selectionModel();
    if (!selection.timeSelectionCoversTempo(m_strip.usedTrackMask()))
        return false;
    const auto &range = selection.timeSelection();
    return tick >= range.startTick && tick < range.endTick;
}

void TempoStrip::TempoLane::deletePoints(const std::vector<uint64_t> &ticks)
{
    SongDocument *document = m_strip.m_view.document();
    if (!document || ticks.empty())
        return;
    const std::set<uint64_t> requested(ticks.begin(), ticks.end());
    TempoEdit edit;
    for (const TempoPoint &point : document->tempoPoints()) {
        if (requested.contains(point.tick))
            edit.remove.push_back(point);
    }
    m_strip.applyTempoEdit(edit);
}

void TempoStrip::TempoLane::movePoints(const std::vector<NodePointMove> &moves)
{
    SongDocument *document = m_strip.m_view.document();
    if (!document || moves.empty())
        return;
    const auto edit = nodelane::resolveTempoMoves(*document, moves);
    if (edit && !edit->empty())
        m_strip.applyTempoEdit(*edit);
}

void TempoStrip::TempoLane::replaceSpan(uint64_t first, uint64_t last,
                                        const std::vector<NodePoint> &replacement)
{
    SongDocument *document = m_strip.m_view.document();
    if (!document)
        return;
    TempoEdit edit;
    for (const TempoPoint &point : document->tempoPoints()) {
        if (point.tick >= first && point.tick <= last)
            edit.remove.push_back(point);
    }
    edit.add.reserve(replacement.size());
    for (const NodePoint &point : replacement) {
        edit.add.push_back(
            {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
    }
    m_strip.applyTempoEdit(edit);
}

} // namespace songview
