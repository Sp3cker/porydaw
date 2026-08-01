#include <cstdio>

#include <QByteArrayView>

#include <QApplication>
#include <QIcon>
#include <QStyleHints>

#include "mainwindow.h"
#include "ui/applicationstartup.h"

// viewcheck.cpp; the optional song label + path save one song's rendered view.
int runViewCheck(const QString &projectRoot, const QString &screenshotSong = QString(),
                 const QString &screenshotPath = QString());
// roundtrip.cpp; M2 save-fidelity check through the project's real mid2agb.
int runRoundTrip(const QString &projectRoot, const QString &mid2agbPath = QString());
// editcheck.cpp; M2 undo-integrity check over every edit-operation type.
int runEditCheck(const QString &projectRoot);
// savecheck.cpp; M2 edited-save check (writes into the project: use a copy).
int runSaveCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &mid2agbPath = QString());
// onboardcheck.cpp; M3 New Song + import check (writes into the project: use a copy).
int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath = QString());
// vgcheck.cpp; voicegroup edit/save/create check (writes into the project: use a copy).
int runVgCheck(const QString &projectRoot, const QString &songLabel);
// vgsavecheck.cpp; unified song+voicegroup undo/save check through MainWindow,
// against redirected QSettings (writes into the project: use a copy).
int runVgSaveCheck(const QString &projectRoot, const QString &songLabel,
                   const QString &screenshotPath = QString());
// exportcheck.cpp; WAV export check (writes a .wav into the project: use a copy).
int runExportCheck(const QString &projectRoot, const QString &songLabel);
// mkcheck.cpp; songs.mk-fallback parse/write check for projects with no
// midi.cfg (writes into the project: use a copy).
int runMkCheck(const QString &projectRoot, const QString &songLabel);
// sessioncheck.cpp; session restore/persistence check against redirected
// QSettings (writes view sidecars into the project: use a copy).
int runSessionCheck(const QString &projectRoot, const QString &songLabel);
// tabcheck.cpp; multi-tab check against redirected QSettings (writes view
// sidecars into the project: use a copy).
int runTabCheck(const QString &projectRoot, const QString &songA, const QString &songB);
// rollcheck.cpp; piano-roll gesture check (pencil draw + velocity latch +
// header-drag track reorder); the optional path saves the rendered view
// after the gestures.
int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &screenshotPath = QString());
// loopcheck.cpp; loop-wrap playback check (self-contained, no project needed).
int runLoopCheck();
// polycheck.cpp; polyphony-overflow debugger check: engine counters/tick
// stamps/invert audibility + offscreen PolyphonyPanel (self-contained, no
// project needed); the optional path saves the rendered panel.
int runPolyCheck(const QString &screenshotPath = QString());
// primecheck.cpp; audition voice-priming check (self-contained, no project needed).
int runPrimeCheck();
// smfcheck.cpp; SMF parse-validation + note-pairing check (self-contained,
// no project needed).
int runSmfCheck();
// transportcheck.cpp; playback-start halts ringing auditions (self-contained,
// no project needed; SKIPs without an audio device).
int runTransportCheck();
// audiocheck.cpp; prints the resolved audio backend and whether the silent
// null-device fallback is in effect (self-contained, no project needed).
int runAudioCheck();
// samplecheck.cpp; Sample Editor check (phases 1-6): registrar/import
// refusals, the headless pipeline (decode, resample, quantize, normalize,
// write, engine-loader parity), the phase-3 editor (pitch detection,
// loop suggestion, crossfade bake, audition slots, offscreen waveform/undo
// driving), the phase-4 compressed decoders (embedded MP3/FLAC/Ogg
// fixtures), the phase-5 SoundFont reader + zone picker (synthesized
// .sf2, offscreen driving), and the phase-6 engine loop-wrap integration +
// provenance sidecar / edit-in-place pipeline, in fully-fresh fake decomp
// projects under the given (nonexistent) scratch dir. The optional second
// argument points at a wav2agb decomp checkout (e.g. pokeemerald) whose
// sound/direct_sound_samples corpus gates the corpus-conditional sections.
// The optional third argument saves editor-dialog screenshots there (plus
// a -oneshot variant with the loop frame hidden).
int runSampleCheck(const QString &scratchDir, const QString &corpusRoot = QString(),
                   const QString &screenshotPath = QString());
// ignorecheck.cpp; sidecar-dir .gitignore check (self-contained, builds its
// own scratch projects; the scratch dir must not exist).
int runIgnoreCheck(const QString &scratchDir);
// keymapcheck.cpp; user-configurable shortcut check: registry table/matching/
// persistence + offscreen shortcuts-dialog driving (self-contained, no
// project needed; redirects QSettings itself).
int runKeymapCheck();
// eventviewcheck.cpp; raw MIDI event list check (model API + offscreen UI);
// the optional song label + path save that song's rendered event list.
int runEventViewCheck(const QString &projectRoot, const QString &screenshotSong = QString(),
                      const QString &screenshotPath = QString());
