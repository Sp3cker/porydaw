#include "ui/editordrawer/automationrows.h"

#include <algorithm>
#include <cstring>
#include <limits>

#include <QCoreApplication>

#include "ui/editordrawer/automationarea.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/m4asemantics.h"

namespace {

EditorAutomationRowId voiceRow(int track)
{
    return {EditorAutomationRowKind::Voice, uint8_t(track), DOC_CC_VOICE};
}

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

QString translated(const char *text)
{
    return QCoreApplication::translate("AutomationArea", text);
}

} // namespace

AutomationRows::AutomationRows(AutomationPage *page) noexcept : m_page(page) {}

void AutomationRows::rebuildRows()
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
    bool hasVoice = m_page->document() != nullptr;
    for (const auto &change : m_page->model().voices) {
        if (change.track == track) {
            hasVoice = true;
            break;
        }
    }
    if (hasVoice)
        appendRow(voiceRow(track));
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

void AutomationRows::syncTimeSelection()
{
    m_timeSelection = {};
    if (!m_page)
        return;
    const auto &selection = m_page->m_owner.selectionModel().timeSelection();
    if (!selection.active() ||
        selection.scope != songview::EditorSelectionModel::TimeSelection::Lanes)
        return;
    m_timeSelection.range = {selection.startTick, selection.endTick};
    for (const auto &lane : selection.lanes) {
        const auto row = std::find_if(m_rows.cbegin(), m_rows.cend(),
                                      [this, &lane](const AutomationRow &candidate) {
                                          return rowIdentity(candidate) == lane;
                                      });
        if (row == m_rows.cend() ||
            std::find(m_timeSelection.scope.lanes.cbegin(), m_timeSelection.scope.lanes.cend(),
                      lane) != m_timeSelection.scope.lanes.cend())
            continue;
        m_timeSelection.scope.lanes.push_back(lane);
        const int rowIndex = int(row - m_rows.cbegin());
        if (m_timeSelection.firstRow < 0)
            m_timeSelection.firstRow = rowIndex;
        else
            m_timeSelection.firstRow = std::min(m_timeSelection.firstRow, rowIndex);
        m_timeSelection.lastRow = std::max(m_timeSelection.lastRow, rowIndex);
    }
}

void AutomationRows::applyHeight(AutomationArea &area, const AutomationGeometry &geometry,
                                 int topInset) const
{
    const AutomationProjection projection(geometry, m_rows, m_page, topInset);
    const int rowsHeight = projection.rowTop(int(m_rows.size()));
    const int strip = m_page && m_page->document() ? geometry.addLaneStripHeight
                                                   : layout::space(layout::Space::Zero);
    area.setMinimumHeight(std::max(geometry.rowDefaultHeight, rowsHeight + strip));
}

bool AutomationRows::clearTimeSelection()
{
    const bool wasActive = m_timeSelection.active();
    m_timeSelection = {};
    if (m_page && m_page->m_owner.selectionModel().timeSelection().active()) {
        m_page->m_owner.selectionModel().clearTimeSelection();
        return true;
    }
    return wasActive;
}

const std::vector<LanePoint> &
AutomationRows::pointsFor(const AutomationRow &row, const AutomationProjection &projection) const
{
    if (const auto *lane = projection.laneFor(row))
        return lane->points;
    static const std::vector<LanePoint> empty;
    return empty;
}

QString AutomationRows::titleFor(const AutomationRow &row) const
{
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return translated("Voice");
    return laneLabel(row.id.controller);
}

const AutomationRows::VoicePaintText &AutomationRows::voicePaintTextFor(int program) const
{
    static const VoicePaintText invalid;
    if (program < 0 || program >= VOICEGROUP_SIZE)
        return invalid;
    auto &cache = m_voicePaintTexts[std::size_t(program)];
    const auto *voicegroup = m_page ? m_page->voicegroup() : nullptr;
    const int type = voicegroup ? int(voicegroup->voices[program].type) : -1;
    const char *sourceName = voicegroup ? voicegroup->voiceNames[program] : "";
    if (cache.group == voicegroup && cache.type == type &&
        std::strncmp(cache.sourceName.data(), sourceName, VG_VOICE_NAME_LEN) == 0 &&
        !cache.label.isEmpty())
        return cache;
    cache.group = voicegroup;
    cache.type = type;
    std::strncpy(cache.sourceName.data(), sourceName, cache.sourceName.size() - 1);
    cache.sourceName.back() = '\0';
    QString name;
    QString typeName;
    if (voicegroup) {
        name = QString::fromUtf8(cache.sourceName.data()).trimmed();
        typeName = m4aVoiceTypeName(voicegroup->voices[program].type);
    }
    const QString shortName = name.isEmpty() ? (typeName.isEmpty() ? translated("Voice") : typeName)
                                             : QStringLiteral("%1 (%2)").arg(name, typeName);
    cache.label = QStringLiteral("%1 %2").arg(program, 3, 10, QLatin1Char('0')).arg(shortName);
    cache.hoverLabel =
        QStringLiteral("→ %1 %2").arg(program, 3, 10, QLatin1Char('0')).arg(shortName);
    return cache;
}

