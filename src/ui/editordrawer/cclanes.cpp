#include "ui/editordrawer/cclanes.h"

#include <algorithm>
#include <set>

#include "core/songdocument.h"
#include "core/timedefaults.h"

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/m4asemantics.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songviewmodel.h"

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

CCLanes::CCLanes(AutomationPage *page) noexcept : m_page(page) {}

CCLanes::~CCLanes() = default;

void CCLanes::rebuildRows()
{
    m_rows.clear();
    m_rowText.clear();
    const auto appendRow = [this](const EditorAutomationRowId &id) {
        m_rows.push_back({id});
        m_rowText.emplace_back();
        m_rowText.back().title = titleFor(m_rows.back());
    };
    if (!m_page || !m_page->ready() || !m_page->timeline()) {
        syncTimeSelection();
        return;
    }
    const int track = m_page->m_owner.selectionModel().primaryTrack();
    if (track < 0) {
        syncTimeSelection();
        return;
    }
    std::vector<uint8_t> controllers;
    const auto addController = [&controllers](uint8_t controller) {
        if (std::find(controllers.cbegin(), controllers.cend(), controller) == controllers.cend())
            controllers.push_back(controller);
    };
    for (const auto &lane : m_page->model().lanes)
        if (lane.track == track)
            addController(lane.cc);
    for (const auto &row : m_page->m_viewState.emptyLanes)
        if (row.kind == EditorAutomationRowKind::ControlChange && row.track == uint8_t(track))
            addController(row.controller);
    std::sort(controllers.begin(), controllers.end());
    for (const uint8_t controller : controllers) {
        const auto row = laneRow(track, controller);
        if (!m_page->m_viewState.isLaneHidden(row))
            appendRow(row);
    }
    syncTimeSelection();
}

void CCLanes::syncTimeSelection()
{
    m_timeSelection = {};
    if (!m_page)
        return;
    const auto &selection = m_page->m_owner.selectionModel().timeSelection();
    if (!selection.active() ||
        selection.scope != songview::EditorSelectionModel::TimeSelection::Lanes)
        return;
    m_timeSelection.startTick = selection.startTick;
    m_timeSelection.endTick = selection.endTick;
    for (const auto &lane : selection.lanes) {
        const auto row = std::find_if(m_rows.cbegin(), m_rows.cend(),
                                      [this, &lane](const AutomationRow &candidate) {
                                          return rowIdentity(candidate) == lane;
                                      });
        if (row == m_rows.cend() ||
            std::find(m_timeSelection.lanes.cbegin(), m_timeSelection.lanes.cend(), lane) !=
                m_timeSelection.lanes.cend())
            continue;
        m_timeSelection.lanes.push_back(lane);
        const int rowIndex = int(row - m_rows.cbegin());
        if (m_timeSelection.firstRow < 0)
            m_timeSelection.firstRow = rowIndex;
        else
            m_timeSelection.firstRow = std::min(m_timeSelection.firstRow, rowIndex);
        m_timeSelection.lastRow = std::max(m_timeSelection.lastRow, rowIndex);
    }
}

int CCLanes::minimumHeight(const AutomationGeometry &geometry, int topInset) const
{
    const AutomationProjection projection(geometry, m_rows, m_page, topInset);
    const int rowsHeight = projection.rowTop(int(m_rows.size()));
    const int strip = m_page && m_page->document() ? geometry.addLaneStripHeight
                                                   : layout::space(layout::Space::Zero);
    return std::max(geometry.rowDefaultHeight, rowsHeight + strip);
}

bool CCLanes::clearTimeSelection()
{
    const bool wasActive = m_timeSelection.active();
    m_timeSelection = {};
    if (m_page && m_page->m_owner.selectionModel().timeSelection().active()) {
        m_page->m_owner.selectionModel().clearTimeSelection();
        return true;
    }
    return wasActive;
}

const std::vector<LanePoint> &CCLanes::pointsFor(const AutomationRow &row,
                                                 const AutomationProjection &projection) const
{
    if (const auto *lane = projection.laneFor(row))
        return lane->points;
    static const std::vector<LanePoint> empty;
    return empty;
}

