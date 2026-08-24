#pragma once

#include <QByteArray>
#include <QString>
#include <optional>

#include "audio/sampleimport.h"

namespace samplecheck {

class Reporter
{
  public:
    void expect(bool ok, const char *what);
    bool expectError(const QString &got, const QString &want, const char *what);
    void noteFailure();
    [[nodiscard]] int failureCount() const;

  private:
    int failures_ = 0;
};

struct RegisteredSampleProject {
    const QString root;
    const QByteArray wavFixture;
    const QString registeredSampleName;
};

struct DspFixture {
    ImportedSample hiRes;
    QByteArray hiResWav;
};

std::optional<RegisteredSampleProject>
prepareRegisteredSampleProject(Reporter &reporter, const QString &root, const QString &scratchDir);
void runDecodeChecks(Reporter &reporter, const RegisteredSampleProject &project);
std::optional<DspFixture> runDspChecks(Reporter &reporter, const RegisteredSampleProject &project);
void runPipelineDialogChecks(Reporter &reporter, const RegisteredSampleProject &project,
                             const DspFixture &dspFixture);
void runAnalysisChecks(Reporter &reporter);
void runEditorChecks(Reporter &reporter, const RegisteredSampleProject &project,
                     const DspFixture &dspFixture, const QString &screenshotPath);
void runCompressedChecks(Reporter &reporter);
void runSoundFontChecks(Reporter &reporter);
void runEngineLoopChecks(Reporter &reporter, const RegisteredSampleProject &project,
                         const DspFixture &dspFixture);
void runProvenanceChecks(Reporter &reporter, const RegisteredSampleProject &project,
                         const DspFixture &dspFixture, const QString &scratchDir);
void runCorpusChecks(Reporter &reporter, const QString &corpusRoot);

} // namespace samplecheck
