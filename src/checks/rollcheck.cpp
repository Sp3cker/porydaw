#include "rollcheck/rollcheck.h"

#include <QElapsedTimer>
#include <QtGlobal>
#include <cstdio>
#include <utility>

#include "checks/support/songfixture.h"

// --rollcheck <projectRoot> <song> [shot.png]: piano-roll gesture check.
// Topic implementations retain the original fixture order and assertions; this
// runner owns startup, the production-like timeline refresh, and final rollback.

int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &screenshotPath)
{
#ifdef Q_OS_WIN
    // DirectComposition pixels are not part of QWidget::grab(). The native
    // path has its own rendering harness; this check exercises the widget
    // fallback whose paint geometry it can inspect.
    qputenv("PORYDAW_FORCE_WIDGET_PLAYHEAD", "1");
#endif

    QString error;
    QElapsedTimer timer;
    timer.start();
    auto loadedSong = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "rollcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    const SongInfo song = loadedSong->songInfo();
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "rollcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    SongDocument &document = rig->document();
    const QByteArray baseline = document.smf().write();
    if (qEnvironmentVariableIsSet("PORYDAW_FORCE_UNCACHED_TIMELINE")) {
        // The diagnostic mode invalidates every paint-budget assertion below.
        std::fprintf(stderr,
                     "rollcheck: FAIL %s: unset PORYDAW_FORCE_UNCACHED_TIMELINE "
                     "(diagnostic mode breaks the cache paint budgets)\n",
                     qUtf8Printable(songLabel));
        return 1;
    }

    checks::rollcheck::Harness check(*rig, songLabel);
    if (!check.prepare())
        return 1;
    const auto earlyFailureStatus = [&] { return check.failures() ? check.failures() : 1; };
    using checks::rollcheck::ScenarioContinuation;

    if (checks::rollcheck::runIdentityScenarios(check, song) == ScenarioContinuation::Stop ||
        checks::rollcheck::runRemapScenarios(check, song) == ScenarioContinuation::Stop ||
        checks::rollcheck::runHeaderReconciliationScenarios(check, song) ==
            ScenarioContinuation::Stop ||
        checks::rollcheck::runCameraScenarios(check) == ScenarioContinuation::Stop)
        return earlyFailureStatus();

    auto paintingFixture = checks::rollcheck::runPencilPaintingScenarios(check);
    if (!paintingFixture)
        return earlyFailureStatus();
    if (checks::rollcheck::runPencilNoteRenderingScenarios(check, *paintingFixture) ==
        ScenarioContinuation::Stop)
        return earlyFailureStatus();
    auto velocityFixture =
        checks::rollcheck::runPencilVelocityScenarios(check, std::move(*paintingFixture));
    if (!velocityFixture)
        return earlyFailureStatus();
    if (checks::rollcheck::runSelectionGestureScenarios(check, *velocityFixture) ==
            ScenarioContinuation::Stop ||
        checks::rollcheck::runSelectionRasterScenarios(check, *velocityFixture) ==
            ScenarioContinuation::Stop)
        return earlyFailureStatus();

    auto resizeFixture = checks::rollcheck::runResizeScenarios(check, *velocityFixture);
    if (!resizeFixture)
        return earlyFailureStatus();
    if (checks::rollcheck::runKeyboardAndTimelineScenarios(check, *resizeFixture) ==
            ScenarioContinuation::Stop ||
        checks::rollcheck::runHeaderAndPresentationScenarios(
            check, *velocityFixture, screenshotPath) == ScenarioContinuation::Stop)
        return earlyFailureStatus();

    // Topic-local undo deltas above protect each gesture seam. The aggregate
    // rollback still proves every retained document mutation restores bytes.
    int undos = 0;
    while (document.undoStack()->canUndo() && undos < 100) {
        document.undoStack()->undo();
        ++undos;
    }
    if (document.undoStack()->canUndo())
        check.fail("gesture pass pushed an unexpected number of undo commands");
    if (document.smf().write() != baseline)
        check.fail("undoing every gesture did not restore the original bytes");

    if (checks::rollcheck::runScaleProjectionScenarios(check) == ScenarioContinuation::Stop ||
        checks::rollcheck::runScaleFoldScenarios(check) == ScenarioContinuation::Stop ||
        checks::rollcheck::runScaleEditingScenarios(check) == ScenarioContinuation::Stop)
        return earlyFailureStatus();

    SongView &view = rig->view();
    view.setDocument(nullptr);
    view.setSong(nullptr, nullptr);

    if (check.failures() == 0)
        std::printf("rollcheck: OK %s (%lld ms)\n", qUtf8Printable(songLabel),
                    static_cast<long long>(timer.elapsed()));
    return check.failures() ? 1 : 0;
}
