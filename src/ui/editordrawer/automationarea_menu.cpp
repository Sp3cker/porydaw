#include "ui/editordrawer/automationarea.h"

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
    if (controller == automation::kBendController)
        return QStringLiteral("Pitch bend (BEND)");
    const auto info = m4aClassifyCc(controller);
    return QStringLiteral("%1 (%2)").arg(QLatin1String(info.display), QLatin1String(info.name));
}

} // namespace

void AutomationArea::showAddLaneMenu(const QPoint &globalPosition)
{
    if (!m_page)
        return;
    const int track = m_page->m_owner.selectionModel().primaryTrack();
    if (track < 0)
        return;
    static constexpr uint8_t candidates[] = {1, 7, 10, 20, 21, automation::kBendController};
    QMenu menu;
    std::vector<EditorAutomationRowId> hidden;
    for (const uint8_t controller : candidates) {
        const auto row = laneRow(track, controller);
        if (m_page->m_viewState.isLaneHidden(row) || projection().laneFor({row}) ||
            m_page->m_viewState.emptyLanes.find(row) != m_page->m_viewState.emptyLanes.cend())
            continue;
        auto *action = menu.addAction(laneLabel(controller));
        action->setData(int(controller));
    }
    for (const auto &row : m_page->m_viewState.hiddenLanes())
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            hidden.push_back(row);
    if (menu.isEmpty())
        menu.addAction(tr("All parameters already have lanes"))->setEnabled(false);
    if (!hidden.empty()) {
        menu.addSeparator();
        menu.addAction(tr("Hidden lanes"))->setEnabled(false);
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
            m_page->announce(tr("Showed the %1 lane").arg(laneLabel(row.controller)));
        }
    } else {
        m_page->addEmptyLane(track, uint8_t(value));
        m_page->announce(tr("Added %1 lane").arg(laneLabel(uint8_t(value))));
    }
}

void AutomationArea::showLaneMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    const bool empty = m_rowData.pointsFor(row, projection()).empty();
    QMenu menu;
    QAction *copy = menu.addAction(tr("Copy lane"));
    copy->setEnabled(!empty);
    QAction *paste = menu.addAction(tr("Paste lane (replace)"));
    paste->setEnabled(!m_clipboard.empty());
    menu.addSeparator();
    QAction *clear = menu.addAction(tr("Clear events"));
    clear->setEnabled(!empty);
    QAction *remove = menu.addAction(empty ? tr("Remove empty lane") : tr("Delete lane"));
    QAction *hide = menu.addAction(tr("Hide lane"));
    std::vector<std::pair<QAction *, uint8_t>> ranges;
    if (automation::rangeZoomable(row.id.controller)) {
        auto *rangeMenu = menu.addMenu(tr("Value range"));
        const auto range = m_page->m_viewState.laneRanges.find(row.id);
        const uint8_t current = range == m_page->m_viewState.laneRanges.cend()
                                    ? automation::defaultRange(row.id.controller)
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
        m_page->announce(tr("Copied the %1 lane (%n point(s))", nullptr, int(points.size()))
                             .arg(m_rowData.titleFor(row)));
    } else if (chosen == paste) {
        std::vector<SongDocument::LanePointValue> replacementPoints;
        replacementPoints.reserve(m_clipboard.size());
        const int minimum = CoreTimeDefaults::laneValueMinimum(controller);
        const int maximum = CoreTimeDefaults::laneValueMaximum(controller);
        for (const auto &point : m_clipboard)
            replacementPoints.push_back({point.tick, std::clamp(point.value, minimum, maximum)});
        auto completion =
            AutomationLaneEdit({track, controller, document->revision()}, laneEditPoints(points))
                .replacePointRange(0, std::numeric_limits<uint64_t>::max(),
                                   std::move(replacementPoints));
        if (!completion.unchanged) {
            SongDocument::RangeEdit edit;
            edit.removePoints = points;
            SongDocument::RangeEdit::LaneWrite replacement{track, controller,
                                                           std::move(completion.points)};
            edit.addPoints.push_back(std::move(replacement));
            document->applyRangeEdit(tr("paste lane"), edit);
            changed = true;
            m_page->announce(tr("Replaced the %1 lane").arg(m_rowData.titleFor(row)));
        }
    } else if (chosen == clear) {
        if (!points.empty()) {
            m_page->addEmptyLane(track, controller);
            document->deleteLanePoints(track, controller, points);
            changed = true;
        }
    } else if (chosen == remove) {
        if (!points.empty() && QMessageBox::question(this, tr("Delete lane"),
                                                     tr("Delete the %1 lane and its %2 events?")
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
            m_page->announce(tr("Hid the %1 lane").arg(m_rowData.titleFor(row)));
        }
    }
    if (changed)
        m_page->requestRefresh();
}

void AutomationArea::showVoiceMenu(const AutomationRow &row, const QPoint &globalPosition)
{
    Q_UNUSED(row);
    if (!m_page || !m_page->document())
        return;
    const int track = m_page->m_owner.selectionModel().primaryTrack();
    if (track < 0)
        return;
    const qreal x = mapFromGlobal(globalPosition).x();
    const qreal dpr = devicePixelRatioF();
    const auto points = m_page->document()->lanePoints(track, DOC_CC_VOICE);
    const DocLanePoint *marker = nullptr;
    qreal distance = m_geometry.deleteTimeRadius + 1;
    for (const auto &point : points) {
        const qreal candidate =
            std::abs(m_page->displayX(point.tick, m_geometry.plotOrigin, dpr) - x);
        if (candidate <= m_geometry.deleteTimeRadius && (!marker || candidate <= distance)) {
            marker = &point;
            distance = candidate;
        }
    }
    const uint64_t tick =
        marker ? marker->tick : m_page->snapTick(projection().rawTickAt(x), false);
    int current = marker ? marker->value : 0;
    if (!marker)
        current = m_page->voiceContext(tick).voiceSlot;
    if (!marker) {
        for (const auto &point : points) {
            if (point.tick > tick)
                break;
            current = point.value;
        }
    }
    int selectedVoice = 0;
    if (!m_page->pickVoice(marker ? tr("Change voice") : tr("Insert voice change"),
                           std::max(0, current), &selectedVoice))
        return;
    DocLanePoint existing;
    bool changed = false;
    if (m_page->document()->findLanePoint(track, DOC_CC_VOICE, tick, &existing)) {
        if (existing.value != selectedVoice) {
            m_page->document()->moveLanePoints(
                {{track, DOC_CC_VOICE, existing, tick, selectedVoice}});
            changed = true;
        }
    } else {
        m_page->document()->addLanePoint(track, DOC_CC_VOICE, tick, selectedVoice);
        changed = true;
    }
    if (changed)
        m_page->requestRefresh();
}
