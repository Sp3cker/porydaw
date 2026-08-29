#include "ui/editorviewstate.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSettings>
#include <QStringView>

#include <algorithm>
#include <cmath>
#include <limits>
#include <optional>
#include <utility>

#include "core/timedefaults.h"
#include "core/xcmd.h"
#include "ui/layout.h"

EditorDrawerState EditorViewState::drawerState() const noexcept
{
    return {velocity, automation, voiceChanges, activePage};
}

void EditorViewState::setDrawerState(const EditorDrawerState &state) noexcept
{
    velocity = state.velocity;
    automation = state.automation;
    voiceChanges = state.voiceChanges;
    activePage = state.activePage;
}

bool EditorViewState::hideLane(EditorAutomationRowId lane)
{
    if (isLaneHidden(lane))
        return false;
    m_hiddenLanes.push_back(lane);
    return true;
}

bool EditorViewState::unhideLane(const EditorAutomationRowId &lane)
{
    return std::erase(m_hiddenLanes, lane) != 0;
}

bool EditorViewState::isLaneHidden(const EditorAutomationRowId &lane) const noexcept
{
    return std::find(m_hiddenLanes.begin(), m_hiddenLanes.end(), lane) != m_hiddenLanes.end();
}

bool EditorViewState::remapEngineTracks(const std::vector<int> &engineTrackMap)
{
    std::set<int> mappedTracks;
    for (const int destination : engineTrackMap) {
        if (destination >= 0 && !mappedTracks.insert(destination).second)
            return false;
    }

    const auto remapRow = [&engineTrackMap](EditorAutomationRowId row,
                                            EditorAutomationRowId *mapped) {
        if (row.kind == EditorAutomationRowKind::Tempo) {
            *mapped = row;
            return true;
        }
        const int source = int(row.track);
        if (source >= int(engineTrackMap.size()))
            return false;
        const int destination = engineTrackMap[source];
        if (destination < 0)
            return false;
        row.track = uint8_t(destination);
        *mapped = row;
        return true;
    };

    auto remapped = *this;
    remapped.laneHeights.clear();
    remapped.laneRanges.clear();
    remapped.emptyLanes.clear();
    remapped.m_hiddenLanes.clear();
    remapped.m_hiddenLanes.reserve(m_hiddenLanes.size());

    for (const auto &[row, height] : laneHeights) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.laneHeights.emplace(destination, height);
    }
    for (const auto &[row, range] : laneRanges) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.laneRanges.emplace(destination, range);
    }
    for (const auto &row : emptyLanes) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.emptyLanes.insert(destination);
    }
    for (const auto &row : m_hiddenLanes) {
        EditorAutomationRowId destination;
        if (remapRow(row, &destination))
            remapped.hideLane(destination);
    }

    *this = std::move(remapped);
    return true;
}

// ---- Global QSettings codec ---------------------------------------------------
//
// The complete EditorViewState is one application-global preference. This
// translation unit owns every drawer settings key/prefix and the lane blob
// grammar; callers pass their one QSettings instance to the two functions.

