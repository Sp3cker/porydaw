#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QComboBox>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLineEdit>
#include <QListWidget>
#include <QSettings>
#include <QSignalSpy>
#include <QStatusBar>

#include <functional>
#include <map>
#include <vector>

#include "mainwindow.h"
#include "project/sidecar.h"
#include "ui/layout.h"
#include "ui/songlistpanel.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace {

using SettingsMap = std::map<QString, QVariant>;

SettingsMap sessionAndEditorSettings()
{
    QSettings settings;
    settings.sync();
    SettingsMap result;
    for (const QString &key : settings.allKeys()) {
        if (key.startsWith(QStringLiteral("editorDrawer/")) ||
            key == QStringLiteral("lastProjectDir") || key == QStringLiteral("lastSongLabel") ||
            key == QStringLiteral("lastOpenSongs") || key == QStringLiteral("windowGeometry") ||
            key == QStringLiteral("windowState") || key.startsWith(QStringLiteral("songFilter")))
            result.emplace(key, settings.value(key));
    }
    return result;
}

bool sidecarSnapshot(const QString &projectRoot, std::map<QString, QByteArray> &snapshot,
                     QString &error)
{
    snapshot.clear();
    const QString root = Sidecar::dirPath(projectRoot);
    const std::function<bool(const QDir &, const QString &)> visit =
        [&snapshot, &error, &visit](const QDir &directory, const QString &prefix) {
            const QFileInfoList entries = directory.entryInfoList(
                QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::DirsFirst);
            for (const QFileInfo &entry : entries) {
                const QString name = prefix.isEmpty()
                                         ? entry.fileName()
                                         : prefix + QLatin1Char('/') + entry.fileName();
                if (entry.isDir()) {
                    if (!visit(QDir(entry.absoluteFilePath()), name))
                        return false;
                    continue;
                }
                QFile file(entry.absoluteFilePath());
                if (!file.open(QIODevice::ReadOnly)) {
                    error = QStringLiteral("could not read sidecar file %1").arg(name);
                    return false;
                }
                snapshot.emplace(name, file.readAll());
            }
            return true;
        };
    return !QDir(root).exists() || visit(QDir(root), QString());
}

EditorViewState completeEditorState()
{
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
    const EditorAutomationRowId firstHidden{EditorAutomationRowKind::ControlChange, 1, 7};
    const EditorAutomationRowId secondHidden{EditorAutomationRowKind::ControlChange, 0, 80};
    const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
    const int floor = layout::fontPx(7.0 / 3.0);
    const int ceiling = layout::fontPx(32.0 / 3.0);
    auto state = EditorViewState{};
    state.velocity = {false, 131};
    state.automation = {true, 143};
    state.voiceChanges = {true, 157};
    state.activePage = EditorDrawerPage::VoiceChanges;
    state.laneHeight = (floor + ceiling) / 2;
    state.laneHeights = {{lane, floor + 3}, {firstHidden, floor + 5}};
    state.laneRanges = {{lane, 90}, {tempo, 100}};
    state.emptyLanes.insert(lane);
    state.hideLane(firstHidden);
    state.hideLane(secondHidden);
    return state;
}

} // namespace

WorkspaceSessionTest::WorkspaceSessionTest(QString projectRoot, QString songLabel)
    : m_songLabel(std::move(songLabel))
    , m_project(std::move(projectRoot))
{}

void WorkspaceSessionTest::init()
{
    QSettings settings;
    settings.clear();
    settings.sync();
    QString error;
    QVERIFY2(m_project.reset(error), qPrintable(error));
}

void WorkspaceSessionTest::cleanup()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

void WorkspaceSessionTest::restoreProjectOnly_data()
{
    QTest::addColumn<QString>("recipe");
    QTest::newRow("nothing") << QStringLiteral("nothing");
    QTest::newRow("vanished-project") << QStringLiteral("gone");
    QTest::newRow("project-without-song") << QStringLiteral("project");
}

void WorkspaceSessionTest::restoreProjectOnly()
{
    QFETCH(QString, recipe);
    QSettings settings;
    if (recipe == QStringLiteral("gone")) {
        settings.setValue(QStringLiteral("lastProjectDir"),
                          m_project.root() + QStringLiteral("/gone"));
        settings.setValue(QStringLiteral("lastSongLabel"), m_songLabel);
    } else if (recipe == QStringLiteral("project")) {
        settings.setValue(QStringLiteral("lastProjectDir"), m_project.root());
    }
    settings.sync();

    MainWindow window;
    if (recipe == QStringLiteral("project")) {
        const QString title = QStringLiteral("%1 — porydaw").arg(QDir(m_project.root()).dirName());
        QTRY_COMPARE(window.windowTitle(), title);
        QVERIFY(window.statusBar()->currentMessage().startsWith(QStringLiteral("Opened")));
        QCOMPARE(window.m_workspace->openTabCount(), 0);
    } else {
        QTRY_COMPARE(window.windowTitle(), QStringLiteral("porydaw"));
        QCOMPARE(window.m_workspace->openTabCount(), 0);
    }
}

