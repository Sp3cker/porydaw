#include <QByteArray>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "project/sidecar.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/viewsidecar.h"

namespace {

QByteArray fileContents(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

EditorAutomationRowId controllerRow(int track, int controller)
{
    return {EditorAutomationRowKind::ControlChange, uint8_t(track), uint8_t(controller)};
}

QJsonObject laneJson(int track, int controller)
{
    QJsonObject lane;
    lane.insert(QStringLiteral("track"), track);
    lane.insert(QStringLiteral("cc"), controller);
    return lane;
}

bool writeJson(const QString &path, const QJsonObject &root)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    return file.write(QJsonDocument(root).toJson()) >= 0;
}

QJsonObject readJson(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

} // namespace

int runViewSidecarCheck(const QString &scratchProject, const QString &songLabel)
{
    auto failures = 0;
    const auto check = [&failures](bool condition, const char *what) {
        if (!condition) {
            std::fprintf(stderr, "sidecar: FAIL: %s\n", what);
            failures++;
        }
    };
    if (scratchProject.isEmpty() || songLabel.isEmpty()) {
        std::fprintf(stderr, "sidecar: scratch project and song label are required\n");
        return 1;
    }
    const QString label = QStringLiteral("sidecar-check-") + songLabel;
    const QString path = ViewSidecar::pathFor(scratchProject, label);
    check(Sidecar::ensureDir(scratchProject), "created sidecar directory");
    QJsonObject originalRoot;
    originalRoot.insert(QStringLiteral("registration"),
                        QJsonObject{{QStringLiteral("pending"), true}});
    QJsonObject originalView;
    originalView.insert(QStringLiteral("futureState"),
                        QJsonArray{QJsonObject{{QStringLiteral("version"), 2}}, 7});
    originalRoot.insert(QStringLiteral("view"), originalView);
    check(writeJson(path, originalRoot), "seeded unrelated root and view fields");

    ViewSidecar::Snapshot saved;
    saved.view.valid = true;
    saved.view.pxPerBeat = 48.0;
    saved.view.keyHeight = 12.0;
    saved.view.scrollPx = 21.5;
    saved.view.scrollY = 7.25;
    saved.view.selectedTrack = 2;
    saved.view.editCursorTick = 96;
    saved.view.gridMinDenom = 16;
    saved.view.gridTriplet = true;
    saved.view.eventList = true;
    saved.editor.velocity = {true, 180};
    saved.editor.automation = {false, 240};
    saved.editor.activePage = EditorDrawerPage::Velocity;
    saved.editor.laneHeight = 96;
    const EditorAutomationRowId volume = controllerRow(2, 7);
    const EditorAutomationRowId hidden = controllerRow(2, 20);
    const EditorAutomationRowId hiddenSecond = controllerRow(2, 21);
    saved.editor.laneHeights.emplace(volume, 112);
    saved.editor.laneRanges.emplace(volume, 91);
    saved.editor.emptyLanes.emplace(volume);
    saved.editor.hideLane(hidden);
    saved.editor.hideLane(hiddenSecond);
    const auto hasSavedLaneState = [&saved](const EditorViewState &editor) {
        return editor.laneHeight == saved.editor.laneHeight &&
               editor.laneHeights == saved.editor.laneHeights &&
               editor.laneRanges == saved.editor.laneRanges &&
               editor.emptyLanes == saved.editor.emptyLanes &&
               editor.hiddenLanes() == saved.editor.hiddenLanes();
    };
    check(ViewSidecar::save(scratchProject, label, saved), "saved detached snapshot");

    ViewSidecar::Snapshot loaded;
    loaded.view.valid = false;
    loaded.editor.hideLane(controllerRow(9, 1));
    check(ViewSidecar::load(scratchProject, label, &loaded), "loaded detached snapshot");
    check(loaded.view.valid && loaded.view.pxPerBeat == saved.view.pxPerBeat &&
              loaded.view.keyHeight == saved.view.keyHeight &&
              loaded.view.scrollPx == saved.view.scrollPx &&
              loaded.view.scrollY == saved.view.scrollY &&
              loaded.view.selectedTrack == saved.view.selectedTrack &&
              loaded.view.editCursorTick == saved.view.editCursorTick &&
              loaded.view.gridMinDenom == saved.view.gridMinDenom &&
              loaded.view.gridTriplet == saved.view.gridTriplet &&
              loaded.view.eventList == saved.view.eventList,
          "round trip restores the detached camera/grid snapshot");
    const EditorViewState defaultEditor;
    check(hasSavedLaneState(loaded.editor) && loaded.editor.velocity == defaultEditor.velocity &&
              loaded.editor.automation == defaultEditor.automation &&
              loaded.editor.activePage == defaultEditor.activePage,
          "round trip restores typed lane state without drawer chrome");
    check(!loaded.editor.isLaneHidden(controllerRow(9, 1)),
          "load replaces rather than merges a caller snapshot");
    const QJsonObject canonicalRoot = readJson(path);
    const QJsonObject canonicalView = canonicalRoot.value(QStringLiteral("view")).toObject();
    const QJsonObject canonicalEditor = canonicalRoot.value(QStringLiteral("editor")).toObject();
    check(canonicalRoot.value(QStringLiteral("registration")).toObject() ==
                  originalRoot.value(QStringLiteral("registration")).toObject() &&
              !canonicalView.contains(QStringLiteral("futureState")),
          "save preserves unrelated root fields and replaces the view schema");
    const auto hasDrawerChrome = [](const QJsonObject &object) {
        return object.contains(QStringLiteral("velocity")) ||
               object.contains(QStringLiteral("automation")) ||
               object.contains(QStringLiteral("activePage")) ||
               object.contains(QStringLiteral("drawerVisible")) ||
               object.contains(QStringLiteral("drawerPage")) ||
               object.contains(QStringLiteral("drawerHeight"));
    };
    check(!hasDrawerChrome(canonicalView) && !hasDrawerChrome(canonicalEditor) &&
              canonicalEditor.value(QStringLiteral("laneHeight")).toInt() == 96 &&
              canonicalEditor.value(QStringLiteral("laneHeights"))
                      .toObject()
                      .value(QStringLiteral("cc:2:7"))
                      .toInt() == 112 &&
              canonicalEditor.value(QStringLiteral("laneRanges"))
                      .toObject()
                      .value(QStringLiteral("cc:2:7"))
                      .toInt() == 91 &&
              canonicalEditor.value(QStringLiteral("emptyLanes")).toArray() ==
                  QJsonArray{laneJson(2, 7)} &&
              canonicalEditor.value(QStringLiteral("hiddenLanes")).toArray() ==
                  QJsonArray{laneJson(2, 20), laneJson(2, 21)},
          "editor JSON stores only ordered lane state");

    QJsonObject viewOnly;
    viewOnly.insert(QStringLiteral("pxPerBeat"), 48.0);
    const EditorAutomationRowId legacyHeightLane = controllerRow(3, 7);
    const EditorAutomationRowId legacyEmptyLane = controllerRow(3, 8);
    const EditorAutomationRowId legacyHiddenFirst = controllerRow(3, 9);
    const EditorAutomationRowId legacyHiddenSecond = controllerRow(3, 10);
    QJsonObject legacyView = viewOnly;
    legacyView.insert(QStringLiteral("laneHeight"), 64);
    legacyView.insert(QStringLiteral("laneHeights"), QJsonObject{{QStringLiteral("cc:3:7"), 72}});
    legacyView.insert(QStringLiteral("laneRanges"), QJsonObject{{QStringLiteral("cc:3:7"), 42}});
    legacyView.insert(QStringLiteral("emptyLanes"), QJsonArray{laneJson(3, 8)});
    legacyView.insert(QStringLiteral("hiddenLanes"), QJsonArray{laneJson(3, 9), laneJson(3, 10)});
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), legacyView}}),
          "seeded legacy view lane state");
    ViewSidecar::Snapshot migrated;
    check(
        ViewSidecar::load(scratchProject, label, &migrated) && migrated.editor.laneHeight == 64 &&
            migrated.editor.laneHeights.size() == 1 &&
            migrated.editor.laneHeights.find(legacyHeightLane) !=
                migrated.editor.laneHeights.end() &&
            migrated.editor.laneHeights.at(legacyHeightLane) == 72 &&
            migrated.editor.laneRanges.size() == 1 &&
            migrated.editor.laneRanges.find(legacyHeightLane) != migrated.editor.laneRanges.end() &&
            migrated.editor.laneRanges.at(legacyHeightLane) == 42 &&
            migrated.editor.emptyLanes.size() == 1 &&
            migrated.editor.emptyLanes.find(legacyEmptyLane) != migrated.editor.emptyLanes.end() &&
            migrated.editor.hiddenLanes() ==
                std::vector<EditorAutomationRowId>{legacyHiddenFirst, legacyHiddenSecond},
        "legacy view lane state migrates in order");
    check(ViewSidecar::save(scratchProject, label, migrated), "saved migrated lane state");
    const QJsonObject migratedRoot = readJson(path);
    const QJsonObject migratedView = migratedRoot.value(QStringLiteral("view")).toObject();
    const QJsonObject migratedEditor = migratedRoot.value(QStringLiteral("editor")).toObject();
    check(!migratedView.contains(QStringLiteral("laneHeight")) &&
              !migratedView.contains(QStringLiteral("laneHeights")) &&
              !migratedView.contains(QStringLiteral("laneRanges")) &&
              !migratedView.contains(QStringLiteral("emptyLanes")) &&
              !migratedView.contains(QStringLiteral("hiddenLanes")) &&
              migratedEditor.contains(QStringLiteral("laneHeight")) &&
              migratedEditor.contains(QStringLiteral("laneHeights")) &&
              migratedEditor.contains(QStringLiteral("laneRanges")) &&
              migratedEditor.contains(QStringLiteral("emptyLanes")) &&
              migratedEditor.contains(QStringLiteral("hiddenLanes")),
          "saving migration writes lane state under editor");

    QJsonObject editorLaneState;
    editorLaneState.insert(QStringLiteral("laneHeight"), 96);
    editorLaneState.insert(QStringLiteral("laneHeights"),
                           QJsonObject{{QStringLiteral("cc:2:7"), 112}});
    editorLaneState.insert(QStringLiteral("laneRanges"),
                           QJsonObject{{QStringLiteral("cc:2:7"), 91}});
    editorLaneState.insert(QStringLiteral("emptyLanes"), QJsonArray{laneJson(2, 7)});
    editorLaneState.insert(QStringLiteral("hiddenLanes"),
                           QJsonArray{laneJson(2, 20), laneJson(2, 21)});
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), legacyView},
                                      {QStringLiteral("editor"), editorLaneState}}),
          "seeded competing editor lane state");
    ViewSidecar::Snapshot editorPreferred;
    check(ViewSidecar::load(scratchProject, label, &editorPreferred) &&
              hasSavedLaneState(editorPreferred.editor),
          "editor lane fields take precedence over legacy view fields");

    check(writeJson(path, QJsonObject{{QStringLiteral("view"), viewOnly}}),
          "seeded view without canonical editor state");
    ViewSidecar::Snapshot defaults;
    check(ViewSidecar::load(scratchProject, label, &defaults) &&
              defaults.editor == EditorViewState{},
          "missing editor object uses editor defaults");

    check(writeJson(path, QJsonObject{{QStringLiteral("view"), viewOnly},
                                      {QStringLiteral("editor"), QStringLiteral("not-an-object")}}),
          "seeded malformed editor object");
    ViewSidecar::Snapshot malformedDefaults;
    check(ViewSidecar::load(scratchProject, label, &malformedDefaults) &&
              malformedDefaults.editor == EditorViewState{},
          "malformed editor object uses editor defaults");

    QJsonObject malformedRoot;
    QJsonObject malformedView;
    malformedView.insert(QStringLiteral("pxPerBeat"), true);
    malformedRoot.insert(QStringLiteral("view"), malformedView);
    QJsonObject malformedEditor;
    malformedEditor.insert(QStringLiteral("laneHeight"), QStringLiteral("96"));
    QJsonObject heights;
    heights.insert(QStringLiteral("cc:2:7"), 112);
    heights.insert(QStringLiteral("cc:2:128"), 64);
    heights.insert(QStringLiteral("cc:2:255"), 64);
    heights.insert(QStringLiteral("voice:01"), 64);
    heights.insert(QStringLiteral("tempo"), QStringLiteral("bad"));
    malformedEditor.insert(QStringLiteral("laneHeights"), heights);
    QJsonObject ranges;
    ranges.insert(QStringLiteral("cc:2:7"), 91);
    ranges.insert(QStringLiteral("cc:2:128"), 91);
    ranges.insert(QStringLiteral("cc:2:255"), 128);
    malformedEditor.insert(QStringLiteral("laneRanges"), ranges);
    QJsonArray emptyLanes;
    emptyLanes.append(laneJson(2, 7));
    emptyLanes.append(laneJson(2, 128));
    emptyLanes.append(
        QJsonObject{{QStringLiteral("track"), QStringLiteral("2")}, {QStringLiteral("cc"), 7}});
    malformedEditor.insert(QStringLiteral("emptyLanes"), emptyLanes);
    QJsonArray hiddenLanes;
    hiddenLanes.append(laneJson(2, 20));
    hiddenLanes.append(laneJson(2, 128));
    malformedEditor.insert(QStringLiteral("hiddenLanes"), hiddenLanes);
    malformedRoot.insert(QStringLiteral("editor"), malformedEditor);
    check(writeJson(path, malformedRoot), "seeded malformed known entries");
    ViewSidecar::Snapshot strict;
    check(ViewSidecar::load(scratchProject, label, &strict),
          "loads canonical objects with malformed entries");
    check(strict.view.pxPerBeat == SongView::ViewState{}.pxPerBeat && strict.editor.laneHeight == 0,
          "invalid known scalars fall back independently");
    check(strict.editor.laneHeights.size() == 2 &&
              strict.editor.laneHeights.find(volume) != strict.editor.laneHeights.end() &&
              strict.editor.laneHeights.find(controllerRow(2, 255)) !=
                  strict.editor.laneHeights.end() &&
              strict.editor.laneRanges.size() == 1 && strict.editor.laneRanges.at(volume) == 91,
          "row keys and range values use canonical strict validation");
    check(strict.editor.emptyLanes.size() == 1 &&
              strict.editor.emptyLanes.find(volume) != strict.editor.emptyLanes.end() &&
              strict.editor.hiddenLanes().size() == 1 && strict.editor.hiddenLanes()[0] == hidden,
          "lane arrays tolerate bad entries without retaining invalid lanes");

    const EditorAutomationRowId tempoRow{EditorAutomationRowKind::Tempo, 0, 0};
    QJsonObject voiceDiscardHeights;
    voiceDiscardHeights.insert(QStringLiteral("tempo"), 94);
    voiceDiscardHeights.insert(QStringLiteral("cc:2:7"), 112);
    voiceDiscardHeights.insert(QStringLiteral("voice:0"), 66);
    voiceDiscardHeights.insert(QStringLiteral("voice:2"), 70);
    QJsonObject voiceDiscardRanges;
    voiceDiscardRanges.insert(QStringLiteral("tempo"), 116);
    voiceDiscardRanges.insert(QStringLiteral("cc:2:7"), 91);
    voiceDiscardRanges.insert(QStringLiteral("voice:0"), 103);
    QJsonObject voiceDiscardEditor;
    voiceDiscardEditor.insert(QStringLiteral("laneHeight"), 96);
    voiceDiscardEditor.insert(QStringLiteral("laneHeights"), voiceDiscardHeights);
    voiceDiscardEditor.insert(QStringLiteral("laneRanges"), voiceDiscardRanges);
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), QJsonObject{}},
                                      {QStringLiteral("editor"), voiceDiscardEditor}}),
          "seeded legacy voice sidecar entries");
    ViewSidecar::Snapshot voiceDiscarded;
    check(ViewSidecar::load(scratchProject, label, &voiceDiscarded),
          "loads sidecar with legacy voice keys");
    check(voiceDiscarded.editor.laneHeight == 96 && voiceDiscarded.editor.laneHeights.size() == 2 &&
              voiceDiscarded.editor.laneHeights.find(tempoRow) !=
                  voiceDiscarded.editor.laneHeights.end() &&
              voiceDiscarded.editor.laneHeights.at(tempoRow) == 94 &&
              voiceDiscarded.editor.laneHeights.at(volume) == 112 &&
              voiceDiscarded.editor.laneRanges.size() == 2 &&
              voiceDiscarded.editor.laneRanges.at(tempoRow) == 116 &&
              voiceDiscarded.editor.laneRanges.at(volume) == 91,
          "legacy voice sidecar entries are discarded while Tempo and CC survive");
    check(ViewSidecar::save(scratchProject, label, voiceDiscarded),
          "saves sidecar after discarding voice keys");
    const QByteArray rewrittenSidecar = fileContents(path);
    const QJsonObject rewrittenHeights = readJson(path)
                                             .value(QStringLiteral("editor"))
                                             .toObject()
                                             .value(QStringLiteral("laneHeights"))
                                             .toObject();
    const QJsonObject rewrittenRanges = readJson(path)
                                            .value(QStringLiteral("editor"))
                                            .toObject()
                                            .value(QStringLiteral("laneRanges"))
                                            .toObject();
    check(!QString::fromUtf8(rewrittenSidecar).contains(QLatin1String("voice:")) &&
              rewrittenHeights.contains(QStringLiteral("tempo")) &&
              rewrittenHeights.contains(QStringLiteral("cc:2:7")) &&
              rewrittenRanges.contains(QStringLiteral("tempo")) &&
              rewrittenRanges.contains(QStringLiteral("cc:2:7")),
          "reserialized sidecar contains no voice key");

    const int maximumRowHeight = layout::fontPx(32.0 / 3.0);
    QJsonObject oversizedHeights;
    oversizedHeights.insert(QStringLiteral("cc:2:7"), maximumRowHeight + 1);
    QJsonObject oversizedEditor;
    oversizedEditor.insert(QStringLiteral("laneHeight"), maximumRowHeight + 1);
    oversizedEditor.insert(QStringLiteral("laneHeights"), oversizedHeights);
    check(writeJson(path, QJsonObject{{QStringLiteral("view"), QJsonObject{}},
                                      {QStringLiteral("editor"), oversizedEditor}}),
          "seeded oversized row heights");
    ViewSidecar::Snapshot clamped;
    check(ViewSidecar::load(scratchProject, label, &clamped), "loads oversized row heights");
    const auto clampedHeight = clamped.editor.laneHeights.find(volume);
    check(clamped.editor.laneHeight == maximumRowHeight &&
              clampedHeight != clamped.editor.laneHeights.end() &&
              clampedHeight->second == maximumRowHeight,
          "oversized row heights restore at the resolved maximum");
    check(ViewSidecar::save(scratchProject, label, clamped), "saves clamped row heights");
    const QJsonObject clampedEditor = readJson(path).value(QStringLiteral("editor")).toObject();
    check(clampedEditor.value(QStringLiteral("laneHeight")).toInt() == maximumRowHeight &&
              clampedEditor.value(QStringLiteral("laneHeights"))
                      .toObject()
                      .value(QStringLiteral("cc:2:7"))
                      .toInt() == maximumRowHeight,
          "save retains canonical row heights");

    ViewSidecar::Snapshot unchanged;
    unchanged.view.valid = true;
    unchanged.editor.laneHeight = 64;
    check(writeJson(path, QJsonObject{{QStringLiteral("view"),
                                       QJsonValue(QStringLiteral("not-an-object"))}}),
          "seeded malformed view root");
    check(!ViewSidecar::load(scratchProject, label, &unchanged) && unchanged.view.valid &&
              unchanged.editor.laneHeight == 64,
          "malformed view leaves caller snapshot untouched");
    check(!ViewSidecar::load(scratchProject, label + QStringLiteral("-missing"), &unchanged),
          "missing sidecar fails silently");
    check(!ViewSidecar::save(scratchProject, QString(), saved), "empty song label fails silently");

    QFile::remove(path);
    std::fprintf(stdout, "sidecar: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
