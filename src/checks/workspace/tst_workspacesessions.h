#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include <cstdint>

#include "checks/workspace/fixture.h"

class MainWindow;
class SongTab;
class SongView;

class WorkspaceSessionTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceSessionTest)

  public:
    WorkspaceSessionTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();
    void restoreProjectOnly_data();
    void restoreProjectOnly();
    void closeReopenPreservesSession();
    void deletedRecipeSongIsIgnored();

  private:
    QString m_songLabel;
    workspace_test::ProjectCopy m_project;
};

class WorkspaceTabsTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceTabsTest)

  public:
    WorkspaceTabsTest(QString projectRoot, QString songA, QString songB);

  private slots:
    void init();
    void cleanup();
    void lifecycle_data();
    void lifecycle();
    void editUndoIsPerTab();
    void persistenceRestoresTabs();
    void voicegroupRefresh();
    void reloadRetainsCameraAndFreshOpenResetsIt();
    void transportVolumesAndRaster();
    void scaleRouting();
    void dirtyCloseUsesProductionGate_data();
    void dirtyCloseUsesProductionGate();
    void tabModelRemovalKeepsSelection();
    void quickTabStripSelectsWithoutStealingFocus();
    void quickTabStripOverflowKeepsTabsReachable();

  private:
    SongTab *open(MainWindow &window, const QString &label, bool newTab = false);
    QString m_songA;
    QString m_songB;
    workspace_test::ProjectCopy m_project;
};

class WorkspaceTimelineSelfTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceTimelineSelfTest)

  public:
    WorkspaceTimelineSelfTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();
    void liveTimelineSwapAndUndo();
    void previewWhileStoppedDoesNotStartTransport();

  private:
    SongTab *openNull(MainWindow &window, SongView *&view);
    bool startObserved(MainWindow &window, SongTab &tab, SongView &view,
                       uint64_t samplePosition = 0);

    QString m_songLabel;
    workspace_test::ProjectCopy m_project;
};

class WorkspaceTransportSelfTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceTransportSelfTest)

  public:
    WorkspaceTransportSelfTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();
    void settingsAndSeekKeepLiveTransport();

  private:
    SongTab *openNull(MainWindow &window, SongView *&view);
    bool startObserved(MainWindow &window, SongTab &tab, SongView &view,
                       uint64_t samplePosition = 0);

    QString m_songLabel;
    workspace_test::ProjectCopy m_project;
};

class WorkspaceEditorCodecSelfTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceEditorCodecSelfTest)

  public:
    WorkspaceEditorCodecSelfTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();
    void codecRows_data();
    void codecRows();
    void livePersistenceAndFinalClose();

  private:
    QString m_songLabel;
    workspace_test::ProjectCopy m_project;
};

int runSessionCheck(const QString &projectRoot, const QString &songLabel,
                    const QStringList &qtArguments);
int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                const QStringList &qtArguments);
int runSelfTestTimelineCheck(const QStringList &checkArguments, const QStringList &qtArguments);
int runSelfTestTransportCheck(const QStringList &checkArguments, const QStringList &qtArguments);
int runSelfTestWorkspaceCheck(const QStringList &checkArguments, const QStringList &qtArguments);
