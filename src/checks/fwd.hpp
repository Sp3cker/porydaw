#pragma once

#include <QString>
#include <QStringList>

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
int runVgBankCheck(const QString &projectRoot, const QString &songLabel);
int runVgLoadCheck(const QString &projectRoot, const QString &songLabel = QString());
int runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                   const QString &screenshotPath = QString());
int runExportCheck(const QString &projectRoot, const QString &songLabel);
int runMkCheck(const QString &projectRoot, const QString &songLabel);
int runProjectIoCheck(const QString &projectRoot);
int runProjectWorkspaceCheck(const QString &projectRoot);
int runSessionCheck(const QString &projectRoot, const QString &songLabel);
int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB);
int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &screenshotPath = QString());
int runTimelinePanCheck(const QString &projectRoot, const QString &songLabel);
int runRollWindowingCheck(const QString &projectRoot, const QString &songLabel);
int runTrackHeaderQuickCheck(const QString &projectRoot, const QString &songLabel);
int runScrollbarQuickCheck(const QString &projectRoot, const QString &songLabel);
int runLoopCheck();
int runClickCheck();
int runPolyCheck(const QString &screenshotPath = QString());
int runPrimeCheck();
int runXcmdCheck();
int runSmfCheck();
int runVoicegroupViewCacheCheck();
int runTransportCheck();
int runAudioCheck();
int runResonanceCheck();
int runTrackActivityCheck();
int runTrackActivityMeterCheck();
int runIgnoreCheck(const QString &scratchDir);
int runSampleCheck(const QString &scratchDir, const QString &corpusRoot = QString(),
                   const QString &screenshotPath = QString());
int runKeymapCheck();
int runSelectionCheck();
int runClipMimeCheck();
int runClipCheck();
int runLaneSelectionCheck();
int runEventViewCheck(const QString &projectRoot, const QString &screenshotSong = QString(),
                      const QString &screenshotPath = QString());
int runNoteIdentityCheck(const QString &scratchProject);
int runHostSeamsCheck();
int runVelocityModelCheck();
int runEditorDrawerCheck(const QString &screenshotPath = QString());
int runAutomationPaintRasterCheck(const QString &scratchProject, const QString &songLabel);
int runAutomationInteractionRasterCheck(const QString &scratchProject, const QString &songLabel);
int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QString &screenshotPath = QString());
int runHostAdapterCheck(const QString &scratchProject, const QString &songLabel);
int runMainWindowRoutingCheck(const QString &scratchProject, const QString &songA,
                              const QString &songB);
int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath = QString());
int runHostIntegrationCheck(const QString &scratchProject, const QString &songA,
                            const QString &songB, const QString &screenshotPath = QString());
int runThemeHarness(QApplication &application, const QString &command);
int runEditorLayoutCheck(QApplication &application, int baseFontPx);
int runVelocityEditingCheck(const QStringList &qtArguments);
int runAutomationEditingCheck(const QStringList &qtArguments);
int runAutomationDomainCheck(const QStringList &qtArguments);
int runAutomationPresentationCheck(const QStringList &qtArguments);
int runAutomationHoverCheck(const QStringList &qtArguments);
