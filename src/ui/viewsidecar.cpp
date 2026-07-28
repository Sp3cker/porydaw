#include "viewsidecar.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStringView>
#include <algorithm>
#include <optional>

#include "project/sidecar.h"

namespace ViewSidecar {

namespace {

std::optional<int> decodeRowNumber(QStringView text, int maximum) {
  if (text.isEmpty() || (text.size() > 1 && text.at(0) == QLatin1Char('0')))
    return std::nullopt;
  for (const QChar character : text) {
    if (character.unicode() < '0' || character.unicode() > '9')
      return std::nullopt;
  }
  bool ok = false;
  const int value = text.toInt(&ok);
  if (!ok || value > maximum)
    return std::nullopt;
  return value;
}

std::optional<SongView::AutomationRowId>
decodeAutomationRowKey(const QString &key) {
  const QStringView keyView(key);
  if (keyView == QLatin1String("tempo"))
    return SongView::AutomationRowId::tempo();
  if (keyView.startsWith(QLatin1String("voice:"))) {
    const auto track = decodeRowNumber(keyView.mid(6), 15);
    if (track.has_value())
      return SongView::AutomationRowId::voice(*track);
    return std::nullopt;
  }
  if (!keyView.startsWith(QLatin1String("cc:")))
    return std::nullopt;
  const qsizetype controllerSeparator = keyView.indexOf(QLatin1Char(':'), 3);
  if (controllerSeparator < 0 ||
      keyView.indexOf(QLatin1Char(':'), controllerSeparator + 1) >= 0)
    return std::nullopt;
  const auto track =
      decodeRowNumber(keyView.mid(3, controllerSeparator - 3), 15);
  const auto controller =
      decodeRowNumber(keyView.mid(controllerSeparator + 1), 255);
  if (!track.has_value() || !controller.has_value())
    return std::nullopt;
  return SongView::AutomationRowId::controller(*track, uint8_t(*controller));
}

QString encodeAutomationRowKey(const SongView::AutomationRowId &id) {
  switch (id.kind) {
  case SongView::AutomationRowId::Kind::Tempo:
    return QStringLiteral("tempo");
  case SongView::AutomationRowId::Kind::Voice:
    return QStringLiteral("voice:%1").arg(id.track);
  case SongView::AutomationRowId::Kind::Controller:
    return QStringLiteral("cc:%1:%2").arg(id.track).arg(int(id.cc));
  }
  return {};
}

std::optional<std::pair<int, uint8_t>>
decodeLaneIdentity(const QJsonValue &value) {
  if (!value.isObject())
    return std::nullopt;
  const QJsonObject object = value.toObject();
  const QJsonValue trackValue = object.value(QLatin1String("track"));
  const QJsonValue ccValue = object.value(QLatin1String("cc"));
  if (!trackValue.isDouble() || !ccValue.isDouble())
    return std::nullopt;
  const int track = trackValue.toInt(-1);
  const int cc = ccValue.toInt(-1);
  if (!SongView::isValidLaneIdentity(track, cc))
    return std::nullopt;
  return std::pair<int, uint8_t>(track, uint8_t(cc));
}

QJsonObject encodeLaneIdentity(const std::pair<int, uint8_t> &laneIdentity) {
  QJsonObject object;
  object.insert(QLatin1String("track"), laneIdentity.first);
  object.insert(QLatin1String("cc"), int(laneIdentity.second));
  return object;
}

} // namespace

QString pathFor(const QString &projectRoot, const QString &songLabel) {
  return QStringLiteral("%1/.porydaw/%2.json").arg(projectRoot, songLabel);
}

bool load(const QString &projectRoot, const QString &songLabel,
          SongView::ViewState *state) {
  QFile file(pathFor(projectRoot, songLabel));
  if (!file.open(QIODevice::ReadOnly))
    return false;
  // The sidecar is shared: SongRegistry keeps pending-registration
  // metadata in the same file, so the view state lives under "view".
  const QJsonObject obj = QJsonDocument::fromJson(file.readAll())
                              .object()
                              .value(QLatin1String("view"))
                              .toObject();
  if (obj.isEmpty())
    return false;

  SongView::ViewState loaded;
  loaded.valid = true;
  loaded.pxPerBeat =
      obj.value(QLatin1String("pxPerBeat")).toDouble(loaded.pxPerBeat);
  loaded.keyHeight =
      obj.value(QLatin1String("keyHeight")).toDouble(loaded.keyHeight);
  loaded.scrollPx = obj.value(QLatin1String("scrollPx")).toDouble(0.0);
  loaded.scrollY = obj.value(QLatin1String("scrollY")).toDouble(0.0);
  loaded.selectedTrack = obj.value(QLatin1String("selectedTrack")).toInt(0);
  loaded.editCursorTick = uint64_t(
      std::max(0.0, obj.value(QLatin1String("editCursorTick")).toDouble(0)));
  loaded.laneHeight =
      obj.value(QLatin1String("laneHeight")).toInt(loaded.laneHeight);
  loaded.gridMinDenom = obj.value(QLatin1String("gridMinDenom")).toInt(0);
  loaded.gridTriplet = obj.value(QLatin1String("gridTriplet")).toBool(false);
  loaded.eventList = obj.value(QLatin1String("eventList")).toBool(false);
  loaded.drawerVisible = obj.value(QLatin1String("drawerVisible")).toBool(true);
  const QString drawerPageStr =
      obj.value(QLatin1String("drawerPage")).toString();
  loaded.drawerPage = (drawerPageStr == QLatin1String("velocity"))
                          ? SongView::DrawerPage::Velocity
                          : SongView::DrawerPage::Automations;
  const QJsonObject heights = obj.value(QLatin1String("laneHeights")).toObject();
  for (auto it = heights.begin(); it != heights.end(); ++it)
    {
    const auto rowId = decodeAutomationRowKey(it.key());
    if (rowId.has_value())
      loaded.rowStates[*rowId].height = it.value().toInt();
  }
  const QJsonObject ranges = obj.value(QLatin1String("laneRanges")).toObject();
  for (auto it = ranges.begin(); it != ranges.end(); ++it)
    {
    const auto rowId = decodeAutomationRowKey(it.key());
    if (rowId.has_value())
      loaded.rowStates[*rowId].range = it.value().toInt();
  }
  for (const QJsonValue &v : obj.value(QLatin1String("splitter")).toArray())
    loaded.splitterSizes.push_back(v.toInt());
  for (const QJsonValue &value : obj.value(QLatin1String("emptyLanes")).toArray()) {
    const auto laneIdentity = decodeLaneIdentity(value);
    if (laneIdentity.has_value())
      loaded.emptyLanes.push_back(
        *laneIdentity);
  }
  for (const QJsonValue &value :
       obj.value(QLatin1String("hiddenLanes")).toArray()) {
    const auto laneIdentity = decodeLaneIdentity(value);
    if (laneIdentity.has_value())
      loaded.hiddenLanes.push_back(*laneIdentity);
  }
  *state = loaded;
  return true;
}

bool save(const QString &projectRoot, const QString &songLabel,
          const SongView::ViewState &state) {
  if (!state.valid || songLabel.isEmpty())
    return false;
  const QString path = pathFor(projectRoot, songLabel);

  // Merge: other keys in the sidecar (e.g. SongRegistry's "registration")
  // must survive a view-state save.
  QJsonObject root;
  {
    QFile in(path);
    if (in.open(QIODevice::ReadOnly))
      root = QJsonDocument::fromJson(in.readAll()).object();
  }

  QJsonObject obj;
  obj.insert(QLatin1String("pxPerBeat"), state.pxPerBeat);
  obj.insert(QLatin1String("keyHeight"), state.keyHeight);
  obj.insert(QLatin1String("scrollPx"), state.scrollPx);
  obj.insert(QLatin1String("scrollY"), state.scrollY);
  obj.insert(QLatin1String("selectedTrack"), state.selectedTrack);
  obj.insert(QLatin1String("editCursorTick"), double(state.editCursorTick));
  obj.insert(QLatin1String("laneHeight"), state.laneHeight);
  obj.insert(QLatin1String("gridMinDenom"), state.gridMinDenom);
  obj.insert(QLatin1String("gridTriplet"), state.gridTriplet);
  obj.insert(QLatin1String("eventList"), state.eventList);
  obj.insert(QLatin1String("drawerVisible"), state.drawerVisible);
  obj.insert(QLatin1String("drawerPage"),
             state.drawerPage == SongView::DrawerPage::Velocity
                 ? QLatin1String("velocity")
                 : QLatin1String("automations"));
  QJsonObject heights;
  QJsonObject ranges;
    for (auto it = state.rowStates.constBegin(); it != state.rowStates.constEnd();
         ++it)
      {
    const QString key = encodeAutomationRowKey(it.key());
    if (key.isEmpty())
      continue;
    if (it.value().height.has_value())
      heights.insert(key, *it.value().height);
    if (it.value().range.has_value())
      ranges.insert(key, *it.value().range);
  }
  if (!heights.isEmpty())
    obj.insert(QLatin1String("laneHeights"), heights);
  if (!ranges.isEmpty()) obj.insert(QLatin1String("laneRanges"), ranges);
  QJsonArray splitter;
  for (int size : state.splitterSizes)
    splitter.append(size);
  obj.insert(QLatin1String("splitter"), splitter);
  if (!state.emptyLanes.empty()) {
    QJsonArray lanes;
    for (const std::pair<int, uint8_t> &lane : state.emptyLanes) lanes.append(encodeLaneIdentity(lane));
    obj.insert(QLatin1String("emptyLanes"), lanes);
  }
  if (!state.hiddenLanes.empty()) {
    QJsonArray lanes;
    for (const std::pair<int, uint8_t> &lane : state.hiddenLanes) lanes.append(encodeLaneIdentity(lane));
    obj.insert(QLatin1String("hiddenLanes"), lanes);
  }
  root.insert(QLatin1String("view"), obj);

  if (!Sidecar::ensureDir(projectRoot))
    return false;
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly))
    return false;
  file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
  return file.commit();
}

} // namespace ViewSidecar
