#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>
#include <QtTest>

#include <memory>

#include "core/smf.h"
#include "project/decompproject.h"
#include "project/songregistry.h"

namespace checks {
class ProjectFixture;
}
enum class OnboardingDialog {
    Register,
    Delete,
};

class MainWindow;
class SongTab;
class QMessageBox;

class OnboardingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(OnboardingTest)

  public:
    explicit OnboardingTest(QString projectRoot, QString mid2agbPath);
    ~OnboardingTest() override;

  private slots:
    void projectEnumerationAndTrackBudgets();

    void newSongRegistration_data();
    void newSongRegistration();
    void registrationBackfill_data();
    void registrationBackfill();
    void registrationAliases_data();
    void registrationAliases();

    void debugLayouts_data();
    void debugLayouts();
    void regionedValueLayouts_data();
    void regionedValueLayouts();
    void regionedAliasLayouts_data();
    void regionedAliasLayouts();

    void importAnalysis_data();
    void importAnalysis();
    void importRescale();
    void importDedup();
    void importWizard();
    void importRoundtrip();
    void compilesThroughMid2agb_data();
    void compilesThroughMid2agb();

    void songDeletion_data();
    void songDeletion();
    void voicegroupDeletion_data();
    void voicegroupDeletion();
    void registerAction();
    void deleteAction_data();
    void deleteAction();

  private:
    std::unique_ptr<checks::ProjectFixture> copyProject(QString &error);
    QByteArray readFile(const QString &path, QString &error) const;
    bool writeFile(const QString &path, const QByteArray &bytes, QString &error) const;
    bool midiFixture(const QString &name, SmfFile &midi, QString &error) const;
    int registeredCount(const DecompProject &project) const;
    QString midiDirectory(const QString &root) const;
    bool defaultCfg(const QString &root, SongCfg &cfg, QString &error) const;
    bool compile(const QString &root, const QString &midPath, const QStringList &flags,
                 QString &error) const;
    bool openSong(MainWindow &window, const QString &root, const QString &label,
                  QString &error) const;
    QMessageBox *waitForDialog(MainWindow &window, OnboardingDialog operation,
                               QString &error) const;
    void closeWorkspace(MainWindow &window) const;

    QString m_projectRoot;
    QString m_mid2agbPath;
};

int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath,
                    const QStringList &qtArguments);
