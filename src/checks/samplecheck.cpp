#include <QDir>
#include <QString>
#include <cstdio>

#include "samplecheck/samplecheck.h"

// --samplecheck <scratchDir> [corpusRoot]: sample import, DSP, editor,
// compressed container, SoundFont, engine-loop, provenance, and optional
// reference-corpus checks. Topic functions retain the established phase order.

namespace samplecheck {

void Reporter::expect(bool ok, const char *what)
{
    if (!ok) {
        std::fprintf(stderr, "samplecheck: FAIL: %s\n", what);
        failures_++;
    }
}

bool Reporter::expectError(const QString &got, const QString &want, const char *what)
{
    if (got == want)
        return true;
    std::fprintf(stderr, "samplecheck: FAIL: %s\n  want: %s\n  got:  %s\n", what,
                 qUtf8Printable(want), qUtf8Printable(got));
    failures_++;
    return false;
}

void Reporter::noteFailure()
{
    failures_++;
}

int Reporter::failureCount() const
{
    return failures_;
}

} // namespace samplecheck

int runSampleCheck(const QString &scratchDir, const QString &corpusRoot,
                   const QString &screenshotPath)
{
    if (QDir(scratchDir).exists()) {
        std::fprintf(stderr,
                     "samplecheck: scratch dir %s already exists; give a "
                     "fresh path\n",
                     qUtf8Printable(scratchDir));
        return 1;
    }

    samplecheck::Reporter reporter;
    const auto project = samplecheck::prepareRegisteredSampleProject(
        reporter, scratchDir + QStringLiteral("/wavproj"), scratchDir);
    if (!project)
        return 1;

    samplecheck::runDecodeChecks(reporter, *project);
    const auto dspFixture = samplecheck::runDspChecks(reporter, *project);
    if (!dspFixture)
        return 1;
    samplecheck::runPipelineDialogChecks(reporter, *project, *dspFixture);
    samplecheck::runAnalysisChecks(reporter);
    samplecheck::runEditorChecks(reporter, *project, *dspFixture, screenshotPath);
    samplecheck::runCompressedChecks(reporter);
    samplecheck::runSoundFontChecks(reporter);
    samplecheck::runEngineLoopChecks(reporter, *project, *dspFixture);
    samplecheck::runProvenanceChecks(reporter, *project, *dspFixture, scratchDir);
    samplecheck::runCorpusChecks(reporter, corpusRoot);

    std::printf("samplecheck: %s\n", reporter.failureCount() == 0 ? "PASS" : "FAIL");
    return reporter.failureCount() == 0 ? 0 : 1;
}
