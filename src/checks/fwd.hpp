#pragma once

#include <QString>
#include <QStringList>

class QApplication;

// Free runner exports for porydaw_checks. Every in-process catalog row binds
// its manifest check arguments and forwards the terminal Qt payload (all
// arguments after the --qt separator) as qtArguments into exactly one qExec.

// PianoRoll (src/checks/rollcheck.cpp).
int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QStringList &qtArguments);

// Static piano-roll coverage (src/checks/rollcheck/static).
namespace checks::rollcheck::staticcheck {
int runPianoRollStaticCheck(const QString &projectRoot, const QString &songLabel,
                            const QStringList &qtArguments);
} // namespace checks::rollcheck::staticcheck

// Timeline pan (src/checks/timelinepan).
int runTimelinePanCheck(const QString &projectRoot, const QString &songLabel,
                        const QStringList &qtArguments);
int runTimelinePanNativeCheck(const QString &projectRoot, const QString &songLabel,
                              const QStringList &qtArguments);

// Workspace sessions (src/checks/workspace).
int runSessionCheck(const QString &projectRoot, const QString &songLabel,
                    const QStringList &qtArguments);
int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                const QStringList &qtArguments);
int runSelfTestTimelineCheck(const QStringList &checkArguments, const QStringList &qtArguments);
int runSelfTestTransportCheck(const QStringList &checkArguments, const QStringList &qtArguments);
int runSelfTestWorkspaceCheck(const QStringList &checkArguments, const QStringList &qtArguments);

// Song document (src/checks/editcheck).
int runEditCheck(const QStringList &checkArguments, const QStringList &qtArguments);
int runScaleCheck(const QStringList &checkArguments, const QStringList &qtArguments);
int runNoteIdentityCheck(const QStringList &checkArguments, const QStringList &qtArguments);

// Onboarding (src/checks/onboardcheck).
int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath,
                    const QStringList &qtArguments);

// Voicegroup bank (src/checks/voicegroup).
int runVgCheck(const QString &projectRoot, const QString &songLabel,
               const QStringList &qtArguments);
int runVgBankCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);
int runVgLoadCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);
int runVoicegroupViewCacheCheck(const QStringList &qtArguments);

// Voicegroup save (src/checks/voicegroupsave).
int runVoicegroupSaveCheck(const QString &projectRoot, const QString &songLabel,
                           const QString &screenshotPath, const QStringList &qtArguments);

// MIDI round trip (src/checks/midi).
int runSmfCheck(const QStringList &qtArguments);
int runRoundTrip(const QString &projectRoot, const QString &mid2agbPath,
                 const QStringList &qtArguments);
int runExportCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments);

// Event views (src/checks/eventviews).
int runEventViewsChromeCheck(const QStringList &qtArguments);
int runEventViewsEditsCheck(const QStringList &qtArguments);
int runEventViewsRemapCheck(const QStringList &qtArguments);
int runEventViewsPlayheadCheck(const QStringList &qtArguments);
int runViewBucketsGridCheck(const QStringList &qtArguments);

// Sample processing (src/checks/samplecheck).
int runSampleCheck(const QString &corpusRoot, const QStringList &qtArguments);

// Keyboard polyphony (src/checks/keyboard, src/checks/polyphony).
int runKeymapCheck(const QStringList &qtArguments);
int runPolyCheck(const QString &screenshotPath, const QStringList &qtArguments);
int runVelocityModelCheck(const QStringList &qtArguments);
int runSettingsDialogCheck(const QStringList &qtArguments);

// Track headers (src/checks/trackheaders).
int runTrackHeaderQuickCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments);
int runTrackActivityMeterCheck(const QStringList &qtArguments);

// Native graphics (src/checks/nativegraphics).
int runRollWindowingCheck(const QString &projectRoot, const QString &songLabel,
                          const QStringList &qtArguments);
int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel,
                              const QString &screenshotPath, const QStringList &qtArguments);

// Drawer presentation (src/checks/drawerpresentation).
int runEditorDrawerCheck(const QStringList &qtArguments);
int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QStringList &qtArguments);

// Automation raster (src/checks/automation/raster).
int runAutomationRasterCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments);

