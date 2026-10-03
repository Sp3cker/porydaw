#pragma once

#include <QString>
#include <QStringList>

#if defined(__APPLE__) || defined(__linux__)
int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
#endif
