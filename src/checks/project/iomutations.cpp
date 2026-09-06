#include <QtTest>

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>
#include <QTimer>

#include <deque>
#include <memory>
#include <optional>
#include <utility>
#include <variant>

#include "checks/project/iofixture.h"

namespace {

using project_check::loadSong;
using project_check::SongLoad;
using project_check::SongLoadEntry;

class FileAside final
{
  public:
    static std::optional<FileAside> moveAside(const QString &source, QString &error)
    {
        const QString aside = source + QStringLiteral(".porydaw_aside");
        if (!QFile::rename(source, aside)) {
            error = QStringLiteral("could not rename %1 aside").arg(source);
            return std::nullopt;
        }
        return FileAside(source, aside);
    }

    ~FileAside() { restoreSilently(); }

    FileAside(const FileAside &) = delete;
    FileAside &operator=(const FileAside &) = delete;

    FileAside(FileAside &&other) noexcept
        : m_source(std::move(other.m_source))
        , m_aside(std::move(other.m_aside))
        , m_active(std::exchange(other.m_active, false))
    {}

    FileAside &operator=(FileAside &&) = delete;

    bool restore(QString &error)
    {
        if (!m_active)
            return true;
        if (!QFile::rename(m_aside, m_source)) {
            error = QStringLiteral("could not restore %1 from its aside").arg(m_source);
            return false;
        }
        m_active = false;
        return true;
    }

  private:
    FileAside(QString source, QString aside)
        : m_source(std::move(source))
        , m_aside(std::move(aside))
    {}

    void restoreSilently()
    {
        if (m_active)
            QFile::rename(m_aside, m_source);
    }

    QString m_source;
    QString m_aside;
    bool m_active = true;
};

struct LegacySongJson {
    QString path;
    QByteArray bytes;
};

std::optional<LegacySongJson> seedLegacySongJson(const QString &projectRoot,
                                                 const QString &songLabel, QString &error)
{
    if (!QDir(projectRoot).mkpath(QStringLiteral(".porydaw"))) {
        error = QStringLiteral("could not create the legacy sidecar directory");
        return std::nullopt;
    }

    QJsonObject root;
    root.insert(QStringLiteral("view"), QJsonObject{{QStringLiteral("pxPerBeat"), 48.0},
                                                    {QStringLiteral("selectedTrack"), 2}});
    root.insert(QStringLiteral("editor"), QJsonObject{{QStringLiteral("laneHeight"), 96}});
    const QByteArray bytes = QJsonDocument(root).toJson(QJsonDocument::Compact);
    const QString path =
        QDir(projectRoot).filePath(QStringLiteral(".porydaw/%1.json").arg(songLabel));

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) ||
        file.write(bytes) != bytes.size()) {
        error = QStringLiteral("could not seed %1").arg(path);
        return std::nullopt;
    }
    return LegacySongJson{path, bytes};
}

std::optional<QByteArray> readBytes(const QString &path, QString &error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("could not read %1").arg(path);
        return std::nullopt;
    }
    return file.readAll();
}

SongSaveSnapshot saveSnapshot(const project_check::OpenedProject &opened, const SongLoad &song)
{
    SongSaveSnapshot snapshot;
    snapshot.smf = song.midi.smf;
    snapshot.midPath = opened.playableSong.midPath;
    snapshot.label = opened.playableSong.label;
    snapshot.cfg = opened.playableSong.cfg;
    snapshot.flagsNeeded = true;
    return snapshot;
}

int firstFilledSlot(const LoadedBankView &view)
{
    for (int index = 0; index < view.slotViews.size(); ++index)
        if (view.slotViews[index].voice.has_value())
            return index;
    return -1;
}

bool waitForResults(std::deque<ProjectResult> &results, QEventLoop &loop, int count, QString &error)
{
    bool timedOut = false;
    QTimer timer;
    timer.setSingleShot(true);
    timer.setInterval(30000);
    QObject::connect(&timer, &QTimer::timeout, &loop, [&] {
        timedOut = true;
        loop.quit();
    });
    while (!timedOut && static_cast<int>(results.size()) < count) {
        timer.start();
        loop.exec();
    }
    timer.stop();
    if (static_cast<int>(results.size()) >= count)
        return true;
    error = QStringLiteral("timed out waiting for %1 ProjectIo result(s); received %2")
                .arg(count)
                .arg(results.size());
    return false;
}

enum class FailureSite { Reconcile, Midi, Voicegroup, Save };

class ProjectIoMutationsTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectIoMutationsTest)

  public:
    explicit ProjectIoMutationsTest(QString stagedRoot) : m_stagedRoot(std::move(stagedRoot)) {}

  private slots:
    void init();
    void cleanup();
    void failureStages_data();
    void failureStages();
    void legacyJsonUntouchedBySaveAndReload();
    void editConflictVsApplied();
    void semanticSaveBareAndWithRecipe();
    void previewCleanupPrivateResult();
    void creationCollisionRefusesLeavingStray();
    void closedTransportFailsAndShutdownJoins();

  private:
    QString m_stagedRoot;
    std::unique_ptr<project_check::ProjectIoFixture> m_fixture;
};

void ProjectIoMutationsTest::init()
{
    m_fixture = std::make_unique<project_check::ProjectIoFixture>(m_stagedRoot);
    QString error;
    QVERIFY2(m_fixture->initialize(error), qPrintable(error));
}

void ProjectIoMutationsTest::cleanup()
{
    QVERIFY(!m_fixture || m_fixture->callbacksReturnToCallerThread());
    m_fixture.reset();
}

void ProjectIoMutationsTest::failureStages_data()
{
    QTest::addColumn<int>("site");
    QTest::newRow("reconcile") << static_cast<int>(FailureSite::Reconcile);
    QTest::newRow("midi") << static_cast<int>(FailureSite::Midi);
    QTest::newRow("voicegroup") << static_cast<int>(FailureSite::Voicegroup);
    QTest::newRow("save") << static_cast<int>(FailureSite::Save);
}

void ProjectIoMutationsTest::failureStages()
{
    QFETCH(int, site);
    const FailureSite failureSite = static_cast<FailureSite>(site);
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    if (failureSite == FailureSite::Reconcile) {
        const std::optional<SongName> missing =
            SongName::create(QStringLiteral("porydaw_missing_song"));
        QVERIFY(missing);
        if (!missing)
            return;
        const int resultBase = m_fixture->resultCount();
        m_fixture->io().submit(ProjectCommand{OpenSongInput{*missing}});
        QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
        const auto *const failure = std::get_if<SongCommandFailure>(&m_fixture->results().back());
        QVERIFY(failure);
        if (failure) {
            QVERIFY(failure->song == *missing);
            QCOMPARE(failure->stage, SongStage::Reconcile);
        }
        return;
    }

    if (failureSite == FailureSite::Midi) {
        std::optional<FileAside> midiAside =
            FileAside::moveAside(opened->playableSong.midPath, error);
        QVERIFY2(midiAside, qPrintable(error));
        if (!midiAside)
            return;
        const int resultBase = m_fixture->resultCount();
        m_fixture->io().submit(ProjectCommand{OpenSongInput{opened->song}});
        QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
        const auto *const failure = std::get_if<SongCommandFailure>(&m_fixture->results().back());
        QVERIFY(failure);
        if (failure) {
            QVERIFY(failure->song == opened->song);
            QCOMPARE(failure->stage, SongStage::Midi);
        }
        QVERIFY2(midiAside->restore(error), qPrintable(error));
        return;
    }

    const std::optional<SongLoad> initial =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Open, nullptr, error);
    QVERIFY2(initial, qPrintable(error));
    if (!initial)
        return;

    if (failureSite == FailureSite::Voicegroup) {
        const QString sourcePath =
            QDir(opened->snapshot.root()).filePath(initial->bankId.sourceRelativePath());
        std::optional<FileAside> sourceAside = FileAside::moveAside(sourcePath, error);
        QVERIFY2(sourceAside, qPrintable(error));
        if (!sourceAside)
            return;
        const int resultBase = m_fixture->resultCount();
        m_fixture->io().submit(ProjectCommand{OpenSongInput{opened->song}});
        QVERIFY2(m_fixture->waitFor(resultBase + 2, error), qPrintable(error));
        QVERIFY(std::holds_alternative<MidiStage>(m_fixture->results()[resultBase]));
        const auto *const failure =
            std::get_if<SongCommandFailure>(&m_fixture->results()[resultBase + 1]);
        QVERIFY(failure);
        if (failure) {
            QVERIFY(failure->song == opened->song);
            QCOMPARE(failure->stage, SongStage::Voicegroup);
        }
        QVERIFY2(sourceAside->restore(error), qPrintable(error));
        return;
    }

    SongSaveSnapshot failing = saveSnapshot(*opened, *initial);
    failing.midPath = QDir::temp().filePath(QStringLiteral("porydaw_iocheck_missing/x.mid"));
    const int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{SaveSongInput{opened->song, failing, std::nullopt}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    const auto *const failure = std::get_if<SongCommandFailure>(&m_fixture->results().back());
    QVERIFY(failure);
    if (failure) {
        QVERIFY(failure->song == opened->song);
        QCOMPARE(failure->stage, SongStage::Save);
    }
}

