#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSettings>
#include <QTemporaryDir>
#include <QTimer>

#include <map>
#include <set>
#include <utility>
#include <vector>

#include "mainwindow.h"
#include "ui/editorviewstate.h"
#include "ui/layout.h"
#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace {

QString laneBlobKey(QSettings &settings)
{
    for (const QString &key : settings.allKeys()) {
        const QVariant value = settings.value(key);
        if (value.typeId() == QMetaType::QByteArray &&
            QJsonDocument::fromJson(value.toByteArray()).isObject())
            return key;
    }
    return {};
}

QByteArray laneBlob(QSettings &settings)
{
    const QString key = laneBlobKey(settings);
    return key.isEmpty() ? QByteArray{} : settings.value(key).toByteArray();
}

bool poisonLaneBlob(QSettings &settings, const QVariant &value)
{
    const QString key = laneBlobKey(settings);
    if (key.isEmpty())
        return false;
    settings.setValue(key, value);
    settings.sync();
    return true;
}

bool compactJsonObject(const QByteArray &bytes)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &error);
    return !bytes.contains('\n') && error.error == QJsonParseError::NoError && document.isObject();
}

bool lanesDefaulted(const EditorViewState &state)
{
    const EditorViewState defaults;
    return state.laneHeight == defaults.laneHeight && state.laneHeights.empty() &&
           state.laneRanges.empty() && state.emptyLanes.empty() && state.hiddenLanes().empty();
}

EditorViewState fullState()
{
    const int minimum = layout::fontPx(7.0 / 3.0);
    const int maximum = layout::fontPx(32.0 / 3.0);
    const EditorAutomationRowId tempo{};
    const EditorAutomationRowId cc074{EditorAutomationRowKind::ControlChange, 0, 74};
    const EditorAutomationRowId cc107{EditorAutomationRowKind::ControlChange, 1, 7};
    const EditorAutomationRowId cc001{EditorAutomationRowKind::ControlChange, 0, 1};
    const EditorAutomationRowId cc310{EditorAutomationRowKind::ControlChange, 3, 10};
    auto state = EditorViewState{};
    state.velocity = {true, 173};
    state.automation = {false, 64};
    state.voiceChanges = {true, 97};
    state.activePage = EditorDrawerPage::Velocity;
    state.laneHeight = minimum + 11;
    state.laneHeights = {{tempo, minimum}, {cc074, maximum}};
    state.laneRanges = {{tempo, 90}, {cc107, 64}};
    state.emptyLanes = {cc001, cc310};
    state.hideLane(cc074);
    state.hideLane(cc107);
    state.hideLane(cc074);
    return state;
}

EditorViewState bareState()
{
    EditorViewState state = fullState();
    state.velocity.height.reset();
    state.automation.height.reset();
    state.voiceChanges.height.reset();
    state.activePage = EditorDrawerPage::VoiceChanges;
    return state;
}

} // namespace

WorkspaceEditorCodecSelfTest::WorkspaceEditorCodecSelfTest(QString projectRoot, QString songLabel)
    : m_songLabel(std::move(songLabel))
    , m_project(std::move(projectRoot))
{}

void WorkspaceEditorCodecSelfTest::init()
{
    QSettings settings;
    settings.clear();
    settings.sync();
    QString error;
    QVERIFY2(m_project.reset(error), qPrintable(error));
}

void WorkspaceEditorCodecSelfTest::cleanup()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

void WorkspaceEditorCodecSelfTest::codecRows_data()
{
    QTest::addColumn<QString>("scenario");
    QTest::newRow("empty-defaults") << QStringLiteral("empty");
    QTest::newRow("full-three-pages") << QStringLiteral("full");
    QTest::newRow("optional-heights") << QStringLiteral("bare");
    QTest::newRow("invalid-json") << QStringLiteral("invalid-json");
    QTest::newRow("empty-lane-blob") << QStringLiteral("empty-blob");
    QTest::newRow("non-object-json") << QStringLiteral("array");
    QTest::newRow("wrong-typed-lane-blob") << QStringLiteral("wrong-type");
    QTest::newRow("row-grammar-and-clamps") << QStringLiteral("grammar");
}

