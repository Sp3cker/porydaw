#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

namespace {

template <typename Test>
int exec(Test &test, const QString &name, const QStringList &qtArguments)
{
    auto arguments = QStringList{name};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace

int runSessionCheck(const QString &projectRoot, const QString &songLabel,
                    const QStringList &qtArguments)
{
    WorkspaceSessionTest test(projectRoot, songLabel);
    return exec(test, QStringLiteral("sessioncheck"), qtArguments);
}

int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                const QStringList &qtArguments)
{
    WorkspaceTabsTest test(projectRoot, songA, songB);
    return exec(test, QStringLiteral("tabcheck"), qtArguments);
}

int runSelfTestTimelineCheck(const QStringList &checkArguments, const QStringList &qtArguments)
{
    WorkspaceTimelineSelfTest test(checkArguments.at(1), checkArguments.at(2));
    return exec(test, QStringLiteral("selftest-timeline"), qtArguments);
}

int runSelfTestTransportCheck(const QStringList &checkArguments, const QStringList &qtArguments)
{
    WorkspaceTransportSelfTest test(checkArguments.at(1), checkArguments.at(2));
    return exec(test, QStringLiteral("selftest-transport"), qtArguments);
}

int runSelfTestWorkspaceCheck(const QStringList &checkArguments, const QStringList &qtArguments)
{
    WorkspaceEditorCodecSelfTest test(checkArguments.at(1), checkArguments.at(2));
    return exec(test, QStringLiteral("selftest-workspace"), qtArguments);
}
