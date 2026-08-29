#include "harness.h"

#include "checks/support/asyncwait.h"
#include "mainwindow.h"

#include <utility>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSettings>
#include <QTemporaryDir>
#include <QTimer>

#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace checks {
namespace {

// Checks observe the codec's store by shape only: keys group under the
// prefix before their first slash, and the lane blob is the single
// QByteArray entry holding a JSON object. editorviewstate.cpp owns every
// key literal, so the checks never name one.

struct StoreShape {
    int entries = 0;
    int laneBlobs = 0;
};

// Top-level group of a settings key: everything before the first slash, or
// the whole key for a root-level entry.
QString keyGroup(const QString &key)
{
    return key.left(key.indexOf(QLatin1Char('/')));
}

// The codec's lane-blob entry: the store's single QByteArray value holding
// a JSON object. Empty when the entry is absent or wrong-shaped.
QString laneBlobKey(QSettings &store)
{
    for (const QString &key : store.allKeys()) {
        const QVariant value = store.value(key);
        if (value.typeId() == QMetaType::QByteArray &&
            QJsonDocument::fromJson(value.toByteArray()).isObject())
            return key;
    }
    return {};
}

// Entry census of the codec's group, identified through the lane blob's
// prefix. Optional height entries exist iff their state values do, so the
// counts defend the save shape without naming keys.
StoreShape storeShape(QSettings &store)
{
    const QString group = keyGroup(laneBlobKey(store));
    StoreShape shape;
    for (const QString &key : store.allKeys()) {
        if (keyGroup(key) != group)
            continue;
        ++shape.entries;
        if (store.value(key).typeId() == QMetaType::QByteArray)
            ++shape.laneBlobs;
    }
    return shape;
}

// The codec's lane-blob bytes, or empty when the entry is absent or
// wrong-shaped.
QByteArray storeLaneBlob(QSettings &store)
{
    const QString blobKey = laneBlobKey(store);
    return blobKey.isEmpty() ? QByteArray{} : store.value(blobKey).toByteArray();
}

// Overwrites the codec's lane-blob entry with poison. Returns false when no
// blob entry exists.
bool poisonLaneBlob(QSettings &store, const QVariant &poison)
{
    const QString blobKey = laneBlobKey(store);
    if (blobKey.isEmpty())
        return false;
    store.setValue(blobKey, poison);
    return true;
}

// Canonical compact self-heal shape: one JSON object on a single line.
bool isCompactJsonObject(const QByteArray &bytes)
{
    if (bytes.contains('\n'))
        return false;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &error);
    return error.error == QJsonParseError::NoError && document.isObject();
}

// Every per-row lane field back at its canonical default.
bool laneRowsDefaulted(const EditorViewState &state)
{
    const EditorViewState defaults;
    return state.laneHeights.empty() && state.laneRanges.empty() && state.emptyLanes.empty() &&
           state.hiddenLanes().empty();
}

// Every lane field back at its canonical default: a missing or malformed blob
// defaults exactly these while the drawer chrome still loads from its entries.
bool lanesDefaulted(const EditorViewState &state)
{
    const EditorViewState defaults;
    return state.laneHeight == defaults.laneHeight && laneRowsDefaulted(state);
}

} // namespace

