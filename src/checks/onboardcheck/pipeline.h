#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>

#include "core/smf.h"
#include "project/decompproject.h"
#include "project/songregistry.h"

namespace OnboardCheck {

class CheckReporter
{
  public:
    void check(bool ok, const char *what);
    void check(bool ok, const QString &what);
    int failureCount() const { return m_failures; }
    bool hasFailures() const { return m_failures > 0; }

  private:
    int m_failures = 0;
};

struct RegisteredSongFixture {
    QString label;
    QString constant;
    RegistrationPlan plan;
};

QByteArray readAllBytes(const QString &path);
bool readMidiFixture(const QString &projectRoot, const QString &fileName, SmfFile *smf,
                     CheckReporter &reporter);
bool compilesThroughMid2agb(const QString &mid2agb, const QString &midPath,
                            const QStringList &flags);

RegisteredSongFixture runRegistrationChecks(const QString &projectRoot, const QString &midiDir,
                                            int registeredCount, DecompProject &project,
                                            const SongCfg &cfg, CheckReporter &reporter);

void runRegisterActionChecks(const QString &projectRoot, const QString &midiDir,
                             const QString &mid2agb, bool haveMid2agb, const SongCfg &cfg,
                             const RegisteredSongFixture &fixture, CheckReporter &reporter);

void runDebugLayoutChecks(const QString &projectRoot, DecompProject &project,
                          const RegisteredSongFixture &fixture, CheckReporter &reporter);

void runRegionedLayoutChecks(const QString &projectRoot, CheckReporter &reporter);

void runImportChecks(const QString &projectRoot, const QString &midiDir, const QString &mid2agb,
                     bool haveMid2agb, const QStringList &voicegroupArgs, DecompProject &project,
                     const SongCfg &cfg, const SmfFile &externalImport,
                     const SmfFile &duplicateSetters, CheckReporter &reporter);

void runDeletionChecks(const QString &projectRoot, const QString &midiDir, DecompProject &project,
                       const SongCfg &cfg, bool charmapApplicable, CheckReporter &reporter);

} // namespace OnboardCheck