void ProjectIoMutationsTest::legacyJsonUntouchedBySaveAndReload()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;
    const std::optional<SongLoad> initial =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Open, nullptr, error);
    QVERIFY2(initial, qPrintable(error));
    if (!initial)
        return;
    const std::optional<LegacySongJson> legacy =
        seedLegacySongJson(opened->snapshot.root(), opened->playableSong.label, error);
    QVERIFY2(legacy, qPrintable(error));
    if (!legacy)
        return;

    SongSaveSnapshot snapshot = saveSnapshot(*opened, *initial);
    int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{SaveSongInput{opened->song, snapshot, std::nullopt}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    QVERIFY(std::holds_alternative<SongSaved>(m_fixture->results().back()));
    const std::optional<QByteArray> afterBare = readBytes(legacy->path, error);
    QVERIFY2(afterBare, qPrintable(error));
    if (afterBare)
        QCOMPARE(*afterBare, legacy->bytes);

    resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{
        SaveSongInput{opened->song, snapshot, SaveVoicegroupInput{initial->bankId, {}}}});
    QVERIFY2(m_fixture->waitFor(resultBase + 2, error), qPrintable(error));
    QVERIFY(std::holds_alternative<LoadedBankView>(m_fixture->results()[resultBase]));
    QVERIFY(std::holds_alternative<SongSaved>(m_fixture->results()[resultBase + 1]));
    const std::optional<QByteArray> afterRecipe = readBytes(legacy->path, error);
    QVERIFY2(afterRecipe, qPrintable(error));
    if (afterRecipe)
        QCOMPARE(*afterRecipe, legacy->bytes);

    const std::optional<SongLoad> reloaded =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Reload, nullptr, error);
    QVERIFY2(reloaded, qPrintable(error));
    const std::optional<QByteArray> afterReload = readBytes(legacy->path, error);
    QVERIFY2(afterReload, qPrintable(error));
    if (afterReload)
        QCOMPARE(*afterReload, legacy->bytes);
}

void ProjectIoMutationsTest::editConflictVsApplied()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;
    const std::optional<SongLoad> initial =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Open, nullptr, error);
    QVERIFY2(initial, qPrintable(error));
    if (!initial)
        return;

    const int viewBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{LoadVoicegroupCommand{opened->song, initial->bankId}});
    QVERIFY2(m_fixture->waitFor(viewBase + 2, error), qPrintable(error));
    const auto *const loadedView = std::get_if<LoadedBankView>(&m_fixture->results()[viewBase]);
    QVERIFY(loadedView);
    if (!loadedView)
        return;
    const int slot = firstFilledSlot(*loadedView);
    QVERIFY(slot >= 0);
    if (slot < 0)
        return;

    // Copy every value before appending to the result deque: the old runner retained pointers
    // into its deque and could read a reallocation-dangling VoicegroupId/LoadedBankView.
    const VoicegroupId bankId = loadedView->id;
    const VgVoice originalVoice = *loadedView->slotViews[slot].voice;

    int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{
        VoicegroupEditInput{bankId, SetVoicegroupSlot{slot, originalVoice, std::nullopt}}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    const auto *const conflictResult =
        std::get_if<VoicegroupEditResult>(&m_fixture->results().back());
    QVERIFY(conflictResult);
    if (conflictResult)
        QVERIFY(std::holds_alternative<VoicegroupEditConflictResult>(*conflictResult));

    VgVoice editedVoice = originalVoice;
    ++editedVoice.key;
    resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{
        VoicegroupEditInput{bankId, SetVoicegroupSlot{slot, editedVoice, originalVoice}}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    const auto *const appliedResult =
        std::get_if<VoicegroupEditResult>(&m_fixture->results().back());
    QVERIFY(appliedResult);
    if (!appliedResult)
        return;
    const auto *const applied = std::get_if<VoicegroupEditAppliedResult>(appliedResult);
    QVERIFY(applied);
    if (!applied)
        return;
    QVERIFY(applied->view.id == bankId);
    QVERIFY(applied->view.slotViews[slot].voice.has_value());
    if (applied->view.slotViews[slot].voice)
        QVERIFY(*applied->view.slotViews[slot].voice == editedVoice);
    QVERIFY(!applied->materialization.has_value());
}

void ProjectIoMutationsTest::semanticSaveBareAndWithRecipe()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;
    const std::optional<SongLoad> initial =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Open, nullptr, error);
    QVERIFY2(initial, qPrintable(error));
    if (!initial)
        return;
    const SongSaveSnapshot snapshot = saveSnapshot(*opened, *initial);

    int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{SaveSongInput{opened->song, snapshot, std::nullopt}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), resultBase + 1);
    const auto *const bareSaved = std::get_if<SongSaved>(&m_fixture->results().back());
    QVERIFY(bareSaved);
    if (bareSaved) {
        QVERIFY(bareSaved->song == opened->song);
        QCOMPARE(bareSaved->savedSnapshot.label, opened->playableSong.label);
        QVERIFY(bareSaved->flagsWritten);
    }

    resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{
        SaveSongInput{opened->song, snapshot, SaveVoicegroupInput{initial->bankId, {}}}});
    QVERIFY2(m_fixture->waitFor(resultBase + 2, error), qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), resultBase + 2);
    const auto *const view = std::get_if<LoadedBankView>(&m_fixture->results()[resultBase]);
    const auto *const recipeSaved = std::get_if<SongSaved>(&m_fixture->results()[resultBase + 1]);
    QVERIFY(view);
    QVERIFY(recipeSaved);
    if (view)
        QVERIFY(view->id == initial->bankId);
    if (recipeSaved) {
        QVERIFY(recipeSaved->song == opened->song);
        QVERIFY(recipeSaved->flagsWritten);
    }

    const std::optional<SongLoad> reloaded =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Reload, nullptr, error);
    QVERIFY2(reloaded, qPrintable(error));
}

