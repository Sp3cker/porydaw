#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <utility>

RenderingPlayheadTest::RenderingPlayheadTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

int runRenderingPlayheadCheck(const QString &projectRoot, const QString &songLabel,
                              const QString &screenshotPath, const QStringList &qtArguments)
{
    Q_UNUSED(screenshotPath);
    RenderingPlayheadTest test{projectRoot, songLabel};
    QStringList arguments{QStringLiteral("rendering-playhead")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#ifdef __APPLE__
RenderingPlayheadNativeTest::RenderingPlayheadNativeTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

int runRenderingPlayheadNativeCheck(const QString &projectRoot, const QString &songLabel,
                                    const QStringList &qtArguments)
{
    RenderingPlayheadNativeTest test{projectRoot, songLabel};
    QStringList arguments{QStringLiteral("rendering-playhead-native")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
#endif
