#include "checks/audio/tst_audiobackend.h"
#include "checks/fwd.hpp"

#include <QtTest>

#include "audio/audioengine.h"

namespace checks {

void AudioBackendTest::initTestCase()
{
    // The catalog row also pins this via its environment map; setting it here
    // keeps the suite self-contained under a direct qExec run.
    m_priorBackendEnv = qEnvironmentVariable("PORYDAW_AUDIO_BACKEND");
    qputenv("PORYDAW_AUDIO_BACKEND", "null");
}

void AudioBackendTest::cleanupTestCase()
{
    if (m_priorBackendEnv.isEmpty())
        qunsetenv("PORYDAW_AUDIO_BACKEND");
    else
        qputenv("PORYDAW_AUDIO_BACKEND", m_priorBackendEnv.toUtf8().constData());
}

void AudioBackendTest::forcedNullBackendIsReportable()
{
    // Required, never skipped: the null backend must init everywhere.
    AudioEngine engine;
    QString error;
    QVERIFY2(engine.init(&error),
             qUtf8Printable(QStringLiteral("forced null audio init failed: %1").arg(error)));

    const QString backend = engine.backendName();
    QVERIFY2(!backend.isEmpty(), "the resolved backend name must be reported");
    QCOMPARE(engine.usingNullBackend(), backend == QStringLiteral("Null"));
    QVERIFY2(engine.nullBackendForced(), "the forced null request must be visible");
    QVERIFY2(engine.usingNullBackend(), "a forced null run must land on the Null backend");
    QCOMPARE(backend, QStringLiteral("Null"));

    // Field aid for silent-playback reports: surface the resolved device
    // buffering in the test log (the legacy harness printed this to stdout).
    const double periodMs =
        engine.sampleRate() > 0 ? 1000.0 * engine.periodSizeFrames() / engine.sampleRate() : 0.0;
    qInfo().noquote() << QStringLiteral("backend=%1 rate=%2 period=%3x%4 frames (~%5 ms)")
                             .arg(backend)
                             .arg(int(engine.sampleRate()))
                             .arg(engine.periodCount())
                             .arg(engine.periodSizeFrames())
                             .arg(periodMs, 0, 'f', 1);

    engine.shutdown();
}

} // namespace checks

int runAudioBackendCheck(const QStringList &qtArguments)
{
    checks::AudioBackendTest test;
    QStringList arguments{QStringLiteral("audiocheck-backend")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
