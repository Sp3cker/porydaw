#pragma once

#include <memory>

#include <QObject>
#include <QString>
#include <QStringList>

namespace voicegroup_test {
struct ProjectSession;
}

class VoicegroupSourceTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicegroupSourceTest)

  public:
    VoicegroupSourceTest(QString stagedRoot, QString songLabel);
    ~VoicegroupSourceTest() override;

  private slots:
    void init();
    void blankSlotCreateAndRestore();
    void sparseInsertionsSerializeAtBothEnds();
    void editedFamiliesPreviewSaveReloadAndCreate_data();
    void editedFamiliesPreviewSaveReloadAndCreate();
    void displayNamesAreStable();
    void typicalAdsrSyntheticScan();
    void typicalAdsrFixtureSuggestionsAreAudible();
    void synthCatalogWriteAndGates();
    void singleColonSymbolsScanAndLoad();
    void synthDescriptorLoadsThroughVoicegroup();

  private:
    QString m_songLabel;
    QString m_stagedRoot;
    std::unique_ptr<voicegroup_test::ProjectSession> m_session;
};

int runVgCheck(const QString &projectRoot, const QString &songLabel,
               const QStringList &qtArguments);
