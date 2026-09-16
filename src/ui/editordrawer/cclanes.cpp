#include "ui/editordrawer/cclanes.h"

#include <algorithm>
#include <array>

#include <QCoreApplication>

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "core/xcmd.h"

#include "core/m4asemantics.h"

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

uint8_t CCLanes::bendController() noexcept
{
    return CoreTimeDefaults::kLaneCcBend;
}

std::span<const uint8_t> CCLanes::supportedControllers() noexcept
{
    // Selector display order, deliberately not ascending controller number:
    // related identities are adjacent so the parameter grid reads as groups —
    // mix (Volume, Pan), modulation (Modulation, LFO type, LFO speed, LFO
    // delay), pitch (Pitch bend, Bend range), then the XCMD echo lanes and
    // the Fine tune singleton.
    static constexpr auto controllers = [] {
        std::array<uint8_t, 9 + xcmd::kLaneDescriptors.size()> result{};
        result[0] = CoreTimeDefaults::kCcVolume;
        result[1] = CoreTimeDefaults::kCcPan;
        result[2] = CoreTimeDefaults::kCcModulation;
        result[3] = CoreTimeDefaults::kCcModType;
        result[4] = CoreTimeDefaults::kCcLfoSpeed;
        result[5] = CoreTimeDefaults::kCcLfoDelay;
        result[6] = CoreTimeDefaults::kLaneCcBend;
        result[7] = CoreTimeDefaults::kCcBendRange;
        std::size_t next = 8;
        for (const auto &descriptor : xcmd::kLaneDescriptors)
            result[next++] = descriptor.laneController;
        result[next] = CoreTimeDefaults::kCcFineTune;
        return result;
    }();
    return controllers;
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
    return CoreTimeDefaults::laneDomain(m_controller).minimum;
}

int CCLaneAdapter::maximumValue() const
{
    return CoreTimeDefaults::laneDomain(m_controller).maximum;
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
    const auto domain = CoreTimeDefaults::laneDomain(m_controller);
    NodeValuePrompt prompt;
    prompt.title = title();
    prompt.label = QCoreApplication::translate("AutomationCanvas", "Value:");
    prompt.storedOffset = domain.centered ? (domain.minimum + domain.maximum + 1) / 2 : 0;
    prompt.minimum = domain.minimum - prompt.storedOffset;
    prompt.maximum = domain.maximum - prompt.storedOffset;
    prompt.initialValue = storedValue - prompt.storedOffset;
    if (domain.centered) {
        prompt.label =
            prompt.storedOffset == 0
                ? QCoreApplication::translate("AutomationCanvas", "Bend (0 = none):")
                : QCoreApplication::translate("AutomationCanvas", "c_v value (0 = center):");
    }
    return prompt;
}

int CCLaneAdapter::neutralValue() const
{
    const auto domain = CoreTimeDefaults::laneDomain(m_controller);
    return domain.centered ? (domain.minimum + domain.maximum + 1) / 2 : -1;
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

void CCLaneAdapter::replaceSpan(Tick first, Tick last, const std::vector<NodePoint> &points)
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
