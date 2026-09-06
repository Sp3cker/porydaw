#include <QtTest>

#include <QDir>
#include <QFileInfo>

#include <deque>
#include <memory>
#include <optional>
#include <utility>
#include <variant>

#include "checks/project/iofixture.h"

namespace {

using project_check::loadSong;
using project_check::songChainAt;
using project_check::SongLoad;
using project_check::SongLoadEntry;

class ProjectIoFlowTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectIoFlowTest)

  public:
    explicit ProjectIoFlowTest(QString stagedRoot) : m_stagedRoot(std::move(stagedRoot)) {}

  private slots:
    void init();
    void cleanup();
    void openPublishesSnapshotDetached();
    void fifoDeliversInSubmissionOrder();
    void failedOpenKeepsWorkerProject();
    void catalogPreemptionRequeuesOneComplete();
    void songChains_openReloadStageTag_data();
    void songChains_openReloadStageTag();
    void voicegroupLoadAndPreviewPaths();

  private:
    QString m_stagedRoot;
    std::unique_ptr<project_check::ProjectIoFixture> m_fixture;
};

void ProjectIoFlowTest::init()
{
    m_fixture = std::make_unique<project_check::ProjectIoFixture>(m_stagedRoot);
    QString error;
    QVERIFY2(m_fixture->initialize(error), qPrintable(error));
}

void ProjectIoFlowTest::cleanup()
{
    QVERIFY(!m_fixture || m_fixture->callbacksReturnToCallerThread());
    m_fixture.reset();
}

void ProjectIoFlowTest::openPublishesSnapshotDetached()
{
    QString error;
    bool completedInline = false;
    const std::optional<project_check::OpenedProject> opened =
        m_fixture->open(error, &completedInline);
    QCOMPARE(completedInline, false);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    QCOMPARE(opened->snapshot.root(), QDir(m_fixture->root()).absolutePath());
    QVERIFY(!opened->snapshot.songs().isEmpty());
    QCOMPARE(opened->snapshot.players().size(), 5);
    QVERIFY(opened->oneTrackSong);
    if (opened->oneTrackSong)
        QCOMPARE(opened->snapshot.trackBudgetFor(*opened->oneTrackSong), 1);
    QVERIFY(opened->playableSong.isPlayable());
    QVERIFY(opened->playableSong.hasCfg);
    QCOMPARE(opened->song.value(), opened->playableSong.label);
}

void ProjectIoFlowTest::fifoDeliversInSubmissionOrder()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    const int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{ProbeSamplesInput{}});
    m_fixture->io().submit(ProjectCommand{RegistrationPlanInput{
        opened->playableSong.label, opened->constant, opened->playableSong.player}});
    m_fixture->io().submit(ProjectCommand{DeletionPlanInput{opened->song, opened->constant}});
    m_fixture->io().submit(ProjectCommand{RefreshCatalogInput{}});
    QCOMPARE(m_fixture->resultCount(), resultBase);
    QVERIFY2(m_fixture->waitFor(resultBase + 4, error), qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), resultBase + 4);

    const std::deque<ProjectResult> &results = m_fixture->results();
    QVERIFY(std::holds_alternative<SamplesProbed>(results[resultBase]));
    const auto *const registration = std::get_if<RegistrationPlanResult>(&results[resultBase + 1]);
    const auto *const deletion = std::get_if<DeletionPlanResult>(&results[resultBase + 2]);
    const auto *const catalog = std::get_if<VoicegroupCatalog>(&results[resultBase + 3]);
    QVERIFY(registration);
    QVERIFY(deletion);
    QVERIFY(catalog);
    if (!(registration && deletion && catalog))
        return;

    QCOMPARE(registration->song.value(), opened->playableSong.label);
    QCOMPARE(registration->plan.label, opened->playableSong.label);
    QCOMPARE(registration->plan.constant, opened->constant);
    QCOMPARE(registration->plan.player, opened->playableSong.player);
    QVERIFY(registration->plan.songId >= 0);
    QVERIFY(registration->plan.songTableLine.contains(opened->playableSong.label));
    QVERIFY(registration->status.inSongTable);

    QVERIFY(deletion->song == opened->song);
    QVERIFY(deletion->plan.tableIndex >= 0);
    QVERIFY(deletion->plan.tableCount > deletion->plan.tableIndex);
    QVERIFY(deletion->deletableVoicegroupName.isEmpty());
    QVERIFY(!catalog->groupArgs.isEmpty());
}

void ProjectIoFlowTest::failedOpenKeepsWorkerProject()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(
        ProjectCommand{OpenProjectInput{m_fixture->root() + QStringLiteral("/missing")}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    const auto *const failure = std::get_if<CommandFailure>(&m_fixture->results().back());
    QVERIFY(failure);
    if (failure)
        QVERIFY(!failure->message.isEmpty());

    resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{ProbeSamplesInput{}});
    QVERIFY2(m_fixture->waitFor(resultBase + 1, error), qPrintable(error));
    QVERIFY(std::holds_alternative<SamplesProbed>(m_fixture->results().back()));
}

