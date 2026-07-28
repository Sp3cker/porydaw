#include "viewsidecar.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <algorithm>

#include "project/sidecar.h"

namespace ViewSidecar {

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
  if (obj.contains(QLatin1String("drawerVisible")))
    loaded.drawerVisible =
        obj.value(QLatin1String("drawerVisible")).toBool(true);
  else if (obj.contains(QLatin1String("automationDrawerVisible")))
    loaded.drawerVisible =
        obj.value(QLatin1String("automationDrawerVisible")).toBool(true);
  else
    loaded.drawerVisible = true;
  const QString drawerPageStr =
      obj.value(QLatin1String("drawerPage")).toString();
  loaded.drawerPage = (drawerPageStr == QLatin1String("velocity"))
                          ? SongView::DrawerPage::Velocity
                          : SongView::DrawerPage::Automations;
  const QJsonObject lanes = obj.value(QLatin1String("laneHeights")).toObject();
  for (auto it = lanes.begin(); it != lanes.end(); ++it)
    loaded.laneHeights.insert(it.key(), it.value().toInt());
  const QJsonObject ranges = obj.value(QLatin1String("laneRanges")).toObject();
  for (auto it = ranges.begin(); it != ranges.end(); ++it)
    loaded.laneRanges.insert(it.key(), it.value().toInt());
  for (const QJsonValue &v : obj.value(QLatin1String("splitter")).toArray())
    loaded.splitterSizes.push_back(v.toInt());
  for (const QJsonValue &v : obj.value(QLatin1String("emptyLanes")).toArray()) {
    const QJsonObject lane = v.toObject();
    loaded.emptyLanes.push_back(
        {lane.value(QLatin1String("track")).toInt(-1),
         uint8_t(lane.value(QLatin1String("cc")).toInt(0))});
  }
  for (const QJsonValue &laneValue :
       obj.value(QLatin1String("hiddenLanes")).toArray()) {
    const QJsonObject lane = laneValue.toObject();
    const int laneTrack = lane.value(QLatin1String("track")).toInt(-1);
    const int laneCc = lane.value(QLatin1String("cc")).toInt(-1);
    if (laneTrack >= 0 && laneTrack < 16 &&
        ((laneCc >= 0 && laneCc <= 0x7F) || laneCc == LANE_CC_BEND))
      loaded.hiddenLanes.push_back({laneTrack, uint8_t(laneCc)});
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
  if (!state.laneHeights.isEmpty()) {
    QJsonObject lanes;
    for (auto it = state.laneHeights.begin(); it != state.laneHeights.end();
         ++it)
      lanes.insert(it.key(), it.value());
    obj.insert(QLatin1String("laneHeights"), lanes);
  }
  if (!state.laneRanges.isEmpty()) {
    QJsonObject ranges;
    for (auto it = state.laneRanges.begin(); it != state.laneRanges.end(); ++it)
      ranges.insert(it.key(), it.value());
    obj.insert(QLatin1String("laneRanges"), ranges);
  }
  QJsonArray splitter;
  for (int size : state.splitterSizes)
    splitter.append(size);
  obj.insert(QLatin1String("splitter"), splitter);
  if (!state.emptyLanes.empty()) {
    QJsonArray lanes;
    for (const std::pair<int, uint8_t> &lane : state.emptyLanes) {
      QJsonObject entry;
      entry.insert(QLatin1String("track"), lane.first);
      entry.insert(QLatin1String("cc"), int(lane.second));
      lanes.append(entry);
    }
    obj.insert(QLatin1String("emptyLanes"), lanes);
  }
  if (!state.hiddenLanes.empty()) {
    QJsonArray hiddenLanes;
    for (const std::pair<int, uint8_t> &hiddenLane : state.hiddenLanes) {
      QJsonObject entry;
      entry.insert(QLatin1String("track"), hiddenLane.first);
      entry.insert(QLatin1String("cc"), int(hiddenLane.second));
      hiddenLanes.append(entry);
    }
    obj.insert(QLatin1String("hiddenLanes"), hiddenLanes);
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
