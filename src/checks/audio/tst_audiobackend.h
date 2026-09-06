#pragma once

// Audio backend diagnostics (migrated from src/checks/audiocheck.cpp,
// device half). The legacy harness SKIPPED cleanly when no device was
// available; this suite runs the forced null backend instead — required, not
// skipped — so headless hosts still prove the engine's backend reporting.
// A failed forced-null init fails the suite.

#include <QObject>

namespace checks {

class AudioBackendTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AudioBackendTest)

  public:
    AudioBackendTest() = default;

  private slots:
    void initTestCase();
    void cleanupTestCase();
    void forcedNullBackendIsReportable();

  private:
    QString m_priorBackendEnv;
};

} // namespace checks
