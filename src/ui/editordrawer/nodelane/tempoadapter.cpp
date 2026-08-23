#include "ui/editordrawer/tempolane.h"

#include <QCoreApplication>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/songview/editorselectionmodel.h"

QString TempoLane::title() const
{
    return QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)");
}

std::vector<NodePoint> TempoLane::points() const
{
    std::vector<NodePoint> points;
    const SongDocument *document = boundDocument();
    if (!document)
        return points;
    const auto &tempoPoints = document->tempoPoints();
    points.reserve(tempoPoints.size());
    for (const TempoPoint &point : tempoPoints)
        points.push_back(
            {point.tick, qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote))});
    return points;
}

int TempoLane::minimumValue() const
{
    return CoreTimeDefaults::kMinTempoBpm;
}

int TempoLane::maximumValue() const
{
    return CoreTimeDefaults::kMaxTempoBpm;
}

QString TempoLane::valueText(int value) const
{
    return QString::number(value);
}

std::optional<NodePoint> TempoLane::leadIn() const
{
    const SongDocument *document = boundDocument();
    if (!document)
        return std::nullopt;
    const auto &tempoPoints = document->tempoPoints();
    if (tempoPoints.empty() || tempoPoints.front().tick == 0)
        return std::nullopt;
    return NodePoint{0, CoreTimeDefaults::kTempoBpm};
}

bool TempoLane::pointSelected(uint64_t tick) const
{
    const auto *selection = boundSelection();
    if (!selection || !selection->timeSelectionCoversTempo(boundUsedTrackMask()))
        return false;
    const auto &range = selection->timeSelection();
    return tick >= range.startTick && tick < range.endTick;
}

void TempoLane::replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points)
{
    SongDocument *document = boundDocument();
    if (!document)
        return;
    const auto &tempoPoints = document->tempoPoints();
    TempoEdit edit;
    for (const TempoPoint &point : tempoPoints) {
        if (point.tick >= first && point.tick <= last)
            edit.remove.push_back(point);
    }
    edit.add.reserve(points.size());
    for (const NodePoint &point : points)
        edit.add.push_back(
            {point.tick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(point.value)});
    document->applyTempoEdit(edit);
    if (m_page)
        m_page->requestRefresh();
}

SongDocument *TempoLane::boundDocument() const noexcept
{
    return m_page ? m_page->document() : m_document;
}

const songview::EditorSelectionModel *TempoLane::boundSelection() const noexcept
{
    return m_page ? &m_page->m_owner.selectionModel() : m_selection;
}

uint32_t TempoLane::boundUsedTrackMask() const noexcept
{
    return m_page ? m_page->usedTrackMask() : m_usedTrackMask;
}
