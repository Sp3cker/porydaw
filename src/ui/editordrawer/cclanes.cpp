#include "ui/editordrawer/cclanes.h"

#include <algorithm>

#include <QCoreApplication>
#include <QInputDialog>

#include <QCoreApplication>

#include "core/songdocument.h"
#include "core/timedefaults.h"

#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/nodelane/batchcommit.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/m4asemantics.h"
#include "ui/songviewmodel.h"

namespace {

EditorAutomationRowId laneRow(int track, uint8_t controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), controller};
}

} // namespace

QString CCLanes::laneLabel(uint8_t controller)
{
    if (controller == bendController())
        return QStringLiteral("Pitch bend (BEND)");
    if (const xcmd::Descriptor *descriptor = xcmd::descriptorForLane(controller))
        return QStringLiteral("%1 (%2)").arg(QLatin1String(descriptor->displayName),
                                             QLatin1String(descriptor->mnemonic));
    const auto info = m4aClassifyCc(controller);
    return QStringLiteral("%1 (%2)").arg(QLatin1String(info.display), QLatin1String(info.name));
}

CCLanes::CCLanes(AutomationPage *page) noexcept : m_page(page) {}

CCLanes::~CCLanes() = default;

uint8_t CCLanes::bendController() noexcept
{
    return CoreTimeDefaults::kLaneCcBend;
}

bool CCLanes::rangeZoomable(uint8_t controller) noexcept
{
    return controller != bendController() && controller != CoreTimeDefaults::kCcPan &&
           controller != 24;
}

uint8_t CCLanes::defaultRange(uint8_t controller) noexcept
{
    return controller == CoreTimeDefaults::kCcModulation ? 0 : 127;
}

int CCLanes::autoRange(int maximum) noexcept
{
    if (maximum <= 16)
        return 16;
    if (maximum <= 32)
        return 32;
    if (maximum <= 64)
        return 64;
    return 127;
}

void CCLanes::rebuildRows()
{
    m_rows.clear();
    m_rowText.clear();
    const auto appendRow = [this](const EditorAutomationRowId &id) {
        m_rows.push_back({id});
        m_rowText.emplace_back();
        m_rowText.back().title = titleFor(m_rows.back());
    };
    if (!m_page || !m_page->ready() || !m_page->timeline())
        return;
    const int track = m_page->m_owner.selectionModel().primaryTrack();
    if (track < 0)
        return;
    std::vector<uint8_t> controllers;
    const auto addController = [&controllers](uint8_t controller) {
        if (std::find(controllers.cbegin(), controllers.cend(), controller) == controllers.cend())
            controllers.push_back(controller);
    };
    for (const uint8_t controller : CoreTimeDefaults::kDefaultVisibleControllers)
        addController(controller);
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
}

int CCLanes::minimumHeight(const AutomationGeometry &geometry, int topInset) const
{
    int rowsHeight = topInset;
    for (const auto &row : m_rows) {
        const int height = m_page ? m_page->laneHeightFor(row.id) : geometry.rowDefaultHeight;
        rowsHeight += std::clamp(height, geometry.rowMinimumHeight, geometry.rowMaximumHeight);
    }
    const int strip = m_page && m_page->document() ? geometry.addLaneStripHeight
                                                   : layout::space(layout::Space::Zero);
    return std::max(geometry.rowDefaultHeight, rowsHeight + strip);
}

QString CCLanes::titleFor(const AutomationRow &row) const
{
    return laneLabel(row.id.controller);
}

CCLaneAdapter::CCLaneAdapter(SongDocument &document, int engineTrack, uint8_t controller) noexcept
    : m_document(document)
    , m_engineTrack(engineTrack)
    , m_controller(controller)
{}

QString CCLaneAdapter::title() const
{
    return CCLanes::laneLabel(m_controller);
}

std::vector<NodePoint> CCLaneAdapter::points() const
{
    std::vector<NodePoint> points;
    const auto documentPoints = m_document.lanePoints(m_engineTrack, m_controller);
    if (const auto synthetic = CoreTimeDefaults::syntheticTickZero(m_controller, documentPoints))
        points.push_back({0, *synthetic});
    for (const DocLanePoint &point : documentPoints) {
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
    if (m_controller == CCLanes::bendController())
        return m4aFormatBend(value);
    if (xcmd::isLaneController(m_controller))
        return QString::number(value);
    return m4aFormatCcValue(m_controller, uint8_t(value));
}

bool CCLaneAdapter::promptValue(QWidget *parent, int currentValue, int *storedValue) const
{
    int value = currentValue;
    int minimum = CoreTimeDefaults::laneValueMinimum(m_controller);
    int maximum = CoreTimeDefaults::laneValueMaximum(m_controller);
    QString label = QCoreApplication::translate("AutomationCanvas", "Value:");
    if (m_controller == CCLanes::bendController()) {
        label = QCoreApplication::translate("AutomationCanvas", "Bend (0 = none):");
    } else if (m_controller == 10 || m_controller == 24) {
        minimum = -64;
        maximum = 63;
        value -= 64;
        label = QCoreApplication::translate("AutomationCanvas", "c_v value (0 = center):");
    }
    bool accepted = false;
    const int entered =
        QInputDialog::getInt(parent, title(), label, value, minimum, maximum, 1, &accepted);
    if (!accepted)
        return false;
    *storedValue = (m_controller == 10 || m_controller == 24) ? entered + 64 : entered;
    return true;
}

int CCLaneAdapter::neutralValue() const
{
    if (m_controller == CCLanes::bendController())
        return 0;
    if (m_controller == 10 || m_controller == 24)
        return 64;
    return -1;
}

std::optional<NodePoint> CCLaneAdapter::leadIn() const
{
    if (CoreTimeDefaults::hasEngineDefaultNode(m_controller))
        return std::nullopt;
    const auto documentPoints = m_document.lanePoints(m_engineTrack, m_controller);
    if (std::ranges::any_of(documentPoints,
                            [](const DocLanePoint &point) { return point.tick == 0; })) {
        return std::nullopt;
    }
    const int defaultValue = m_controller == CCLanes::bendController()
                                 ? 0
                                 : CoreTimeDefaults::controllerDefault(m_controller);
    return defaultValue >= 0 ? std::optional<NodePoint>{{0, defaultValue}} : std::nullopt;
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