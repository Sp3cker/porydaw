#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <utility>

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
