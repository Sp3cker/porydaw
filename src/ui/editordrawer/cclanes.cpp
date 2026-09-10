#include "ui/editordrawer/cclanes.h"

#include <algorithm>
#include <array>

#include <QCoreApplication>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "core/xcmd.h"

#include "core/m4asemantics.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editorviewstate.h"

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

std::span<const uint8_t> CCLanes::supportedControllers() noexcept
{
    static constexpr auto controllers = [] {
        std::array<uint8_t, 6 + xcmd::kLaneDescriptors.size()> result{};
        result[0] = CoreTimeDefaults::kCcModulation;
        result[1] = CoreTimeDefaults::kCcVolume;
        result[2] = CoreTimeDefaults::kCcPan;
        result[3] = CoreTimeDefaults::kCcBendRange;
        result[4] = CoreTimeDefaults::kCcLfoSpeed;
        std::size_t next = 5;
        for (const auto &descriptor : xcmd::kLaneDescriptors)
            result[next++] = descriptor.laneController;
        result[next] = CoreTimeDefaults::kLaneCcBend;
        std::sort(result.begin(), result.end());
        return result;
    }();
    return controllers;
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
    // Every supported identity has a stable row, including lanes without events.
    for (const uint8_t controller : supportedControllers())
        appendRow(laneRow(track, controller));
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

NodeValuePrompt CCLaneAdapter::valuePrompt(int storedValue) const
{
    NodeValuePrompt prompt;
    prompt.title = title();
    prompt.label = QCoreApplication::translate("AutomationCanvas", "Value:");
    prompt.minimum = CoreTimeDefaults::laneValueMinimum(m_controller);
    prompt.maximum = CoreTimeDefaults::laneValueMaximum(m_controller);
    prompt.initialValue = storedValue;
    if (m_controller == CCLanes::bendController()) {
        prompt.label = QCoreApplication::translate("AutomationCanvas", "Bend (0 = none):");
    } else if (m_controller == 10 || m_controller == 24) {
        // Pan-style controllers present a centered range and store the
        // displayed value shifted by 64.
        prompt.minimum = -64;
        prompt.maximum = 63;
        prompt.initialValue = storedValue - 64;
        prompt.storedOffset = 64;
        prompt.label = QCoreApplication::translate("AutomationCanvas", "c_v value (0 = center):");
    }
    return prompt;
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
