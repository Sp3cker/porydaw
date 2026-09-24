#pragma once

#include <QString>
#include <QStringList>

int runAudioBackendCheck(const QStringList &qtArguments);
int runVgBankCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);

#ifdef __APPLE__
int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
#endif

int runExportCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);
