#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>

#include "core/smf.h"
#include "project/decompproject.h"
#include "project/songregistry.h"

namespace OnboardCheck {

struct Context {
    QString projectRoot;
    QString midiDir;
    QString mid2agb;
    bool haveMid2agb = false;
    int registeredCount = 0;
    QStringList voicegroupArgs;
    DecompProject project;
    SongCfg cfg;
    SmfFile externalImport;
    SmfFile duplicateSetters;
};

struct RegisteredSongFixture {
    QString label;
    QString constant;
    RegistrationPlan plan;
};

void check(bool ok, const char *what);
int failureCount();
QByteArray readAllBytes(const QString &path);
bool readMidiFixture(const QString &projectRoot, const QString &fileName, SmfFile *smf);
bool compilesThroughMid2agb(const QString &mid2agb, const QString &midPath,
                            const QStringList &flags);

RegisteredSongFixture runRegistrationChecks(Context &context);
void runRegisterActionChecks(Context &context, const RegisteredSongFixture &fixture);
void runDebugLayoutChecks(Context &context, const RegisteredSongFixture &fixture);
void runRegionedLayoutChecks(Context &context);
void runImportChecks(Context &context);
void runDeletionChecks(Context &context);

} // namespace OnboardCheck