void WorkspaceSessionTest::closeReopenPreservesSession()
{
    QSettings settings;
    settings.setValue(QStringLiteral("lastProjectDir"), m_project.root());
    settings.setValue(QStringLiteral("lastSongLabel"), m_songLabel);
    settings.sync();

    const EditorViewState complete = completeEditorState();
    std::map<QString, QByteArray> sidecarBefore;
    QString snapshotError;
    QString category;
    {
        MainWindow window;
        auto *workspace = window.m_workspace.get();
        QVERIFY(workspace);
        auto *panel = window.findChild<SongListPanel *>();
        auto *list = panel ? panel->findChild<QListWidget *>() : nullptr;
        QTRY_VERIFY(list && list->currentItem() &&
                    list->currentItem()->text().startsWith(m_songLabel));
        SongTab *tab = workspace->selectedSongTab();
        QVERIFY(tab);
        QTRY_VERIFY(tab->isReady());

        workspace->setEditorViewState(complete);
        QVERIFY(loadEditorViewState(settings) == complete);
        QVERIFY(tab->view().editorViewState() == complete);
        QVERIFY(sidecarSnapshot(m_project.root(), sidecarBefore, snapshotError));

        auto *search = window.findChild<QLineEdit *>(QStringLiteral("songListSearch"));
        auto *sort = window.findChild<QComboBox *>(QStringLiteral("songListSort"));
        auto *categoryBox = window.findChild<QComboBox *>(QStringLiteral("songListCategory"));
        QVERIFY(search);
        QVERIFY(sort);
        QVERIFY(categoryBox);
        QVERIFY(categoryBox->count() > 1);
        categoryBox->setCurrentIndex(1);
        category = categoryBox->currentData().toString();
        sort->setCurrentIndex(1);
        search->setText(QStringLiteral("filterme"));
        window.resize(777, 505);
        // The legacy contract records a geometry blob on close but does not
        // assert relaunch dimensions; do not expand this migration with a
        // geometry-restoration oracle.
        window.close();
        QTRY_VERIFY(!settings.value(QStringLiteral("windowGeometry")).toByteArray().isEmpty());
        QCOMPARE(settings.value(QStringLiteral("lastProjectDir")).toString(), m_project.root());
        QCOMPARE(settings.value(QStringLiteral("lastSongLabel")).toString(), m_songLabel);
        QCOMPARE(settings.value(QStringLiteral("lastOpenSongs")).toStringList(),
                 QStringList{m_songLabel});
        QCOMPARE(settings.value(QStringLiteral("songFilterText")).toString(),
                 QStringLiteral("filterme"));
    }

    const SettingsMap beforeRestore = sessionAndEditorSettings();
    std::map<QString, QByteArray> sidecarAfterClose;
    QVERIFY2(sidecarSnapshot(m_project.root(), sidecarAfterClose, snapshotError),
             qPrintable(snapshotError));
    QVERIFY(sidecarAfterClose == sidecarBefore);

    MainWindow restored;
    auto *workspace = restored.m_workspace.get();
    QVERIFY(workspace);
    const std::vector<SongTab *> startupTabs = workspace->tabsInDisplayOrder();
    QVERIFY(!startupTabs.empty());
    for (SongTab *tab : startupTabs) {
        QVERIFY(tab);
        QCOMPARE(tab->view().editorViewState(), complete);
    }
    QVERIFY(sessionAndEditorSettings() == beforeRestore);

    QSignalSpy editorChanges(workspace, &WorkspaceUi::editorViewStateChanged);
    QSignalSpy editorWrites(&restored, &MainWindow::editorViewStatePersisted);
    SongTab *restoredTab = nullptr;
    QTRY_VERIFY((restoredTab = workspace->selectedSongTab()) && restoredTab->isReady());
    QVERIFY(restored.windowTitle().startsWith(m_songLabel));
    QVERIFY(sessionAndEditorSettings() == beforeRestore);
    QVERIFY(restoredTab->view().editorViewState() == complete);
    QVERIFY(restoredTab->view().editorViewState().hiddenLanes() == complete.hiddenLanes());
    auto *search = restored.findChild<QLineEdit *>(QStringLiteral("songListSearch"));
    auto *sort = restored.findChild<QComboBox *>(QStringLiteral("songListSort"));
    auto *categoryBox = restored.findChild<QComboBox *>(QStringLiteral("songListCategory"));
    QVERIFY(search);
    QVERIFY(sort);
    QVERIFY(categoryBox);
    QCOMPARE(search->text(), QStringLiteral("filterme"));
    QCOMPARE(sort->currentIndex(), 1);
    QTRY_COMPARE(categoryBox->currentData().toString(), category);
    std::map<QString, QByteArray> sidecarAfterRestore;
    QVERIFY2(sidecarSnapshot(m_project.root(), sidecarAfterRestore, snapshotError),
             qPrintable(snapshotError));
    QVERIFY(sidecarAfterRestore == sidecarBefore);
}

void WorkspaceSessionTest::deletedRecipeSongIsIgnored()
{
    QSettings settings;
    settings.setValue(QStringLiteral("lastProjectDir"), m_project.root());
    settings.setValue(QStringLiteral("lastOpenSongs"), QStringList{QStringLiteral("mus_missing")});
    settings.setValue(QStringLiteral("lastSongLabel"), QStringLiteral("mus_missing"));
    settings.sync();

    MainWindow window;
    const QString title = QStringLiteral("%1 — porydaw").arg(QDir(m_project.root()).dirName());
    QTRY_COMPARE(window.windowTitle(), title);
    QCOMPARE(window.m_workspace->openTabCount(), 0);
}