// Pitch bend popup (src/checks/pitchbend).
int runPitchBendEditingCheck(const QStringList &qtArguments);
int runPitchBendRasterCheck(const QStringList &qtArguments);

// Host integration (src/checks/host, src/checks/mainwindowrouting).
int runHostSeamsCheck(const QStringList &qtArguments);
int runRulerGridMenuCheck(const QStringList &qtArguments);
int runHostAdapterCheck(const QString &projectRoot, const QString &songLabel,
                        const QStringList &qtArguments);
int runHostIntegrationCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                            const QString &screenshotPath, const QStringList &qtArguments);

namespace checks::mainwindowrouting {
int runMainWindowRoutingNativeCheck(const QString &projectRoot, const QString &songA,
                                    const QString &songB, const QStringList &qtArguments);
int runMainWindowRoutingInputCheck(const QString &projectRoot, const QString &songA,
                                   const QString &songB, const QStringList &qtArguments);
int runMainWindowRoutingStateCheck(const QString &projectRoot, const QString &songA,
                                   const QString &songB, const QStringList &qtArguments);
int runMainWindowRoutingLifecycleCheck(const QString &projectRoot, const QString &songA,
                                       const QString &songB, const QStringList &qtArguments);
} // namespace checks::mainwindowrouting

// Theme layout (src/checks/themelayout). Handler-owned startup: these runners
// own application initialization and must run in dedicated processes.
int runThemeLayoutThemeCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutFontCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutDarkBaseCheck(QApplication &application, const QStringList &qtArguments);
int runThemeLayoutScaleCheck(QApplication &application, int baseFontPx,
                             const QStringList &qtArguments);

// Audio DSP (src/checks/audio).
int runAudioCheck(const QStringList &qtArguments);
int runAudioBackendCheck(const QStringList &qtArguments);
int runClickCheck(const QStringList &qtArguments);
int runResonanceCheck(const QStringList &qtArguments);
int runResonanceTimingCheck(const QStringList &qtArguments);
int runTrackActivityCheck(const QStringList &qtArguments);

// Project persistence (src/checks/project).
int runProjectIdentityCheck(const QStringList &qtArguments);
int runProjectIoFlowCheck(const QString &projectRoot, const QStringList &qtArguments);
int runProjectIoMutationsCheck(const QString &projectRoot, const QStringList &qtArguments);
int runProjectWorkspaceCheck(const QString &projectRoot, const QStringList &qtArguments);
int runSaveCheck(const QString &projectRoot, const QString &songLabel, const QString &mid2agbPath,
                 const QStringList &qtArguments);
int runMkCheck(const QString &projectRoot, const QString &songLabel,
               const QStringList &qtArguments);
int runIgnoreCheck(const QStringList &qtArguments);

// Playback (src/checks/playback).
int runLoopCheck(const QStringList &qtArguments);
int runPrimeCheck(const QStringList &qtArguments);
int runXcmdCheck(const QStringList &qtArguments);
int runTransportCheck(const QStringList &qtArguments);

// Clipboard and selection (src/checks/clipboard).
int runSelectionCheck(const QStringList &qtArguments);
int runClipMimeCheck(const QStringList &qtArguments);
int runClipCheck(const QStringList &qtArguments);
int runLaneSelectionCheck(const QStringList &qtArguments);

// Established pilot suites.
int runScrollbarCheck(const QString &projectRoot, const QString &songLabel,
                      const QStringList &qtArguments);
int runVelocityEditingCheck(const QStringList &qtArguments);
int runAutomationEditingCheck(const QStringList &qtArguments);
int runAutomationDomainCheck(const QStringList &qtArguments);
int runAutomationPresentationCheck(const QStringList &qtArguments);
int runAutomationHoverCheck(const QStringList &qtArguments);

// Selection-driven keyboard routing (src/checks/selectionkey).
int runSelectionKeyCoreCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments);
int runSelectionKeyGestureCheck(const QString &projectRoot, const QString &songLabel,
                                const QStringList &qtArguments);
int runSelectionKeyWindowCheck(const QString &projectRoot, const QString &songA,
                               const QString &songB, const QStringList &qtArguments);
int runSelectionKeyLocalInputCheck(const QString &projectRoot, const QString &songLabel,
                                   const QStringList &qtArguments);
