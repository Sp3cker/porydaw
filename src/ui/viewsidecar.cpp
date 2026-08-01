#include "viewsidecar.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSaveFile>
#include <QStringView>
#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>
#include <optional>

#include "project/sidecar.h"
#include "ui/layout.h"

namespace ViewSidecar {

namespace {

constexpr auto kViewKey = "view";
constexpr auto kEditorKey = "editor";
constexpr auto kPxPerBeatKey = "pxPerBeat";
constexpr auto kKeyHeightKey = "keyHeight";
constexpr auto kScrollPxKey = "scrollPx";
constexpr auto kScrollYKey = "scrollY";
constexpr auto kSelectedTrackKey = "selectedTrack";
constexpr auto kEditCursorTickKey = "editCursorTick";
constexpr auto kLaneHeightKey = "laneHeight";
constexpr auto kLaneHeightsKey = "laneHeights";
constexpr auto kLaneRangesKey = "laneRanges";
constexpr auto kEmptyLanesKey = "emptyLanes";
constexpr auto kHiddenLanesKey = "hiddenLanes";
constexpr auto kGridMinDenomKey = "gridMinDenom";
constexpr auto kGridTripletKey = "gridTriplet";
constexpr auto kEventListKey = "eventList";
constexpr auto kDrawerVisibleKey = "drawerVisible";
constexpr auto kDrawerPageKey = "drawerPage";
constexpr auto kDrawerHeightKey = "drawerHeight";
constexpr auto kTrackKey = "track";
constexpr auto kControllerKey = "cc";

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

std::optional<uint64_t> decodeTick(const QJsonValue &value)
{
    const auto number = decodeNumber(value);
    if (!number || std::floor(*number) != *number || *number < 0.0 ||
        *number >= std::ldexp(1.0, 64))
        return std::nullopt;
    return uint64_t(*number);
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
    return (controller >= 0 && controller <= 127) || controller == 255;
}

std::optional<EditorAutomationRowId> decodeRowId(const QString &key)
{
    const QStringView text(key);
    if (text == QLatin1String("tempo"))
        return EditorAutomationRowId{EditorAutomationRowKind::Tempo, 0, 0};
    if (text.startsWith(QLatin1String("voice:"))) {
        const auto track = decodeRowNumber(text.mid(6), 15);
        if (track)
            return EditorAutomationRowId{EditorAutomationRowKind::Voice, uint8_t(*track), 0};
        return std::nullopt;
    }
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
    case EditorAutomationRowKind::Voice:
        return row.track < 16 && row.controller == 0;
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
    case EditorAutomationRowKind::Voice:
        return QStringLiteral("voice:%1").arg(row.track);
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
    const auto track = decodeInteger(object.value(QLatin1String(kTrackKey)), 0, 15);
    const auto controller = decodeInteger(object.value(QLatin1String(kControllerKey)), 0, 255);
    if (!track || !controller || !isControllerNumber(*controller))
        return std::nullopt;
    return EditorAutomationRowId{EditorAutomationRowKind::ControlChange, uint8_t(*track),
                                 uint8_t(*controller)};
}

QJsonObject encodeLane(const EditorAutomationRowId &lane)
{
    QJsonObject object;
    object.insert(QLatin1String(kTrackKey), lane.track);
    object.insert(QLatin1String(kControllerKey), lane.controller);
    return object;
}

int clampAutomationRowHeight(int height)
{
    return std::clamp(height, layout::editorGeometry().automationRowMinimumHeight,
                      layout::editorGeometry().automationRowMaximumHeight);
}

void decodeRowHeights(const QJsonValue &value, Snapshot *snapshot)
{
    if (!value.isObject())
        return;
    const QJsonObject heights = value.toObject();
    for (auto it = heights.constBegin(); it != heights.constEnd(); ++it) {
        const auto row = decodeRowId(it.key());
        const auto height = decodeInteger(it.value(), 0, std::numeric_limits<int>::max());
        if (!row || !height)
            continue;
        const int clampedHeight = clampAutomationRowHeight(*height);
        snapshot->editor.laneHeights.emplace(*row, clampedHeight);
    }
}

void decodeRowRanges(const QJsonValue &value, Snapshot *snapshot)
{
    if (!value.isObject())
        return;
    const QJsonObject ranges = value.toObject();
    for (auto it = ranges.constBegin(); it != ranges.constEnd(); ++it) {
        const auto row = decodeRowId(it.key());
        const auto range = decodeInteger(it.value(), 0, 127);
        if (!row || !range)
            continue;
        snapshot->editor.laneRanges.emplace(*row, uint8_t(*range));
    }
}

void decodeEmptyLanes(const QJsonValue &value, Snapshot *snapshot)
{
    if (!value.isArray())
        return;
    const QJsonArray lanes = value.toArray();
    for (const QJsonValue &value : lanes) {
        if (const auto lane = decodeLane(value))
            snapshot->editor.emptyLanes.emplace(*lane);
    }
}

void decodeHiddenLanes(const QJsonValue &value, EditorViewState *editor)
{
    if (!value.isArray())
        return;
    const QJsonArray lanes = value.toArray();
    for (const QJsonValue &value : lanes) {
        const auto lane = decodeLane(value);
        if (lane)
            editor->hideLane(*lane);
    }
}

double finiteOrDefault(double value, double defaultValue)
{
    return std::isfinite(value) ? value : defaultValue;
}

QJsonObject encodeRows(const EditorViewState &editor, bool ranges)
{
    QJsonObject object;
    if (ranges) {
        for (const auto &[row, range] : editor.laneRanges) {
            const QString key = encodeRowId(row);
            if (!key.isEmpty())
                object.insert(key, range);
        }
    } else {
        for (const auto &[row, height] : editor.laneHeights) {
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

QJsonArray encodeHiddenLanes(const EditorViewState &editor)
{
    QJsonArray array;
    for (const EditorAutomationRowId &lane : editor.hiddenLanes()) {
        if (lane.kind == EditorAutomationRowKind::ControlChange && isValidRowId(lane))
            array.append(encodeLane(lane));
    }
    return array;
}

QJsonObject existingRoot(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return {};
    return document.object();
}

} // namespace

QString pathFor(const QString &projectRoot, const QString &songLabel)
{
    return QStringLiteral("%1/.porydaw/%2.json").arg(projectRoot, songLabel);
}

bool load(const QString &projectRoot, const QString &songLabel, Snapshot *snapshot)
{
    if (!snapshot)
        return false;
    QFile file(pathFor(projectRoot, songLabel));
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return false;
    const QJsonObject root = document.object();
    const QJsonValue viewValue = root.value(QLatin1String(kViewKey));
    if (!viewValue.isObject())
        return false;
    const QJsonObject view = viewValue.toObject();
    Snapshot loaded;
    loaded.view.valid = true;
    if (const auto value = decodeNumber(view.value(QLatin1String(kPxPerBeatKey))))
        loaded.view.pxPerBeat = *value;
    if (const auto value = decodeNumber(view.value(QLatin1String(kKeyHeightKey))))
        loaded.view.keyHeight = *value;
    if (const auto value = decodeNumber(view.value(QLatin1String(kScrollPxKey))))
        loaded.view.scrollPx = *value;
    if (const auto value = decodeNumber(view.value(QLatin1String(kScrollYKey))))
        loaded.view.scrollY = *value;
    if (const auto value = decodeInteger(view.value(QLatin1String(kSelectedTrackKey)), 0, 15))
        loaded.view.selectedTrack = *value;
    if (const auto value = decodeTick(view.value(QLatin1String(kEditCursorTickKey))))
        loaded.view.editCursorTick = *value;
    if (const QJsonValue value = view.value(QLatin1String(kGridMinDenomKey)); value.isDouble()) {
        if (const auto decoded = decodeInteger(value, 0, std::numeric_limits<int>::max()))
            loaded.view.gridMinDenom = *decoded;
    }
    if (const QJsonValue value = view.value(QLatin1String(kGridTripletKey)); value.isBool())
        loaded.view.gridTriplet = value.toBool();
    if (const QJsonValue value = view.value(QLatin1String(kEventListKey)); value.isBool())
        loaded.view.eventList = value.toBool();
    const QJsonValue editorValue = root.value(QLatin1String(kEditorKey));
    if (editorValue.isObject()) {
        const QJsonObject editor = editorValue.toObject();
        if (const QJsonValue value = editor.value(QLatin1String(kDrawerVisibleKey)); value.isBool())
            loaded.editor.drawerVisible = value.toBool();
        if (const QJsonValue value = editor.value(QLatin1String(kDrawerPageKey));
            value.isString() && value.toString() == QLatin1String("velocity")) {
            loaded.editor.drawerPage = EditorDrawerPage::Velocity;
        }
        if (const auto value = decodeInteger(editor.value(QLatin1String(kDrawerHeightKey)), 0,
                                             std::numeric_limits<int>::max())) {
            loaded.editor.drawerHeight = *value;
        }
        if (const auto value = decodeInteger(editor.value(QLatin1String(kLaneHeightKey)), 0,
                                             std::numeric_limits<int>::max())) {
            loaded.editor.laneHeight = *value == 0 ? 0 : clampAutomationRowHeight(*value);
        }
        decodeRowHeights(editor.value(QLatin1String(kLaneHeightsKey)), &loaded);
        decodeRowRanges(editor.value(QLatin1String(kLaneRangesKey)), &loaded);
        decodeEmptyLanes(editor.value(QLatin1String(kEmptyLanesKey)), &loaded);
        decodeHiddenLanes(editor.value(QLatin1String(kHiddenLanesKey)), &loaded.editor);
    }
    *snapshot = std::move(loaded);
    return true;
}

bool save(const QString &projectRoot, const QString &songLabel, const Snapshot &snapshot)
{
    if (!snapshot.view.valid || songLabel.isEmpty())
        return false;
    const QString path = pathFor(projectRoot, songLabel);
    QJsonObject root = existingRoot(path);
    QJsonObject view;
    view.insert(QLatin1String(kPxPerBeatKey), finiteOrDefault(snapshot.view.pxPerBeat, 32.0));
    view.insert(QLatin1String(kKeyHeightKey), finiteOrDefault(snapshot.view.keyHeight, 8.0));
    view.insert(QLatin1String(kScrollPxKey), finiteOrDefault(snapshot.view.scrollPx, 0.0));
    view.insert(QLatin1String(kScrollYKey), finiteOrDefault(snapshot.view.scrollY, 0.0));
    view.insert(QLatin1String(kSelectedTrackKey), snapshot.view.selectedTrack);
    view.insert(QLatin1String(kEditCursorTickKey), double(snapshot.view.editCursorTick));
    view.insert(QLatin1String(kGridMinDenomKey), std::max(0, snapshot.view.gridMinDenom));
    view.insert(QLatin1String(kGridTripletKey), snapshot.view.gridTriplet);
    view.insert(QLatin1String(kEventListKey), snapshot.view.eventList);
    const EditorViewState &editor = snapshot.editor;
    QJsonObject editorObject;
    editorObject.insert(QLatin1String(kDrawerVisibleKey), editor.drawerVisible);
    editorObject.insert(QLatin1String(kDrawerPageKey),
                        editor.drawerPage == EditorDrawerPage::Velocity
                            ? QLatin1String("velocity")
                            : QLatin1String("automations"));
    editorObject.insert(QLatin1String(kDrawerHeightKey), std::max(0, editor.drawerHeight));
    editorObject.insert(QLatin1String(kLaneHeightKey), std::max(0, editor.laneHeight));
    const QJsonObject heights = encodeRows(editor, false);
    if (!heights.isEmpty())
        editorObject.insert(QLatin1String(kLaneHeightsKey), heights);
    const QJsonObject ranges = encodeRows(editor, true);
    if (!ranges.isEmpty())
        editorObject.insert(QLatin1String(kLaneRangesKey), ranges);
    const QJsonArray emptyLanes = encodeLanes(editor.emptyLanes);
    if (!emptyLanes.isEmpty())
        editorObject.insert(QLatin1String(kEmptyLanesKey), emptyLanes);
    const QJsonArray hiddenLanes = encodeHiddenLanes(editor);
    if (!hiddenLanes.isEmpty())
        editorObject.insert(QLatin1String(kHiddenLanesKey), hiddenLanes);
    root.insert(QLatin1String(kViewKey), view);
    root.insert(QLatin1String(kEditorKey), editorObject);
    if (!Sidecar::ensureDir(projectRoot))
        return false;
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    if (file.write(QJsonDocument(root).toJson(QJsonDocument::Indented)) < 0)
        return false;
    return file.commit();
}

} // namespace ViewSidecar
