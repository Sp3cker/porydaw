#include <QtTest>

#include "checks/samplecheck/samplecheck.h"

// The legacy screenshotPath argument was output-only raster diagnostics, not
// a sample-processing oracle, so this runner deliberately no longer accepts
// or writes it. The harness forwards Qt's terminal arguments to one qExec.

namespace samplecheck {

SampleProcessingTest::SampleProcessingTest(QString corpusRoot) : m_corpusRoot(corpusRoot) {}

} // namespace samplecheck

int runSampleCheck(const QString &corpusRoot, const QStringList &qtArguments)
{
    samplecheck::SampleProcessingTest test(corpusRoot);
    QStringList arguments{QStringLiteral("samplecheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
