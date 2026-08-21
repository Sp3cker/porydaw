#pragma once

#include <QString>

class QApplication;

int runViewCheck(const QString &projectRoot, const QString &screenshotSong = QString(),
                 const QString &screenshotPath = QString());
int runRoundTrip(const QString &projectRoot, const QString &mid2agbPath = QString());
int runEditCheck(const QString &projectRoot);
int runScaleCheck(const QString &projectRoot);
int runSaveCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &mid2agbPath = QString());
int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath = QString());
int runVgCheck(const QString &projectRoot, const QString &songLabel);
int runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                   const QString &screenshotPath = QString());
int runExportCheck(const QString &projectRoot, const QString &songLabel);
int runMkCheck(const QString &projectRoot, const QString &songLabel);
int runSessionCheck(const QString &projectRoot, const QString &songLabel);
int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB);
int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &screenshotPath = QString());
int runRollWindowingCheck(const QString &projectRoot, const QString &songLabel);
int runLoopCheck();
int runClickCheck();
int runPolyCheck(const QString &screenshotPath = QString());
int runPrimeCheck();
int runXcmdCheck();
int runSmfCheck();
int runTransportCheck();
int runAudioCheck();
int runResonanceCheck();
int runTrackActivityCheck();
int runTrackActivityMeterCheck();
int runSampleCheck(const QString &scratchDir, const QString &corpusRoot = QString(),
                   const QString &screenshotPath = QString());
int runIgnoreCheck(const QString &scratchDir);
int runKeymapCheck();
int runSelectionCheck();
int runEventViewCheck(const QString &projectRoot, const QString &screenshotSong = QString(),
                      const QString &screenshotPath = QString());
int runNoteIdentityCheck(const QString &scratchProject);
int runHostSeamsCheck();
int runVelocityModelCheck();
int runEditorDrawerCheck(const QString &screenshotPath = QString());
int runAutomationCheck(const QString &scratchProject, const QString &songLabel,
                       const QString &screenshotPath = QString());
int runAutomationGestureCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &domain = QString());
int runAutomationPopupMenuCheck(const QString &scratchProject, const QString &songLabel,
                                const QString &screenshotPath = QString());
int runTempoStripCheck(const QString &scratchProject, const QString &songLabel);
int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QString &screenshotPath = QString());
int runViewSidecarCheck(const QString &scratchProject, const QString &songLabel);
int runHostAdapterCheck(const QString &scratchProject, const QString &songLabel);
int runMainWindowRoutingCheck(const QString &scratchProject, const QString &songA,
                              const QString &songB);
int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath = QString());
int runHostIntegrationCheck(const QString &scratchProject, const QString &songA,
                            const QString &songB, const QString &screenshotPath = QString());
int runThemeHarness(QApplication &application, const QString &command);
int runEditorLayoutCheck(QApplication &application, int baseFontPx);
