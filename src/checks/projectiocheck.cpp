#include "project/projectio.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThread>
#include <QTimer>

#include <cstdio>
#include <memory>
#include <utility>

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
    check(snapshot.players().size() == 5, "async project open did not retain the music players");
    auto bgmPlayer = snapshot.players().cend();
    for (auto it = snapshot.players().cbegin(); it != snapshot.players().cend(); ++it) {
        if (it->name == QStringLiteral("MUSIC_PLAYER_BGM")) {
            bgmPlayer = it;
            break;
        }
    }
    check(bgmPlayer != snapshot.players().cend() && bgmPlayer->trackCount == 16,
          "async project open retained an invalid BGM player");
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
    auto hydratedProject = DecompProject{};
    hydratedProject.replaceWith(snapshot);
    check(hydratedProject.players().size() == snapshot.players().size(),
          "project hydration dropped the music players");
    auto playableSong = snapshot.songs().cend();
    for (auto it = snapshot.songs().cbegin(); it != snapshot.songs().cend(); ++it) {
        if (it->isPlayable() && QFileInfo::exists(it->midPath)) {
            playableSong = it;
            break;
        }
    }
    check(playableSong != snapshot.songs().cend(), "project snapshot has no playable songs");
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
    if (playableSong != snapshot.songs().cend()) {
        const auto song = *playableSong;
        check(song.hasCfg, "playable song is missing its midi.cfg entry");
        auto songCompleted = false;
        auto songSucceeded = false;
        auto songCompletionOnCaller = false;
        auto songResult = SongFileResult{};
        projectIo.loadSongFile(song, [&](SongFileResult result) {
            songCompletionOnCaller = QThread::currentThread() == callerThread;
            check(songCompletionOnCaller,
                  "song-file completion did not return to the caller thread");
            songSucceeded = result.succeeded();
            check(songSucceeded, "song-file load failed");
            songResult = std::move(result);
            songCompleted = true;
            loop.quit();
        });
        check(!songCompleted, "song-file load completed inline instead of being queued");
        waitForCompletion("song-file load timed out");
        check(songCompleted, "song-file load did not complete");
        check(songCompletionOnCaller,
              "song-file completion was not delivered on the caller thread");
        check(songSucceeded, "song-file load did not succeed");
        check(!songResult.smf.tracks.empty(), "song-file load returned no SMF tracks");
        auto cancelledSongCompletionCalled = false;
        const auto cancelledSongRequest = projectIo.loadSongFile(song, [&](SongFileResult) {
            cancelledSongCompletionCalled = true;
            loop.quit();
        });
        projectIo.cancel(cancelledSongRequest);
        check(!cancelledSongCompletionCalled,
              "cancelled song-file load completed inline instead of being suppressed");
        auto saveSnapshot = SongSaveSnapshot{};
        saveSnapshot.smf = songResult.smf;
        saveSnapshot.midPath = song.midPath;
        saveSnapshot.label = song.label;
        saveSnapshot.cfg = song.cfg;
        saveSnapshot.flagsNeeded = true;
        auto saveCompleted = false;
        auto saveCompletionOnCaller = false;
        auto saveResult = SaveSongResult{};
        auto saveTurnObserved = false;
        const auto observerInvoked = QMetaObject::invokeMethod(
            &loop,
            [&] {
                saveTurnObserved = true;
                check(!saveCompleted,
                      "save completed before the queued event-loop turn was observed");
            },
            Qt::QueuedConnection);
        check(observerInvoked, "save queued-turn observer was not queued");
        auto saveRequestId = uint64_t{0};
        saveRequestId = projectIo.saveSong(saveSnapshot, [&](SaveSongResult result) {
            saveCompletionOnCaller = QThread::currentThread() == callerThread;
            check(saveCompletionOnCaller,
                  "song-save completion did not return to the caller thread");
            check(result.requestId == saveRequestId, "song-save completion returned the wrong ID");
            saveResult = std::move(result);
            saveCompleted = true;
            loop.quit();
        });
        check(!saveCompleted, "song save completed inline instead of being queued");
        waitForCompletion("song save timed out");
        check(saveCompleted, "song save did not complete");
        check(saveTurnObserved, "event loop did not process a queued turn during song save");
        check(saveCompletionOnCaller,
              "song-save completion was not delivered on the caller thread");
        check(saveResult.succeeded(), "song save failed");
        check(saveResult.midiOk, "song save did not report MIDI success");
        check(saveResult.flagsOk, "song save did not report flags success");
        check(saveResult.flagsWritten, "song save did not report that flags were written");
        auto cancelledSaveCompletionCalled = false;
        const auto cancelledSaveRequest = projectIo.saveSong(saveSnapshot, [&](SaveSongResult) {
            cancelledSaveCompletionCalled = true;
            loop.quit();
        });
        projectIo.cancel(cancelledSaveRequest);
        auto cancelledSaveBarrierCompleted = false;
        projectIo.loadSongFile(song, [&](SongFileResult result) {
            check(result.succeeded(), "cancelled song-save barrier load failed");
            cancelledSaveBarrierCompleted = true;
            loop.quit();
        });
        waitForCompletion("cancelled song save did not drain");
        check(cancelledSaveBarrierCompleted, "cancelled song save barrier did not complete");
        check(!cancelledSaveCompletionCalled, "cancelled song save delivered a completion");
        const QString strayLabel = QStringLiteral("projectiocheck_stray");
        const QString strayPath =
            QDir(snapshot.root())
                .filePath(QStringLiteral("sound/songs/midi/%1.mid").arg(strayLabel));
        const QByteArray strayBytes = QByteArrayLiteral("do not overwrite this stray MIDI");
        auto strayFile = QFile{strayPath};
        const auto strayOpened = strayFile.open(QIODevice::WriteOnly | QIODevice::Truncate);
        check(strayOpened, "could not seed the stray MIDI file");
        if (strayOpened)
            check(strayFile.write(strayBytes) == strayBytes.size(),
                  "could not write the stray MIDI fixture");
        strayFile.close();
        auto createRequest = CreateSongRequest{};
        createRequest.projectRoot = snapshot.root();
        createRequest.label = strayLabel;
        createRequest.constant = SongRegistry::constantForLabel(strayLabel);
        createRequest.player = song.player;
        createRequest.cfg = song.cfg;
        createRequest.smf = songResult.smf;
        auto createCompleted = false;
        auto createResult = CreateSongResult{};
        projectIo.createSong(std::move(createRequest), [&](CreateSongResult result) {
            createResult = std::move(result);
            createCompleted = true;
            loop.quit();
        });
        check(!createCompleted, "song creation completed inline instead of being queued");
        waitForCompletion("stray MIDI song creation timed out");
        check(createCompleted, "stray MIDI song creation did not complete");
        check(!createResult.succeeded() && !createResult.midiOk && !createResult.error.isEmpty(),
              "song creation did not refuse the existing MIDI path");
        auto preservedFile = QFile{strayPath};
        const auto preservedOpened = preservedFile.open(QIODevice::ReadOnly);
        check(preservedOpened, "stray MIDI file disappeared after refused creation");
        if (preservedOpened)
            check(preservedFile.readAll() == strayBytes,
                  "refused song creation overwrote the stray MIDI file");
        preservedFile.close();
        QFile::remove(strayPath);
        const auto sidecarPath = ViewSidecar::pathFor(snapshot.root(), song.label);
        check(QDir(snapshot.root()).mkpath(QStringLiteral(".porydaw")),
              "created sidecar directory for the ProjectIo check");
        QJsonObject seededRoot;
        seededRoot.insert(QStringLiteral("registration"),
                          QJsonObject{{QStringLiteral("pending"), true}});
        auto seedFile = QFile{sidecarPath};
        const auto seedOpened = seedFile.open(QIODevice::WriteOnly | QIODevice::Truncate);
        check(seedOpened, "seeded sidecar file for unrelated-root preservation");
        if (seedOpened)
            check(seedFile.write(QJsonDocument(seededRoot).toJson()) >= 0,
                  "wrote sidecar preservation fixture");
        seedFile.close();
        auto sidecarSnapshot = ViewSidecar::Snapshot{};
        sidecarSnapshot.view.valid = true;
        sidecarSnapshot.view.pxPerBeat = 48.0;
        sidecarSnapshot.view.keyHeight = 12.0;
        sidecarSnapshot.view.scrollPx = 21.5;
        sidecarSnapshot.view.scrollY = 7.25;
        sidecarSnapshot.view.selectedTrack = 2;
        sidecarSnapshot.view.editCursorTick = 96;
        sidecarSnapshot.view.gridMinDenom = 16;
        sidecarSnapshot.view.gridTriplet = true;
        sidecarSnapshot.view.eventList = true;
        sidecarSnapshot.editor.laneHeight = 96;
        auto sidecarWriteCompleted = false;
        auto sidecarWriteOnCaller = false;
        auto sidecarWriteResult = SidecarSaveResult{};
        projectIo.writeSidecar(
            SidecarSaveRequest{snapshot.root(), song.label, sidecarSnapshot},
            [&](SidecarSaveResult result) {
                sidecarWriteOnCaller = QThread::currentThread() == callerThread;
                check(sidecarWriteOnCaller,
                      "sidecar-save completion did not return to the caller thread");
                sidecarWriteResult = std::move(result);
                sidecarWriteCompleted = true;
                loop.quit();
            });
        check(!sidecarWriteCompleted, "sidecar save completed inline instead of being queued");
        waitForCompletion("sidecar save timed out");
        check(sidecarWriteCompleted, "sidecar save did not complete");
        check(sidecarWriteOnCaller,
              "sidecar save completion was not delivered on the caller thread");
        check(sidecarWriteResult.succeeded(), "sidecar save failed");
        auto sidecarReadCompleted = false;
        auto sidecarReadOnCaller = false;
        auto sidecarReadResult = SidecarLoadResult{};
        projectIo.readSidecar(
            SidecarLoadRequest{snapshot.root(), song.label}, [&](SidecarLoadResult result) {
                sidecarReadOnCaller = QThread::currentThread() == callerThread;
                check(sidecarReadOnCaller,
                      "sidecar-load completion did not return to the caller thread");
                sidecarReadResult = std::move(result);
                sidecarReadCompleted = true;
                loop.quit();
            });
        check(!sidecarReadCompleted, "sidecar load completed inline instead of being queued");
        waitForCompletion("sidecar load timed out");
        check(sidecarReadCompleted, "sidecar load did not complete");
        check(sidecarReadOnCaller,
              "sidecar load completion was not delivered on the caller thread");
        check(sidecarReadResult.succeeded(), "sidecar load failed");
        check(sidecarReadResult.snapshot.view.valid &&
                  sidecarReadResult.snapshot.view.pxPerBeat == sidecarSnapshot.view.pxPerBeat &&
                  sidecarReadResult.snapshot.view.selectedTrack ==
                      sidecarSnapshot.view.selectedTrack,
              "sidecar load returned the wrong detached view snapshot");
        auto storedRoot = QJsonObject{};
        auto storedFile = QFile{sidecarPath};
        const auto storedOpened = storedFile.open(QIODevice::ReadOnly);
        check(storedOpened, "reopened sidecar after ProjectIo write");
        if (storedOpened)
            storedRoot = QJsonDocument::fromJson(storedFile.readAll()).object();
        check(storedRoot.value(QStringLiteral("registration"))
                  .toObject()
                  .value(QStringLiteral("pending"))
                  .toBool(),
              "sidecar write discarded the unrelated JSON root key");
        const auto constant = SongRegistry::constantForLabel(song.label);
        auto registrationRequest = RegistrationPlanRequest{};
        registrationRequest.projectRoot = snapshot.root();
        registrationRequest.label = song.label;
        registrationRequest.constant = constant;
        registrationRequest.player = song.player;
        auto registrationCompleted = false;
        auto registrationOnCaller = false;
        auto registrationResult = RegistrationPlanResult{};
        auto registrationRequestId = uint64_t{0};
        registrationRequestId = projectIo.registrationPlan(
            std::move(registrationRequest), [&](RegistrationPlanResult result) {
                registrationOnCaller = QThread::currentThread() == callerThread;
                check(registrationOnCaller, "registration-plan completion did not return to "
                                            "the caller thread");
                check(result.requestId == registrationRequestId,
                      "registration-plan completion returned the wrong "
                      "ID");
                registrationResult = std::move(result);
                registrationCompleted = true;
                loop.quit();
            });
        check(!registrationCompleted, "registration plan completed inline instead of being queued");
        waitForCompletion("registration plan timed out");
        check(registrationCompleted, "registration plan did not complete");
        check(registrationOnCaller,
              "registration-plan completion was not delivered on the caller thread");
        check(registrationResult.succeeded() && registrationResult.plan.label == song.label &&
                  registrationResult.plan.constant == constant &&
                  registrationResult.plan.player == song.player &&
                  registrationResult.plan.songId >= 0 &&
                  registrationResult.plan.songTableLine.contains(song.label) &&
                  registrationResult.status.inSongTable,
              "registration plan did not return detached sensible values");
        auto deletionRequest = DeletionPlanRequest{};
        deletionRequest.projectRoot = snapshot.root();
        deletionRequest.label = song.label;
        deletionRequest.constant = constant;
        deletionRequest.songs = snapshot.songs();
        auto deletionCompleted = false;
        auto deletionOnCaller = false;
        auto deletionResult = DeletionPlanResult{};
        auto deletionRequestId = uint64_t{0};
        deletionRequestId =
            projectIo.deletionPlan(std::move(deletionRequest), [&](DeletionPlanResult result) {
                deletionOnCaller = QThread::currentThread() == callerThread;
                check(deletionOnCaller,
                      "deletion-plan completion did not return to the caller thread");
                check(result.requestId == deletionRequestId,
                      "deletion-plan completion returned the wrong ID");
                deletionResult = std::move(result);
                deletionCompleted = true;
                loop.quit();
            });
        check(!deletionCompleted, "deletion plan completed inline instead of being queued");
        waitForCompletion("deletion plan timed out");
        check(deletionCompleted, "deletion plan did not complete");
        check(deletionOnCaller, "deletion-plan completion was not delivered on the caller thread");
        check(deletionResult.succeeded() && deletionResult.plan.tableIndex >= 0 &&
                  deletionResult.plan.tableCount > deletionResult.plan.tableIndex &&
                  deletionResult.deletableVoicegroupName.isEmpty(),
              "deletion plan did not return detached sensible values");
        auto previewRequest = PreviewPlanRequest{};
        previewRequest.projectRoot = snapshot.root();
        previewRequest.loadName = QStringLiteral("fixture_rich");
        auto previewCompleted = false;
        auto previewOnCaller = false;
        auto previewResult = PreviewPlanResult{};
        auto previewRequestId = uint64_t{0};
        previewRequestId =
            projectIo.previewPlan(std::move(previewRequest), [&](PreviewPlanResult result) {
                previewOnCaller = QThread::currentThread() == callerThread;
                check(previewOnCaller,
                      "preview-plan completion did not return to the caller thread");
                check(result.requestId == previewRequestId,
                      "preview-plan completion returned the wrong ID");
                previewResult = std::move(result);
                previewCompleted = true;
                loop.quit();
            });
        check(!previewCompleted, "preview plan completed inline instead of being queued");
        waitForCompletion("preview plan timed out");
        check(previewCompleted, "preview plan did not complete");
        check(previewOnCaller, "preview-plan completion was not delivered on the caller thread");
        const auto expectedPreviewDir =
            QDir(snapshot.root()).filePath(QStringLiteral(".porydaw/vgpreview"));
        check(previewResult.succeeded() && previewResult.shadowSourcePath == expectedPreviewDir &&
                  previewResult.targetIncPath ==
                      QDir(expectedPreviewDir).filePath(QStringLiteral("fixture_rich.inc")),
              "preview plan did not return detached sensible values");
        auto voicegroupCompleted = false;
        auto voicegroupSucceeded = false;
        auto voicegroupCompletionOnCaller = false;
        auto voicegroupSourceReturned = false;
        projectIo.loadVoicegroup(snapshot.root(), song.cfg, [&](VoicegroupLoadResult result) {
            voicegroupCompletionOnCaller = QThread::currentThread() == callerThread;
            check(voicegroupCompletionOnCaller,
                  "voicegroup completion did not return to the caller thread");
            voicegroupSucceeded = result.succeeded();
            check(voicegroupSucceeded, "voicegroup load failed");
            check(result.voicegroup != nullptr, "voicegroup load returned a null voicegroup");
            voicegroupSourceReturned = result.source != nullptr;
            check(voicegroupSourceReturned, "voicegroup load returned a null source");
            if (result.voicegroup != nullptr)
                voicegroup_free(result.voicegroup);
            voicegroupCompleted = true;
            loop.quit();
        });
        check(!voicegroupCompleted, "voicegroup load completed inline instead of being queued");
        waitForCompletion("voicegroup load timed out");
        check(voicegroupCompleted, "voicegroup load did not complete");
        check(voicegroupCompletionOnCaller,
              "voicegroup completion was not delivered on the caller thread");
        check(voicegroupSucceeded, "voicegroup load did not succeed");
        check(voicegroupSourceReturned, "voicegroup load did not return its source");
        check(!cancelledSongCompletionCalled, "cancelled song-file load delivered a completion");
        auto cancelledVoicegroupCompletionCalled = false;
        const auto cancelledVoicegroupRequest =
            projectIo.loadVoicegroup(snapshot.root(), song.cfg, [&](VoicegroupLoadResult result) {
                cancelledVoicegroupCompletionCalled = true;
                if (result.voicegroup != nullptr)
                    voicegroup_free(result.voicegroup);
            });
        projectIo.cancel(cancelledVoicegroupRequest);
        check(!cancelledVoicegroupCompletionCalled,
              "cancelled voicegroup load completed inline instead of being suppressed");
        auto drainBarrierCallbackCompleted = false;
        auto drainBarrierEventCompleted = false;
        projectIo.loadSongFile(song, [&](SongFileResult result) {
            check(QThread::currentThread() == callerThread,
                  "voicegroup cancellation barrier did not return to the caller thread");
            check(result.succeeded(), "voicegroup cancellation barrier song load failed");
            check(!result.smf.tracks.empty(),
                  "voicegroup cancellation barrier returned no SMF tracks");
            drainBarrierCallbackCompleted = true;
            QTimer::singleShot(0, &loop, [&] {
                drainBarrierEventCompleted = true;
                loop.quit();
            });
        });
        check(!drainBarrierCallbackCompleted,
              "voicegroup cancellation barrier completed inline instead of being queued");
        waitForCompletion("cancelled voicegroup load did not drain");
        check(drainBarrierCallbackCompleted, "voicegroup cancellation barrier did not complete");
        check(drainBarrierEventCompleted,
              "voicegroup cancellation event-loop barrier did not complete");
        check(!cancelledVoicegroupCompletionCalled,
              "cancelled voicegroup load delivered a completion");
    }
    if (failures == 0)
        std::printf("projectiocheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