int runNoteIdentityCheck(const QString &scratchProject);
int runHostSeamsCheck();
int runVelocityModelCheck();
int runEditorDrawerCheck(const QString &screenshotPath = QString());
int runAutomationCheck(const QString &scratchProject, const QString &songLabel,
                       const QString &screenshotPath = QString());
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

namespace {

int missingCheckArguments(const char *command, const char *arguments)
{
    std::fprintf(stderr, "porydaw: %s requires %s\n", command, arguments);
    return 2;
}

} // namespace
namespace {
QtMessageHandler s_previousCheckMessageHandler = nullptr;

bool isCheckInvocation(int argc, char *argv[])
{
    for (int index = 1; index < argc; ++index) {
        const QByteArrayView argument(argv[index]);
        if (argument.startsWith("--check-")
            || (argument.startsWith("--") && argument.endsWith("check")))
            return true;
    }
    return false;
}

void checkMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (type == QtWarningMsg
        && (message.startsWith(QStringLiteral("Populating font family aliases took "))
            || message.startsWith(QStringLiteral("This plugin does not support "))))
        return;
    s_previousCheckMessageHandler(type, context, message);
}

void suppressOffscreenWarningsForChecks(int argc, char *argv[])
{
    if (isCheckInvocation(argc, argv))
        s_previousCheckMessageHandler = qInstallMessageHandler(checkMessageHandler);
}
} // namespace