QString AutomationRows::valueTextFor(const AutomationRow &row, int value) const
{
    if (m_valueTextCache.valid && m_valueTextCache.row == row.id && m_valueTextCache.value == value)
        return m_valueTextCache.text;
    m_valueTextCache.row = row.id;
    m_valueTextCache.value = value;
    if (row.id.controller == automation::kBendController)
        m_valueTextCache.text = m4aFormatBend(value);
    else
        m_valueTextCache.text = m4aFormatCcValue(row.id.controller, uint8_t(value));
    m_valueTextCache.valid = true;
    return m_valueTextCache.text;
}

bool AutomationRows::rowTarget(const AutomationRow &row, int *track, uint8_t *controller) const
{
    if (!m_page || !m_page->document())
        return false;
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return false;
    *track = int(row.id.track);
    *controller = row.id.controller;
    return true;
}

std::pair<int, uint8_t> AutomationRows::rowIdentity(const AutomationRow &row) const
{
    if (row.id.kind == EditorAutomationRowKind::Voice)
        return {m_page ? m_page->m_owner.selectionModel().primaryTrack() : -1, DOC_CC_VOICE};
    return {int(row.id.track), row.id.controller};
}

bool AutomationRows::selectionContains(int rowIndex, qreal x, const AutomationGeometry &geometry,
                                       qreal devicePixelRatio) const
{
    if (!m_timeSelection.active() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return false;
    const auto lane = rowIdentity(m_rows[rowIndex]);
    if (!m_timeSelection.scope.coversLane(lane.first, lane.second))
        return false;
    const qreal first =
        m_page->displayX(m_timeSelection.range.startTick, geometry.plotOrigin, devicePixelRatio);
    const qreal last =
        m_page->displayX(m_timeSelection.range.endTick, geometry.plotOrigin, devicePixelRatio);
    return x >= first && x < last;
}

bool AutomationRows::pointInTimeSelection(int rowIndex, uint64_t tick) const
{
    if (!m_timeSelection.active() || rowIndex < 0 || rowIndex >= int(m_rows.size()))
        return false;
    const auto lane = rowIdentity(m_rows[rowIndex]);
    return m_timeSelection.scope.coversLane(lane.first, lane.second) &&
           m_timeSelection.range.contains(tick);
}

bool AutomationRows::selectionHasMultipleNodes() const
{
    if (!m_timeSelection.active() || !m_page || !m_page->document())
        return false;
    int count = 0;
    for (int rowIndex = 0; rowIndex < int(m_rows.size()); ++rowIndex) {
        const auto lane = rowIdentity(m_rows[rowIndex]);
        if (!m_timeSelection.scope.coversLane(lane.first, lane.second))
            continue;
        int track = -1;
        uint8_t controller = 0;
        if (!rowTarget(m_rows[rowIndex], &track, &controller))
            continue;
        const auto points = m_page->document()->lanePoints(track, controller);
        for (const auto &point : points) {
            if (!m_timeSelection.range.contains(point.tick))
                continue;
            if (++count > 1)
                return true;
        }
    }
    return false;
}

LaneNodeDragState
AutomationRows::collectSelectedNodeDrags(const AutomationProjection &projection) const
{
    LaneNodeDragState result;
    if (!m_timeSelection.active() || !m_page || !m_page->document())
        return result;
    for (int rowIndex = 0; rowIndex < int(m_rows.size()); ++rowIndex) {
        const auto lane = rowIdentity(m_rows[rowIndex]);
        if (!m_timeSelection.scope.coversLane(lane.first, lane.second))
            continue;
        int track = -1;
        uint8_t controller = 0;
        if (!rowTarget(m_rows[rowIndex], &track, &controller))
            continue;
        const auto docPoints = m_page->document()->lanePoints(track, controller);
        for (const auto &point : docPoints) {
            if (!m_timeSelection.range.contains(point.tick))
                continue;
            const DocLanePoint documentPoint{point.smfTrack, point.index, point.tick, point.value};
            result.gesture.points.push_back({rowIndex,
                                             {documentPoint.tick, documentPoint.value},
                                             {documentPoint.tick, documentPoint.value},
                                             projection.rowMinimum(m_rows[rowIndex]),
                                             projection.rowMaximum(m_rows[rowIndex])});
            result.identities.push_back({track, controller, documentPoint});
        }
    }
    return result;
}

bool AutomationRows::cachedPointHit(const AutomationRow &row, int rowIndex, const QPointF &position,
                                    const AutomationProjection &projection,
                                    const AutomationGeometry &geometry, qreal devicePixelRatio,
                                    DocLanePoint *hit) const
{
    if (!m_page || !m_page->document() || row.id.kind == EditorAutomationRowKind::Voice ||
        rowIndex < 0 || rowIndex >= int(m_rows.size()))
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
    const auto pointIndex = nearestPointInRadius(
        points, projection.rawTickAt(position.x()), position, geometry.pointHitRadius,
        [this, &geometry, devicePixelRatio](const DocLanePoint &point) {
            return m_page->displayX(point.tick, geometry.plotOrigin, devicePixelRatio);
        },
        [top, bottom, minimum, valueRange](const DocLanePoint &point) {
            return qreal(bottom - (point.value - minimum) * (bottom - top) / valueRange);
        });
    if (!pointIndex)
        return false;
    if (hit)
        *hit = points[*pointIndex];
    return true;
}

std::optional<LaneNodeDragState>
AutomationRows::nodeDragGestureAt(int rowIndex, const QPointF &position, bool axisLockArmed,
                                  const AutomationProjection &projection, bool pencilMode,
                                  const AutomationGeometry &geometry, qreal devicePixelRatio) const
{
    if (rowIndex < 0 || rowIndex >= int(m_rows.size()) ||
        m_rows[rowIndex].id.kind == EditorAutomationRowKind::Voice || !m_page ||
        !m_page->document() || (pencilMode && !projection.nodeMarkersVisible()))
        return std::nullopt;
    DocLanePoint hit;
    if (!cachedPointHit(m_rows[rowIndex], rowIndex, position, projection, geometry,
                        devicePixelRatio, &hit))
        return std::nullopt;
    int track = -1;
    uint8_t controller = 0;
    if (!rowTarget(m_rows[rowIndex], &track, &controller))
        return std::nullopt;
    LaneNodeDragState state;
    state.gesture.row = rowIndex;
    const NodeDrag grabbed{rowIndex,
                           {hit.tick, hit.value},
                           {hit.tick, hit.value},
                           projection.rowMinimum(m_rows[rowIndex]),
                           projection.rowMaximum(m_rows[rowIndex])};
    const LaneNodeIdentity grabbedIdentity{track, controller, hit};
    if (pointInTimeSelection(rowIndex, hit.tick)) {
        auto selected = collectSelectedNodeDrags(projection);
        const auto grabbedPosition =
            std::find_if(selected.identities.cbegin(), selected.identities.cend(),
                         [&hit](const LaneNodeIdentity &identity) {
                             return identity.documentPoint.smfTrack == hit.smfTrack &&
                                    identity.documentPoint.index == hit.index;
                         });
        if (grabbedPosition != selected.identities.cend()) {
            selected.gesture.grabbedPoint = size_t(grabbedPosition - selected.identities.cbegin());
            selected.gesture.selectionDrag = true;
            state = std::move(selected);
            state.gesture.row = rowIndex;
        }
    }
    if (state.gesture.points.empty()) {
        state.gesture.points.push_back(grabbed);
        state.identities.push_back(grabbedIdentity);
    }
    state.gesture.drag.press(position, !axisLockArmed);
    std::vector<std::vector<ValuePoint>> lanePointsByRow(m_rows.size());
    for (size_t i = 0; i < m_rows.size(); ++i)
        for (const LanePoint &point : pointsFor(m_rows[i], projection))
            lanePointsByRow[i].push_back({point.tick, point.value});
    state.gesture.preparePreview(m_rows.size(), lanePointsByRow);
    return state;
}