void ProjectIoMutationsTest::previewCleanupPrivateResult()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    const int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{CleanupPreviewInput{}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), resultBase + 1);
    QVERIFY(std::holds_alternative<PreviewCleanupCompleted>(m_fixture->results().back()));
}

void ProjectIoMutationsTest::creationCollisionRefusesLeavingStray()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;
    const std::optional<SongLoad> initial =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Open, nullptr, error);
    QVERIFY2(initial, qPrintable(error));
    if (!initial)
        return;

    const QString label = QStringLiteral("projectiocheck_stray");
    const QString strayPath = QDir(opened->snapshot.root())
                                  .filePath(QStringLiteral("sound/songs/midi/%1.mid").arg(label));
    const QByteArray strayBytes = QByteArrayLiteral("do not overwrite this stray MIDI");
    QFile stray(strayPath);
    QVERIFY2(stray.open(QIODevice::WriteOnly | QIODevice::Truncate),
             qPrintable(stray.errorString()));
    QCOMPARE(stray.write(strayBytes), static_cast<qint64>(strayBytes.size()));
    stray.close();

    const int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(
        ProjectCommand{CreateSongInput{label, opened->constant, opened->playableSong.player,
                                       opened->playableSong.cfg, QString{}, initial->midi.smf}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    const auto *const failure = std::get_if<CommandFailure>(&m_fixture->results().back());
    QVERIFY(failure);
    if (failure)
        QVERIFY(!failure->message.isEmpty());
    const std::optional<QByteArray> preserved = readBytes(strayPath, error);
    QVERIFY2(preserved, qPrintable(error));
    if (preserved)
        QCOMPARE(*preserved, strayBytes);
    QVERIFY(QFile::remove(strayPath));
    QVERIFY(!QFileInfo::exists(strayPath));
}

void ProjectIoMutationsTest::closedTransportFailsAndShutdownJoins()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    std::deque<ProjectResult> results;
    QEventLoop loop;
    const QThread *const callerThread = QThread::currentThread();
    bool callbacksOnCallerThread = true;
    auto closed =
        std::make_unique<ProjectIo>([&](ProjectResult result, std::optional<ProjectCommand>) {
            callbacksOnCallerThread &= QThread::currentThread() == callerThread;
            results.push_back(std::move(result));
            loop.quit();
        });

    closed->submit(ProjectCommand{RefreshCatalogInput{}});
    closed->submit(ProjectCommand{OpenSongInput{opened->song}});
    QVERIFY2(waitForResults(results, loop, 2, error), qPrintable(error));
    QVERIFY(callbacksOnCallerThread);
    QCOMPARE(static_cast<int>(results.size()), 2);
    const auto *const catalogFailure = std::get_if<CommandFailure>(&results[0]);
    const auto *const songFailure = std::get_if<SongCommandFailure>(&results[1]);
    QVERIFY(catalogFailure);
    QVERIFY(songFailure);
    if (catalogFailure)
        QVERIFY(!catalogFailure->message.isEmpty());
    if (songFailure) {
        QVERIFY(songFailure->song == opened->song);
        QCOMPARE(songFailure->stage, SongStage::Reconcile);
    }

    closed->submit(ProjectCommand{OpenProjectInput{m_fixture->root()}});
    closed->submit(ProjectCommand{OpenSongInput{opened->song}});
    const int delivered = static_cast<int>(results.size());
    closed.reset();
    loop.processEvents();
    QCOMPARE(static_cast<int>(results.size()), delivered);
}

} // namespace

int runProjectIoMutationsCheck(const QString &stagedRoot, const QStringList &qtArguments)
{
    ProjectIoMutationsTest test(stagedRoot);
    QStringList arguments{QStringLiteral("project-io-mutations")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "iomutations.moc"
