#include "checks/timelinepan/timelinepanfixture.h"

#include <QImage>
#include <QStringList>
#include <QtTest>

#include <algorithm>

namespace {

constexpr qint64 kMinimumSelectionPanMilliseconds = 100;
constexpr qint64 kMaximumSelectionPanMultiplier = 8;

class TimelinePanNativeTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelinePanNativeTest)

  public:
    TimelinePanNativeTest(const QString &projectRoot, const QString &songLabel)
        : m_fixture(projectRoot, songLabel)
    {}

    ~TimelinePanNativeTest() override = default;

  private slots:
    void init();
    void cleanup();

    void selectionExtentPanPerformance();

  private:
    void initializeFixture();

    checks::timelinepan::TimelinePanFixture m_fixture;
    bool m_initialized = false;
};

void TimelinePanNativeTest::initializeFixture()
{
    m_initialized = false;

    QString error;
    QVERIFY2(m_fixture.load(error), qPrintable(error));
    m_fixture.show();
    QTRY_VERIFY(m_fixture.isReady(true));

    const QImage captured = m_fixture.capture(&error);
    QVERIFY2(!captured.isNull(), qPrintable(error));
    QVERIFY(!m_fixture.render().isNull());
    QVERIFY(!m_fixture.render().isNull());
    m_initialized = true;
}

void TimelinePanNativeTest::init()
{
    initializeFixture();
}

void TimelinePanNativeTest::cleanup()
{
    m_initialized = false;
    m_fixture.cleanup();
}

void TimelinePanNativeTest::selectionExtentPanPerformance()
{
    qint64 shortMilliseconds = 0;
    QVERIFY(m_initialized);

    QString error;
    QVERIFY2(m_fixture.measureSelectedPan(4, &shortMilliseconds, &error), qPrintable(error));

    // The compared extents must not share selection or renderer state.
    cleanup();
    initializeFixture();
    QVERIFY(m_initialized);

    qint64 longMilliseconds = 0;
    error.clear();
    QVERIFY2(m_fixture.measureSelectedPan(65536, &longMilliseconds, &error), qPrintable(error));

    qInfo().nospace() << "timelinepan-native: short=" << shortMilliseconds
                      << "ms long=" << longMilliseconds << "ms";
    QVERIFY2(longMilliseconds < std::max(kMinimumSelectionPanMilliseconds,
                                         shortMilliseconds * kMaximumSelectionPanMultiplier),
             "pan time grows with the offscreen selection extent");
}

} // namespace

int runTimelinePanNativeCheck(const QString &projectRoot, const QString &songLabel,
                              const QStringList &qtArguments)
{
    TimelinePanNativeTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("timelinepan-native")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_timelinepannative.moc"