namespace {

constexpr auto kLaneHeightMember = "laneHeight";
constexpr auto kLaneHeightsMember = "laneHeights";
constexpr auto kLaneRangesMember = "laneRanges";
constexpr auto kEmptyLanesMember = "emptyLanes";
constexpr auto kHiddenLanesMember = "hiddenLanes";
constexpr auto kTrackMember = "track";
constexpr auto kControllerMember = "cc";

const QString kVelocityVisibleKey = QStringLiteral("editorDrawer/velocityVisible");
const QString kVelocityHeightKey = QStringLiteral("editorDrawer/velocityHeight");
const QString kAutomationVisibleKey = QStringLiteral("editorDrawer/automationVisible");
const QString kAutomationHeightKey = QStringLiteral("editorDrawer/automationHeight");
const QString kVoiceChangesVisibleKey = QStringLiteral("editorDrawer/voiceChangesVisible");
const QString kVoiceChangesHeightKey = QStringLiteral("editorDrawer/voiceChangesHeight");
const QString kActivePageKey = QStringLiteral("editorDrawer/activePage");
const QString kAutomationLanesKey = QStringLiteral("editorDrawer/automationLanes");

std::optional<int> loadDrawerHeight(const QSettings &settings, const QString &key)
{
    if (!settings.contains(key))
        return std::nullopt;
    bool ok = false;
    const int height = settings.value(key).toInt(&ok);
    return ok && height > 0 ? std::optional<int>(height) : std::nullopt;
}

void saveDrawerHeight(QSettings &settings, const QString &key, const std::optional<int> &height)
{
    if (height)
        settings.setValue(key, *height);
    else
        settings.remove(key);
}

std::optional<double> decodeNumber(const QJsonValue &value)
{
    if (!value.isDouble())
        return std::nullopt;
    const double number = value.toDouble();
    if (!std::isfinite(number))
        return std::nullopt;
    return number;
}

std::optional<int> decodeInteger(const QJsonValue &value, int minimum, int maximum)
{
    const auto number = decodeNumber(value);
    if (!number || std::floor(*number) != *number || *number < minimum || *number > maximum)
        return std::nullopt;
    return int(*number);
}

std::optional<int> decodeRowNumber(QStringView text, int maximum)
{
    if (text.isEmpty() || (text.size() > 1 && text.at(0) == QLatin1Char('0')))
        return std::nullopt;
    for (const QChar character : text) {
        if (character.unicode() < '0' || character.unicode() > '9')
            return std::nullopt;
    }
    bool ok = false;
    const int number = text.toInt(&ok);
    if (!ok || number > maximum)
        return std::nullopt;
    return number;
}

bool isControllerNumber(int controller)
{
    return (controller >= 0 && controller <= 127) || controller == CoreTimeDefaults::kLaneCcBend ||
           (controller >= 0 && controller <= 255 && xcmd::isLaneController(uint8_t(controller)));
}

// Row keys are exactly "tempo" or "cc:<track>:<cc>" with decimal integers and
// no leading zeroes; "voice:*" and every other prefix reject.
std::optional<EditorAutomationRowId> decodeRowId(const QString &key)
{
    const QStringView text(key);
    if (text == QLatin1String("tempo"))
        return EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0};
    if (text.startsWith(QLatin1String("voice:")))
        return std::nullopt;
    if (!text.startsWith(QLatin1String("cc:")))
        return std::nullopt;
    const qsizetype separator = text.indexOf(QLatin1Char(':'), 3);
    if (separator < 0 || text.indexOf(QLatin1Char(':'), separator + 1) >= 0)
        return std::nullopt;
    const auto track = decodeRowNumber(text.mid(3, separator - 3), 15);
    const auto controller = decodeRowNumber(text.mid(separator + 1), 255);
    if (!track || !controller || !isControllerNumber(*controller))
        return std::nullopt;
    return EditorAutomationRowId{EditorAutomationRowKind::ControlChange, uint8_t(*track),
                                 uint8_t(*controller)};
}

bool isValidRowId(const EditorAutomationRowId &row)
{
    switch (row.kind) {
    case EditorAutomationRowKind::Tempo:
        return row.track == 0 && row.controller == 0;
    case EditorAutomationRowKind::ControlChange:
        return row.track < 16 && isControllerNumber(row.controller);
    }
    return false;
}

QString encodeRowId(const EditorAutomationRowId &row)
{
    if (!isValidRowId(row))
        return {};
    switch (row.kind) {
    case EditorAutomationRowKind::Tempo:
        return QStringLiteral("tempo");
    case EditorAutomationRowKind::ControlChange:
        return QStringLiteral("cc:%1:%2").arg(row.track).arg(row.controller);
    }
    return {};
}

