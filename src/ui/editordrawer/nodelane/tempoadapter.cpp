#include "ui/editordrawer/tempolane.h"

#include <QCoreApplication>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"

QString TempoLane::title() const
{
    return QCoreApplication::translate("AutomationCanvas", "Tempo (BPM)");
}

std::vector<NodePoint> TempoLane::points() const
{
    std::vector<NodePoint> points;
    const SongDocument *document = m_page ? m_page->document() : m_document;
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
    const SongDocument *document = m_page ? m_page->document() : m_document;
    if (!document)
        return std::nullopt;
    const auto &tempoPoints = document->tempoPoints();
    if (tempoPoints.empty() || tempoPoints.front().tick == 0)
        return std::nullopt;
    return NodePoint{0, CoreTimeDefaults::kTempoBpm};
}

void TempoLane::replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points)
{
    SongDocument *document = m_page ? m_page->document() : m_document;
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
}
