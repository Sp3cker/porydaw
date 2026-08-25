#include "project/projectio.h"

#include <QDir>
#include <QEventLoop>
#include <QThread>
#include <QTimer>

#include <cstdio>
#include <memory>

namespace {
struct CompletionProbe {
    QThread **destroyedOn = nullptr;
    ~CompletionProbe() { *destroyedOn = QThread::currentThread(); }
};
} // namespace

int runProjectIoCheck(const QString &projectRoot)
{
    auto failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "projectiocheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
    auto projectIo = ProjectIo{};
    auto loop = QEventLoop{};
    auto completed = false;
    auto snapshot = ProjectSnapshot{};
    auto *callerThread = QThread::currentThread();
    const auto waitForCompletion = [&](const char *what) {
        auto timedOut = false;
        auto timer = QTimer{};
        timer.setSingleShot(true);
        timer.setInterval(30000);
        QObject::connect(&timer, &QTimer::timeout, &loop, [&] {
            timedOut = true;
            loop.quit();
        });
        timer.start();
        loop.exec();
        return check(!timedOut, what);
    };
    projectIo.openProject(projectRoot, [&](ProjectOpenResult result) {
        check(QThread::currentThread() == callerThread,
              "project-open completion did not return to the caller thread");
        check(result.succeeded(), "project open failed");
        snapshot = std::move(result.snapshot);
        completed = true;
        loop.quit();
    });
    check(!completed, "project open completed inline instead of being queued");
    waitForCompletion("project open timed out");
    check(completed, "project open did not complete");
    check(snapshot.isOpen(), "project snapshot is not open");
    check(snapshot.root() == QDir(projectRoot).absolutePath(), "project snapshot root is wrong");
    check(!snapshot.songs().isEmpty(), "project snapshot has no songs");
    auto oneTrackSong = snapshot.songs().cend();
    for (auto it = snapshot.songs().cbegin(); it != snapshot.songs().cend(); ++it) {
        if (it->label == QStringLiteral("se_fanfare_1trk")) {
            oneTrackSong = it;
            break;
        }
    }
    check(oneTrackSong != snapshot.songs().cend(), "one-track fixture song is missing");
    if (oneTrackSong != snapshot.songs().cend())
        check(snapshot.trackBudgetFor(*oneTrackSong) == 1,
              "project snapshot did not retain the song track budget");
    auto replacementCompleted = false;
    projectIo.openProject(projectRoot, [&](ProjectOpenResult result) {
        check(result.succeeded(), "replacement project open failed");
        replacementCompleted = true;
        loop.quit();
    });
    waitForCompletion("replacement project open timed out");
    check(replacementCompleted, "replacement project open did not complete");
    check(snapshot.isOpen() && !snapshot.songs().isEmpty(),
          "project snapshot depended on replaced worker-owned state");
    auto staleCompletionCalled = false;
    auto latestCompletionCalled = false;
    auto *completionDestroyedOn = static_cast<QThread *>(nullptr);
    auto completionProbe = std::make_shared<CompletionProbe>();
    completionProbe->destroyedOn = &completionDestroyedOn;
    projectIo.openProject(projectRoot, [&, completionProbe](ProjectOpenResult) {
        staleCompletionCalled = true;
        loop.quit();
    });
    completionProbe.reset();
    projectIo.openProject(projectRoot + QStringLiteral("/missing"), [&](ProjectOpenResult result) {
        check(QThread::currentThread() == callerThread,
              "failed project-open completion did not return to the caller thread");
        check(!result.succeeded(), "missing project unexpectedly opened");
        check(!result.error.isEmpty(), "missing project did not report an error");
        latestCompletionCalled = true;
        loop.quit();
    });
    check(completionDestroyedOn == callerThread,
          "superseded completion was not destroyed on the caller thread");
    waitForCompletion("failed replacement project open timed out");
    check(!staleCompletionCalled, "superseded project open delivered a stale result");
    check(latestCompletionCalled, "latest project open did not complete");
    if (failures == 0)
        std::printf("projectiocheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
