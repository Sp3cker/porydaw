#pragma once

#include <QByteArray>
#include <QMetaObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>

#include <functional>
#include <memory>
#include <optional>

#include "project/voicegroupsource.h"

class MainWindow;
class SongTab;
class SongDocument;

namespace checks {
class ProjectFixture;
class VoicegroupBrowserDriver;

class VoicegroupSaveTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicegroupSaveTest)

  public:
    VoicegroupSaveTest(const QString &projectRoot, const QString &songLabel,
                       const QString &screenshotPath);
    ~VoicegroupSaveTest() override;

  private slots:
    void init();
    void cleanup();

    void failedRebindRetainsBinding();
    void catalogOutageRetainsLastValid();
    void releaseEditDirtiesOnlyBank_data();
    void releaseEditDirtiesOnlyBank();
    void undoShortcutRestoresWithoutWrite();
    void unifiedSavePersistsSongAndBank();
    void queuedSaveSnapshotPreservesNewerEdit();
    void undoSaveRoundTripsBankBytes();
    void cleanSaveEmitsNoReceipt();

    void switchCarriesUnsavedBankEdit();
    void selectorSwitchUsesUndoableCfgEdit();
    void valueCommandSurvivesSourceReplacement();
    void blankTokenRebasesAcrossSourceReplacement();

    void releaseEditorUsesBankUndoPipeline_data();
    void releaseEditorUsesBankUndoPipeline();
    void blankTemplateMaterializesUndoably();
    void dockMinimumWidthIsFamilyInvariant();

    void synthDefinitionsStayMemoryOnlyUntilSave();
    void revealsTrackProgramsAndUsedMarks();
    void quickHeaderPressSurvivesVoicegroupRebuild();
    void samplePickerAuditionsAndCommits();
    void samplePickerKeysplitAuditions();
    void samplePickerWaveModeAuditionsAndCommits();
    void newVoicegroupCreatesAndAssignsUndoably();

  private:
    bool openSong(QString &error);
    bool selectFirstDirectSoundVoice(QString &error);
    bool selectFirstPlayableTrack(QString &error);
    int firstBlankSlot() const;
    int firstCgbSlot() const;
    int firstSynthableSlot() const;
    QString otherVoicegroupArg() const;
    QByteArray readFileBytes(const QString &path) const;
    bool refreshCatalog();
    bool saveSelectedSong();
    void requestUndo();
    void requestRedo();
    bool settle(const std::function<bool()> &predicate) const;
    bool waitForBankRelease(int slot, int release, bool dirty) const;
    bool waitForVoicegroup(const QString &arg, const VoicegroupId &id) const;
    bool waitForCleanSave(int receiptsBefore) const;

    QString m_sourceRoot;
    QString m_songLabel;
    std::unique_ptr<QTemporaryDir> m_settingsDirectory;
    QString m_screenshotPath;
    std::unique_ptr<ProjectFixture> m_project;
    std::unique_ptr<MainWindow> m_window;
    SongTab *m_tab = nullptr;
    SongDocument *m_document = nullptr;
    std::unique_ptr<VoicegroupBrowserDriver> m_browser;
    std::optional<VoicegroupId> m_homeId;
    QString m_homeArg;
    QString m_voicegroupPath;
    QString m_loadName;
    QByteArray m_voicegroupBytes;
    QByteArray m_midiBytes;
    VgVoice m_originalVoice;
    int m_dsSlot = -1;
    int m_track = -1;
    int m_savedReceipts = 0;
    QStringList m_failures;
    QMetaObject::Connection m_receiptConnection;
};

} // namespace checks

int runVoicegroupSaveCheck(const QString &projectRoot, const QString &songLabel,
                           const QString &screenshotPath, const QStringList &qtArguments);