QString CCLanes::titleFor(const AutomationRow &row) const
{
    return laneLabel(row.id.controller);
}

QString CCLanes::valueTextFor(const AutomationRow &row, int value) const
{
    if (m_valueTextCache.valid && m_valueTextCache.track == int(row.id.track) &&
        m_valueTextCache.controller == row.id.controller && m_valueTextCache.value == value)
        return m_valueTextCache.text;
    m_valueTextCache.track = int(row.id.track);
    m_valueTextCache.controller = row.id.controller;
    m_valueTextCache.value = value;
    if (row.id.controller == automation::kBendController)
        m_valueTextCache.text = m4aFormatBend(value);
    else
        m_valueTextCache.text = m4aFormatCcValue(row.id.controller, uint8_t(value));
    m_valueTextCache.valid = true;
    return m_valueTextCache.text;
}

bool CCLanes::rowTarget(const AutomationRow &row, int *track, uint8_t *controller) const
{
    if (!m_page || !m_page->document())
        return false;
    *track = int(row.id.track);
    *controller = row.id.controller;
    return true;
}

std::pair<int, uint8_t> CCLanes::rowIdentity(const AutomationRow &row) const
{
    return {int(row.id.track), row.id.controller};
}

bool CCLanes::selectionContains(int rowIndex, qreal x, const AutomationGeometry &geometry,
                                qreal devicePixelRatio) const
{
    if (!m_timeSelection.active() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return false;
    const auto lane = rowIdentity(m_rows[rowIndex]);
    if (!m_timeSelection.coversLane(lane.first, lane.second))
        return false;
    const qreal first =
        m_page->displayX(m_timeSelection.startTick, geometry.plotOrigin, devicePixelRatio);
    const qreal last =
        m_page->displayX(m_timeSelection.endTick, geometry.plotOrigin, devicePixelRatio);
    return x >= first && x < last;
}

bool CCLanes::pointInTimeSelection(int rowIndex, uint64_t tick) const
{
    if (!m_timeSelection.active() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return false;
    const auto lane = rowIdentity(m_rows[rowIndex]);
    return m_timeSelection.coversLane(lane.first, lane.second) && m_timeSelection.contains(tick);
}

bool CCLanes::selectionHasMultipleNodes() const
{
    if (!m_timeSelection.active() || !m_page || !m_page->document())
        return false;
    int count = 0;
    for (int rowIndex = 0; rowIndex < int(m_rows.size()); ++rowIndex) {
        const auto lane = rowIdentity(m_rows[rowIndex]);
        if (!m_timeSelection.coversLane(lane.first, lane.second))
            continue;
        int track = -1;
        uint8_t controller = 0;
        if (!rowTarget(m_rows[rowIndex], &track, &controller))
            continue;
        const auto points = m_page->document()->lanePoints(track, controller);
        for (const auto &point : points) {
            if (!m_timeSelection.contains(point.tick))
                continue;
            if (++count > 1)
                return true;
        }
    }
    return false;
}

bool CCLanes::cachedPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                             const AutomationProjection &projection,
                             const AutomationGeometry &geometry, qreal devicePixelRatio,
                             DocLanePoint *hit) const
{
    if (!m_page || !m_page->document() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return false;
    int track = -1;
    uint8_t controller = 0;
    if (!rowTarget(row, &track, &controller))
        return false;
    const auto points = m_page->document()->lanePoints(track, controller);
    if (points.empty())
        return false;
    const auto [top, bottom] = projection.valuePlotBounds(rowIndex);
    const int minimum = projection.rowMinimum(row);
    const int maximum = projection.rowMaximum(row);
    const int valueRange = std::max(1, maximum - minimum);
    const qreal radiusSquared = geometry.pointHitRadius * geometry.pointHitRadius;
    auto nearest = points.size();
    qreal nearestDistance = radiusSquared;
    for (auto index = std::size_t{0}; index < points.size(); ++index) {
        const qreal dx =
            m_page->displayX(points[index].tick, geometry.plotOrigin, devicePixelRatio) -
            position.x();
        const qreal dy =
            qreal(bottom - (points[index].value - minimum) * (bottom - top) / valueRange) -
            position.y();
        const qreal distance = dx * dx + dy * dy;
        if (distance <= nearestDistance) {
            nearestDistance = distance;
            nearest = index;
        }
    }
    if (nearest == points.size())
        return false;
    if (hit)
        *hit = points[nearest];
    return true;
}

CCLaneAdapter::CCLaneAdapter(SongDocument &document,
                             const songview::EditorSelectionModel &selection,
                             uint32_t usedTrackMask, int engineTrack, uint8_t controller) noexcept
    : m_document(document)
    , m_selection(selection)
    , m_usedTrackMask(usedTrackMask)
    , m_engineTrack(engineTrack)
    , m_controller(controller)
{}

QString CCLaneAdapter::title() const
{
    return laneLabel(m_controller);
}

std::vector<NodePoint> CCLaneAdapter::points() const
{
    std::vector<NodePoint> points;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, m_controller)) {
        if (!points.empty() && points.back().tick == point.tick)
            points.back().value = point.value;
        else
            points.push_back({point.tick, point.value});
    }
    return points;
}

