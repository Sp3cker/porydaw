#include "ui/editordrawer/tempolane.h"

#include <algorithm>

#include <QCoreApplication>
#include <QInputDialog>

#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"

namespace {

QString translated(const char *text)
{
    return QCoreApplication::translate("AutomationCanvas", text);
}

EditorAutomationRowId tempoHeightKey()
{
    return {EditorAutomationRowKind::Tempo, 0, 0};
}

} // namespace

TempoLane::TempoLane(AutomationPage *page) noexcept : m_page(page) {}

TempoLane::TempoLane(SongDocument &document) noexcept : m_document(&document) {}

void TempoLane::updateLayout(int width, int top, int gutterWidth,
                             const AutomationGeometry &geometry)
{
    // Expanded, the lane is a single automation row: the header shrinks to
    // the resolved physical gutter (the collapse click target) while the body
    // spans the full row. Collapsed, only a thin caption strip remains.
    const int height = totalHeight(geometry);
    m_header = {layout::space(layout::Space::Zero), top, m_expanded ? gutterWidth : width, height};
    m_body = {layout::space(layout::Space::Zero), top, width, m_expanded ? height : 0};
}

int TempoLane::totalHeight(const AutomationGeometry &geometry) const
{
    return m_expanded ? bodyHeight(geometry) : collapsedHeight(geometry);
}

bool TempoLane::containsHeader(const QPoint &position) const
{
    return m_header.contains(position);
}

void TempoLane::toggleExpanded()
{
    m_expanded = !m_expanded;
}

void TempoLane::cancel() {}

int TempoLane::collapsedHeight(const AutomationGeometry &geometry) const
{
    return geometry.addLaneStripHeight;
}

int TempoLane::bodyHeight(const AutomationGeometry &geometry) const
{
    if (!m_page)
        return geometry.rowDefaultHeight;
    return std::clamp(m_page->laneHeightFor(tempoHeightKey()), geometry.rowMinimumHeight,
                      geometry.rowMaximumHeight);
}

bool TempoLane::promptValue(QWidget *parent, int currentValue, int *storedValue) const
{
    bool accepted = false;
    const int entered = QInputDialog::getInt(
        parent, translated("Set tempo"), translated("BPM:"),
        std::clamp(currentValue, CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm),
        CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm, 1, &accepted);
    if (!accepted)
        return false;
    *storedValue = entered;
    return true;
}