void WorkspaceEditorCodecSelfTest::codecRows()
{
    QFETCH(QString, scenario);
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    QSettings store(directory.filePath(QStringLiteral("editorviewstate.ini")),
                    QSettings::IniFormat);
    QSettings reloaded(directory.filePath(QStringLiteral("editorviewstate.ini")),
                       QSettings::IniFormat);
    const EditorViewState full = fullState();
    const EditorViewState bare = bareState();
    const int minimum = layout::fontPx(7.0 / 3.0);
    const int maximum = layout::fontPx(32.0 / 3.0);

    if (scenario == QStringLiteral("empty")) {
        QVERIFY(loadEditorViewState(store) == EditorViewState{});
        return;
    }
    if (scenario == QStringLiteral("full")) {
        for (const EditorDrawerPage page :
             {EditorDrawerPage::Velocity, EditorDrawerPage::VoiceChanges,
              EditorDrawerPage::Automations}) {
            EditorViewState state = full;
            state.activePage = page;
            saveEditorViewState(store, state);
            store.sync();
            reloaded.sync();
            QVERIFY(loadEditorViewState(reloaded) == state);
            QVERIFY(compactJsonObject(laneBlob(reloaded)));
        }
        return;
    }
    if (scenario == QStringLiteral("bare")) {
        saveEditorViewState(store, bare);
        store.sync();
        reloaded.sync();
        QVERIFY(loadEditorViewState(reloaded) == bare);
        QVERIFY(compactJsonObject(laneBlob(reloaded)));
        return;
    }

    saveEditorViewState(store, full);
    store.sync();
    if (scenario == QStringLiteral("invalid-json"))
        QVERIFY(poisonLaneBlob(store, QByteArray("{ not json")));
    else if (scenario == QStringLiteral("empty-blob"))
        QVERIFY(poisonLaneBlob(store, QByteArray{}));
    else if (scenario == QStringLiteral("array"))
        QVERIFY(poisonLaneBlob(store, QByteArray("[1,2]")));
    else if (scenario == QStringLiteral("wrong-type"))
        QVERIFY(poisonLaneBlob(store, QStringLiteral("seventy-four")));
    else {
        const EditorAutomationRowId tempo{};
        const EditorAutomationRowId cc074{EditorAutomationRowKind::ControlChange, 0, 74};
        const EditorAutomationRowId cc107{EditorAutomationRowKind::ControlChange, 1, 7};
        const EditorAutomationRowId cc001{EditorAutomationRowKind::ControlChange, 0, 1};
        const EditorAutomationRowId cc080{EditorAutomationRowKind::ControlChange, 0, 80};
        auto heights = QJsonObject{{"tempo", minimum + 2}, {"cc:0:74", 5},    {"cc:0:80", 99999999},
                                   {"cc:00:7", 12},        {"voice:0:5", 12}, {"cc:16:7", 12},
                                   {"cc:0:300", 12},       {"nonsense", 12}};
        auto ranges = QJsonObject{{"tempo", 90}, {"cc:1:7", 64}, {"cc:2:3", 128}, {"cc:3:4", -1}};
        auto empty =
            QJsonArray{QJsonObject{{"track", 0}, {"cc", 1}}, QJsonObject{{"track", 16}, {"cc", 1}},
                       QJsonObject{{"track", 2}, {"cc", 300}}, QJsonValue(QStringLiteral("bad"))};
        auto hidden =
            QJsonArray{QJsonObject{{"track", 1}, {"cc", 7}}, QJsonObject{{"track", 0}, {"cc", 74}},
                       QJsonObject{{"track", 1}, {"cc", 7}}};
        const QJsonObject blob{{"laneHeight", 5},       {"laneHeights", heights},
                               {"laneRanges", ranges},  {"emptyLanes", empty},
                               {"hiddenLanes", hidden}, {"unheardOf", true}};
        QVERIFY(poisonLaneBlob(store, QJsonDocument(blob).toJson(QJsonDocument::Compact)));
        const EditorViewState decoded = loadEditorViewState(store);
        QVERIFY(decoded.drawerState() == full.drawerState());
        QCOMPARE(decoded.laneHeight, minimum);
        const std::map<EditorAutomationRowId, int> expectedLaneHeights{
            {tempo, minimum + 2}, {cc074, minimum}, {cc080, maximum}};
        const std::map<EditorAutomationRowId, uint8_t> expectedLaneRanges{{tempo, 90}, {cc107, 64}};
        QVERIFY(decoded.laneHeights == expectedLaneHeights);
        QVERIFY(decoded.laneRanges == expectedLaneRanges);
        QVERIFY(decoded.emptyLanes == std::set<EditorAutomationRowId>{cc001});
        QVERIFY(decoded.hiddenLanes() == std::vector<EditorAutomationRowId>({cc107, cc074}));
        for (int raw : {0, 99999999}) {
            saveEditorViewState(store, full);
            QVERIFY(poisonLaneBlob(
                store,
                QJsonDocument(QJsonObject{{"laneHeight", raw}}).toJson(QJsonDocument::Compact)));
            const EditorViewState clamped = loadEditorViewState(store);
            QVERIFY(clamped.drawerState() == full.drawerState());
            QVERIFY(clamped.laneHeights.empty() && clamped.laneRanges.empty() &&
                    clamped.emptyLanes.empty() && clamped.hiddenLanes().empty());
            QCOMPARE(clamped.laneHeight, raw == 0 ? 0 : maximum);
        }
        return;
    }
    const EditorViewState corrupted = loadEditorViewState(store);
    QVERIFY(corrupted.drawerState() == full.drawerState());
    QVERIFY(lanesDefaulted(corrupted));
}