bool SelfTestHarness::runWorkspaceScenario()
{
    QSettings store;
    store.sync();
    if (!laneBlobKey(store).isEmpty()) {
        qWarning("selftest-workspace: startup wrote editor view state before any semantic change");
        return false;
    }

    const ProjectState &project = m_window.m_workspace->projectState();
    NewSongWizard::ProjectData projectData;
    projectData.songs = project.snapshot.songs();
    projectData.players = project.snapshot.players();
    projectData.voicegroupArgs = project.catalog.groupArgs;
    projectData.canCreateVoicegroup = project.catalog.perFileVoicegroups;
    NewSongWizard wizard(projectData, &m_window);
    const SongTarget songTarget{m_tab->document().cfg(), m_tab->document().label()};
    SettingsDialog settingsDialog(m_window.m_engineSettings, songTarget, project.catalog.groupArgs,
                                  SettingsDialog::Tab::Engine, &m_window);
    qInfo("selftest-workspace: New Song wizard + unified settings dialog constructed");
    const EditorViewState original = m_view->editorViewState();
    if (!SongRegistry::saveRegistrationMeta(m_projectRoot, m_songInfo.label,
                                            QStringLiteral("MUS_SELFTEST"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"))) {
        qWarning("selftest-workspace: registration metadata save failed");
        return false;
    }

    const int laneHeightMin = layout::fontPx(7.0 / 3.0);
    const int laneHeightMax = layout::fontPx(32.0 / 3.0);
    const EditorAutomationRowId tempoRow{};
    const EditorAutomationRowId cc074{EditorAutomationRowKind::ControlChange, 0, 74};
    const EditorAutomationRowId cc107{EditorAutomationRowKind::ControlChange, 1, 7};
    const EditorAutomationRowId cc001{EditorAutomationRowKind::ControlChange, 0, 1};
    const EditorAutomationRowId cc310{EditorAutomationRowKind::ControlChange, 3, 10};
    const EditorAutomationRowId cc080{EditorAutomationRowKind::ControlChange, 0, 80};

    EditorViewState full;
    full.velocity = DrawerSectionState{true, 173};
    full.automation = DrawerSectionState{false, 64};
    full.voiceChanges = DrawerSectionState{true, 97};
    full.activePage = EditorDrawerPage::Velocity;
    full.laneHeight = laneHeightMin + 11;
    full.laneHeights = {{tempoRow, laneHeightMin}, {cc074, laneHeightMax}};
    full.laneRanges = {{tempoRow, 90}, {cc107, 64}};
    full.emptyLanes = {cc001, cc310};
    full.hideLane(cc074);
    full.hideLane(cc107);
    full.hideLane(cc074); // hideLane drops later duplicates; the order sticks.
    EditorViewState bare = full;
    bare.velocity.height.reset();
    bare.automation.height.reset();
    bare.voiceChanges.height.reset();
    bare.activePage = EditorDrawerPage::VoiceChanges;

    // Public codec coverage against a check-owned store: an empty store loads
    // canonical defaults, and the complete state round-trips through a second
    // settings instance, forcing the values through the file. All three active
    // pages share one lane blob, so the page sweep covers the whole state.
    QTemporaryDir codecDir;
    if (!codecDir.isValid()) {
        qWarning("selftest-workspace: could not create a codec scratch store");
        return false;
    }
    const QString codecPath = codecDir.filePath(QStringLiteral("editorviewstate.ini"));
    QSettings codec(codecPath, QSettings::IniFormat);
    if (!(loadEditorViewState(codec) == EditorViewState{})) {
        qWarning("selftest-workspace: an empty store did not load canonical defaults");
        return false;
    }
    QSettings reloaded(codecPath, QSettings::IniFormat);
    for (const auto page : {EditorDrawerPage::Velocity, EditorDrawerPage::VoiceChanges,
                            EditorDrawerPage::Automations}) {
        EditorViewState paged = full;
        paged.activePage = page;
        saveEditorViewState(codec, paged);
        codec.sync();
        reloaded.sync();
        if (!(loadEditorViewState(reloaded) == paged)) {
            qWarning("selftest-workspace: codec save/load did not round-trip the complete state");
            return false;
        }
    }
    const StoreShape completeShape = storeShape(reloaded);
    if (completeShape.entries != 8 || completeShape.laneBlobs != 1 ||
        !isCompactJsonObject(storeLaneBlob(reloaded))) {
        qWarning("selftest-workspace: the complete state did not persist as eight entries with "
                 "one compact lane blob");
        return false;
    }
    saveEditorViewState(codec, bare);
    codec.sync();
    reloaded.sync();
    const StoreShape bareShape = storeShape(reloaded);
    if (bareShape.entries != 5 || bareShape.laneBlobs != 1 ||
        !(loadEditorViewState(reloaded) == bare)) {
        qWarning("selftest-workspace: optional height entries did not exist iff their values did");
        return false;
    }

    // A missing, empty, invalid-JSON, non-object, or wrong-typed blob defaults
    // the lane fields only; the drawer chrome still loads from its entries.
    const std::pair<const char *, QVariant> poisons[] = {
        {"invalid JSON", QVariant(QByteArray("{ not json"))},
        {"empty bytes", QVariant(QByteArray(""))},
        {"non-object JSON", QVariant(QByteArray("[1, 2]"))},
        {"wrong-typed", QVariant(QStringLiteral("seventy-four"))},
    };
    for (const auto &[what, poison] : poisons) {
        saveEditorViewState(codec, full);
        if (!poisonLaneBlob(codec, poison)) {
            qWarning("selftest-workspace: could not locate the lane blob entry to corrupt");
            return false;
        }
        const EditorViewState corrupted = loadEditorViewState(codec);
        if (!(corrupted.drawerState() == full.drawerState()) || !lanesDefaulted(corrupted)) {
            qWarning("selftest-workspace: a %s lane blob did not default the lanes only", what);
            return false;
        }
    }
    saveEditorViewState(codec, full);
    codec.sync();
    if (!isCompactJsonObject(storeLaneBlob(codec))) {
        qWarning("selftest-workspace: the codec did not rewrite a canonical compact blob");
        return false;
    }

    // Row grammar, clamps, and invalid-entry drops inside the lane blob.
    QJsonObject heights;
    heights.insert("tempo", laneHeightMin + 2);
    heights.insert("cc:0:74", 5);
    heights.insert("cc:0:80", 99999999);
    heights.insert("cc:00:7", 12);
    heights.insert("voice:0:5", 12);
    heights.insert("cc:16:7", 12);
    heights.insert("cc:0:300", 12);
    heights.insert("nonsense", 12);
    QJsonObject ranges;
    ranges.insert("tempo", 90);
    ranges.insert("cc:1:7", 64);
    ranges.insert("cc:2:3", 128);
    ranges.insert("cc:3:4", -1);
    QJsonArray emptyLanes;
    emptyLanes.append(QJsonObject{{"track", 0}, {"cc", 1}});
    emptyLanes.append(QJsonObject{{"track", 16}, {"cc", 1}});
    emptyLanes.append(QJsonObject{{"track", 2}, {"cc", 300}});
    emptyLanes.append(QJsonValue(QStringLiteral("nope")));
    QJsonArray hiddenLanes;
    hiddenLanes.append(QJsonObject{{"track", 1}, {"cc", 7}});
    hiddenLanes.append(QJsonObject{{"track", 0}, {"cc", 74}});
    hiddenLanes.append(QJsonObject{{"track", 1}, {"cc", 7}});
    QJsonObject blob;
    blob.insert("laneHeight", 5);
    blob.insert("laneHeights", heights);
    blob.insert("laneRanges", ranges);
    blob.insert("emptyLanes", emptyLanes);
    blob.insert("hiddenLanes", hiddenLanes);
    blob.insert("unheardOf", true);
    saveEditorViewState(codec, full);
    poisonLaneBlob(codec, QJsonDocument(blob).toJson(QJsonDocument::Compact));
    const EditorViewState grammar = loadEditorViewState(codec);
    const bool grammarOk =
        grammar.drawerState() == full.drawerState() && grammar.laneHeight == laneHeightMin &&
        grammar.laneHeights == std::map<EditorAutomationRowId, int>{{tempoRow, laneHeightMin + 2},
                                                                    {cc074, laneHeightMin},
                                                                    {cc080, laneHeightMax}} &&
        grammar.laneRanges ==
            std::map<EditorAutomationRowId, uint8_t>{{tempoRow, 90}, {cc107, 64}} &&
        grammar.emptyLanes == std::set<EditorAutomationRowId>{cc001} &&
        grammar.hiddenLanes() == std::vector<EditorAutomationRowId>{cc107, cc074};
    if (!grammarOk) {
        qWarning("selftest-workspace: lane blob row grammar, clamps, or drops diverged");
        return false;
    }
    for (const int rawLaneHeight : {0, 99999999}) {
        QJsonObject laneHeightOnly;
        laneHeightOnly.insert("laneHeight", rawLaneHeight);
        saveEditorViewState(codec, full);
        poisonLaneBlob(codec, QJsonDocument(laneHeightOnly).toJson(QJsonDocument::Compact));
        const EditorViewState clamped = loadEditorViewState(codec);
        const int expected = rawLaneHeight == 0 ? 0 : laneHeightMax;
        if (clamped.drawerState() != full.drawerState() || !laneRowsDefaulted(clamped) ||
            clamped.laneHeight != expected) {
            qWarning("selftest-workspace: laneHeight %d did not decode to %d", rawLaneHeight,
                     expected);
            return false;
        }
    }

    // The live store: one semantic origin commit fans out and persists the
    // complete state, and optional height entries come and go with their
    // values.
    m_view->setEditorViewState(full);
    if (async_wait::waitUntil([] { return true; },
                              [&] {
                                  store.sync();
                                  return storeShape(store).laneBlobs == 1;
                              },
                              2000) != async_wait::Result::Ready ||
        !(loadEditorViewState(store) == full) || !(m_view->editorViewState() == full)) {
        qWarning("selftest-workspace: the semantic editor save did not persist the complete state");
        return false;
    }
    m_view->setEditorViewState(bare);
    if (async_wait::waitUntil([] { return true; },
                              [&] {
                                  store.sync();
                                  const StoreShape shape = storeShape(store);
                                  return shape.entries == 5 && shape.laneBlobs == 1;
                              },
                              2000) != async_wait::Result::Ready ||
        !(loadEditorViewState(store) == bare)) {
        qWarning("selftest-workspace: the live store did not drop optional height entries");
        return false;
    }

    // Corrupting the live blob defaults the lanes on the next load, and the
    // next semantic editor save rewrites the canonical compact blob — the
    // store self-heals without a startup write.
    if (!poisonLaneBlob(store, QVariant(QByteArray("{ not json")))) {
        qWarning("selftest-workspace: the live lane blob entry disappeared");
        return false;
    }
    store.sync();
    const EditorViewState liveCorrupted = loadEditorViewState(store);
    if (!(liveCorrupted.drawerState() == bare.drawerState()) || !lanesDefaulted(liveCorrupted)) {
        qWarning("selftest-workspace: the live store load did not default the lanes only");
        return false;
    }
    m_view->setDrawerSectionHeight(EditorDrawerPage::Velocity, laneHeightMin + 7);
    if (async_wait::waitUntil([] { return true; },
                              [&] {
                                  store.sync();
                                  return storeShape(store).laneBlobs == 1;
                              },
                              2000) != async_wait::Result::Ready ||
        !isCompactJsonObject(storeLaneBlob(store)) ||
        !(loadEditorViewState(store) == m_view->editorViewState())) {
        qWarning("selftest-workspace: the next semantic save did not self-heal the lane blob");
        return false;
    }
    m_view->setEditorViewState(original);
    if (async_wait::waitUntil([] { return true; },
                              [&] {
                                  store.sync();
                                  return loadEditorViewState(store) == original;
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-workspace: restoring the original view state did not persist");
        return false;
    }
    qInfo("selftest-workspace: editor view-state codec round trip OK");
    if (m_window.m_workspace->selectedSongDirty()) {
        qWarning("selftest-workspace: song still dirty before closing its tab");
        return false;
    }
    if (!beginObservedPlayback())
        return false;
    if (async_wait::waitUntil([this] { return tabIsLive(); },
                              [this] {
                                  m_window.synchronizePlayhead();
                                  return m_window.m_playheadTimer->isActive();
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-workspace: playhead timer did not start during playback");
        return false;
    }
    const SongName closingSong = m_tab->name();
    m_window.m_workspace->requestCloseSelectedTab();
    if (async_wait::waitUntil([] { return true; },
                              [this, &closingSong] {
                                  return !m_window.m_workspace->songTabFor(closingSong) &&
                                         !m_window.m_playheadTimer->isActive();
                              },
                              2000) != async_wait::Result::Ready) {
        qWarning("selftest-workspace: closing final tab left playhead timer active");
        return false;
    }
    m_tab = nullptr;
    m_view = nullptr;
    qInfo("selftest-workspace: closing final tab stopped playhead timer");
    return m_window.m_workspace->openTabCount() == 0;
}

} // namespace checks
