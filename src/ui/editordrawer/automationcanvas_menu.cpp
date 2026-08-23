#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <limits>

#include <QAction>
#include <QMenu>
#include <QMessageBox>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/m4asemantics.h"

namespace {

EditorAutomationRowId laneRow(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

QString laneLabel(uint8_t controller)
{
    if (controller == CCLanes::bendController())
        return QStringLiteral("Pitch bend (BEND)");
    const auto info = m4aClassifyCc(controller);
    return QStringLiteral("%1 (%2)").arg(QLatin1String(info.display), QLatin1String(info.name));
}

} // namespace

void AutomationCanvas::showTimeSelectionMenuFor(LaneHandle contextLane,
                                                const QPoint &globalPosition)
{
    if (!m_page)
        return;
    auto &model = m_page->m_owner.selectionModel();
    const auto &selection = model.timeSelection();
    if (selection.active()) {
        DrawerPageTimeSelectionMenuRequest request{.startTick = selection.startTick,
                                                   .endTick = selection.endTick,
                                                   .tempo = contextLane.index == 0,
                                                   .globalPosition = globalPosition};
        if (!request.tempo && m_laneSelection)
            request.lanes = m_laneSelection->visibleLanes();
        m_page->showTimeSelectionMenu(request);
        return;
    }
    QMenu menu;
    if (menu.exec(globalPosition) == menu.addAction(tr("Clear time selection")) &&
        model.timeSelection().active()) {
        model.clearTimeSelection();
        invalidateContent();
    }
}

void AutomationCanvas::showLaneMenuFor(LaneHandle handle, const QPoint &globalPosition)
{
    if (!handle.valid())
        return;
    if (handle.index == 0) {
        m_tempoLane.showTempoMenu(*this, globalPosition);
        return;
    }
    const int rowIndex = m_rowData.rowIndexFor(handle);
    if (rowIndex >= 0)
        showLaneMenu(m_rowData.rows()[std::size_t(rowIndex)], globalPosition);
}

bool AutomationCanvas::showEmptyBodyMenuFor(LaneHandle handle, const QPoint &globalPosition)
{
    if (handle.index == 0) {
        m_tempoLane.showTempoMenu(*this, globalPosition);
        return true;
    }
    return false;
}

void AutomationCanvas::showAddLaneMenu(const QPoint &globalPosition)
{
    if (!m_page)
        return;
    const int track = m_page->m_owner.selectionModel().primaryTrack();
    if (track < 0)
        return;
    const uint8_t candidates[] = {1, 7, 10, 20, 21, CCLanes::bendController()};
    QMenu menu;
    std::vector<EditorAutomationRowId> hidden;
    for (const uint8_t controller : candidates) {
        const auto row = laneRow(track, controller);
        if (m_page->m_viewState.isLaneHidden(row) || m_page->model().findLane(track, controller) ||
            m_page->m_viewState.emptyLanes.find(row) != m_page->m_viewState.emptyLanes.cend())
            continue;
        auto *action = menu.addAction(laneLabel(controller));
        action->setData(int(controller));
    }
    for (const auto &row : m_page->m_viewState.hiddenLanes())
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            hidden.push_back(row);
    if (menu.isEmpty())
        menu.addAction(tr("All parameters already have CC lanes"))->setEnabled(false);
    if (!hidden.empty()) {
        menu.addSeparator();
        menu.addAction(tr("Hidden CC lanes"))->setEnabled(false);
        for (const auto &row : hidden) {
            auto *action = menu.addAction(tr("Show: %1 (hidden)").arg(laneLabel(row.controller)));
            action->setData(256 + int(row.controller));
        }
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen || !chosen->data().isValid())
        return;
    const int value = chosen->data().toInt();
    if (value >= 256) {
        const auto row = laneRow(track, uint8_t(value - 256));
        if (m_page->m_viewState.unhideLane(row)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Showed the %1 CC lane").arg(laneLabel(row.controller)));
        }
    } else {
        m_page->addEmptyLane(track, uint8_t(value));
        m_page->announce(tr("Added %1 CC lane").arg(laneLabel(uint8_t(value))));
    }
}

void AutomationCanvas::showLaneMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    const auto documentPoints =
        m_page && m_page->document()
            ? m_page->document()->lanePoints(int(row.id.track), row.id.controller)
            : std::vector<DocLanePoint>{};
    const bool empty = documentPoints.empty();
    QMenu menu;
    QAction *copy = menu.addAction(tr("Copy CC lane"));
    copy->setEnabled(!empty);
    QAction *paste = menu.addAction(tr("Paste CC lane (replace)"));
    paste->setEnabled(!m_clipboard.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(tr("Clear events"));
    clear->setEnabled(!empty);
    QAction *remove = menu.addAction(empty ? tr("Remove empty CC lane") : tr("Delete CC lane"));
    QAction *hide = menu.addAction(tr("Hide CC lane"));
    std::vector<std::pair<QAction *, uint8_t>> ranges;
    if (CCLanes::rangeZoomable(row.id.controller)) {
        auto *rangeMenu = menu.addMenu(tr("Value range"));
        const auto range = m_page->m_viewState.laneRanges.find(row.id);
        const uint8_t current = range == m_page->m_viewState.laneRanges.cend()
                                    ? CCLanes::defaultRange(row.id.controller)
                                    : range->second;
        for (const uint8_t value :
             {uint8_t(0), uint8_t(16), uint8_t(32), uint8_t(64), uint8_t(127)}) {
            const QString label = value == 0     ? tr("Auto (fit to data)")
                                  : value == 127 ? tr("0–127 (full)")
                                                 : QStringLiteral("0–%1").arg(value);
            auto *action = rangeMenu->addAction(label);
            action->setCheckable(true);
            action->setChecked(value == current);
            ranges.emplace_back(action, value);
        }
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen)
        return;
    for (const auto &[action, range] : ranges) {
        if (chosen == action) {
            m_page->setLaneRange(row.id, range);
            return;
        }
    }
    const int track = int(row.id.track);
    const uint8_t controller = row.id.controller;
    auto *document = m_page->document();
    const auto points = document->lanePoints(track, controller);
    bool changed = false;
    if (chosen == copy) {
        m_clipboard.clear();
        for (const auto &point : points)
            m_clipboard.push_back({point.tick, point.value});
        m_page->announce(tr("Copied the %1 CC lane (%n point(s))", nullptr, int(points.size()))
                             .arg(m_rowData.titleFor(row)));
    } else if (chosen == paste) {
        std::vector<NodeLaneEdit::Point> replacementPoints;
        replacementPoints.reserve(m_clipboard.size());
        const int minimum = CoreTimeDefaults::laneValueMinimum(controller);
        const int maximum = CoreTimeDefaults::laneValueMaximum(controller);
        for (const auto &point : m_clipboard)
            replacementPoints.push_back({point.tick, std::clamp(point.value, minimum, maximum)});
        LaneHandle handle;
        for (int i = 0; i < int(m_rowData.rows().size()); ++i) {
            if (m_rowData.rows()[std::size_t(i)].id.track == row.id.track &&
                m_rowData.rows()[std::size_t(i)].id.controller == row.id.controller) {
                handle = LaneHandle{i + 1};
                break;
            }
        }
        std::vector<NodePoint> original;
        original.reserve(points.size());
        for (const auto &point : points)
            original.push_back({point.tick, point.value});
        auto completion = NodeLaneEdit({handle, document->revision()}, std::move(original))
                              .replacePointRange(0, std::numeric_limits<uint64_t>::max(),
                                                 std::move(replacementPoints));
        if (!completion.unchanged) {
            SongDocument::RangeEdit edit;
            edit.removePoints = points;
            std::vector<SongDocument::LanePointValue> lanePoints;
            lanePoints.reserve(completion.points.size());
            for (const auto &point : completion.points)
                lanePoints.push_back({point.tick, point.value});
            SongDocument::RangeEdit::LaneWrite replacement{track, controller,
                                                           std::move(lanePoints)};
            edit.addPoints.push_back(std::move(replacement));
            document->applyRangeEdit(tr("paste CC lane"), edit);
            changed = true;
            m_page->announce(tr("Replaced the %1 CC lane").arg(m_rowData.titleFor(row)));
        }
    } else if (chosen == clear) {
        if (!points.empty()) {
            m_page->addEmptyLane(track, controller);
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == remove) {
        if (!points.empty() && QMessageBox::question(this, tr("Delete CC lane"),
                                                     tr("Delete the %1 CC lane and its %2 events?")
                                                         .arg(m_rowData.titleFor(row))
                                                         .arg(points.size())) != QMessageBox::Yes)
            return;
        m_page->removeEmptyLane(track, controller);
        if (!points.empty()) {
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == hide) {
        if (m_page->m_viewState.hideLane(row.id)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Hid the %1 CC lane").arg(m_rowData.titleFor(row)));
        }
    }
    if (changed)
        m_page->requestRefresh();
}