std::optional<EditorAutomationRowId> decodeLane(const QJsonValue &value)
{
    if (!value.isObject())
        return std::nullopt;
    const QJsonObject object = value.toObject();
    const auto track = decodeInteger(object.value(QLatin1String(kTrackMember)), 0, 15);
    const auto controller = decodeInteger(object.value(QLatin1String(kControllerMember)), 0, 255);
    if (!track || !controller || !isControllerNumber(*controller))
        return std::nullopt;
    return EditorAutomationRowId{EditorAutomationRowKind::ControlChange, uint8_t(*track),
                                 uint8_t(*controller)};
}

QJsonObject encodeLane(const EditorAutomationRowId &lane)
{
    QJsonObject object;
    object.insert(QLatin1String(kTrackMember), lane.track);
    object.insert(QLatin1String(kControllerMember), lane.controller);
    return object;
}

// Stored lane heights clamp into the layout font bounds; 0 keeps the layout
// default.
int clampLaneHeight(int height)
{
    return std::clamp(height, layout::fontPx(7.0 / 3.0), layout::fontPx(32.0 / 3.0));
}

// Every decode helper drops invalid entries and keeps the remaining fields.

void decodeRowHeights(const QJsonValue &value, EditorViewState *state)
{
    if (!value.isObject())
        return;
    const QJsonObject heights = value.toObject();
    for (auto it = heights.constBegin(); it != heights.constEnd(); ++it) {
        const auto row = decodeRowId(it.key());
        const auto height = decodeInteger(it.value(), 0, std::numeric_limits<int>::max());
        if (!row || !height)
            continue;
        state->laneHeights.emplace(*row, clampLaneHeight(*height));
    }
}

void decodeRowRanges(const QJsonValue &value, EditorViewState *state)
{
    if (!value.isObject())
        return;
    const QJsonObject ranges = value.toObject();
    for (auto it = ranges.constBegin(); it != ranges.constEnd(); ++it) {
        const auto row = decodeRowId(it.key());
        const auto range = decodeInteger(it.value(), 0, 127);
        if (!row || !range)
            continue;
        state->laneRanges.emplace(*row, uint8_t(*range));
    }
}

void decodeEmptyLanes(const QJsonValue &value, EditorViewState *state)
{
    if (!value.isArray())
        return;
    const QJsonArray lanes = value.toArray();
    for (const QJsonValue &laneValue : lanes) {
        if (const auto lane = decodeLane(laneValue))
            state->emptyLanes.emplace(*lane);
    }
}

void decodeHiddenLanes(const QJsonValue &value, EditorViewState *state)
{
    if (!value.isArray())
        return;
    const QJsonArray lanes = value.toArray();
    for (const QJsonValue &laneValue : lanes) {
        if (const auto lane = decodeLane(laneValue))
            state->hideLane(*lane);
    }
}

// The blob must be a JSON object; anything else defaults every lane field.
void decodeLaneBlob(const QByteArray &blob, EditorViewState *state)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(blob, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return;
    const QJsonObject root = document.object();
    const auto member = [&root](const char *key) { return root.value(QLatin1String(key)); };
    if (const auto height =
            decodeInteger(member(kLaneHeightMember), 0, std::numeric_limits<int>::max()))
        state->laneHeight = *height == 0 ? 0 : clampLaneHeight(*height);
    decodeRowHeights(member(kLaneHeightsMember), state);
    decodeRowRanges(member(kLaneRangesMember), state);
    decodeEmptyLanes(member(kEmptyLanesMember), state);
    decodeHiddenLanes(member(kHiddenLanesMember), state);
}

QJsonObject encodeRows(const EditorViewState &state, bool ranges)
{
    QJsonObject object;
    if (ranges) {
        for (const auto &[row, range] : state.laneRanges) {
            const QString key = encodeRowId(row);
            if (!key.isEmpty())
                object.insert(key, range);
        }
    } else {
        for (const auto &[row, height] : state.laneHeights) {
            const QString key = encodeRowId(row);
            if (!key.isEmpty() && height >= 0)
                object.insert(key, height);
        }
    }
    return object;
}

