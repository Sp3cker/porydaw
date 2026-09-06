#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

int runRenderingPlayheadCheck(const QString &projectRoot, const QString &songLabel,
                              const QString &screenshotPath, const QStringList &qtArguments)
{
    Q_UNUSED(screenshotPath);
    RenderingPlayheadTest test{projectRoot, songLabel};
    QStringList arguments{QStringLiteral("rendering-playhead")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
