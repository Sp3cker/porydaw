#include "ui/editordrawer/automationcanvas.h"

#include <QAction>
#include <QMenu>
#include <QMessageBox>
#include <algorithm>
#include <limits>
#include <optional>
#include <vector>

#include "ui/editordrawer/automationpage.h"

namespace {

EditorAutomationRowId laneRow(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

// Per-kind presentation for the unified lane menu; built once via the slot
// visit so the menu body carries no tempo/CC branching.
struct LaneMenuKind {
    QString copyLabel;
    QString pasteLabel;
    QString clearLabel;
    QString copiedMessage;
    QString pastedMessage;
    std::optional<QString> clearedMessage;
    bool hasLaneActions = false;
};

} // namespace

void AutomationCanvas::showTimeSelectionMenuFor(LaneHandle contextLane,
                                                const QPoint &globalPosition)
{
    if (!m_page)
        return;
    const auto *slot = resolveSlot(contextLane);
    if (!slot)
        return;
    auto &model = m_page->m_owner.selectionModel();
    const auto &selection = model.timeSelection();
    if (selection.active()) {
        DrawerPageTimeSelectionMenuRequest request{.startTick = selection.startTick,
                                                   .endTick = selection.endTick,
                                                   .tempo = slot->isTempo(),
                                                   .globalPosition = globalPosition};
        if (!request.tempo)
            request.lanes = m_laneSelection.visibleLanes();
        m_page->showTimeSelectionMenu(request);
        return;
    }
    QMenu menu;
    QAction *clear = menu.addAction(tr("Clear time selection"));
    if (menu.exec(globalPosition) == clear && model.timeSelection().active()) {
        model.clearTimeSelection();
        invalidateContent();
    }
}

void AutomationCanvas::showLaneMenuFor(LaneHandle handle, const QPoint &globalPosition)
{
    const auto *slot = resolveSlot(handle);
    if (!m_page || !slot || !slot->lane)
        return;
    NodeLane *lane = slot->lane;
    const auto rowId = slot->id;
    const QString laneTitle = lane->title();
    const auto points = lane->points();
    const LaneMenuKind kind = slot->visit(
        [&] {
            return LaneMenuKind{tr("Copy"),
                                tr("Paste"),
                                tr("Clear Tempo"),
                                tr("Copied Tempo"),
                                tr("Pasted Tempo"),
                                tr("Cleared Tempo"),
                                false};
        },
        [&] {
            return LaneMenuKind{
                tr("Copy CC lane"),
                tr("Paste CC lane (replace)"),
                tr("Clear events"),
                tr("Copied the %1 CC lane (%n point(s))", nullptr, int(points.size()))
                    .arg(laneTitle),
                tr("Replaced the %1 CC lane").arg(laneTitle),
                std::nullopt,
                true};
        });
    QMenu menu;
    QAction *copy = menu.addAction(kind.copyLabel);
    copy->setEnabled(!points.empty());
    QAction *paste = menu.addAction(kind.pasteLabel);
    paste->setEnabled(!m_clipboard.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(kind.clearLabel);
    clear->setEnabled(!points.empty());
    QAction *remove = nullptr;
    QAction *hide = nullptr;
    std::vector<std::pair<QAction *, uint8_t>> ranges;
    if (kind.hasLaneActions) {
        const uint8_t controller = rowId.controller;
        const bool empty = points.empty();
        remove = menu.addAction(empty ? tr("Remove empty CC lane") : tr("Delete CC lane"));
        hide = menu.addAction(tr("Hide CC lane"));
        if (CCLanes::rangeZoomable(controller)) {
            auto *rangeMenu = menu.addMenu(tr("Value range"));
            const auto range = m_page->m_viewState.laneRanges.find(rowId);
            const uint8_t current = range == m_page->m_viewState.laneRanges.cend()
                                        ? CCLanes::defaultRange(controller)
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
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen)
        return;
    for (const auto &[action, range] : ranges) {
        if (chosen == action) {
            m_page->setLaneRange(rowId, range);
            return;
        }
    }
    const auto maxTick = std::numeric_limits<uint64_t>::max();
    if (chosen == copy) {
        m_clipboard = points;
        m_page->announce(kind.copiedMessage);
    } else if (chosen == paste) {
        std::vector<NodePoint> replacement;
        replacement.reserve(m_clipboard.size());
        const int minimum = lane->minimumValue();
        const int maximum = lane->maximumValue();
        for (const auto &point : m_clipboard)
            replacement.push_back({point.tick, std::clamp(point.value, minimum, maximum)});
        lane->replaceSpan(0, maxTick, replacement);
        m_page->requestRefresh();
        m_page->announce(kind.pastedMessage);
    } else if (chosen == clear) {
        lane->replaceSpan(0, maxTick, {});
        if (kind.hasLaneActions)
            m_page->addEmptyLane(int(rowId.track), rowId.controller);
        m_page->requestRefresh();
        if (kind.clearedMessage)
            m_page->announce(*kind.clearedMessage);
    } else if (kind.hasLaneActions && chosen == remove) {
        const int track = int(rowId.track);
        const uint8_t controller = rowId.controller;
        if (!points.empty() &&
            QMessageBox::question(
                this, tr("Delete CC lane"),
                tr("Delete the %1 CC lane and its %2 events?").arg(laneTitle).arg(points.size())) !=
                QMessageBox::Yes)
            return;
        if (!points.empty())
            lane->replaceSpan(0, maxTick, {});
        m_page->removeEmptyLane(track, controller);
        if (points.empty() && CoreTimeDefaults::isDefaultVisibleController(controller) &&
            m_page->m_viewState.hideLane(rowId)) {
            m_page->publishViewState();
            rebuildRows();
        }
        m_page->requestRefresh();
    } else if (kind.hasLaneActions && chosen == hide) {
        if (m_page->m_viewState.hideLane(rowId)) {
            m_page->publishViewState();
            rebuildRows();
            m_page->announce(tr("Hid the %1 CC lane").arg(laneTitle));
        }
    }
}

void AutomationCanvas::showAddLaneMenu(const QPoint &globalPosition)
{
    if (!m_page)
        return;
    const int track = m_page->m_owner.selectionModel().primaryTrack();
    if (track < 0)
        return;
    std::vector<uint8_t> candidates{CoreTimeDefaults::kCcModulation, CoreTimeDefaults::kCcVolume,
                                    CoreTimeDefaults::kCcPan, CoreTimeDefaults::kCcBendRange,
                                    CoreTimeDefaults::kCcLfoSpeed};
    for (const xcmd::Descriptor &descriptor : xcmd::laneDescriptors())
        candidates.push_back(descriptor.laneController);
    candidates.push_back(CCLanes::bendController());
    QMenu menu;
    std::vector<EditorAutomationRowId> hidden;
    for (const uint8_t controller : candidates) {
        const auto row = laneRow(track, controller);
        if (m_page->m_viewState.isLaneHidden(row) || m_page->model().findLane(track, controller) ||
            m_page->m_viewState.emptyLanes.find(row) != m_page->m_viewState.emptyLanes.cend())
            continue;
        auto *action = menu.addAction(CCLanes::laneLabel(controller));
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
            auto *action =
                menu.addAction(tr("Show: %1 (hidden)").arg(CCLanes::laneLabel(row.controller)));
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
            m_page->announce(tr("Showed the %1 CC lane").arg(CCLanes::laneLabel(row.controller)));
        }
    } else {
        m_page->addEmptyLane(track, uint8_t(value));
        m_page->announce(tr("Added %1 CC lane").arg(CCLanes::laneLabel(uint8_t(value))));
    }
}