int main(int argc, char *argv[])
{
    suppressOffscreenWarningsForChecks(argc, argv);
    QApplication app(argc, argv);
#if defined(Q_OS_WIN) && QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    // The Windows dark theme renders badly; force light until the widgets are
    // audited for dark palettes. macOS keeps the system appearance.
    app.styleHints()->setColorScheme(Qt::ColorScheme::Light);
#endif
    // Fusion everywhere: the native windows11 style paints item-view
    // selections as low-contrast accent-colored per-cell pills and has
    // sticky-hover repaint bugs. Set after QApplication so it also wins
    // over -style/QT_STYLE_OVERRIDE — released binaries should look the
    // same on every machine.
    QApplication::setStyle(QStringLiteral("fusion"));
    QApplication::setApplicationName("porydaw");
    QApplication::setApplicationVersion(QStringLiteral(PORYDAW_VERSION));
    QApplication::setOrganizationName("huderlem");
    QIcon appIcon;
    for (int size : {16, 32, 48, 128, 256})
        appIcon.addFile(QStringLiteral(":/icons/porydaw-%1.png").arg(size));
    QApplication::setWindowIcon(appIcon);
    // Wayland ignores the window icon; it resolves the icon through the
    // desktop entry instead (Icon=porydaw in resources/porydaw.desktop).
    QGuiApplication::setDesktopFileName(QStringLiteral("porydaw"));
    if (!ui::initializeApplication(app))
        return 1;

    const auto args = app.arguments();
    const auto noteIdentityCheck = args.indexOf(QStringLiteral("--check-note-identity"));
    if (noteIdentityCheck >= 0) {
        if (noteIdentityCheck + 1 >= args.size())
            return missingCheckArguments("--check-note-identity", "<scratch-project>");
        return runNoteIdentityCheck(args[noteIdentityCheck + 1]);
    }
    if (args.contains(QStringLiteral("--check-host-seams")))
        return runHostSeamsCheck();
    if (args.contains(QStringLiteral("--check-velocity-model")))
        return runVelocityModelCheck();
    const auto drawerCheck = args.indexOf(QStringLiteral("--check-editor-drawer"));
    if (drawerCheck >= 0) {
        const auto screenshotPath =
            drawerCheck + 1 < args.size() ? args[drawerCheck + 1] : QString();
        return runEditorDrawerCheck(screenshotPath);
    }
    const auto automationCheck = args.indexOf(QStringLiteral("--check-automation"));
    if (automationCheck >= 0) {
        if (automationCheck + 2 >= args.size())
            return missingCheckArguments("--check-automation",
                                         "<scratch-project> <song-label>");
        const auto screenshotPath =
            automationCheck + 3 < args.size() ? args[automationCheck + 3] : QString();
        return runAutomationCheck(args[automationCheck + 1], args[automationCheck + 2],
                                  screenshotPath);
    }
    const auto velocityPageCheck = args.indexOf(QStringLiteral("--check-velocity-page"));
    if (velocityPageCheck >= 0) {
        if (velocityPageCheck + 2 >= args.size())
            return missingCheckArguments("--check-velocity-page",
                                         "<scratch-project> <song-label>");
        const auto screenshotPath =
            velocityPageCheck + 3 < args.size() ? args[velocityPageCheck + 3] : QString();
        return runVelocityPageCheck(args[velocityPageCheck + 1], args[velocityPageCheck + 2],
                                    screenshotPath);
    }
    const auto sidecarCheck = args.indexOf(QStringLiteral("--check-sidecar"));
    if (sidecarCheck >= 0) {
        if (sidecarCheck + 2 >= args.size())
            return missingCheckArguments("--check-sidecar", "<scratch-project> <song-label>");
        return runViewSidecarCheck(args[sidecarCheck + 1], args[sidecarCheck + 2]);
    }
    const auto hostAdapterCheck = args.indexOf(QStringLiteral("--check-host-adapter"));
    if (hostAdapterCheck >= 0) {
        if (hostAdapterCheck + 2 >= args.size())
            return missingCheckArguments("--check-host-adapter",
                                         "<scratch-project> <song-label>");
        return runHostAdapterCheck(args[hostAdapterCheck + 1], args[hostAdapterCheck + 2]);
    }
    const auto mainWindowRoutingCheck =
        args.indexOf(QStringLiteral("--check-mainwindow-routing"));
    if (mainWindowRoutingCheck >= 0) {
        if (mainWindowRoutingCheck + 3 >= args.size())
            return missingCheckArguments("--check-mainwindow-routing",
                                         "<scratch-project> <song-a> <song-b>");
        return runMainWindowRoutingCheck(args[mainWindowRoutingCheck + 1],
                                         args[mainWindowRoutingCheck + 2],
                                         args[mainWindowRoutingCheck + 3]);
    }
    const auto renderingPlayheadCheck =
        args.indexOf(QStringLiteral("--check-rendering-playhead"));
    if (renderingPlayheadCheck >= 0) {
        if (renderingPlayheadCheck + 2 >= args.size())
            return missingCheckArguments("--check-rendering-playhead",
                                         "<scratch-project> <song-label>");
        const auto screenshotPath = renderingPlayheadCheck + 3 < args.size()
            ? args[renderingPlayheadCheck + 3]
            : QString();
        return runRenderingPlayheadCheck(args[renderingPlayheadCheck + 1],
                                         args[renderingPlayheadCheck + 2], screenshotPath);
    }
    const auto hostIntegrationCheck =
        args.indexOf(QStringLiteral("--check-host-integration"));
    if (hostIntegrationCheck >= 0) {
        if (hostIntegrationCheck + 3 >= args.size())
            return missingCheckArguments("--check-host-integration",
                                         "<scratch-project> <song-a> <song-b>");
        const auto screenshotPath = hostIntegrationCheck + 4 < args.size()
            ? args[hostIntegrationCheck + 4]
            : QString();
        return runHostIntegrationCheck(args[hostIntegrationCheck + 1],
                                       args[hostIntegrationCheck + 2],
                                       args[hostIntegrationCheck + 3], screenshotPath);
    }
    if (args.contains(QStringLiteral("--version"))) {
        std::printf("porydaw %s (Qt %s)\n", PORYDAW_VERSION, qVersion());
        return 0;
    }
    const int selfTest = args.indexOf(QStringLiteral("--selftest"));
    if (selfTest >= 0 && selfTest + 2 < args.size()) {
        MainWindow window;
        window.show();
        return window.runSelfTest(args[selfTest + 1], args[selfTest + 2]) ? 0 : 1;
    }
    const int saveCheck = args.indexOf(QStringLiteral("--savecheck"));
    if (saveCheck >= 0 && saveCheck + 2 < args.size()) {
        const QString mid2agb = saveCheck + 3 < args.size() ? args[saveCheck + 3] : QString();
        return runSaveCheck(args[saveCheck + 1], args[saveCheck + 2], mid2agb);
    }
    const int onboardCheck = args.indexOf(QStringLiteral("--onboardcheck"));
    if (onboardCheck >= 0 && onboardCheck + 1 < args.size()) {
        const QString mid2agb = onboardCheck + 2 < args.size() ? args[onboardCheck + 2] : QString();
        return runOnboardCheck(args[onboardCheck + 1], mid2agb);
    }
    const int vgCheck = args.indexOf(QStringLiteral("--vgcheck"));
    if (vgCheck >= 0 && vgCheck + 2 < args.size())
        return runVgCheck(args[vgCheck + 1], args[vgCheck + 2]);
    const int vgSaveCheck = args.indexOf(QStringLiteral("--vgsavecheck"));
    if (vgSaveCheck >= 0 && vgSaveCheck + 2 < args.size()) {
        const QString shot = vgSaveCheck + 3 < args.size() ? args[vgSaveCheck + 3] : QString();
        return runVgSaveCheck(args[vgSaveCheck + 1], args[vgSaveCheck + 2], shot);
    }
    const int exportCheck = args.indexOf(QStringLiteral("--exportcheck"));
    if (exportCheck >= 0 && exportCheck + 2 < args.size())
        return runExportCheck(args[exportCheck + 1], args[exportCheck + 2]);
    const int mkCheck = args.indexOf(QStringLiteral("--mkcheck"));
    if (mkCheck >= 0 && mkCheck + 2 < args.size())
        return runMkCheck(args[mkCheck + 1], args[mkCheck + 2]);
    const int sessionCheck = args.indexOf(QStringLiteral("--sessioncheck"));
    if (sessionCheck >= 0 && sessionCheck + 2 < args.size())
        return runSessionCheck(args[sessionCheck + 1], args[sessionCheck + 2]);
    const int tabCheck = args.indexOf(QStringLiteral("--tabcheck"));
    if (tabCheck >= 0 && tabCheck + 3 < args.size())
        return runTabCheck(args[tabCheck + 1], args[tabCheck + 2], args[tabCheck + 3]);
    if (args.contains(QStringLiteral("--loopcheck")))
        return runLoopCheck();
    const int polyCheck = args.indexOf(QStringLiteral("--polycheck"));
    if (polyCheck >= 0) {
        const QString path = polyCheck + 1 < args.size() ? args[polyCheck + 1] : QString();
        return runPolyCheck(path);
    }
    const int sampleCheck = args.indexOf(QStringLiteral("--samplecheck"));
    if (sampleCheck >= 0 && sampleCheck + 1 < args.size()) {
        const QString corpus = sampleCheck + 2 < args.size() ? args[sampleCheck + 2] : QString();
        const QString shot = sampleCheck + 3 < args.size() ? args[sampleCheck + 3] : QString();
        return runSampleCheck(args[sampleCheck + 1], corpus, shot);
    }
    if (args.contains(QStringLiteral("--primecheck")))
        return runPrimeCheck();
    if (args.contains(QStringLiteral("--smfcheck")))
        return runSmfCheck();
    const int ignoreCheck = args.indexOf(QStringLiteral("--ignorecheck"));
    if (ignoreCheck >= 0 && ignoreCheck + 1 < args.size())
        return runIgnoreCheck(args[ignoreCheck + 1]);
    if (args.contains(QStringLiteral("--transportcheck")))
        return runTransportCheck();
    if (args.contains(QStringLiteral("--audiocheck")))
        return runAudioCheck();
    if (args.contains(QStringLiteral("--keymapcheck")))
        return runKeymapCheck();
    const int editCheck = args.indexOf(QStringLiteral("--editcheck"));
    if (editCheck >= 0 && editCheck + 1 < args.size())
        return runEditCheck(args[editCheck + 1]);
    const int eventViewCheck = args.indexOf(QStringLiteral("--eventviewcheck"));
    if (eventViewCheck >= 0 && eventViewCheck + 1 < args.size()) {
        const QString song =
            eventViewCheck + 2 < args.size() ? args[eventViewCheck + 2] : QString();
        const QString path =
            eventViewCheck + 3 < args.size() ? args[eventViewCheck + 3] : QString();
        return runEventViewCheck(args[eventViewCheck + 1], song, path);
    }
    const int rollCheck = args.indexOf(QStringLiteral("--rollcheck"));
    if (rollCheck >= 0 && rollCheck + 2 < args.size()) {
        const QString path = rollCheck + 3 < args.size() ? args[rollCheck + 3] : QString();
        return runRollCheck(args[rollCheck + 1], args[rollCheck + 2], path);
    }
    const int roundTrip = args.indexOf(QStringLiteral("--roundtrip"));
    if (roundTrip >= 0 && roundTrip + 1 < args.size()) {
        const QString mid2agb = roundTrip + 2 < args.size() ? args[roundTrip + 2] : QString();
        return runRoundTrip(args[roundTrip + 1], mid2agb);
    }
    const int viewCheck = args.indexOf(QStringLiteral("--viewcheck"));
    if (viewCheck >= 0 && viewCheck + 1 < args.size()) {
        const QString song = viewCheck + 2 < args.size() ? args[viewCheck + 2] : QString();
        const QString path = viewCheck + 3 < args.size() ? args[viewCheck + 3] : QString();
        return runViewCheck(args[viewCheck + 1], song, path);
    }

    MainWindow window;
    ui::showCoveredWhileRestoring(window, [&window] { window.restoreSession(); });
    return app.exec();
}
