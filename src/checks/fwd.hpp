#pragma once

#include <QString>
#include <QStringList>

int runAudioBackendCheck(const QStringList &qtArguments);

#ifdef __APPLE__
int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
#endif