void ProjectIoFlowTest::catalogPreemptionRequeuesOneComplete()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    const int resultBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{RefreshCatalogInput{}});
    m_fixture->io().submit(ProjectCommand{OpenSongInput{opened->song}});
    QCOMPARE(m_fixture->resultCount(), resultBase);
    QVERIFY2(m_fixture->waitFor(resultBase + 4, error), qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), resultBase + 4);
    QVERIFY2(songChainAt(m_fixture->results(), resultBase, opened->song, error), qPrintable(error));

    int completeCatalogs = 0;
    for (int index = resultBase; index < m_fixture->resultCount(); ++index) {
        const ProjectResult &result = m_fixture->results()[index];
        completeCatalogs += std::holds_alternative<VoicegroupCatalog>(result) ? 1 : 0;
        QVERIFY(!std::holds_alternative<CommandFailure>(result));
    }
    QCOMPARE(completeCatalogs, 1);
    QVERIFY(std::holds_alternative<VoicegroupCatalog>(m_fixture->results()[resultBase + 3]));
}

void ProjectIoFlowTest::songChains_openReloadStageTag_data()
{
    QTest::addColumn<int>("entryPoint");
    QTest::newRow("open") << static_cast<int>(SongLoadEntry::Open);
    QTest::newRow("reload") << static_cast<int>(SongLoadEntry::Reload);
    QTest::newRow("private-load") << static_cast<int>(SongLoadEntry::PrivateLoad);
}

void ProjectIoFlowTest::songChains_openReloadStageTag()
{
    QFETCH(int, entryPoint);
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    const int resultBase = m_fixture->resultCount();
    bool completedInline = false;
    const std::optional<SongLoad> chain = loadSong(
        *m_fixture, opened->song, static_cast<SongLoadEntry>(entryPoint), &completedInline, error);
    QCOMPARE(completedInline, false);
    QVERIFY2(chain, qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), resultBase + 3);
}

void ProjectIoFlowTest::voicegroupLoadAndPreviewPaths()
{
    QString error;
    const std::optional<project_check::OpenedProject> opened = m_fixture->open(error);
    QVERIFY2(opened, qPrintable(error));
    if (!opened)
        return;

    const std::optional<SongLoad> firstSong =
        loadSong(*m_fixture, opened->song, SongLoadEntry::Open, nullptr, error);
    QVERIFY2(firstSong, qPrintable(error));
    if (!firstSong)
        return;
    const VoicegroupId bankId = firstSong->bankId;

    const int loadBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{LoadVoicegroupCommand{opened->song, bankId}});
    QVERIFY2(m_fixture->waitFor(loadBase + 2, error), qPrintable(error));
    QCOMPARE(m_fixture->resultCount(), loadBase + 2);
    const auto *const view = std::get_if<LoadedBankView>(&m_fixture->results()[loadBase]);
    const auto *const bound = std::get_if<VoicegroupBound>(&m_fixture->results()[loadBase + 1]);
    QVERIFY(view);
    QVERIFY(bound);
    if (!(view && bound))
        return;
    QCOMPARE(view->id.sourceRelativePath(), bankId.sourceRelativePath());
    QCOMPARE(view->id.sectionLabel(), bankId.sectionLabel());
    QVERIFY(view->bank);
    QVERIFY(bound->id == bankId);

    const int previewBase = m_fixture->resultCount();
    m_fixture->io().submit(ProjectCommand{PreviewPlanInput{bankId}});
    QVERIFY2(m_fixture->waitFor(previewBase + 1, error), qPrintable(error));
    const auto *const plan = std::get_if<PreviewPlan>(&m_fixture->results().back());
    QVERIFY(plan);
    if (!plan)
        return;

    const QString previewDir =
        QDir(opened->snapshot.root()).filePath(QStringLiteral(".porydaw/vgpreview"));
    const QString loadName = bankId.sectionLabel().isEmpty()
                                 ? QFileInfo(bankId.sourceRelativePath()).completeBaseName()
                                 : bankId.sectionLabel();
    QVERIFY(plan->voicegroup == bankId);
    QCOMPARE(plan->shadowSourcePath, previewDir);
    QCOMPARE(plan->targetIncPath, QDir(previewDir).filePath(loadName + QStringLiteral(".inc")));
}

} // namespace

int runProjectIoFlowCheck(const QString &stagedRoot, const QStringList &qtArguments)
{
    ProjectIoFlowTest test(stagedRoot);
    QStringList arguments{QStringLiteral("project-io-flow")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "ioflow.moc"
