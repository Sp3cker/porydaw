#pragma once

#include <QString>
#include <QStringList>
int runRetainedBoundaryCheck(const QString &mode, const QString &projectRoot,
                             const QString &songLabel, const QString &toolPath,
                             const QStringList &qtArguments);