int CCLaneAdapter::minimumValue() const
{
    return CoreTimeDefaults::laneValueMinimum(m_controller);
}

int CCLaneAdapter::maximumValue() const
{
    return CoreTimeDefaults::laneValueMaximum(m_controller);
}

QString CCLaneAdapter::valueText(int value) const
{
    if (m_controller == automation::kBendController)
        return m4aFormatBend(value);
    return m4aFormatCcValue(m_controller, uint8_t(value));
}

bool CCLaneAdapter::pointSelected(uint64_t tick) const
{
    if (!m_selection.timeSelectionCoversLane(m_engineTrack, m_controller, m_usedTrackMask))
        return false;
    const auto &range = m_selection.timeSelection();
    return tick >= range.startTick && tick < range.endTick;
}

void CCLaneAdapter::deletePoints(const std::vector<uint64_t> &ticks)
{
    if (ticks.empty())
        return;
    const std::set<uint64_t> tickSet(ticks.begin(), ticks.end());
    std::vector<DocLanePoint> doomed;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, m_controller)) {
        if (tickSet.contains(point.tick))
            doomed.push_back(point);
    }
    if (doomed.empty())
        return;
    m_document.deleteLanePoints(m_engineTrack, m_controller, doomed);
}

void CCLaneAdapter::movePoints(const std::vector<NodePointMove> &moves)
{
    if (moves.empty())
        return;
    const auto raw = m_document.lanePoints(m_engineTrack, m_controller);
    std::vector<SongDocument::LanePointMove> planned;
    for (const NodePointMove &move : moves) {
        std::vector<DocLanePoint> group;
        for (const DocLanePoint &point : raw) {
            if (point.tick == move.fromTick)
                group.push_back(point);
        }
        if (group.empty())
            continue;
        const int newValue = CoreTimeDefaults::clampLaneValue(m_controller, move.to.value);
        for (auto index = std::size_t{0}; index < group.size(); ++index) {
            const int value = index + 1 == group.size() ? newValue : group[index].value;
            planned.push_back({m_engineTrack, m_controller, group[index], move.to.tick, value});
        }
    }
    if (planned.empty())
        return;
    m_document.moveLanePoints(planned);
}

void CCLaneAdapter::replaceSpan(uint64_t first, uint64_t last, const std::vector<NodePoint> &points)
{
    std::vector<SongDocument::LanePointValue> written;
    written.reserve(points.size());
    for (const NodePoint &point : points)
        written.push_back({point.tick, point.value});
    std::vector<SongDocument::LanePointValue> existing;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, m_controller)) {
        if (point.tick >= first && point.tick <= last)
            existing.push_back({point.tick, point.value});
    }
    if (existing.size() == written.size() &&
        std::equal(existing.cbegin(), existing.cend(), written.cbegin(),
                   [](const SongDocument::LanePointValue &left,
                      const SongDocument::LanePointValue &right) {
                       return left.tick == right.tick && left.value == right.value;
                   }))
        return;
    m_document.writeLanePoints(m_engineTrack, m_controller, first, last, written);
}
