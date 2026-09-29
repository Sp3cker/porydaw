#pragma once

#include <QString>
#include <QStringList>

int runAudioBackendCheck(const QStringList &qtArguments);

#if defined(__APPLE__) || defined(__linux__)
int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
#endif
