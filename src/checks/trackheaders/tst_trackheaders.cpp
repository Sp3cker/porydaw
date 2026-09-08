#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <utility>

TrackHeadersTest::TrackHeadersTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

TrackHeadersTest::~TrackHeadersTest() = default;

void TrackHeadersTest::init()
{
    m_fixture = std::make_unique<TrackHeadersFixture>(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(m_fixture->create(error), qPrintable(error));
    QVERIFY2(m_fixture->acquireInputFocus(error), qPrintable(error));
}

void TrackHeadersTest::cleanup()
{
    m_fixture.reset();
}

TrackHeadersFixture &TrackHeadersTest::fixture() noexcept
{
    return *m_fixture;
}

int runTrackHeaderQuickCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments)
{
    TrackHeadersTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("trackheaders")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