void WorkspaceEditorCodecSelfTest::livePersistenceAndFinalClose()
{
    MainWindow window;
    window.m_persistSession = false;
    QVERIFY(window.m_audioOk && window.m_audio.usingNullBackend() &&
            window.m_audio.backendName() == QStringLiteral("Null"));
    QSettings store;
    store.sync();
    QVERIFY(laneBlobKey(store).isEmpty());
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));
    const ProjectState &project = workspace->projectState();
    NewSongWizard::ProjectData data;
    data.songs = project.snapshot.songs();
    data.players = project.snapshot.players();
    data.voicegroupArgs = project.catalog.groupArgs;
    data.canCreateVoicegroup = project.catalog.perFileVoicegroups;
    NewSongWizard wizard(data, &window);
    Q_UNUSED(wizard);
    const std::optional<SongName> name = workspace_test::songName(m_songLabel);
    QVERIFY(name);
    SongTab *tab = workspace_test::openReady(*workspace, *name);
    QVERIFY(tab);
    const SongTarget songTarget{tab->document().cfg(), tab->document().label()};
    SettingsDialog dialog(window.m_engineSettings, songTarget, project.catalog.groupArgs,
                          SettingsDialog::Tab::Engine, &window);
    Q_UNUSED(dialog);
    SongView &view = tab->view();
    const EditorViewState original = view.editorViewState();
    const EditorViewState full = fullState();
    const EditorViewState bare = bareState();
    view.setEditorViewState(full);
    QTRY_VERIFY([&] {
        store.sync();
        return loadEditorViewState(store) == full && view.editorViewState() == full;
    }());
    view.setEditorViewState(bare);
    QTRY_VERIFY([&] {
        store.sync();
        return loadEditorViewState(store) == bare;
    }());
    const QString blobKey = laneBlobKey(store);
    QVERIFY(poisonLaneBlob(store, QByteArray("{ not json")));
    const QByteArray poisoned = store.value(blobKey).toByteArray();
    const EditorViewState corrupted = loadEditorViewState(store);
    QVERIFY(corrupted.drawerState() == bare.drawerState());
    QVERIFY(lanesDefaulted(corrupted));
    QCOMPARE(store.value(blobKey).toByteArray(), poisoned);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, layout::fontPx(7.0 / 3.0) + 7);
    QTRY_VERIFY([&] {
        store.sync();
        return compactJsonObject(laneBlob(store)) &&
               loadEditorViewState(store) == view.editorViewState();
    }());
    view.setEditorViewState(original);
    QTRY_VERIFY([&] {
        store.sync();
        return loadEditorViewState(store) == original;
    }());
    window.startPlayback();
    QTRY_VERIFY(window.m_playheadTimer->isActive());
    const SongName closing = tab->name();
    window.m_workspace->requestCloseSelectedTab();
    QTRY_VERIFY(!window.m_workspace->songTabFor(closing) && !window.m_playheadTimer->isActive());
    QCOMPARE(window.m_workspace->openTabCount(), qsizetype(0));
}
