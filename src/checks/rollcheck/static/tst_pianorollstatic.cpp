#include "checks/rollcheck/static/tst_pianorollstatic.h"

#include <QtTest>

namespace checks::rollcheck::staticcheck {

int runPianoRollStaticCheck(const QString &projectRoot, const QString &songLabel,
                            const QStringList &qtArguments)
{
    PianoRollStaticTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("pianoroll-static")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace checks::rollcheck::staticcheck