QJsonArray encodeLanes(const std::set<EditorAutomationRowId> &lanes)
{
    QJsonArray array;
    for (const EditorAutomationRowId &lane : lanes) {
        if (lane.kind == EditorAutomationRowKind::ControlChange && isValidRowId(lane))
            array.append(encodeLane(lane));
    }
    return array;
}

QJsonArray encodeHiddenLanes(const EditorViewState &state)
{
    QJsonArray array;
    for (const EditorAutomationRowId &lane : state.hiddenLanes()) {
        if (lane.kind == EditorAutomationRowKind::ControlChange && isValidRowId(lane))
            array.append(encodeLane(lane));
    }
    return array;
}

} // namespace

EditorViewState loadEditorViewState(const QSettings &settings)
{
    EditorViewState state;
    state.velocity.visible = settings.value(kVelocityVisibleKey, state.velocity.visible).toBool();
    state.velocity.height = loadDrawerHeight(settings, kVelocityHeightKey);
    state.automation.visible =
        settings.value(kAutomationVisibleKey, state.automation.visible).toBool();
    state.automation.height = loadDrawerHeight(settings, kAutomationHeightKey);
    state.voiceChanges.visible =
        settings.value(kVoiceChangesVisibleKey, state.voiceChanges.visible).toBool();
    state.voiceChanges.height = loadDrawerHeight(settings, kVoiceChangesHeightKey);
    const QString page = settings.value(kActivePageKey).toString();
    if (page == QLatin1String("velocity"))
        state.activePage = EditorDrawerPage::Velocity;
    else if (page == QLatin1String("voiceChanges"))
        state.activePage = EditorDrawerPage::VoiceChanges;
    // A missing, wrong-typed, empty, or invalid blob defaults the lane fields
    // only — the drawer chrome above still loads. The next semantic mutation
    // rewrites the entry as canonical compact JSON, so QSettings self-heals
    // without a startup write.
    const QVariant lanes = settings.value(kAutomationLanesKey);
    if (lanes.typeId() == QMetaType::QByteArray)
        decodeLaneBlob(lanes.toByteArray(), &state);
    return state;
}

void saveEditorViewState(QSettings &settings, const EditorViewState &state)
{
    settings.setValue(kVelocityVisibleKey, state.velocity.visible);
    settings.setValue(kAutomationVisibleKey, state.automation.visible);
    settings.setValue(kVoiceChangesVisibleKey, state.voiceChanges.visible);
    saveDrawerHeight(settings, kVelocityHeightKey, state.velocity.height);
    saveDrawerHeight(settings, kAutomationHeightKey, state.automation.height);
    saveDrawerHeight(settings, kVoiceChangesHeightKey, state.voiceChanges.height);
    switch (state.activePage) {
    case EditorDrawerPage::Velocity:
        settings.setValue(kActivePageKey, QLatin1String("velocity"));
        break;
    case EditorDrawerPage::VoiceChanges:
        settings.setValue(kActivePageKey, QLatin1String("voiceChanges"));
        break;
    case EditorDrawerPage::Automations:
        settings.setValue(kActivePageKey, QLatin1String("automations"));
        break;
    }
    // One atomic compact-JSON entry keeps the tested lane row grammar and the
    // ordered hidden-lane sequence together.
    QJsonObject lanes;
    lanes.insert(QLatin1String(kLaneHeightMember), state.laneHeight);
    lanes.insert(QLatin1String(kLaneHeightsMember), encodeRows(state, /*ranges=*/false));
    lanes.insert(QLatin1String(kLaneRangesMember), encodeRows(state, /*ranges=*/true));
    lanes.insert(QLatin1String(kEmptyLanesMember), encodeLanes(state.emptyLanes));
    lanes.insert(QLatin1String(kHiddenLanesMember), encodeHiddenLanes(state));
    settings.setValue(kAutomationLanesKey, QJsonDocument(lanes).toJson(QJsonDocument::Compact));
}
